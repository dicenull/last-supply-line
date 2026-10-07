extends RefCounted
## Seeded five-sector expedition. No rendering or file IO.
const SECTORS = 5
const ROUTES = ["scrapyard","coalfield","arsenal"]
const REWARDS = ["production","economy","magazine","autoload","cargo"]
const CONDITIONS = {"road":{"speed":3.3,"fuel":1.0},"mud":{"speed":2.8,"fuel":1.35},"rubble":{"speed":3.0,"fuel":1.15}}
const FORMATIONS = {"patrol":[0,1,2,0,1,2],"raiders":[1,1,0,1,1,0],"battery":[2,0,2,0,2,2]}

static func condition(route: Dictionary) -> Dictionary:
	return CONDITIONS[route.get("terrain","road")]

static func enemy_role(route: Dictionary, index: int) -> int:
	return FORMATIONS[route.get("formation","patrol")][index]

static func enemy_health(route: Dictionary, index: int) -> int:
	var extra = 1 if route.get("formation","patrol") == "battery" and enemy_role(route,index) == 2 else 0
	return int(route.get("enemy_hp",3))+extra+(6 if route.get("boss",false) and index == 5 else 0)

static func total_health(route: Dictionary) -> int:
	var total = 0
	for i in range(6): total += enemy_health(route,i)
	return total
var run_seed = 1
var sector = 1
var phase = "prepare"
var hull = 100
var cleared = 0
var rewards_taken = 0
var modifiers = {"work":1.0,"fuel":1.0,"magazine":12,"reload":1.0,"cargo":100}
var route_options: Array = []
var reward_options: Array = []
var current: Dictionary = {}
var rng = RandomNumberGenerator.new()

func _init(value: int = 1):
	run_seed = value
	rng.seed = value
	current = make_route("scrapyard",true)

func make_route(kind: String, opening: bool = false) -> Dictionary:
	var scrap = 36 if kind == "scrapyard" else 18
	var coal = 30 if kind == "coalfield" else 16
	if kind == "arsenal": scrap = 26
	var route_seed = int(rng.randi())
	var local_rng = RandomNumberGenerator.new()
	local_rng.seed = route_seed
	var terrain = "road" if opening else CONDITIONS.keys()[local_rng.randi_range(0,2)]
	var formation = "patrol" if opening else FORMATIONS.keys()[local_rng.randi_range(0,2)]
	return {"kind":kind,"seed":route_seed,"terrain":terrain,"formation":formation,"sector":sector,"length":100.0+(sector-1)*8.0,
		"scrap":scrap,"coal":coal,"shells":12 if kind == "arsenal" else 0,"enemy_hp":3+(1 if sector >= 3 else 0)+(1 if kind == "arsenal" else 0),
		"damage":10+(sector-1)*2,"attack_period":maxf(5,8-(sector-1)*0.5),
		"boss":sector == SECTORS,"opening":opening}

func start_sector() -> bool:
	if phase != "prepare": return false
	phase = "travel"
	return true

func finish_sector(won: bool, remaining_hull: int) -> bool:
	if phase != "travel": return false
	hull = clampi(remaining_hull,0,100)
	if not won or hull == 0:
		phase = "lost"
		return true
	cleared += 1
	if sector == SECTORS:
		phase = "won"
	else:
		phase = "reward"
		reward_options = ["production","economy","magazine"]
		if cleared > 1:
			var pool = REWARDS.duplicate()
			reward_options.clear()
			for i in range(3):
				var pick = rng.randi_range(0,pool.size()-1)
				reward_options.append(pool.pop_at(pick))
	return true

func choose_reward(index: int) -> bool:
	if phase != "reward" or index < 0 or index >= reward_options.size(): return false
	match reward_options[index]:
		"production": modifiers.work = maxf(0.4,modifiers.work*0.85)
		"economy": modifiers.fuel = maxf(0.4,modifiers.fuel*0.8)
		"magazine": modifiers.magazine += 4
		"autoload": modifiers["reload"] = maxf(0.4,modifiers.get("reload",1.0)*0.8)
		"cargo": modifiers["cargo"] = mini(200,modifiers.get("cargo",100)+25)
	rewards_taken += 1
	reward_options.clear()
	sector += 1
	var first = rng.randi_range(0,2)
	var second = (first+rng.randi_range(1,2))%3
	route_options = [make_route(ROUTES[first]),make_route(ROUTES[second])]
	phase = "route"
	return true

func choose_route(index: int) -> bool:
	if phase != "route" or index < 0 or index >= route_options.size(): return false
	current = route_options[index].duplicate(true)
	route_options.clear()
	phase = "prepare"
	return true

func retreat() -> bool:
	if phase not in ["prepare","travel","reward","route"]: return false
	phase = "retreated"
	return true
