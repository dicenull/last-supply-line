extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Shapes = preload("res://scripts/map_shapes.gd")
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1440,940)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	DirAccess.make_dir_recursive_absolute("res://build/map-shapes-view")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"map_shapes_view_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var failures = 0
	for shape in Shapes.IDS:
		game.reset_battle(42)
		game.expedition.current.map_shape = shape
		game.release_battle()
		game.toggle_running()
		game._process(0)
		var battle = game.battlefield
		var bounds: Rect2 = battle.field_course.bounds
		var center = Vector3(bounds.get_center().x,0,bounds.get_center().y)
		battle.camera.position = center+Vector3(0,400,0)
		battle.camera.far = 1000
		battle.camera.look_at(center,Vector3(0,0,-1))
		battle.camera.size = maxf(bounds.size.y,bounds.size.x/1.5)*1.15
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		var path = "res://build/map-shapes-view/"+shape+".png"
		if root.get_texture().get_image().save_png(path) != OK: failures += 1
	game.free()
	Fixture.clean("map_shapes_view_test")
	print("RESULT: 6 checks, ",failures," failures")
	quit(1 if failures else 0)
