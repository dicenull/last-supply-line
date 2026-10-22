extends SceneTree
const Gear = preload("res://scripts/equipment_catalog.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment catalog: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	var counts = {"normal":0,"uncommon":0,"rare":0,"legendary":0}
	var kinds = {}
	for i in range(10000):
		var item = Gear.roll(73519,i,i%16)
		counts[item.rarity] += 1
		kinds[item.kind] = true
	check(kinds.size() == 17,"every equipment family is reachable across enemy roles")
	for rarity in counts:
		check(absf(counts[rarity]/10000.0-Gear.RARITIES[rarity].weight/100.0) < 0.015,"rarity distribution follows configured weight: "+rarity)
	for role in range(16):
		var allowed = Gear.DROP_TABLES[Gear.ROLE_TABLES[role]].map(func(row): return row[0])
		var valid = true
		for i in range(100):
			var item = Gear.roll(42,i,role)
			valid = valid and item.kind in allowed and item == Gear.roll(42,i,role)
		check(valid,"enemy role uses a deterministic isolated table: "+str(role))
	var boss_valid = true
	for i in range(1000): boss_valid = boss_valid and Gear.roll(42,i,0,true).rarity != "normal"
	check(boss_valid,"boss loot cannot be normal quality")
	for id in Gear.DEFINITIONS:
		var previous = {"scrap":0,"coal":0}
		var increasing = true
		for rarity in Gear.RARITIES:
			var item = {"kind":id,"rarity":rarity}
			var material = Gear.salvage(item)
			increasing = increasing and Gear.valid(item) and material.scrap > previous.scrap and material.coal >= previous.coal
			previous = material
		check(increasing,"all four variants dismantle into increasing value: "+id)
	check(not Gear.valid({}) and not Gear.valid({"kind":"armor","rarity":"unknown"}),"malformed item definitions are rejected")
	print("EQUIPMENT CATALOG RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
