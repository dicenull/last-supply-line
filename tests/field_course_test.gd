extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Course = preload("res://scripts/field_course.gd")
const Obstacles = preload("res://scripts/course_obstacles.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS field: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var shapes = {}
	var kinds = {}
	var hazard_counts = {}
	var valid = true
	for seed_value in range(64):
		for count in [2,3]:
			var r = Run.new(seed_value)
			r.current.destination_count = count
			var c = Course.new(r.current)
			var duplicate = Course.new(r.current)
			valid = valid and c.trunk == duplicate.trunk and c.branches == duplicate.branches and c.hazard_sites() == duplicate.hazard_sites()
			shapes[str(c.trunk)] = true
			var seen = []
			for goal in c.destinations:
				valid = valid and goal.position.x > 100 and goal.position.z < 0 and goal.kind not in seen
				seen.append(goal.kind)
			for row in c.hazard_sites():
				kinds[row.kind] = true
				valid = valid and c.road_distance(Vector3(row.x,0,row.z)) >= Course.ROAD_HALF_WIDTH+11
			hazard_counts[c.hazard_sites().size()] = true
	check(valid,"128 seeded fields reproduce roads and hazards with distinct upper-right destinations and clear corridors")
	check(shapes.size() == 64 and kinds.size() == 3 and hazard_counts.size() >= 3,"curves, obstacle groups, models and density vary across seeds")
	var invalid_choice = Run.new(42)
	invalid_choice.start_sector()
	check(not invalid_choice.finish_sector(true,100,{},true,2) and invalid_choice.phase == "travel" and invalid_choice.cleared == 0,"invalid arrival cannot advance the expedition")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"field_course_test")
	game.show_start_menu = false
	root.size = Vector2i(1440,940)
	root.add_child(game)
	game.set_process(false)
	game.ensure_battle()
	for count in [2,3]:
		for destination in range(count):
			game.reset_battle(42+destination)
			game.expedition.current.destination_count = count
			game.release_battle()
			game.toggle_running()
			var b = game.battlefield
			var f = game.factory
			for enemy in b.enemies: enemy.hp = 0
			b.kills = b.total
			var picked_kind = b.field_course.destinations[destination].kind
			var safe = true
			for tick in range(2400):
				f.fuel = 12
				Fixture.drive(game,0.1,destination)
				safe = safe and b.obstacles.clear_pose(b.player.position,b.player.rotation.y)
				if game.expedition.phase != "travel": break
			if b.result != 1 or b.arrived_destination != destination: print("FIELD STOP ",count," ",destination," pos=",b.player.position," yaw=",b.player.rotation.y," arrived=",b.arrived_destination," paths=",b.field_course.navigation_points(destination))
			check(b.result == 1 and b.arrived_destination == destination and safe and b.hull == 100,"steering reaches selected yard with full hull clearance: %d/%d" % [destination,count])
			check(b.obstacles.mines.all(func(m): return not m.spent),"road avoids every mine footprint")
			var saved = game.checkpoint.snapshot(game)
			check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"arrival and pending reward round-trip")
			check(game.battlefield.arrived_destination == destination and game.expedition.current.destination_index == destination,"reload retains the physical destination choice")
			var bad = saved.duplicate(true)
			bad.run.current.destination_index = count
			check(not game.checkpoint.validate(bad),"out-of-range destination is rejected")
			bad = saved.duplicate(true)
			bad.run.current.destination_index = (destination+1)%count
			check(not game.checkpoint.validate(bad),"saved choice must match the yard actually reached")
			var stocks = f.reserves.duplicate()
			preload("res://tests/profile_fixture.gd").claim_reward(game,0)
			check(game.expedition.phase == "prepare" and game.expedition.current.kind == picked_kind and game.expedition.route_options.is_empty() and not game.choice_popup.visible and not game.started,"reward proceeds to the field-selected encounter without a route popup")
			check(game.factory.reserves == stocks and game.checkpoint.validate(game.checkpoint.snapshot(game)),"next stage preserves stock and is saveable")
	# Mid-fork save uses only the seed; loading cannot reroll roads or obstacles.
	game.reset_battle(77)
	game.toggle_running()
	var b = game.battlefield
	b.player.position = b.field_course.trunk.back()
	b.player.rotation.y = 0.7
	var snapshot = game.checkpoint.snapshot(game)
	var roads = b.field_course.branches.duplicate(true)
	var hazards = b.obstacles.rows.duplicate(true)
	check(game.checkpoint.apply(game,snapshot) and game.battlefield.field_course.branches == roads and game.battlefield.obstacles.rows == hazards,"mid-fork restore reproduces the whole road and scattered obstacles")
	check(game.battlefield.player.transform == snapshot.battle.player and not game.factory.running,"mid-fork restore retains pose and pauses")
	var field = game.battlefield
	var fuel_factory = game.factory
	fuel_factory.fuel = 12
	field.player.position = Vector3.ZERO
	field.player.rotation.y = 0
	field.movement_direction = Vector3.RIGHT
	field.move_player(fuel_factory,0.1)
	var road_travel = field.player.position.x
	field.player.position = Vector3(-8,0,field.field_course.bounds.end.y-2)
	field.move_player(fuel_factory,0.1)
	check(is_equal_approx(field.player.position.x+8,road_travel*0.65),"leaving the road slows actual forward travel")
	field.player.position = Vector3(field.field_course.bounds.position.x,0,0)
	field.movement_direction = Vector3.LEFT
	var fuel_before = fuel_factory.fuel
	field.move_player(fuel_factory,0.1)
	check(field.player.position.x == field.field_course.bounds.position.x and fuel_factory.fuel == fuel_before,"expanded field boundary blocks reverse without burning fuel")
	check(game.checkpoint.apply(game,snapshot),"restore approach after boundary probe")
	game.battle_mode = true
	game.refresh_view()
	await process_frame
	check(game.field_map.visible and game.field_map.mouse_filter == Control.MOUSE_FILTER_IGNORE,"overview is visible during driving and never consumes steering input")
	if DisplayServer.get_name() != "headless":
		await capture(game,"res://build/field-audit/field-1440.png")
		root.size = Vector2i(960,628)
		await process_frame
		await capture(game,"res://build/field-audit/field-960.png")
	# Reaching the last sector still requires entering one of its physical yards.
	game.reset_battle(99)
	game.expedition.sector = 5
	game.expedition.cleared = 4
	game.expedition.current = game.expedition.make_route("arsenal")
	game.release_battle()
	game.toggle_running()
	game.battlefield.player.position = game.battlefield.goals[1].position+Vector3(2,0,0)
	game._process(0)
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	check(game.expedition.phase == "won" and game.expedition.cleared == 5 and game.checkpoint.validate(game.checkpoint.snapshot(game)),"entering either final destination completes the five-sector run after its reward")
	game.queue_free()
	await process_frame
	print("FIELD COURSE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func capture(game, path: String):
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func _finalize(): Fixture.clean("field_course_test")
