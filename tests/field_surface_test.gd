extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Course = preload("res://scripts/field_course.gd")
const Surface = preload("res://scripts/field_surface.gd")
const View = preload("res://scripts/field_surface_view.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS field surface: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var themes = {}
	var deterministic = true
	var clear = true
	var bounded = true
	var unchanged = true
	var kinds = {}
	var lowest = 10000
	var highest = 0
	for seed_value in range(128):
		var route = Run.new(seed_value).current
		var course = Course.new(route)
		var before = [course.trunk.duplicate(true),course.branches.duplicate(true),course.landmarks.duplicate(true),course.hazard_sites()]
		var rows = Surface.generate(course,route)
		themes[course.landscape] = seed_value
		deterministic = deterministic and rows == Surface.generate(course,route)
		bounded = bounded and rows.size() <= Surface.MAX_INSTANCES
		lowest = mini(lowest,rows.size())
		highest = maxi(highest,rows.size())
		unchanged = unchanged and before == [course.trunk,course.branches,course.landmarks,course.hazard_sites()]
		for row in rows:
			kinds[row.kind] = true
			if row.kind in ["rut","scuff"]: continue
			clear = clear and course.road_distance(row.position) > course.ROAD_HALF_WIDTH+1
			for site in course.destinations: clear = clear and row.position.distance_to(site.position) > 20
	check(deterministic,"128 seeds reproduce every cosmetic transform and color")
	check(unchanged,"cosmetic generation leaves roads, landmarks and hazards untouched")
	check(clear,"raised roadside details stay outside driving lanes and arrival yards")
	check(bounded and lowest > 0,"details stay within their instance budget: "+str(lowest)+".."+str(highest))
	check(kinds.size() == 5 and themes.size() == 4,"all landscape palettes and detail shapes appear")
	var wide_valid = true
	for seed_value in range(32):
		var route = Run.new(seed_value).current
		route.length = 196.0
		route.destination_count = 3
		var rows = Surface.generate(Course.new(route),route)
		wide_valid = wide_valid and not rows.is_empty() and rows.size() <= Surface.MAX_INSTANCES
	check(wide_valid,"long final-sector roads and three destinations retain bounded detail counts")
	var legacy_route = Run.new(42).current
	legacy_route.erase("landscape_version")
	check(Surface.generate(Course.new(legacy_route),legacy_route).is_empty(),"legacy scenery keeps its original generator")
	for theme in themes:
		var route = Run.new(themes[theme]).current
		var course = Course.new(route)
		var view = View.new()
		root.add_child(view)
		view.build(course,route)
		check(view.instance_total == Surface.generate(course,route).size() and view.get_child_count() < 80,"regional batches represent every instance with bounded node count: "+theme)
		# The headless dummy renderer does not retain MultiMesh GPU transforms.
		if DisplayServer.get_name() != "headless":
			var bounds_valid = true
			for batch in view.get_children():
				var mm = batch.multimesh
				for i in range(mm.instance_count):
					var bounds: AABB = mm.get_instance_transform(i)*mm.mesh.get_aabb()
					bounds_valid = bounds_valid and mm.custom_aabb.encloses(bounds)
			check(bounds_valid,"batch culling bounds contain their transformed meshes: "+theme)
		view.queue_free()
		await process_frame
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/surface-audit")
		var game = load("res://main.tscn").instantiate()
		Fixture.assign(game,"field_surface_test",2)
		game.show_start_menu = false
		root.add_child(game)
		game.set_process(false)
		await process_frame
		game.ensure_battle()
		for theme in themes:
			game.reset_battle(themes[theme])
			game.toggle_running()
			game.factory.running = false
			game.battlefield.player.position = game.battlefield.field_course.trunk[1]
			game.battlefield.update_camera()
			for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
				root.size = dimensions
				game._process(0)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://build/surface-audit/"+theme+"-"+str(dimensions.x)+".png")
		game.queue_free()
		await process_frame
		Fixture.clean("field_surface_test")
	print("FIELD SURFACE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
