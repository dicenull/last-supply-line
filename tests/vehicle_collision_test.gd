extends SceneTree
const Battle = preload("res://scripts/battle_world.gd")
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS collision: ",label)
	else:
		failures += 1
		push_error(label)
func separated(battle) -> bool:
	for i in range(battle.enemies.size()):
		var a = battle.enemies[i]
		if not a.active: continue
		for j in range(i):
			var b = battle.enemies[j]
			if not b.active: continue
			if a.node.position.distance_to(b.node.position)+0.0001 < a.collision_radius+b.collision_radius+Battle.VEHICLE_CLEARANCE: return false
	return true
func run():
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1408,752)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for moving in [false,true]:
		var battle = Battle.new()
		battle.sector_config = Run.new(42).current.duplicate(true)
		# Isolate vehicle/wreck avoidance on open ground. Staggered roadblocks
		# and enemy barrier collisions are covered by course_obstacles_test.
		battle.sector_config.erase("obstacles_version")
		battle.sector_config.erase("field_version") # Isolate steering from generated field geometry.
		battle.sector_config.erase("encounters_version")
		battle.sector_config.enemies = range(13)+range(13)+range(4)
		battle.sector_config.boss = true
		battle.sector_config.wave_size = 5
		battle.sector_config.wave_delay = 2
		viewport.add_child(battle)
		battle.hull = 100000
		var factory = Factory.new()
		factory.running = true
		factory.auto_fire = false
		factory.fuel = 1000
		var no_overlap = true
		var continuous = true
		var offscreen = true
		var approached = 0
		for tick in range(1200):
			battle.movement_direction = Vector3.RIGHT if moving and tick < 300 else Vector3.ZERO
			var positions: Array = []
			var active: Array = []
			for enemy in battle.enemies:
				positions.append(enemy.node.position)
				active.append(enemy.active)
			battle.tick_battle(factory,0.05)
			no_overlap = no_overlap and separated(battle)
			for i in range(battle.enemies.size()):
				var enemy = battle.enemies[i]
				if active[i]:
					continuous = continuous and enemy.node.position.distance_to(positions[i]) <= Run.Content.ENEMIES[enemy.role].speed*0.05+0.001
				elif enemy.active:
					offscreen = offscreen and not battle.camera.get_viewport().get_visible_rect().intersects(battle.enemy_screen_bounds(enemy,enemy.node.position))
			# Retain wreck colliders while later waves approach.
			if tick == 400: battle.kill_enemy(battle.enemies[0],factory,battle.enemies[0].node.position)
		for enemy in battle.enemies:
			if battle.can_engage(enemy,48): approached += 1
		check(no_overlap,"30 mixed vehicles including boss and wreck never overlap; moving="+str(moving))
		check(continuous,"avoidance never exceeds vehicle speed or teleports")
		check(offscreen,"every wave enters with its whole model outside the screen")
		check(battle.enemies.all(func(e): return e.active) and approached >= 15,"later waves continue approaching around slower vehicles and wrecks")
		check(battle.enemies.back().collision_radius > 4,"boss uses its enlarged collision footprint")
		if not moving and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://preview-vehicle-collision.png")
		for enemy in battle.enemies: enemy.active = false
		var first = battle.enemies[0]
		var second = battle.enemies[1]
		first.active = true
		second.active = true
		first.node.position = Vector3.ZERO
		second.node.position = Vector3(10,0,0)
		check(not battle.enemy_position_clear(first,Vector3(20,0,0),true),"swept collision rejects crossing another vehicle in one step")
		var step = battle.move_enemy(first,Vector3(20,0,0),20)
		check(battle.enemy_position_clear(first,first.node.position+step,true) and step.length() <= 20,"blocked movement chooses a clear bounded detour")
		battle.queue_free()
		await process_frame
	check(is_equal_approx(Battle.shell_flight_time(Vector3.ZERO,Vector3(30,0,0)),0.4),"30m heavy-shell flight lasts 400ms")
	print("VEHICLE COLLISION RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
