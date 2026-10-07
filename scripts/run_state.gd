extends RefCounted
## Seeded five-sector expedition. No rendering or file IO.
const SECTORS = 5
const ROUTES = ["scrapyard","coalfield","arsenal"]
var run_seed = 1
var sector = 1
var phase = "prepare"
var hull = 100
var cleared = 0
var rewards_taken = 0
var modifiers = {"work":1.0,"fuel":1.0,"magazine":12}
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
	return {"kind":kind,"seed":int(rng.randi()),"sector":sector,"length":100.0+(sector-1)*8.0,
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
	return true

func choose_reward(index: int) -> bool:
	if phase != "reward" or index < 0 or index >= reward_options.size(): return false
	match reward_options[index]:
		"production": modifiers.work = maxf(0.4,modifiers.work*0.85)
		"economy": modifiers.fuel = maxf(0.4,modifiers.fuel*0.8)
		"magazine": modifiers.magazine += 4
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
