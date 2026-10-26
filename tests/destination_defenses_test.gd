extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Defenses = Run.Defenses
const Obstacles = preload("res://scripts/course_obstacles.gd")
const Schema = preload("res://scripts/run_snapshot_schema.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS destination defenses: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var shop_fields = 0
	var stable = true
	var clear_gates = true
	var closed_sides = true
	var valid_routes = true
	var schema = Schema.new()
	for seed_value in range(1024):
		var model = Run.new(seed_value)
		model.modifiers.routes = 2+seed_value%2
		model.current = model.make_route("scrapyard")
		model.enable_items()
		var route = model.current
		var course = Run.FieldCourse.new(route)
		var replay = Run.FieldCourse.new(route)
		stable = stable and course.destinations == replay.destinations and course.branches == replay.branches
		var shops = course.destinations.filter(func(site): return site.encounter == "shop").size()
		stable = stable and shops <= 1
		if shops > 0: shop_fields += 1
		valid_routes = valid_routes and schema.valid_route(route) and route.enemies.size() == route.patrol_count+route.destination_count*6
		if seed_value >= 64: continue
		for site in course.destinations:
			var obstacles = Obstacles.new()
			obstacles.barriers = Defenses.fences(site.position)
			for at in Defenses.mines(site.position): obstacles.mines.append({"position":at,"spent":false})
			for x in range(-24,11):
				var at: Vector3 = site.position+Vector3(x,0,0)
				clear_gates = clear_gates and obstacles.clear_pose(at,0) and obstacles.triggered(at,0).is_empty()
			for x in range(0,30):
				for side in [-1,1]: closed_sides = closed_sides and not obstacles.clear_pose(site.position+Vector3(x,0,side*18),PI/2)
			for z in range(-18,19): closed_sides = closed_sides and not obstacles.clear_pose(site.position+Vector3(30,0,z),PI)
			obstacles.free()
	check(stable,"seeded destinations reproduce, with at most one shop per field")
	check(shop_fields >= 150 and shop_fields <= 260,"shops occur on approximately 20 percent of fields: %d/1024" % shop_fields)
	check(valid_routes,"all modern rosters and route metadata validate")
	check(clear_gates,"all 64 sampled fields have a hull-width, mine-free entrance")
	check(closed_sides,"side and rear approaches are blocked by continuous fences")
	for difficulty in ["easy","normal","hard"]:
		for sector in range(1,6):
			var model = Run.new(42,difficulty)
			model.enable_items()
			model.sector = sector
			model.modifiers.routes = 3
			check(schema.valid_route(model.make_route("arsenal",false,"hostile")),"maximum defense roster saves: %s/%d" % [difficulty,sector])
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"destination_defenses_test",2)
	game.expedition = Run.new(42,"easy")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.toggle_running()
	var b = game.battlefield
	var guards = b.enemies.filter(func(e): return e.has("guard_home"))
	check(guards.size() == b.goals.size()*6 and guards.all(func(e): return e.active and e.node.visible and b.obstacles.circle_clear(e.node.position,e.collision_radius)),"six visible guards per destination spawn clear of fences and scenery")
	var poses = guards.map(func(e): return e.node.position)
	b.tick_battle(game.factory,0.1)
	check(guards.map(func(e): return e.node.position) == poses,"distant guards remain at their destination")
	check(b.obstacles.mines.size() == Obstacles.mine_count(b.sector_config),"save schema counts both roadside and perimeter mines")
	b.obstacles.set_spent(b.obstacles.mines.size()-1,true)
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"fortified field and guard states round-trip through checkpoint")
	b = game.battlefield
	check(b.obstacles.mines.back().spent and b.enemies.filter(func(e): return e.has("guard_home")).size() == guards.size(),"reload preserves spent perimeter mines and the guard roster")
	var target: Vector3 = b.goals[0].position
	b.player.position = target-Vector3(24,0,0)
	b.player.rotation = Vector3.ZERO
	b.movement_direction = Vector3.RIGHT
	game.factory.fuel = 12
	var plan = b.drive_plan(28,0)
	check(plan.position.x >= target.x and b.goals[0].contains_position(plan.position),"actual swept drive can enter through the front gate")
	b.player.position = target+Vector3(10,0,35)
	b.player.rotation.y = PI/2
	plan = b.drive_plan(35,0)
	check(plan.position.z >= target.z+Defenses.HALF_WIDTH and not b.goals[0].contains_position(plan.position),"actual swept drive cannot enter through a side fence")
	var old = Run.new(42).current
	check(not old.has("defenses_version") and old.encounters_version == 1 and schema.valid_route(old),"legacy generated routes retain their original saved layout")
	game.queue_free()
	await process_frame
	Fixture.clean("destination_defenses_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
