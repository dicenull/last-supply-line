extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS phase movement: ",title)
	else:
		failures += 1
		push_error(title)
func key(code: int, pressed: bool = true):
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event)
	await process_frame
func tap(code: int):
	await key(code)
	await key(code,false)
func click_cell(cell: Vector2i, button: int = MOUSE_BUTTON_LEFT):
	var at = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(cell)+Vector3(0,0.03,0))
	var event = InputEventMouseButton.new()
	event.position = root.get_final_transform()*at
	event.button_index = button
	event.pressed = true
	root.push_input(event,false)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,false)
	await process_frame
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"phase_movement_test")
	game.show_start_menu = false
	# Exercise keys at fixed poses without placing those fixtures inside a barricade.
	game.expedition.current.erase("obstacles_version")
	game.expedition.current.erase("field_version") # Isolate steering from generated field geometry.
	game.expedition.current.erase("encounters_version")
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game._process(0)
	await click_cell(Vector2i(12,7))
	check(game.factory.cells.has(Vector2i(12,7)) and game.can_manage_layout(),"construction accepts real grid placement")
	game.factory.install_auxiliary("left_gun")
	game.expedition.recipes = ["left_gun"]
	game.expedition.equipment = ["left_gun"]
	check(game.move_auxiliary("left_gun",Vector2i(10,0)),"auxiliary output can move during construction")
	await tap(KEY_SPACE)
	var f = game.factory
	var b = game.battlefield
	check(game.expedition.phase == "travel" and not f.layout_locked and game.battle_mode,"departure enters combat with editable line")
	check(not game.tool_buttons.belt.visible and game.start_button.visible,"combat hides construction tools and retains pause")
	f.fuel = 12
	var before = b.player.position
	var ticks = f.ticks
	for i in range(5): game._process(0.1)
	check(b.player.position == before and f.fuel_used == 0 and f.ticks > ticks,"without movement input tank stays still while production continues")
	for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_LEFT,KEY_DOWN,KEY_RIGHT]:
		b.player.position = Vector3(40,0,0)
		b.distance = 40
		b.player.rotation.y = 0
		b.update_camera()
		f.fuel = 12
		before = b.player.position
		var used = f.fuel_used
		await key(code)
		game._process(0.1)
		await key(code,false)
		var straight = code in [KEY_W,KEY_UP,KEY_S,KEY_DOWN]
		if straight:
			var expected = Vector3.RIGHT if code in [KEY_W,KEY_UP] else Vector3.LEFT
			check((b.player.position-before).is_equal_approx(expected*0.33) and is_zero_approx(b.player.rotation.y),"forward/reverse key drives along hull without turning: "+str(code))
			check(is_equal_approx(f.fuel_used-used,b.player.position.distance_to(before)*0.12),"straight travel consumes fuel for actual distance: "+str(code))
		else:
			var turn = 0.12 if code in [KEY_A,KEY_LEFT] else -0.12
			check(b.player.position == before and is_equal_approx(b.player.rotation.y,turn),"steering key pivots in place in the requested direction: "+str(code))
			check(is_equal_approx(f.fuel_used-used,absf(turn)*b.TRACK_HALF_WIDTH*0.12),"opposing tracks consume fuel during stationary pivot: "+str(code))
	b.player.rotation.y = PI
	before = b.player.position
	await key(KEY_W)
	game._process(0.1)
	await key(KEY_W,false)
	var screen_delta = b.camera.unproject_position(b.player.position)-b.camera.unproject_position(before)
	check((b.player.position-before).is_equal_approx(Vector3.LEFT*0.33) and screen_delta.x < 0 and screen_delta.y > 0,"W follows reversed hull heading instead of the original route direction")
	before = b.player.position
	var used = f.fuel_used
	game._process(0.1)
	check(b.player.position == before and f.fuel_used == used,"key release stops movement without fuel drain")
	await key(KEY_W)
	await key(KEY_D)
	before = b.player.position
	game._process(0.1)
	check(b.player.position.distance_to(before) <= 0.33001 and b.player.position.distance_to(before) > 0.32 and not is_equal_approx(absf(b.player.rotation.y),PI),"forward plus steering traces a curve without a diagonal speed bonus")
	await key(KEY_W,false)
	await key(KEY_D,false)
	await key(KEY_A)
	await key(KEY_D)
	before = b.player.position
	game._process(0.1)
	check(b.player.position == before,"opposing movement keys cancel")
	await key(KEY_A,false)
	await key(KEY_D,false)
	await tap(KEY_B)
	game._process(0)
	var layout = f.layout()
	await click_cell(Vector2i(13,7))
	await click_cell(Vector2i(1,2),MOUSE_BUTTON_RIGHT)
	await tap(KEY_F)
	check(f.layout() != layout and not f.layout_locked,"interior permits real placement removal and rotation")
	f.edit(Vector2i(13,7),"belt",0)
	f.rotate(Vector2i(1,2))
	f.clear_layout()
	f.undo()
	check(f.restore(layout),"live layout restore remains available")
	check(game.move_auxiliary("left_gun",Vector2i(11,0)),"combat permits auxiliary relocation")
	f.restore(layout)
	await key(KEY_D)
	before = b.player.position
	var prior_yaw = b.player.rotation.y
	var prior_pan = game.world.camera_offset
	game._process(0.1)
	check(b.player.position == before and b.player.rotation.y == prior_yaw and game.world.camera_offset != prior_pan,"WASD pans the construction camera without pivoting the tank")
	await tap(KEY_SPACE)
	before = b.player.position
	game.paint(Vector2i(13,7),false)
	game._process(0.1)
	check(not f.running and b.player.position == before and f.layout() != layout and not f.layout_locked,"pause freezes combat while allowing construction")
	await key(KEY_D,false)
	await tap(KEY_SPACE)
	game._process(0.1)
	check(b.player.position == before and b.movement_direction == Vector3.ZERO,"resume does not retain an old movement command")
	await key(KEY_D)
	await tap(KEY_ESCAPE)
	game.menu.layout_action("erase")
	check(game.menu.visible and not f.layout_locked and f.layout() != layout,"Esc menu allows live layout management")
	f.restore(layout)
	await key(KEY_D,false)
	await tap(KEY_ESCAPE)
	game._process(0.1)
	check(b.player.position == before and b.movement_direction == Vector3.ZERO,"closing menu does not replay a held movement key")
	await key(KEY_D)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._process(0.1)
	check(b.player.position == before and b.movement_direction == Vector3.ZERO,"losing focus clears movement to avoid a stuck key")
	await key(KEY_D,false)
	await key(KEY_D)
	game._process(0.1)
	var saved = game.checkpoint.snapshot(game)
	before = b.player.position
	check(game.checkpoint.apply(game,saved),"manual position and orientation checkpoint validates and restores")
	b = game.battlefield
	f = game.factory
	check(b.player.position.is_equal_approx(before) and not f.layout_locked and f.combat_editing and not f.running,"restore permits edits and pauses at the saved position")
	await key(KEY_D,false)
	await tap(KEY_SPACE)
	game._process(0.1)
	check(b.player.position.is_equal_approx(before) and b.movement_direction == Vector3.ZERO,"save does not serialize a held movement command")
	f.fuel = 0
	b.movement_direction = Vector3.RIGHT
	b.tick_battle(f,0.1)
	check(b.player.position.is_equal_approx(before),"empty fuel prevents manual movement")
	f.fuel = 12
	b.player.position = Vector3(40,0,0)
	b.distance = 40
	b.player.rotation.y = 0
	b.movement_direction = Vector3.BACK
	b.tick_battle(f,0.1)
	check(is_equal_approx(b.distance,40) and b.player.position.z == 0 and b.player.rotation.y < 0,"stationary pivot does not change route progress")
	b.movement_direction = Vector3.LEFT
	b.tick_battle(f,0.1)
	check(b.distance < 40 and game.destination_text() == "あと%dm" % ceili(b.route_length-b.player.position.x),"reversing updates actual remaining distance")
	b.player.position = Vector3(0,0,b.BATTLE_HALF_WIDTH)
	b.player.rotation.y = 0
	b.movement_direction = Vector3.LEFT
	before = b.player.position
	used = f.fuel_used
	b.tick_battle(f,0.1)
	check(b.player.position == before and f.fuel_used == used,"battlefield boundary blocks excess movement without charging fuel")
	game.battle_mode = true
	game.refresh_view()
	root.size = Vector2i(960,628)
	await process_frame
	game._process(0)
	game.queue_redraw()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-manual-combat-960.png")
	for enemy in b.enemies: b.kill_enemy(enemy,f,enemy.node.position)
	b.player.position = Vector3(b.route_length,0,0)
	b.movement_direction = Vector3.ZERO
	game._process(0.1)
	check(game.expedition.phase == "reward" and not f.layout_locked,"stage victory releases the lock for post-clear progression")
	game.finish_crafting()
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	check(game.can_manage_layout() and not game.battle_mode and not game.world.playback_only,"next route returns to the construction phase")
	game.paint(Vector2i(13,7),false)
	check(f.cells.has(Vector2i(13,7)) and game.move_auxiliary("left_gun",Vector2i(11,0)),"next construction phase permits line changes and auxiliary relocation")
	game.toggle_running()
	check(not f.layout_locked and f.combat_editing,"next departure permits line changes")
	game.battlefield.hull = 0
	game._process(0.1)
	check(game.expedition.phase == "lost" and f.layout_locked,"defeat does not reopen the same stage for editing")
	game.reset_battle()
	check(game.can_manage_layout() and not f.layout_locked,"a new run restores construction access")
	await check_dodge()
	print("PHASE MOVEMENT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func check_dodge():
	for movement in [Vector3.ZERO,Vector3.RIGHT]:
		var battle = game.BattleWorld.new()
		battle.sector_config = game.RunState.new(42).current
		battle.sector_config.enemies = [0,0,0,0,0,0]
		root.add_child(battle)
		var f = game.Factory.new()
		f.fuel = 12
		f.running = true
		for enemy in battle.enemies:
			enemy.active = true
			enemy.hp = 0
		var shooter = battle.enemies[0]
		shooter.hp = 1
		shooter.node.position = Vector3(20,0,0)
		shooter.cooldown = 1.8
		battle.movement_direction = movement
		for i in range(70): battle.tick_battle(f,0.05)
		check(battle.impact_serial > 0 and (battle.hull == 90 if movement == Vector3.ZERO else battle.hull == 100 and battle.player.position.x > 6),"marked attack hits stationary tank but driving forward evades: "+str(movement))
		battle.queue_free()
		await process_frame
func _finalize(): Fixture.clean("phase_movement_test")
