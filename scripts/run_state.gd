extends RefCounted
## Seeded five-sector expedition. No rendering or file IO.
const SECTORS = 5
const ROUTES = ["scrapyard","coalfield","arsenal"]
const Content = preload("res://scripts/content.gd")
const REWARDS = ["production","economy","magazine","autoload","cargo","scrap_cache","coal_cache","shell_cache","field_repair","scout_maps","craft_discount","salvage_boost","range_training","reinforcement","engine_tuning"]
const EQUIPMENT = Content.EQUIPMENT
const ENEMY_RECIPES = ["left_gun","right_gun","armor","rapid_gun","long_gun","mortar_gun","rear_gun","rangefinder","servo","supercharger","economizer","salvage_arm","skirts","scatter_gun","arc_gun","blast_fuse","drum_loader"]
const CONDITIONS = {"road":{"speed":3.3,"fuel":1.0},"mud":{"speed":2.8,"fuel":1.35},"rubble":{"speed":3.0,"fuel":1.15}}
const FORMATIONS = {"patrol":[0,1,2,0,1,2],"raiders":[1,1,0,1,1,0],"battery":[2,0,2,0,2,2]}

static func condition(route: Dictionary) -> Dictionary:
	return CONDITIONS[route.get("terrain","road")]

static func enemy_role(route: Dictionary, index: int) -> int:
	return int(route.enemies[index]) if route.has("enemies") else FORMATIONS[route.get("formation","patrol")][index]

static func enemy_health(route: Dictionary, index: int) -> int:
	# Keep old checkpoint health valid; every new encounter uses one-hit enemies.
	if route.is_empty() or route.get("combat_version",1) >= 2: return 1
	var extra = 1 if route.get("formation","patrol") == "battery" and enemy_role(route,index) == 2 else 0
	return int(route.get("enemy_hp",3))+extra+(6 if route.get("boss",false) and index == 5 else 0)

static func total_health(route: Dictionary) -> int:
	var total = 0
	for i in range(enemy_count(route)): total += enemy_health(route,i)
	return total
static func enemy_count(route: Dictionary) -> int:
	return route.get("enemies",[0,1,2,0,1,2]).size()

var difficulty = "normal"
var run_seed = 1
var sector = 1
var phase = "prepare"
var hull = 100
var cleared = 0
var rewards_taken = 0
var modifiers = {"work":1.0,"fuel":1.0,"magazine":12,"reload":1.0,"cargo":100,"craft":1.0,"salvage":0,"range":0.0,"damage":1.0,"speed":1.0,"routes":2}
var route_options: Array = []
var reward_options: Array = []
var current: Dictionary = {}
var recipes: Array = []
var equipment: Array = []
var stage_recipes: Array = []
var rng = RandomNumberGenerator.new()

func _init(value: int = 1, mode: String = "normal"):
	difficulty = mode if mode in Content.DIFFICULTIES else "normal"
	run_seed = value
	rng.seed = value
	current = make_route("scrapyard",true)

func make_route(kind: String, opening: bool = false) -> Dictionary:
	var scrap = 36 if kind == "scrapyard" else 18
	var coal = 30 if kind == "coalfield" else 16
	var length = 110.0+(sector-1)*14.0
	# Cover the added track travel and pivoting without removing route fuel choices.
	coal += preload("res://scripts/course_obstacles.gd").layout({"obstacles_version":1,"length":length}).size()*6
	if kind == "arsenal": scrap = 26
	var settings = Content.DIFFICULTIES[difficulty]
	scrap = int(round(scrap*settings.salvage))
	coal = int(round(coal*settings.salvage))
	var route_seed = int(rng.randi())
	var local_rng = RandomNumberGenerator.new()
	local_rng.seed = route_seed
	var terrain = "road" if opening else CONDITIONS.keys()[local_rng.randi_range(0,2)]
	var formation = "patrol" if opening else FORMATIONS.keys()[local_rng.randi_range(0,2)]
	var roster = make_roster(kind,local_rng)
	return {"kind":kind,"difficulty":difficulty,"enemies":roster,"wave_size":3 if difficulty == "easy" else 5 if difficulty == "hard" else 4,"wave_delay":18.0*settings.period,"warning_scale":settings.warning,"seed":route_seed,"terrain":terrain,"formation":formation,"sector":sector,"length":length,
		"scrap":scrap,"coal":coal,"shells":12 if kind == "arsenal" else 0,"enemy_hp":1,"combat_version":3,"obstacles_version":1,
		"damage":int(round((10+(sector-1)*2)*settings.damage)),"attack_period":maxf(4,8-(sector-1)*0.5)*settings.period,
		"boss":sector == SECTORS,"opening":opening}

func start_sector() -> bool:
	if phase != "prepare": return false
	stage_recipes.clear()
	phase = "travel"
	return true

func recover_recipe(role: int) -> String:
	# Equipment is now awarded by the clear draft, not by individual kills.
	return ""

func make_roster(kind: String, local_rng: RandomNumberGenerator) -> Array:
	var pools = [[0,1,2,3],[0,1,3,4,5,6,13],[2,4,5,7,8,9,13,14,15],[3,6,7,10,11,12,13,14,15],[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]]
	var pool: Array = pools[sector-1].duplicate()
	var result: Array = []
	var count = 12+(sector-1)*3+int(Content.DIFFICULTIES[difficulty].enemies)
	# Each stage introduces its full lesson set, then reinforces the route's theme.
	while not pool.is_empty(): result.append(pool.pop_at(local_rng.randi_range(0,pool.size()-1)))
	var theme = [0,2,7,9,13] if kind == "scrapyard" else [1,3,6,12,15] if kind == "coalfield" else [2,4,5,10,14]
	while result.size() < count:
		var role: int = theme[local_rng.randi_range(0,theme.size()-1)]
		if Content.ENEMIES[role].tier > sector: role = 0
		result.append(role)
	return result.slice(0,count)

func craft_cost(id: String) -> Dictionary:
	if not EQUIPMENT.has(id): return {}
	return {"scrap":ceili(EQUIPMENT[id].scrap*modifiers.get("craft",1.0)),"coal":ceili(EQUIPMENT[id].coal*modifiers.get("craft",1.0))}

func can_craft(id: String, reserves: Dictionary) -> bool:
	if phase != "craft" or id not in recipes or id in equipment or not EQUIPMENT.has(id): return false
	var recipe: Dictionary = craft_cost(id)
	return reserves.get("scrap",0) >= recipe.scrap and reserves.get("coal",0) >= recipe.coal

func craft(id: String, reserves: Dictionary) -> bool:
	if not can_craft(id,reserves): return false
	var cost = craft_cost(id)
	reserves.scrap -= cost.scrap
	reserves.coal -= cost.coal
	equipment.append(id)
	return true

func finish_sector(won: bool, remaining_hull: int, inventory: Dictionary = {}, mount_space: bool = true) -> bool:
	if phase != "travel": return false
	hull = clampi(remaining_hull,0,100)
	if not won or hull == 0:
		phase = "lost"
		return true
	hull = 100
	cleared += 1
	offer_rewards(inventory,mount_space)
	return true

func reward_pool(inventory: Dictionary = {}, mount_space: bool = true) -> Array:
	var pool: Array = []
	for id in EQUIPMENT:
		if id not in equipment and (mount_space or id not in Content.GUNS): pool.append("gear:"+id)
	return pool

func offer_rewards(inventory: Dictionary = {}, mount_space: bool = true):
	var pool = reward_pool(inventory,mount_space)
	reward_options.clear()
	for i in range(mini(3,pool.size())): reward_options.append(pool.pop_at(rng.randi_range(0,pool.size()-1)))
	phase = "reward"
	if reward_options.is_empty(): advance_after_reward()

func finish_crafting(_stock: Dictionary = {}, inventory: Dictionary = {}, mount_space: bool = true) -> bool:
	# Compatibility for an old checkpoint paused in the removed workshop phase.
	if phase != "craft": return false
	offer_rewards(inventory,mount_space)
	return true

func choose_reward(index: int) -> bool:
	if phase != "reward" or index < 0 or index >= reward_options.size(): return false
	var id: String = reward_options[index]
	if id.begins_with("gear:"):
		var gear = id.trim_prefix("gear:")
		if not EQUIPMENT.has(gear) or gear in equipment: return false
		if gear not in recipes: recipes.append(gear)
		equipment.append(gear)
	elif id.begins_with("block:"):
		if not Content.BLOCK_LIMITS.has(id.trim_prefix("block:")): return false
	elif id not in REWARDS: return false
	match reward_options[index]:
		"production": modifiers.work = maxf(0.4,modifiers.work*0.85)
		"economy": modifiers.fuel = maxf(0.4,modifiers.fuel*0.8)
		"magazine": modifiers.magazine += 4
		"autoload": modifiers["reload"] = maxf(0.4,modifiers.get("reload",1.0)*0.8)
		"cargo": modifiers["cargo"] = mini(200,modifiers.get("cargo",100)+25)
		"field_repair": hull = mini(100,hull+20)
		"scout_maps": modifiers["routes"] = 3
		"craft_discount": modifiers["craft"] = maxf(0.4,modifiers.get("craft",1.0)*0.8)
		"salvage_boost": modifiers["salvage"] = modifiers.get("salvage",0)+1
		"range_training": modifiers["range"] = modifiers.get("range",0.0)+4.0
		"reinforcement": modifiers["damage"] = maxf(0.5,modifiers.get("damage",1.0)*0.9)
		"engine_tuning": modifiers["speed"] = minf(1.5,modifiers.get("speed",1.0)*1.1)
	rewards_taken += 1
	reward_options.clear()
	advance_after_reward()
	return true

func advance_after_reward():
	if sector == SECTORS:
		phase = "won"
		return
	sector += 1
	var first = rng.randi_range(0,2)
	var second = (first+rng.randi_range(1,2))%3
	route_options = [make_route(ROUTES[first]),make_route(ROUTES[second])]
	if modifiers.get("routes",2) == 3: route_options.append(make_route(ROUTES[3-first-second]))
	phase = "route"

func choose_route(index: int) -> bool:
	if phase != "route" or index < 0 or index >= route_options.size(): return false
	current = route_options[index].duplicate(true)
	route_options.clear()
	phase = "prepare"
	return true

func retreat() -> bool:
	if phase not in ["prepare","travel","craft","reward","route"]: return false
	phase = "retreated"
	return true
