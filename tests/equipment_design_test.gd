extends SceneTree
const Data = preload("res://scripts/equipment_data.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment design: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	check(Data.ITEMS.size() == 300 and Data.DEFINITIONS.size() == 300,"300 base designs exist independently of rarity")
	var names = {}
	var signatures = {}
	var genres = {"secondary":0,"protection":0,"engine":0,"support":0}
	var levels = {}
	var groups = {}
	var shape_valid = true
	var finite_stats = true
	for id in Data.ITEMS:
		var item = Data.ITEMS[id]
		names[item.name] = true
		var stats = {}
		for key in ["interval","range","ammo","turn","splash","chain","pellets","ballistics","effects"]:
			if item.has(key): stats[key] = item[key]
		signatures[JSON.stringify(stats)] = true
		genres[item.genre] += 1
		levels[item.level] = true
		var key = item.family+":"+item.profile
		if not groups.has(key): groups[key] = []
		groups[key].append(item)
		var footprint: Vector2i = Data.DEFINITIONS[id].size
		shape_valid = shape_valid and footprint == Vector2i(item.size[0],item.size[1]) and footprint.x >= 1 and footprint.x <= 2 and footprint.y >= 1 and footprint.y <= 2
		finite_stats = finite_stats and item.level >= 1 and item.level <= 10 and item.shop_price >= 32 and item.scrap > 0 and item.coal > 0
		for value in item.effects.values(): finite_stats = finite_stats and is_finite(value)
	check(names.size() == 300 and signatures.size() == 300,"every name and actual performance vector is distinct")
	check(genres == {"secondary":120,"protection":60,"engine":60,"support":60},"all four equipment genres receive the planned number of designs")
	check(levels.size() == 10 and shape_valid and finite_stats,"level 1–10 designs have finite stats, prices and reserved footprints")
	check(Data.GUNS.size() == 120 and Data.GUN_PORTS.size() == 120,"every new weapon has a feed definition")
	var old_ids = true
	for id in Data.ORIGINAL_IDS:
		old_ids = old_ids and Data.ITEMS.has(id) and Data.ITEMS[id].family == id and Data.ITEMS[id].level == 1 and Data.ITEMS[id].profile == "balanced"
	check(old_ids and Data.ORIGINAL_IDS.size() == 17,"all original save IDs remain baseline designs")
	var progression = true
	var budgets = true
	for key in groups:
		var rows: Array = groups[key]
		for index in range(1,rows.size()):
			var before = rows[index-1]
			var after = rows[index]
			progression = progression and after.level > before.level and after.shop_price > before.shop_price and after.scrap >= before.scrap
			if after.genre == "secondary":
				progression = progression and after.interval < before.interval and after.range > before.range and after.turn > before.turn
			else:
				var primary = after.effects.keys()[0]
				progression = progression and absf(after.effects[primary]) > absf(before.effects[primary])
		var first = rows[0]
		var last = rows.back()
		if first.genre == "secondary":
			budgets = budgets and first.interval/last.interval <= 1.23 and last.range/first.range <= 1.10
		else:
			var primary = first.effects.keys()[0]
			budgets = budgets and absf(last.effects[primary]/first.effects[primary]) <= 1.23
	check(progression,"levels improve their primary effect and increase acquisition cost in every progression branch")
	check(budgets,"level scaling stays inside a 23 percent primary-stat budget before rarity")
	var tradeoffs = true
	for id in Data.ITEMS:
		var item = Data.ITEMS[id]
		if item.profile == "balanced": continue
		var base_id = item.family if item.level == 1 else item.family+"_balanced_l%02d" % item.level
		var base = Data.ITEMS[base_id]
		if item.genre == "secondary":
			tradeoffs = tradeoffs and ((item.range > base.range and item.interval > base.interval) or (item.interval < base.interval and item.range < base.range))
		elif item.genre == "protection":
			tradeoffs = tradeoffs and ((item.effects.damage_reduction > base.effects.damage_reduction and item.effects.speed_bonus < 0) or (item.effects.damage_reduction < base.effects.damage_reduction and item.effects.speed_bonus > 0))
		else:
			tradeoffs = tradeoffs and item.effects.size() >= 2 and item.effects != base.effects
	check(tradeoffs,"specializations exchange real benefits and costs instead of renaming identical equipment")
	print("EQUIPMENT DESIGN RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
