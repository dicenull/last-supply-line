extends SceneTree
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS battle: ",label)
func _initialize(): call_deferred("run")
func advance(seconds: float):
	for i in range(int(seconds/0.025)):
		game.battlefield.movement_direction = Vector3.RIGHT
		game.factory.step(0.025)
		game.battlefield.tick_battle(game.factory,0.025)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"battle_test")
	game.expedition = preload("res://scripts/run_state.gd").new(42)
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.factory.example()
	var layout = game.factory.layout()
	game.toggle_battle()
	check(not game.started and not game.factory.running,"B previews exterior without starting simulation")
	var initial_remaining = game.battlefield.remaining_distance()
	check(game.destination_text() == "あと%dm" % ceili(initial_remaining),"preparation shows compact distance to the nearest field yard")
	var camera = game.battlefield.camera
	var view = camera.get_viewport().get_visible_rect()
	var visible_ahead = true
	for point in [Vector3.ZERO,Vector3(28,0,-16),Vector3(28,0,16)]:
		visible_ahead = visible_ahead and not camera.is_position_behind(point) and view.has_point(camera.unproject_position(point))
	check(visible_ahead and camera.size > game.world.camera.size,"battle overview keeps own vehicle and both sides of the road ahead visible")
	var own_position = camera.unproject_position(Vector3(0,2,0))/view.size
	check(own_position.x > 0.15 and own_position.x < 0.38 and own_position.y > 0.6 and own_position.y < 0.85,"own tank occupies the lower-left area with forward space")
	var forward_position = camera.unproject_position(Vector3(28,0,0))/view.size
	check(forward_position.x > own_position.x and forward_position.y < own_position.y,"route extends from lower-left to upper-right")
	game.toggle_running()
	check(game.battle_mode and not game.factory.auto_fire,"battle mode disables test firing")
	check(game.factory.layout() == layout,"entering battle preserves factory layout")
	check(game.battlefield.roof_closed and game.battlefield.mats.turret_armor.albedo_color.a == 1.0,"battle presents opaque tank exterior")
	check(game.cell_at(Vector2(550,400)) == Vector2i(-1,-1),"battlefield clicks cannot edit factory")
	advance(0.025)
	var offscreen = true
	for i in range(2):
		var enemy = game.battlefield.enemies[i]
		offscreen = offscreen and not view.intersects(game.battlefield.enemy_screen_bounds(enemy,enemy.node.position))
	check(offscreen,"entire incoming vehicles start beyond the forward screen edge")
	advance(1)
	check(game.battlefield.distance == 0,"tank cannot move before first manufactured fuel arrives")
	var blocking_road = true
	for i in range(2):
		var pos = game.battlefield.enemies[i].node.position-game.battlefield.player.position
		blocking_road = blocking_road and pos.x >= 20 and absf(pos.z) <= 12
	check(blocking_road,"first enemies approach from ahead within the road instead of the sides")
	advance(11)
	check(game.battlefield.distance > 0 and game.factory.fuel_used > 0,"manufactured fuel powers real movement")
	check(game.battlefield.remaining_distance() < initial_remaining and game.destination_text() == "あと%dm" % ceili(game.battlefield.remaining_distance()),"destination counter decreases with actual travel toward the field yards")
	check(is_equal_approx(game.battlefield.distance*game.battlefield.FUEL_PER_METER,game.factory.fuel_used),"straight-line travel consumes fuel in proportion to distance")
	check(game.battlefield.enemies[0].active and not game.battlefield.enemies[4].active,"enemies arrive in stages instead of a stationary ring")
	check(game.factory.shots > 0 and game.battlefield.visual_shots == game.factory.shots,"each battle shot consumes one manufactured round")
	game.queue_redraw()
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-battle.png")
	root.get_texture().get_image().save_png("res://preview-battle-approach.png")
	var combat_time = game.battlefield.elapsed
	var hp = game.battlefield.hull
	game.toggle_battle()
	check(game.factory.running and not game.factory.auto_fire,"interior view leaves simulation running")
	game.paint(Vector2i(10,7),false)
	check(game.factory.cells.has(Vector2i(10,7)) and game.factory.running,"combat permits placement without stopping production")
	game.last_paint = Vector2i(-1,-1)
	game.paint(Vector2i(1,2),true)
	check(not game.factory.cells.has(Vector2i(1,2)) and game.factory.running,"combat permits removal without stopping production")
	game.factory.restore(layout)
	var before_progress = game.battlefield.elapsed
	preload("res://tests/profile_fixture.gd").drive(game,0.1)
	check(game.battlefield.elapsed > before_progress,"battle advances while viewing interior")
	combat_time = game.battlefield.elapsed
	hp = game.battlefield.hull
	check(game.factory.layout() == layout,"return preserves layout")
	check(game.battlefield.elapsed == combat_time and game.battlefield.hull == hp,"return preserves encounter state")
	game.toggle_battle()
	game.toggle_running()
	game.toggle_battle()
	check(not game.factory.running,"B preserves paused state")
	game.paint(Vector2i(11,7),false)
	check(game.factory.cells.has(Vector2i(11,7)) and not game.factory.running,"combat pause permits construction")
	advance(3)
	check(game.battlefield.elapsed == combat_time,"pause freezes combat and production")
	game.toggle_running()
	# Straight travel above isolates fuel use; arrival now requires steering
	# around the physical barriers introduced by the current course rules.
	# Back away from the first fence so the full hull has room to pivot.
	for tick in range(800):
		if game.battlefield.player.position.x <= 14: break
		game.battlefield.movement_direction = Vector3.LEFT
		game.factory.step(0.025)
		game.battlefield.tick_battle(game.factory,0.025)
	for tick in range(8800):
		preload("res://tests/profile_fixture.gd").pilot(game.battlefield)
		game.factory.step(0.025)
		game.battlefield.tick_battle(game.factory,0.025)
		if game.battlefield.result != 0: break
	check(game.battlefield.result == 1 and game.battlefield.goal.contains_position(game.battlefield.player.position),"sample factory travels route and enters the destination yard")
	check(game.destination_text() == "あと0m","arrival shows zero remaining meters")
	check(not game.factory.running,"victory stops encounter")
	game.reset_battle()
	check(not game.started and not game.factory.running,"retry returns to preparation")
	game.toggle_running()
	check(game.battlefield.result == 0 and game.battlefield.hull == 100 and game.factory.shots == 0,"retry resets encounter and stock without changing layout")
	game.reset_battle()
	game.factory.clear_layout(false)
	game.toggle_running()
	game.factory.ammo = 2
	# Isolate firing without fuel from variable off-screen approach time.
	var stock_target = game.battlefield.enemies[0]
	stock_target.active = true
	stock_target.node.visible = true
	stock_target.node.position = Vector3(28,0,-3)
	stock_target.cooldown = 60
	advance(1)
	check(game.factory.shots > 0 and game.battlefield.distance == 0,"fuel-starved tank can still fire stocked ammunition")
	game.reset_battle()
	check(not game.started and not game.factory.running,"retry returns to preparation")
	game.factory.clear_layout(false)
	game.toggle_running()
	game.factory.running = true
	game.factory.fuel = 12.0
	game.battlefield.enemies[0].active = true
	game.battlefield.enemies[0].node.position = Vector3(28,0,-3)
	game.battlefield.enemies[0].cooldown = 1.5
	advance(0.05)
	var locked = game.battlefield.enemies[0].aim
	check(game.battlefield.enemies[0].locked and game.battlefield.enemies[0].mark.visible,"enemy marks a fixed impact location before firing")
	advance(4.5)
	check(game.battlefield.hull == 100 and game.battlefield.player.position.distance_to(locked) > 6,"moving beyond warning zone avoids the enemy shell")
	var before_click = game.battlefield.player.position
	var click_event = InputEventMouseButton.new()
	click_event.position = Vector2(900,650)
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	game._unhandled_input(click_event)
	advance(1)
	check(game.battlefield.player.position.x > before_click.x and game.battlefield.player.position.z == 0,"battlefield clicks do not replace the manual movement command")
	game.reset_battle()
	check(not game.started and not game.factory.running,"retry returns to preparation")
	game.factory.clear_layout(false)
	game.toggle_running()
	game.factory.running = true
	advance(100)
	check(game.factory.shots == 0 and game.battlefield.kills == 0,"empty factory never fires or defeats opponents")
	check(game.battlefield.result == -1 and game.battlefield.hull == 0,"unsupplied tank reaches defeat")
	game.toggle_running()
	check(not game.factory.running,"finished encounter cannot resume with Space")
	await check_entry_motion()
	await check_one_hit_encounters()
	print("BATTLE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func check_entry_motion():
	game.reset_battle()
	game.factory.clear_layout(false)
	game.factory.running = true
	game.factory.ammo = 6
	var battle = game.battlefield
	for enemy in battle.enemies: enemy.cooldown = 0
	battle.tick_battle(game.factory,0.025)
	check(game.factory.shots == 0 and battle.bolts.is_empty(),"neither side fires at offscreen arrivals even when loaded and ready")
	var previous: Dictionary = {}
	for index in range(battle.enemies.size()):
		if battle.enemies[index].active: previous[index] = battle.enemies[index].node.position
	var continuous = true
	var crossed_edge = false
	var screen = battle.camera.get_viewport().get_visible_rect()
	for tick in range(1600):
		battle.tick_battle(game.factory,0.025)
		for index in range(battle.enemies.size()):
			var enemy = battle.enemies[index]
			if not enemy.active: continue
			var at: Vector3 = enemy.node.position
			if previous.has(index):
				continuous = continuous and previous[index].distance_to(at) <= float(game.RunState.Content.ENEMIES[enemy.role].speed)*0.025+0.001
			crossed_edge = crossed_edge or screen.intersects(battle.enemy_screen_bounds(enemy,at))
			previous[index] = at
		if game.factory.shots > 0: break
	check(continuous and crossed_edge and game.factory.shots > 0,"incoming tank crosses the edge continuously and becomes targetable after approaching")
	game.queue_free()
	await process_frame

func check_one_hit_encounters():
	for scenario in ["patrol","boss","legacy"]:
		var battle = preload("res://scripts/battle_world.gd").new()
		battle.sector_config = preload("res://scripts/run_state.gd").new(42).current
		if scenario != "patrol":
			battle.sector_config.formation = "battery"
			battle.sector_config.boss = true
		if scenario == "legacy":
			for key in ["combat_version","enemies","wave_size","wave_delay","warning_scale","difficulty"]: battle.sector_config.erase(key)
			battle.sector_config.enemy_hp = 4
		root.add_child(battle)
		var factory = preload("res://scripts/factory.gd").new()
		factory.ammo = battle.total
		factory.rate = 90
		factory.running = true
		var health_ok = true
		for i in range(battle.total):
			var enemy = battle.enemies[i]
			enemy.active = true
			enemy.node.position = Vector3(32+i*0.4,0,(i%2)*4)
			health_ok = health_ok and (enemy.hp > 1 if scenario == "legacy" else enemy.hp == 1)
		check(health_ok,"new enemies have one hit point while old health can be restored: "+scenario)
		var no_duplicate_rounds = true
		for tick in range(800):
			battle.update_gun(factory,0.025)
			var targets: Array = []
			for shot in battle.projectiles:
				no_duplicate_rounds = no_duplicate_rounds and shot.target.node not in targets
				targets.append(shot.target.node)
			if battle.kills == battle.total: break
		check(no_duplicate_rounds,"in-flight lethal rounds reserve targets without wasting shells: "+scenario)
		var pips_hidden = true
		for enemy in battle.enemies:
			for pip in enemy.health: pips_hidden = pips_hidden and not pip.visible
		check(battle.kills == battle.total and factory.shots == battle.total and factory.ammo == 0 and pips_hidden,"each real impact kills one enemy without wasting shells: "+scenario)
		battle.queue_free()
		await process_frame

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("battle_test")
