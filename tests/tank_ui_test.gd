extends SceneTree
var game
var checks = 0
var failures = 0
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS 3D: ",title)
	else:
		failures += 1
		push_error(title)
func _initialize(): call_deferred("run")
func click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT):
	var m = InputEventMouseMotion.new()
	m.position = pos
	Input.parse_input_event(m)
	await create_timer(0.04).timeout
	var e = InputEventMouseButton.new()
	e.position = pos
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(0.05).timeout
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await create_timer(0.05).timeout
func key(code: int):
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(0.04).timeout
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
func screen(p: Vector2i) -> Vector2:
	return game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(p)+Vector3(0,0.03,0))
func screenshot(path: String):
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.7).timeout
	check(game.world.turret.position.x > 0 and game.world.turret.position.x < 4 and game.world.turret.position.z == 0, "turret is centered over the forward half of the deck")
	check(game.world.turret.position.y > game.world.DECK_Y+1.0, "turret sits above the factory equipment")
	check(game.world.mats.turret_armor.albedo_color.a < 0.5, "turret armor is translucent")
	check(game.world.camera != null and game.world.roof != null,"native 3D camera and tank hull instantiated")
	for p in [Vector2i(1,2),Vector2i(10,6),Vector2i(7,0),Vector2i(13,7)]:
		check(game.cell_at(screen(p)) == p,"3D projection maps back to deck cell "+str(p))
	await click(screen(Vector2i(1,2)))
	check(game.factory.cells.has(Vector2i(1,2)),"mouse places equipment on 3D deck")
	await key(KEY_2)
	await click(screen(Vector2i(2,2)))
	check(game.factory.cells[Vector2i(2,2)].kind == "furnace","furnace placed in 3D")
	await key(KEY_Q)
	check(game.factory.cells[Vector2i(2,2)].dir == 1,"3D hovered machinery rotates")
	await click(screen(Vector2i(1,2)),MOUSE_BUTTON_RIGHT)
	check(not game.factory.cells.has(Vector2i(1,2)),"right click removes deck equipment")
	await key(KEY_Z)
	check(game.factory.cells.has(Vector2i(1,2)),"undo restores 3D layout")
	await click(Vector2(1120,45))
	check(game.world.roof_closed and game.cell_at(screen(Vector2i(1,2))) == Vector2i(-1,-1),"closed roof blocks placement")
	for mat_name in ["turret_armor","turret_edge","turret_dark"]:
		var mat = game.world.mats[mat_name]
		check(mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and mat.albedo_color.a == 1.0,"closed roof makes turret opaque: "+mat_name)
	await screenshot("res://preview-exterior.png")
	await key(KEY_TAB)
	check(not game.world.roof_closed,"Tab opens cutaway roof")
	for mat_name in ["turret_armor","turret_edge","turret_dark"]:
		var mat = game.world.mats[mat_name]
		check(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and is_equal_approx(mat.albedo_color.a,float(mat.get_meta("interior_alpha"))),"Tab restores turret translucency: "+mat_name)
	game.world.yaw += 0.4
	game.world.pitch = 1.15
	game.world.update_camera()
	check(game.cell_at(screen(Vector2i(10,6))) == Vector2i(10,6),"picking follows camera orbit")
	var before_zoom = game.world.zoom
	await click(Vector2(550,400),MOUSE_BUTTON_WHEEL_UP)
	check(game.world.zoom < before_zoom,"mouse wheel zooms the 3D camera")
	var before_yaw = game.world.yaw
	await key(KEY_LEFT)
	check(game.world.yaw < before_yaw,"keyboard orbit works without a middle mouse button")
	game.reset_camera()
	await click(Vector2(95,897))
	check(game.factory.count_kind("press") == 1,"example layout built inside tank")
	await click(Vector2(1290,45))
	check(game.factory.running,"instrument panel starts factory")
	for i in range(300): game.factory.step(0.25)
	await screenshot("res://preview-tank.png")
	check(game.factory.shots > 20 and game.world.goods_pool.size() > 0,"real 3D materials supply firing cannon")
	await key(KEY_SPACE)
	var frames = game.world.item_frames(game.factory)
	await create_timer(0.2).timeout
	check(game.world.item_frames(game.factory) == frames,"paused 3D cargo does not move")
	check(game.start_button.text.is_empty(),"UI has no explanatory button text")
	# Run the same simulation and animation clock together, with real ammunition use.
	game.set_process(false)
	game.factory.clear_layout(false)
	game.factory.rate = 60
	game.factory.running = true
	for i in range(80):
		game.factory.step(0.025)
		game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0.025)
	check(game.world.visual_shots == 0, "empty magazine produces no visual firing")
	game.factory.ammo = 8
	var saw_flash = false
	var saw_recoil = false
	var saw_projectile = false
	var directions_ok = true
	var last_count = 0
	for i in range(400):
		game.factory.step(0.025)
		game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0.025)
		saw_flash = saw_flash or game.world.muzzle.visible
		saw_recoil = saw_recoil or game.world.barrel.position.x < game.world.BARREL_REST-0.01
		saw_projectile = saw_projectile or not game.world.projectiles.is_empty()
		if game.world.visual_shots > last_count:
			var expected = Vector3(cos(last_count*PI/2),0,-sin(last_count*PI/2))
			directions_ok = directions_ok and game.world.projectiles[-1].dir.dot(expected) > 0.999
			last_count = game.world.visual_shots
	check(game.world.fired_directions == [0,1,2,3,0,1,2,3], "full-circle turret fires all four directions in order")
	check(directions_ok, "projectiles travel along the aligned barrel direction")
	check(game.factory.shots == 8 and game.factory.ammo == 0 and game.world.visual_shots == 8, "each visible shot matches one consumed shell")
	check(saw_flash and saw_recoil and saw_projectile, "muzzle flash, recoil and traveling rounds are visible")
	var images_ok = true
	for kind in game.PixelIcons.KINDS:
		var texture = game.pixel_icons.texture(kind)
		images_ok = images_ok and texture.get_width() == 32 and texture.get_height() == 32
	check(images_ok and game.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "all pixel icons are native 32px with nearest filtering")
	# Capture a real firing moment on the already-built example for review.
	game.factory.example()
	game.factory.rate = 60
	game.factory.running = true
	game.factory.ammo = 4
	for i in range(120):
		game.factory.step(0.025)
		game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0.025)
		if game.world.visual_shots == 2 and game.world.muzzle.visible: break
	game.queue_redraw()
	await screenshot("res://preview-turret.png")
	print("3D RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
