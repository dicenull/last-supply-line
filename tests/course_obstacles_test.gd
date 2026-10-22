extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Battle = preload("res://scripts/battle_world.gd")
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS obstacles: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	for seed_value in [42,77]:
		for stage in range(1,6):
			var run_state = Run.new(seed_value)
			run_state.sector = stage
			var route = run_state.make_route("scrapyard",true)
			var b = Battle.new()
			b.sector_config = route
			root.add_child(b)
			var f = Factory.new()
			f.fuel = 10000
			f.running = true
			for enemy in b.enemies: enemy.hp = 0
			b.kills = b.total
			var clear = true
			var low = 0.0
			var high = 0.0
			for tick in range(5000):
				Fixture.pilot(b)
				b.tick_battle(f,0.05)
				clear = clear and b.obstacles.clear_pose(b.player.position,b.player.rotation.y)
				low = minf(low,b.player.position.z)
				high = maxf(high,b.player.position.z)
				if b.result != 0: break
			var label = str(seed_value)+" stage "+str(stage)
			if b.result != 1: print("STUCK ",label," ",b.player.position," yaw ",b.player.rotation.y," target input ",b.movement_direction)
			check(b.result == 1 and clear,"full-size tank navigates every staggered row without collision: "+label)
			check(low < -8.5 and high > 8.5,"route requires both left and right detours: "+label)
			check(b.hull == 100 and b.obstacles.mines.all(func(m): return not m.spent),"clear passage avoids all mine footprints: "+label)
			b.queue_free()
			await process_frame
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"course_obstacles_test")
	game.show_start_menu = false
	game.expedition = Run.new(42)
	root.add_child(game)
	game.set_process(false)
	game.toggle_running()
	var b = game.battlefield
	var f = game.factory
	var row = b.obstacles.rows[0]
	b.player.position = Vector3(row.x-20,0,0)
	f.fuel = 12
	b.movement_direction = Vector3.RIGHT
	var used = f.fuel_used
	b.move_player(f,20)
	check(b.player.position.x < row.x-10 and b.obstacles.clear_pose(b.player.position,0),"large forward step cannot tunnel through fence")
	check(is_equal_approx(f.fuel_used-used,(b.player.position.x-(row.x-20))*0.12),"blocked movement charges only actual travel")
	var at = b.player.position
	used = f.fuel_used
	b.move_player(f,1)
	check(b.player.position == at and f.fuel_used == used,"pushing into a solid fence does not burn movement fuel")
	b.movement_direction = Vector3.BACK
	b.move_player(f,2)
	check(absf(b.player.rotation.y) < 1 and b.obstacles.clear_pose(b.player.position,b.player.rotation.y),"hull corners cannot pivot through steel barriers")
	b.movement_direction = Vector3.LEFT
	b.move_player(f,0.2)
	check(b.player.position.x < at.x,"reverse remains available after a blocked approach")
	check(not b.obstacles.clear_enemy_path(Vector3(row.x-5,0,-row.open_side*3),Vector3(row.x+5,0,-row.open_side*3),2),"enemy collision also blocks crossing a fence")
	check(b.obstacles.clear_enemy_path(Vector3(row.x-5,0,row.open_side*12),Vector3(row.x+5,0,row.open_side*12),2),"enemy vehicles can use the same open passage")
	await check_shots_through_barriers()
	b.player.position = Vector3(10,0,0)
	b.player.rotation = Vector3.ZERO
	b.update_camera()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440,940)
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview-course-obstacles.png")
	var mine = b.obstacles.mines[0]
	b.player.position = mine.position+Vector3(-8,0,0)
	b.movement_direction = Vector3.ZERO
	f.cells[Vector2i(13,4)] = f.make_cell("belt",2)
	b.tick_battle(f,0)
	check(mine.spent and not mine.live.visible and mine.crater.visible and b.hull < 100,"mine contact uses the hull footprint and leaves a spent crater")
	check(f.wrecks.has(Vector2i(13,4)),"mine damage destroys the nearby line section")
	var hull_before = b.hull
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"detonated mines round-trip through checkpoint")
	b = game.battlefield
	f = game.factory
	f.running = true
	b.tick_battle(f,0)
	check(b.hull == hull_before and b.obstacles.mines[0].spent,"resumed mine cannot detonate twice")
	var bad = saved.duplicate(true)
	bad.battle.erase("mines")
	check(not game.checkpoint.validate(bad),"new obstacle route requires complete mine state")
	bad = saved.duplicate(true)
	bad.battle.mines[0] = 1
	check(not game.checkpoint.validate(bad),"malformed mine flags are rejected")
	var legacy = saved.duplicate(true)
	legacy.run.current.erase("obstacles_version")
	legacy.battle.erase("mines")
	check(game.checkpoint.apply(game,legacy) and game.battlefield.obstacles.barriers.is_empty(),"legacy battle resumes without spawning barriers into an existing vehicle")
	print("COURSE OBSTACLES RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func check_shots_through_barriers():
	for row_index in [0,1]:
		var b = Battle.new()
		b.sector_config = Run.new(42).current
		root.add_child(b)
		var row = b.obstacles.rows[row_index]
		var z = -row.open_side*12.0
		b.player.position = Vector3(row.x-12,0,z)
		b.update_camera()
		var f = Factory.new()
		f.running = true
		f.ammo = 0
		for enemy in b.enemies:
			enemy.active = true
			enemy.hp = 0
		var target = b.enemies[0]
		target.hp = 1
		target.node.position = Vector3(row.x+12,0,z)
		check(b.can_engage(target,48,b.player.position+Vector3(0,1,0)),"target remains visible through "+row.kind)
		target.aim = b.player.position
		b.launch_enemy(target)
		# Use a low shot so its segment crosses the actual barrier volume.
		var origin = b.player.position+Vector3(0,1,0)
		var shot = Node3D.new()
		b.add_child(shot)
		shot.position = origin
		b.projectiles.append({"node":shot,"origin":origin,"dir":Vector3.RIGHT,"age":0.0,"duration":0.3,"target":target,"style":"heavy"})
		b.update_gun(f,0.4)
		check(target.hp == 0 and b.projectiles.is_empty(),"player shell reaches enemy through "+row.kind)
		b.tick_battle(f,0.5)
		check(b.hull < 100 and b.bolts.is_empty(),"enemy shell reaches player through "+row.kind)
		b.queue_free()
		await process_frame

func _finalize(): Fixture.clean("course_obstacles_test")
