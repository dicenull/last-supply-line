extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS empty loadout: ",label)
	else:
		failures += 1
		push_error(label)
func key(code: int, pressed: bool):
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	root.push_input(event)
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"empty_loadout_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	game.refresh_view()
	var initial = game.checkpoint.snapshot(game)
	check(Inventory.effects(game.expedition) == Inventory.effects_for([]),"registering stock parts does not add performance bonuses")
	var old_stock = initial.duplicate(true)
	old_stock.version = 16
	old_stock.run.gear_items = old_stock.run.gear_items.filter(func(item): return not item.get("stock",false))
	check(game.checkpoint.apply(game,old_stock) and Inventory.vehicle_parts(game.expedition).size() == 4,"old saves register implicit stock parts without removal")
	var migrated = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,migrated) and game.expedition.gear_items.size() == 7,"repeated restore cannot duplicate stock parts")
	var bad_stock = migrated.duplicate(true)
	bad_stock.run.gear_items[0].stock = true
	check(not game.checkpoint.validate(bad_stock),"non-chassis equipment cannot impersonate a stock part")
	for slot in Inventory.Catalog.PART_SLOTS:
		var before = game.expedition.gear_items.size()
		var stock_part: Dictionary = Inventory.vehicle_parts(game.expedition)[slot]
		check(stock_part.get("stock",false),"initial component exists before removal: "+slot)
		check(game.empty_vehicle_slot(slot) and slot in game.expedition.empty_part_slots,"remove standard component: "+slot)
		check(game.expedition.gear_items.size() == before and stock_part.position == Inventory.STOWED,"standard component is retained in storage: "+slot)
		check(not game.empty_vehicle_slot(slot) and game.expedition.gear_items.size() == before,"repeated removal cannot duplicate parts")
	check(not game.world.barrel.visible and not game.battlefield.barrel.visible,"empty main gun has no barrel in either scene")
	check(game.world.track_belts.all(func(n): return not n.visible) and game.world.engine_shell.all(func(n): return not n.visible),"removed tracks and engine expose chassis fittings")
	check(game.world.vehicle_part_visuals.has_node("Empty_engine") and game.world.vehicle_part_visuals.has_node("Empty_gear") and game.world.vehicle_part_visuals.has_node("Empty_cannon"),"empty slots have distinct socket models")
	var empty = game.checkpoint.snapshot(game)
	var b = game.battlefield
	game.factory.fuel = 10
	game.factory.ammo = 5
	b.motion.command = Vector3.RIGHT
	var pose = b.player.transform
	b.move_player(game.factory,0.1)
	check(b.player.transform == pose and game.factory.fuel == 10 and game.vehicle_parameters().speed == "0.00 m/s","missing drivetrain cannot move or consume fuel")
	for enemy in b.enemies: enemy.hp = 0
	var enemy = b.enemies[0]
	enemy.hp = 1
	enemy.active = true
	enemy.node.position = Vector3(28,0,0)
	b.cooldown = 0
	b.turret.rotation.y = 0
	b.update_gun(game.factory,0.1)
	check(b.projectiles.is_empty() and game.factory.ammo == 5,"empty main gun cannot fire or consume ammunition")
	check(game.checkpoint.validate(empty) and game.checkpoint.apply(game,empty) and game.expedition.empty_part_slots.size() == 4 and not game.world.barrel.visible,"empty loadout survives save and restore")
	for slot in Inventory.Catalog.PART_SLOTS:
		var item = game.expedition.gear_items.filter(func(i): return i.kind == "vehicle_"+slot)[0]
		check(game.equip_vehicle_part(item.uid) and slot not in game.expedition.empty_part_slots,"stored standard part can be equipped again: "+slot)
	check(game.world.barrel.visible and game.world.track_belts.all(func(n): return n.visible) and game.world.engine_shell.all(func(n): return n.visible),"reequipping restores all visible components")
	var conflict = game.checkpoint.snapshot(game)
	conflict.run.empty_part_slots.append("cannon")
	check(not game.checkpoint.validate(conflict),"save cannot mark an equipped slot empty")
	var duplicate = empty.duplicate(true)
	duplicate.run.empty_part_slots.append("engine")
	check(not game.checkpoint.validate(duplicate),"save rejects duplicate empty slots")
	var legacy = initial.duplicate(true)
	legacy.version = 12
	legacy.run.erase("empty_part_slots")
	legacy.view.erase("camera_offset")
	check(game.checkpoint.apply(game,legacy) and game.expedition.empty_part_slots.is_empty() and game.world.barrel.visible,"old saves retain their original standard equipment")
	var camera = game.world.camera.position
	key(KEY_W,true)
	game._process(0.1)
	key(KEY_W,false)
	check(game.world.camera.position != camera and game.world.camera_offset.length() > 0 and game.battlefield.motion.command == Vector3.ZERO,"W pans construction camera without commanding the tank")
	var offset = game.world.camera_offset
	game._process(0.1)
	check(game.world.camera_offset == offset,"releasing movement stops camera pan")
	game.open_menu(false)
	key(KEY_D,true)
	game._process(0.1)
	key(KEY_D,false)
	check(game.world.camera_offset == offset,"menu input does not move the camera")
	game.close_menu()
	var camera_save = game.checkpoint.snapshot(game)
	game.reset_camera()
	check(game.world.camera_offset == Vector3.ZERO and game.checkpoint.apply(game,camera_save) and game.world.camera_offset == offset,"camera reset and save restore work with pan")
	game.toggle_running()
	key(KEY_W,true)
	check(game.battlefield.motion.command.x > 0,"W still drives the tank in battlefield view")
	game.toggle_battle()
	check(game.battlefield.motion.command == Vector3.ZERO and game.movement_keys.is_empty(),"switching to construction clears held driving input")
	key(KEY_D,true)
	game._process(0.1)
	key(KEY_D,false)
	check(game.world.camera_offset != offset and game.battlefield.motion.command == Vector3.ZERO,"construction camera pans during a live battle without driving")
	check(not game.empty_vehicle_slot("cannon"),"departure still locks equipment removal")
	game.free()
	Fixture.clean("empty_loadout_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
