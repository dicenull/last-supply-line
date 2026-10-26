extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Course = Run.FieldCourse
const Obstacles = preload("res://scripts/course_obstacles.gd")
const Schema = preload("res://scripts/run_snapshot_schema.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS destination spacing: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var separated = true
	var varied = true
	var repeatable = true
	var bounded = true
	var roads_clear = true
	var schema = Schema.new()
	for seed_value in range(256):
		var model = Run.new(seed_value)
		model.enable_items()
		model.sector = 1+seed_value%5
		model.modifiers.routes = 2+seed_value%2
		var route = model.make_route("scrapyard")
		var course = Course.new(route)
		var replay = Course.new(route)
		repeatable = repeatable and schema.valid_route(route) and course.destinations == replay.destinations and course.segments == replay.segments and course.hazard_sites() == replay.hazard_sites()
		var xs = course.destinations.map(func(site): return site.position.x)
		var zs = course.destinations.map(func(site): return site.position.z)
		varied = varied and xs.max()-xs.min() >= 20 and zs.min() < course.trunk.back().z and zs.max() > course.trunk.back().z
		var obstacles = Obstacles.new()
		for site in course.destinations:
			obstacles.barriers.append_array(Run.Defenses.fences(site.position))
			for at in Run.Defenses.mines(site.position):
				obstacles.mines.append({"position":at,"spent":false})
				bounded = bounded and course.bounds.grow(-5).has_point(Vector2(at.x,at.z))
			for other in course.destinations:
				if other != site: separated = separated and site.position.distance_to(other.position) >= Course.DESTINATION_MIN_SPACING
		for segment in course.segments:
			var yaw = atan2(-(segment[1]-segment[0]).z,(segment[1]-segment[0]).x)
			for step in range(21):
				var at: Vector3 = segment[0].lerp(segment[1],step/20.0)
				bounded = bounded and course.bounds.has_point(Vector2(at.x,at.z))
				roads_clear = roads_clear and obstacles.clear_pose(at,yaw) and obstacles.triggered(at,yaw).is_empty()
		obstacles.free()
	check(separated,"256 fields keep every pair of destinations at least 90m apart")
	check(varied,"destinations vary in depth and spread to both sides of the junction")
	check(repeatable,"seed and generation version reproduce roads, rewards and hazards")
	check(bounded,"map bounds contain every road and complete perimeter minefield")
	check(roads_clear,"every branch and connector avoids all perimeter fences and mines")
	var old = Run.new(42)
	old.enable_items()
	old.current.erase("destination_layout_version")
	var legacy = Course.new(old.current)
	check(schema.valid_route(old.current) and legacy.destinations[0].position.distance_to(legacy.destinations[1].position) < 70,"existing saves retain the original close destination layout")
	old.current.destination_layout_version = 2
	check(not schema.valid_route(old.current),"unknown destination generation version is rejected")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"destination_spacing_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for count in [2,3]:
		for destination in range(count):
			game.reset_battle(42+destination)
			game.expedition.modifiers.routes = count
			game.expedition.current = game.expedition.make_route("scrapyard")
			game.release_battle()
			game.toggle_running()
			var battle = game.battlefield
			for enemy in battle.enemies: enemy.hp = 0
			battle.kills = battle.total
			var safe = true
			for tick in range(5000):
				game.factory.fuel = 12
				Fixture.drive(game,0.1,destination)
				safe = safe and battle.obstacles.clear_pose(battle.player.position,battle.player.rotation.y)
				if game.expedition.phase != "travel": break
			check(safe and battle.result == 1 and battle.arrived_destination == destination and battle.hull == 100,"actual tank reaches the selected scattered yard through its gate: %d/%d" % [destination,count])
			var before = battle.field_course.destinations.duplicate(true)
			var snapshot = game.checkpoint.snapshot(game)
			check(game.checkpoint.validate(snapshot) and game.checkpoint.apply(game,snapshot) and game.battlefield.field_course.destinations == before,"checkpoint preserves scattered destinations and arrival")
	game.free()
	Fixture.clean("destination_spacing_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
