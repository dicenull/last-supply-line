extends SceneTree
const Data = preload("res://scripts/equipment_data.gd")
const Catalog = preload("res://scripts/equipment_catalog.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment design: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	check(Data.ITEMS.size() == 312 and Data.DEFINITIONS.size() == 312,"all historical item IDs remain loadable")
	check(Data.ACTIVE_IDS.size() == 28 and not "right_gun" in Data.ACTIVE_IDS,"sixteen distinct accessories and twelve chassis parts")
	var families = {}
	var names = {}
	for id in Data.ACTIVE_IDS:
		var item = Data.ITEMS[id]
		check(not names.has(item.name) and not item.name.is_empty(),"distinct current name: "+id)
		names[item.name] = true
		if Catalog.part_slot(id).is_empty():
			check(not families.has(item.family),"one current design per accessory family: "+id)
			families[item.family] = true
		var spec = Catalog.effect_values({"kind":id,"rarity":"normal"})
		var rare = Catalog.effect_values({"kind":id,"rarity":"legendary"})
		for key in spec:
			if key in ["ammo_tax","shot_fuel"] or (key == "fuel_bonus" and spec[key] > 0) or (key != "fuel_bonus" and spec[key] < 0):
				check(is_equal_approx(spec[key],rare[key]),"rarity does not erase the operating cost: "+id+" "+key)
	check(Data.ITEMS.rear_gun.get("interceptor",false) and not Data.ITEMS.left_gun.get("interceptor",false),"interception and direct fire have different jobs")
	check(Data.ITEMS.skirts.effects.has("blast_reduction") and not Data.ITEMS.skirts.effects.has("damage_reduction"),"blast screens differ from universal armour")
	check(Data.ITEMS.vehicle_cannon_long.damage == 4 and Data.ITEMS.vehicle_cannon_long.ammo == 2 and Data.ITEMS.vehicle_cannon_howitzer.ammo == 3,"main guns exchange ammo consumption for anti-armour or area power")
	check(Catalog.models(10).size() == 28 and Catalog.models(1).size() == 28,"levels never reintroduce minor variants")
	print("EQUIPMENT DESIGN RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
