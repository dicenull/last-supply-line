extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Course = Run.FieldCourse
const Shapes = Course.Shapes
const Obstacles = preload("res://scripts/course_obstacles.gd")
const Schema = preload("res://scripts/run_snapshot_schema.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS map shapes: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var schema = Schema.new()
	var distinct = {}
	for shape in Shapes.IDS:
		var safe = true
		var repeatable = true
		for seed_value in range(24):
			var model = Run.new(seed_value)
			model.enable_items()
			model.modifiers.routes = 2+seed_value%2
			var route = model.make_route("scrapyard")
			route.map_shape = shape
			var course = Course.new(route)
			var replay = Course.new(route)
			repeatable = repeatable and schema.valid_route(route) and course.segments == replay.segments and course.landmarks == replay.landmarks and course.bounds == replay.bounds
			if seed_value == 0: distinct[str(course.segments)] = true
			var obstacles = Obstacles.new()
			for site in course.destinations:
				obstacles.barriers.append_array(Run.Defenses.fences(site.position))
				for at in Run.Defenses.mines(site.position): obstacles.mines.append({"position":at,"spent":false})
			for landmark in course.landmarks:
				obstacles.barriers.append(Rect2(Vector2(landmark.position.x,landmark.position.z)-Vector2.ONE*landmark.radius,Vector2.ONE*landmark.radius*2))
			for hazard in course.hazard_sites():
				var at = Vector3(hazard.x,0,hazard.z)
				var half = 4.3*hazard.scale
				obstacles.barriers.append(Rect2(Vector2(at.x,at.z)-Vector2.ONE*half,Vector2.ONE*half*2))
				for offset in [Vector3(-5,0,0),Vector3(5,0,0),Vector3(0,0,5)]: obstacles.mines.append({"position":at+offset,"spent":false})
			for segment in course.segments:
				var delta: Vector3 = segment[1]-segment[0]
				safe = safe and delta.length() > 0.01
				var yaw = atan2(-delta.z,delta.x)
				for i in range(31):
					var at: Vector3 = segment[0].lerp(segment[1],i/30.0)
					safe = safe and obstacles.clear_pose(at,yaw) and obstacles.triggered(at,yaw).is_empty()
			obstacles.free()
		check(safe,"24 fields have full-hull road clearance from scenery, fences and mines: "+shape)
		check(repeatable,"24 seeds reproduce geometry, scenery and bounds: "+shape)
	check(distinct.size() == 6,"all six shapes produce distinct road networks for the same seed")
	var cycling = true
	for seed_value in range(12):
		var model = Run.new(seed_value)
		model.enable_items()
		var seen = {}
		for sector in range(1,6):
			model.sector = sector
			var route = model.make_route("scrapyard")
			if sector < 5: seen[route.map_shape] = true
			else: cycling = cycling and not route.has("map_shape") and route.final_base_version == 1 and Course.new(route).destinations.size() == 1
		cycling = cycling and seen.size() == 4
	check(cycling,"four ordinary sectors use different shapes; final sector retains the large base")
	var model = Run.new(42)
	model.enable_items()
	var invalid = model.current.duplicate(true)
	invalid.map_shape = "unknown"
	check(not schema.valid_route(invalid),"unknown shape is rejected")
	invalid = model.current.duplicate(true)
	invalid.map_shape_version = 2
	check(not schema.valid_route(invalid),"unknown generation version is rejected")
	invalid = model.current.duplicate(true)
	invalid.erase("destination_layout_version")
	check(not schema.valid_route(invalid),"shape without scattered destinations is rejected")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"map_shapes_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for shape in Shapes.IDS:
		game.reset_battle(42)
		game.expedition.current.map_shape = shape
		game.release_battle()
		game.toggle_running()
		var battle = game.battlefield
		for enemy in battle.enemies: enemy.hp = 0
		battle.kills = battle.total
		for tick in range(5000):
			game.factory.fuel = 12
			Fixture.drive(game,0.1,1)
			if game.expedition.phase != "travel": break
		check(battle.result == 1 and battle.arrived_destination == 1 and battle.hull == 100,"actual tank reaches the selected destination unharmed: "+shape)
		var before = battle.field_course.segments.duplicate(true)
		var snapshot = game.checkpoint.snapshot(game)
		check(game.checkpoint.validate(snapshot) and game.checkpoint.apply(game,snapshot) and game.battlefield.field_course.segments == before,"checkpoint retains shape and arrival: "+shape)
	game.reset_battle(42)
	game.expedition.current.erase("map_shape")
	game.expedition.current.erase("map_shape_version")
	game.release_battle()
	game.ensure_battle()
	var old_segments = game.battlefield.field_course.segments.duplicate(true)
	var old_save = game.checkpoint.snapshot(game)
	old_save.version = 15
	check(game.checkpoint.validate(old_save) and game.checkpoint.apply(game,old_save) and game.battlefield.field_course.segments == old_segments,"version 15 checkpoint retains its original map")
	game.free()
	Fixture.clean("map_shapes_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
