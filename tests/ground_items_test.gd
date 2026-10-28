extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Models = preload("res://scripts/item_model.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS ground items: ",label)
	else:
		failures += 1
		push_error(label)
func model_signature(node: Node) -> String:
	var parts: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh = child.mesh
			parts.append([child.transform,mesh.get_class(),mesh.get_aabb(),child.material_override.albedo_color])
		if child is Node3D and not child is MeshInstance3D: parts.append([child.transform,model_signature(child)])
	return str(parts)
func run():
	var builder = Models.new()
	var signatures: Dictionary = {}
	for kind in Models.Catalog.DEFINITIONS:
		var model = builder.build(kind)
		check(model.get_child_count() > 3 and model.get_meta("kind") == kind,"catalog model: "+kind)
		signatures[model_signature(model)] = true
		model.free()
	check(signatures.size() == Models.Catalog.DEFINITIONS.size(),"all 300 models have distinct geometry or markings")
	for rarity in Models.Catalog.RARITIES:
		var drop = Node3D.new()
		var model = builder.build("arc_gun",rarity)
		drop.add_child(model)
		var original = model_signature(model)
		builder.decorate_drop(drop,model,rarity)
		var marker = drop.get_node("RarityRing")
		check(marker.material_override.albedo_color == Color(Models.Catalog.RARITIES[rarity].color) and marker.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and model_signature(model) == original,"field marker conveys rarity without repainting the model: "+rarity)
		var preview = builder.build("arc_gun",rarity)
		check(model_signature(preview) == original,"field tint cannot leak into shared preview materials: "+rarity)
		preview.free()
		drop.free()
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"ground_items_test",2)
	game.expedition = preload("res://scripts/run_state.gd").new(42)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	# Enlarged production machines remain inside one cell at every rotation.
	for kind in ["armor_block","source","coal_source","furnace","press","refinery","engine","depot","gun"]+game.factory.Content.BLOCKS.keys():
		var machine = Node3D.new()
		game.world.machine(kind,machine,[1,2,3])
		var fits = true
		for direction in range(4):
			for point in Models.vertices(machine,Transform3D(Basis(Vector3.UP,direction*PI/2),Vector3.ZERO)):
				fits = fits and absf(point.x) <= 0.501 and absf(point.z) <= 0.501
		check(fits,"large machine and real couplings fit the cell in all orientations: "+kind)
		machine.free()
	for kind in ["scrap","coal","steel","fuel","shell"]:
		var resource = builder.build(kind)
		check(Models.vertices(resource).size() > 0,"recognizable resource model: "+kind)
		resource.free()
		var storage = game.factory.get_script().new(1)
		var cell = storage.make_cell("depot",0)
		cell.items = [kind,kind,kind,kind,kind,kind,kind,kind]
		storage.cells[Vector2i(6,4)] = cell
		var frames = game.world.item_frames(storage)
		var boxes: Array[AABB] = []
		var separated = true
		var good = game.world.make_good(kind)
		for frame in frames:
			var points = Models.vertices(good,Transform3D(Basis.IDENTITY.scaled(good.scale*frame.scale),frame.pos))
			var bounds = AABB(points[0],Vector3.ZERO)
			for point in points: bounds = bounds.expand(point)
			for other in boxes: separated = separated and not bounds.intersects(other)
			boxes.append(bounds)
		check(separated and boxes.size() == 8,"full storage keeps all eight enlarged resources separate: "+kind)
		good.free()
	game.toggle_running()
	var b = game.battlefield
	for site in b.resource_sites:
		site.taken = true
		site.node.set_taken(true)
	var count = game.expedition.gear_items.size()
	var stock = game.factory.reserves.duplicate()
	var enemy = b.enemies[0]
	enemy.node.position = Vector3(40,0,20)
	b.kill_enemy(enemy,game.factory,enemy.node.position)
	check(b.ground_items.size() == 2 and b.ground_items[0].position == enemy.node.position and game.factory.reserves == stock,"enemy drops at its actual position without remote collection")
	check(b.ground_items[1].item == {"kind":"coal","amount":1} and b.ground_items[1].position.distance_to(enemy.node.position) <= 5,"ordinary enemies drop one physical coal beside their scrap")
	b.kill_enemy(enemy,game.factory,enemy.node.position)
	check(b.ground_items.size() == 2,"repeated defeat cannot duplicate scrap or coal")
	b.drop_item({"kind":"arc_gun","rarity":"legendary"},Vector3(60,0,-20))
	b.drive_poses = [{"position":Vector3.ZERO,"yaw":0.0}]
	b.update_ground_items(game.factory)
	check(b.ground_items.size() == 3 and game.expedition.gear_items.size() == count and game.factory.reserves == stock,"distant drops stay uncollected")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved),"uncollected loot is a valid checkpoint: "+game.checkpoint.error)
	var bad = saved.duplicate(true)
	bad.battle.ground_items[0].item.amount = -1
	check(not game.checkpoint.validate(bad),"negative ground material rejected")
	bad = saved.duplicate(true)
	bad.battle.ground_items[2].item.kind = "missing"
	check(not game.checkpoint.validate(bad),"unknown ground equipment rejected")
	bad = saved.duplicate(true)
	bad.battle.ground_items[2].position = "invalid"
	check(not game.checkpoint.validate(bad),"invalid ground position rejected")
	check(game.checkpoint.apply(game,saved),"checkpoint restores pending drops")
	b = game.battlefield
	check(b.ground_item_snapshot() == saved.battle.ground_items and game.loot_feed.entries.is_empty(),"reload preserves positions and quality without awarding or replaying receipts")
	check(b.ground_items[2].node.get_node("RarityRing").material_override.albedo_color == Color(Models.Catalog.RARITIES.legendary.color),"reload recreates the saved rarity color")
	b.player.position = Vector3(60,0,-20)
	game.factory.running = false
	b.tick_battle(game.factory,1)
	check(b.ground_items.size() == 3 and game.expedition.gear_items.size() == count,"paused simulation cannot collect nearby loot")
	game.factory.running = true
	b.movement_direction = Vector3.ZERO
	b.tick_battle(game.factory,0)
	check(b.ground_items.size() == 2 and game.expedition.gear_items.size() == count+1 and game.expedition.gear_items.back().kind == "arc_gun" and game.expedition.gear_items.back().rarity == "legendary","real proximity tick collects the exact equipment once")
	b.tick_battle(game.factory,0)
	check(game.expedition.gear_items.size() == count+1,"standing still cannot duplicate a collected item")
	b.drive_poses = [{"position":Vector3(20,0,20),"yaw":0.0},{"position":Vector3(60,0,20),"yaw":0.0}]
	b.update_ground_items(game.factory)
	check(b.ground_items.is_empty() and game.factory.reserves.scrap == stock.scrap+2 and game.factory.reserves.coal == stock.coal+1,"swept movement collects materials even if both endpoints are outside the radius")
	var collected = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,collected) and game.battlefield.ground_items.is_empty() and game.factory.reserves.scrap == stock.scrap+2 and game.factory.reserves.coal == stock.coal+1,"collected loot remains gone after reload")
	var old = saved.duplicate(true)
	old.battle.erase("ground_items")
	check(game.checkpoint.apply(game,old) and game.battlefield.ground_items.is_empty(),"older checkpoints load without regenerating already awarded loot")
	b = game.battlefield
	b.sector_config.encounter = "rich"
	b.resource_sites[0].taken = false
	b.resource_sites[0].node.set_taken(false)
	b.player.position = b.resource_sites[0].node.position
	b.movement_direction = Vector3.ZERO
	game.factory.running = true
	b.tick_battle(game.factory,0)
	check(b.resource_sites[0].taken and b.ground_items.size() == 6 and game.expedition.gear_items.size() == count,"rich supply opens into six physical drops")
	b.tick_battle(game.factory,0)
	check(b.ground_items.is_empty() and game.expedition.gear_items.size() == count+6,"nearby supply drops are collected on the next tick")
	b.tick_battle(game.factory,0)
	check(game.expedition.gear_items.size() == count+6,"opened supply cannot drop twice")
	b.drop_item({"kind":"armor","rarity":"rare"},Vector3(80,0,0))
	game.reset_battle(42)
	game.ensure_battle()
	check(game.battlefield.ground_items.is_empty(),"new expedition clears old field loot")
	game.queue_free()
	await process_frame
	Fixture.clean("ground_items_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
