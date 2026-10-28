extends SceneTree
const Params = preload("res://scripts/vehicle_parameters.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS parameters: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	var run = Run.new(42)
	run.enable_items()
	var factory = Factory.new(2)
	var names = {}
	for kind in Inventory.Catalog.Data.ITEMS:
		var spec: Dictionary = Inventory.Catalog.Data.ITEMS[kind]
		check(not spec.name.is_empty() and not names.has(spec.name),"unique visible name: "+kind)
		names[spec.name] = true
		if Inventory.Catalog.part_slot(kind).is_empty(): continue
		for rarity in Inventory.Catalog.RARITIES:
			var uid = run.add_item({"kind":kind,"rarity":rarity})
			var before = run.gear_items.duplicate(true)
			var empty_before = run.empty_part_slots.duplicate()
			var preview = Params.compare(run,factory,uid)
			check(before == run.gear_items and empty_before == run.empty_part_slots,"selection does not mutate inventory")
			check(Inventory.equip_part(run,factory,uid),"perform projected swap")
			var actual = Params.compare(run,factory)
			var matches = true
			for key in Params.METRICS:
				matches = matches and is_equal_approx(preview.rows[key].after,actual.rows[key].current)
				matches = matches and is_equal_approx(preview.rows[key].bonus,preview.rows[key].current-preview.rows[key].base)
			check(matches,"prediction equals actual swap, including rarity: "+kind+" "+rarity)
			var selected_equipped = Params.compare(run,factory,uid)
			check(selected_equipped.rows.values().all(func(row): return is_zero_approx(row.change)),"equipped selection has zero change")
	for slot in Inventory.Catalog.PART_SLOTS:
		check(Inventory.empty_slot(run,factory,slot),"remove "+slot)
	var empty = Params.compare(run,factory)
	check(empty.rows.speed.current == 0 and empty.rows.reload.current == null and empty.rows.range.current == null,"missing drive and gun are represented as unavailable")
	var cannon = run.add_item({"kind":"vehicle_cannon_long","rarity":"rare"})
	var restored = Params.compare(run,factory,cannon)
	check(restored.rows.reload.change == null and restored.rows.reload.after > 0 and Params.benefit("reload",restored.rows.reload.after,null) == 1,"gun restoration has a meaningful availability transition")
	check(Params.benefit("fuel",0.5,1.0) == 1 and Params.benefit("reload",3,2) == -1 and Params.benefit("speed",5,4) == 1,"lower operating costs and faster movement have the correct benefit sign")
	check(Params.number("fuel",-0.000001,true) == "0.000" and Params.number("speed",1.25,true) == "+1.25" and Params.number("reload",null) == "—","signed formatting handles precision and unavailable values")
	# Accessories replace their family in the projection, not add a second bonus.
	run.empty_part_slots.clear()
	run.gear_items.clear()
	var armor = run.add_item({"kind":"armor","rarity":"normal"})
	check(Inventory.place(run,factory,armor,Vector2i.ZERO),"mount existing armor")
	var replacement = run.add_item({"kind":"armor_heavy_l10","rarity":"legendary"})
	var projected = Params.compare(run,factory,replacement,Vector2i.ZERO)
	check(Inventory.stow(run,factory,armor) and Inventory.place(run,factory,replacement,Vector2i.ZERO),"perform family replacement")
	var actual = Params.compare(run,factory)
	check(projected.rows.damage.after == actual.rows.damage.current and projected.rows.speed.after == actual.rows.speed.current,"accessory projection replaces the old family and includes tradeoffs")
	run.modifiers.speed = 1.2
	run.modifiers.fuel = 0.8
	var modified = Params.compare(run,factory)
	check(is_equal_approx(modified.rows.speed.base,actual.rows.speed.base*1.2) and is_equal_approx(modified.rows.fuel.base,actual.rows.fuel.base*0.8),"baseline retains course and permanent modifiers")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
