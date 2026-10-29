extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Gear = preload("res://scripts/equipment_catalog.gd")
const Models = preload("res://scripts/item_model.gd")
const Transmission = preload("res://scripts/battle_transmission.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS historical parts: ",label)
	else:
		failures += 1
		push_error(label)
func geometry(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D: result.append([node.transform,node.mesh.get_class(),node.mesh.get_aabb()])
	for child in node.get_children(): result.append_array(geometry(child))
	return result
func run():
	var ids = Gear.Data.ACTIVE_IDS.filter(func(id): return Gear.Data.ITEMS[id].has("historical_model"))
	var countries = {}
	var eras = {}
	var shapes = []
	var performance = []
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"historical_parts_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	for id in ids:
		var spec = Gear.Data.ITEMS[id]
		countries[spec.country] = true
		eras[spec.era] = true
		check(spec.sources.size() > 0 and spec.sources[0].begins_with("https://") and spec.base_rarity in Gear.RARITIES and spec.shop_price <= game.factory.reserve_capacity,"source and assigned rarity: "+id)
		var model = Models.new().build(id,spec.base_rarity)
		var shape = geometry(model)
		check(shape not in shapes and shape.size() > 10 and model.has_node("QualityUpgrade/RarityAccent"),"unique mechanical geometry and limited rarity accent: "+id)
		shapes.append(shape)
		model.free()
		var effect = str(spec.effects)+str(spec.get("damage",0))
		check(effect not in performance and (spec.effects.values().any(func(v): return v < 0) or spec.effects.get("fuel_bonus",0) > 0),"distinct performance with an operating tradeoff: "+id)
		performance.append(effect)
		var uid = game.expedition.add_item({"kind":id,"rarity":spec.base_rarity})
		check(game.equip_vehicle_part(uid) and game.world.vehicle_parts[spec.slot].kind == id and game.battlefield.vehicle_parts[spec.slot].kind == id,"swap reflects in interior and battlefield: "+id)
		if spec.slot == "cannon":
			var fitted = game.world.vehicle_part_visuals.get_node("CannonFittings/Item_"+id)
			check(fitted.get_meta("historical_model") == spec.historical_model and is_equal_approx(game.world.muzzle.position.x,spec.barrel_length*2.2+0.12),"fitted historical barrel and muzzle use the actual gun shape")
		elif spec.slot == "tracks":
			check(game.world.stock_track_visuals.all(func(node): return not node.visible) and game.world.vehicle_part_visuals.has_node("HistoricalTrack-1"),"historical running gear replaces the original track silhouette")
		elif spec.slot == "gear":
			var gearbox = Transmission.new()
			gearbox.configure(id)
			var stages = [1]
			for frame in range(1200):
				gearbox.travel(1,1.0/60,true)
				if stages.back() != gearbox.gear: stages.append(gearbox.gear)
			check(stages.size() == spec.transmission.ratios.size() and Transmission.valid(gearbox.snapshot()),"historical gearbox sequentially shifts through every installed ratio")
	check(ids.size() == 12 and countries.size() == 6 and eras.size() == 2,"twelve distinct parts cover six countries and both world wars")
	var found = {}
	var respects_rarity = true
	for i in range(8000):
		var item = Gear.roll(42,i,i%16,true,10)
		if item.kind in ids:
			found[item.kind] = true
			respects_rarity = respects_rarity and Gear.quality(item.kind,item.rarity) == item.rarity
	check(found.size() == ids.size() and respects_rarity,"every historical part is reachable as loot at or above its assigned rarity")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"all new identities and fitted models survive save/load")
	DirAccess.make_dir_recursive_absolute("res://build/historical-parts")
	check(game.checkpoint.write_file("res://build/historical-parts/web-fixture.mfv",game.checkpoint.snapshot(game)),"historical loadout fixture validates for browser inspection")
	game.free()
	Fixture.clean("historical_parts_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
