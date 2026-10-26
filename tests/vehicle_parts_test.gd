extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS vehicle parts: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"vehicle_parts_test",2)
	game.expedition = preload("res://scripts/run_state.gd").new(42)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	var factory = game.factory
	factory.fuel = 8
	factory.ammo = 7
	var deck = factory.equipment_mounts.duplicate()
	var cells = factory.cells.duplicate(true)
	for kind in Gear.DEFINITIONS:
		var slot = Gear.part_slot(kind)
		if slot.is_empty(): continue
		for rarity in Gear.RARITIES:
			var previous: Dictionary = Inventory.vehicle_parts(game.expedition).get(slot,{})
			var uid = game.expedition.add_item({"kind":kind,"rarity":rarity})
			check(game.equip_vehicle_part(uid) and Inventory.vehicle_parts(game.expedition)[slot].uid == uid and (previous.is_empty() or previous.position == Inventory.STOWED),"atomic swap retains the old item: "+kind+" "+rarity)
			check(factory.cells == cells and factory.equipment_mounts == deck and factory.ammo == 7 and factory.fuel == 8,"swap preserves deck, ammunition and fuel")
			check(not game.dismantle_item(uid) and not Inventory.can_place(game.expedition,factory,uid,Vector2i.ZERO),"installed component cannot be salvaged or placed on the deck")
		check(game.world.vehicle_parts[slot].kind == kind and game.battlefield.vehicle_parts[slot].kind == kind,"interior and battlefield use the same equipped model")
		if slot in ["gear","engine"]:
			var model = game.world.vehicle_part_visuals.get_node("Item_"+kind)
			var clear = true
			for point in game.world.EquipmentModels.vertices(model): clear = clear and (model.transform*point).x <= -6.999
			check(clear,"rear chassis component cannot overlap deck reservations: "+kind)
		if slot == "cannon":
			var clear = true
			for point in game.battlefield.EquipmentModels.vertices(game.battlefield.barrel):
				clear = clear and game.battlefield.barrel.to_global(point).y > 5.43
			check(clear,"main barrel stays above the enlarged secondary weapons: "+kind)
	var selected = {"gear":"vehicle_gear_torque","engine":"vehicle_engine_power","tracks":"vehicle_tracks_wide","cannon":"vehicle_cannon_long"}
	for kind in selected.values():
		var uid = game.expedition.add_item({"kind":kind,"rarity":"rare"})
		check(game.equip_vehicle_part(uid),"equip a complete differentiated chassis: "+kind)
	var effects = Inventory.effects(game.expedition)
	check(effects.speed > 1 and effects.drive_turn > 1 and effects.offroad > 0 and effects.main_range == 15 and effects.main_reload > 1,"part quality changes the intended independent performance axes")
	game.battlefield.turret.rotation.y = 0.7
	game.battlefield.recoil = 0.4
	game.battlefield.update_gun(game.factory,0.0)
	check(game.battlefield.vehicle_part_visuals.get_node("CannonFittings").global_transform.is_equal_approx(game.battlefield.barrel.global_transform),"equipped cannon fittings follow turret aiming and recoil")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved),"complete chassis validates: "+game.checkpoint.error)
	check(game.checkpoint.apply(game,saved) and Inventory.vehicle_parts(game.expedition).size() == 4,"save round trip retains all four slots")
	var bad = saved.duplicate(true)
	for item in bad.run.gear_items:
		if item.kind == "vehicle_engine" and item.position == Inventory.STOWED:
			item.position = Gear.part_position(item.kind)
			break
	check(not game.checkpoint.validate(bad),"duplicate engines are rejected before restore")
	bad = saved.duplicate(true)
	for item in bad.run.gear_items:
		if item.position == Gear.part_position("vehicle_cannon"):
			item.position = Gear.part_position("vehicle_tracks")
			break
	check(not game.checkpoint.validate(bad),"part cannot occupy a different dedicated slot")
	var legacy = saved.duplicate(true)
	legacy.run.gear_items = legacy.run.gear_items.filter(func(item): return Gear.part_slot(item.kind).is_empty())
	check(game.checkpoint.apply(game,legacy) and Inventory.vehicle_parts(game.expedition).is_empty() and game.world.barrel.scale == game.world.MAIN_BARREL_SCALE,"old saves without replaceable parts use the standard chassis")
	check(game.checkpoint.apply(game,saved),"return to upgraded chassis")
	var engine = game.world.vehicle_part_visuals.get_node("Item_vehicle_engine_power")
	var screen_position = game.WORLD_RECT.position+game.world.camera.unproject_position(engine.to_global(Vector3(0,0.5,0)))
	check(game.stow_at_screen(game.get_canvas_transform()*screen_position) and not Inventory.vehicle_parts(game.expedition).has("engine"),"right-click on the physical engine returns that part to storage")
	check(game.checkpoint.apply(game,saved),"restore chassis after right-click storage")
	factory = game.factory
	var b = game.battlefield
	var terrain = b.field_course
	var barriers = b.obstacles.barriers
	b.field_course = null
	b.obstacles.barriers = []
	b.player.position = Vector3.ZERO
	b.motion.command = Vector3.RIGHT
	b.move_player(factory,0.1)
	check(is_equal_approx(b.player.position.x,0.33*effects.speed),"engine power affects actual travel")
	b.motion.command = Vector3.BACK
	b.move_player(factory,0.1)
	check(is_equal_approx(b.player.rotation.y,-b.TURN_SPEED*0.1*effects.speed*effects.drive_turn),"gear ratio affects actual hull turning")
	b.field_course = terrain
	b.player.position = Vector3(40,0,terrain.bounds.position.y+5)
	b.player.rotation.y = 0
	b.motion.command = Vector3.RIGHT
	var offroad_start: Vector3 = b.player.position
	b.move_player(factory,0.1)
	check(terrain.road_distance(offroad_start) > b.FieldCourse.ROAD_HALF_WIDTH and absf(b.player.position.x-offroad_start.x-0.33*effects.speed*minf(1,0.65+effects.offroad)) < 0.00001,"wide tracks reduce the real off-road movement penalty: road_distance=%.3f, travel=%.6f, expected=%.6f" % [terrain.road_distance(offroad_start),b.player.position.x-offroad_start.x,0.33*effects.speed*minf(1,0.65+effects.offroad)])
	b.obstacles.barriers = barriers
	b.player.position = Vector3.ZERO
	b.player.rotation.y = 0
	b.update_camera()
	for enemy in b.enemies:
		enemy.hp = 0
		enemy.active = true
	var target = b.enemies[0]
	target.hp = 1
	target.node.position = Vector3(28,0,0)
	b.turret.rotation.y = 0
	b.cooldown = 0
	factory.ammo = 3
	b.update_gun(factory,0.001)
	check(b.projectiles.size() == 1 and b.projectiles[0].style == "sniper" and factory.ammo == 2,"replacement main gun fires its own projectile and consumes existing ammo")
	if not b.projectiles.is_empty():
		var shot = b.projectiles[0]
		check(is_equal_approx(shot.duration,b.shell_flight_time(shot.origin,target.node.position+Vector3(0,1.3,0),"sniper")),"main gun flight uses the replaced cannon's ballistics")
	check(is_equal_approx(b.cooldown,60.0/factory.rate*effects.main_reload*effects.reload),"cannon reload tradeoff changes actual firing interval")
	check(game.checkpoint.apply(game,saved),"restore before pickup and UI checks")
	b = game.battlefield
	factory = game.factory
	var count = game.expedition.gear_items.size()
	b.drop_item({"kind":"vehicle_engine_efficient","rarity":"legendary"},Vector3(30,0,0))
	b.motion.poses = [{"position":Vector3(30,0,0),"yaw":0}]
	b.update_ground_items(factory)
	check(game.expedition.gear_items.size() == count+1 and game.expedition.gear_items.back().kind == "vehicle_engine_efficient","physical field pickup puts a replacement part in inventory")
	game.inventory_panel.genre = "gear"
	game.inventory_panel.quality_order = false
	game.inventory_panel.show()
	game.inventory_panel.refresh()
	var panel = game.inventory_panel
	var uid: int = panel.rows[0].uid
	panel.stow_buttons[0].button_down.emit()
	panel.stow_buttons[0].pressed.emit()
	check(Inventory.vehicle_parts(game.expedition).gear.uid == uid,"inventory swap button installs the item originally pressed")
	var right_click = InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	panel.row_buttons[0].gui_input.emit(right_click)
	check(not Inventory.vehicle_parts(game.expedition).has("gear") and Inventory.find_item(game.expedition,uid).position == Inventory.STOWED,"right-clicking an installed part row restores the standard component and retains the item")
	game.toggle_running()
	factory.running = false
	check(not game.equip_vehicle_part(uid) and not game.stow_item(Inventory.vehicle_parts(game.expedition).engine.uid),"deployment locks core swaps even while paused")
	if DisplayServer.get_name() != "headless":
		game.checkpoint.apply(game,saved)
		b = game.battlefield
		if not game.battle_mode: game.toggle_battle()
		game.inventory_panel.genre = "gear"
		DirAccess.make_dir_recursive_absolute("res://build/vehicle-parts")
		for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
			root.size = dimensions
			game.inventory_panel.show()
			game.inventory_panel.refresh()
			game._process(0)
			await process_frame
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png("res://build/vehicle-parts/inventory-"+str(dimensions.x)+".png")
		game.inventory_panel.hide()
		root.size = Vector2i(1440,940)
		game._process(0)
		b.camera.position -= Vector3(14,0,0)
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://build/vehicle-parts/chassis.png")
	game.queue_free()
	await process_frame
	Fixture.clean("vehicle_parts_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
