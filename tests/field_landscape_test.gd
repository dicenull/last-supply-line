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
	if ok: print("PASS landscape: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var themes = {}
	var patterns = {}
	var consistent = true
	var clear = true
	var bounded = true
	var smallest = 100
	for seed_value in range(64):
		var route = Run.new(seed_value).current
		var a = Course.new(route)
		var b = Course.new(route)
		themes[a.landscape] = seed_value
		patterns[a.pattern] = seed_value
		smallest = mini(smallest,a.landmarks.size())
		consistent = consistent and a.trunk == b.trunk and a.connectors == b.connectors and a.landmarks == b.landmarks and a.patches == b.patches
		bounded = bounded and a.landmarks.size() <= 14 and a.patches.size() == 10
		var hazards = a.hazard_sites()
		for segment in a.segments:
			var yaw = atan2(-(segment[1]-segment[0]).z,(segment[1]-segment[0]).x)
			for i in range(21):
				var at: Vector3 = segment[0].lerp(segment[1],i/20.0)
				for landmark in a.landmarks:
					var rect = Rect2(Vector2(landmark.position.x,landmark.position.z)-Vector2.ONE*landmark.radius,Vector2.ONE*landmark.radius*2)
					clear = clear and not Obstacles.overlaps(at,yaw,rect)
				for site in hazards:
					var half = 4.3*site.scale
					clear = clear and not Obstacles.overlaps(at,yaw,Rect2(Vector2(site.x,site.z)-Vector2.ONE*half,Vector2.ONE*half*2))
	check(consistent,"64 seeds reproduce roads, alternate routes, districts and landmarks")
	check(themes.size() == 4 and patterns.size() == 4,"all four landscapes and four road patterns appear")
	check(clear,"landmarks and obstacles leave full-hull passage on every road and connector")
	check(bounded and smallest > 0,"scenery is bounded and every seed has landmarks; minimum="+str(smallest))
	var legacy_route = Run.new(42).current
	legacy_route.erase("landscape_version")
	var legacy = Course.new(legacy_route)
	check(legacy.landscape == "" and legacy.landmarks.is_empty() and legacy.connectors.is_empty() and legacy.trunk.size() == 4,"old saves retain their original Y-shaped road and scenery generator")
	var schema = preload("res://scripts/run_snapshot_schema.gd").new()
	legacy_route.landscape_version = 2
	check(not schema.valid_route(legacy_route),"unknown landscape generation versions are rejected")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"field_landscape_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	for pattern in patterns:
		game.reset_battle(patterns[pattern])
		game.toggle_running()
		var b = game.battlefield
		var f = game.factory
		for enemy in b.enemies: enemy.hp = 0
		b.kills = b.total
		var points = b.field_course.navigation_points(1,true)
		var index = 0
		var safe = true
		for tick in range(4000):
			if b.player.position.distance_to(points[index]) < 0.65 and index < points.size()-1: index += 1
			var offset: Vector3 = points[index]-b.player.position
			var error = angle_difference(b.player.rotation.y,atan2(-offset.z,offset.x))
			b.movement_direction = Vector3(1 if absf(error) < 0.06 else 0,0,clampf(-error/0.12,-1,1))
			f.fuel = 12
			b.tick_battle(f,0.1)
			safe = safe and b.obstacles.clear_pose(b.player.position,b.player.rotation.y)
			if b.result != 0: break
		check(safe and b.result == 1 and b.arrived_destination == 1 and b.hull == 100,"actual driving follows the alternate road and reaches the chosen yard: "+str(pattern))
	for theme in themes:
		game.reset_battle(themes[theme])
		game.toggle_running()
		var b = game.battlefield
		b.player.position = b.field_course.trunk[1]
		b.update_camera()
		game.factory.running = false
		var save = game.checkpoint.snapshot(game)
		var before = b.field_course.landmarks.duplicate(true)
		check(game.checkpoint.apply(game,save) and game.battlefield.field_course.landmarks == before and game.battlefield.field_course.landscape == theme,"checkpoint preserves district, landmarks and position: "+theme)
		if DisplayServer.get_name() != "headless":
			root.size = Vector2i(1440,940)
			await capture(game,"res://build/landscape-audit/"+theme+".png")
			root.size = Vector2i(960,628)
			await capture(game,"res://build/landscape-audit/"+theme+"-960.png")
			game.battlefield.player.position = game.battlefield.field_course.trunk[-1]
			game.battlefield.update_camera()
			root.size = Vector2i(1440,940)
			await capture(game,"res://build/landscape-audit/"+theme+"-junction.png")
	game.queue_free()
	await process_frame
	print("FIELD LANDSCAPE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func capture(game, path: String):
	game._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func _finalize(): Fixture.clean("field_landscape_test")
