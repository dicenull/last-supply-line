extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("window_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS window: ",label)
	else:
		failures += 1
		push_error(label)
func click_logical(pos: Vector2):
	var event = InputEventMouseButton.new()
	event.position = root.get_final_transform()*pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,false)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,false)
	await process_frame
func key(code: int):
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"window_test")
	root.add_child(game)
	game.set_process(false)
	check(game.WORLD_RECT.size.x >= 1400 and game.WORLD_RECT.get_area() > 900000 and is_equal_approx(game.WORLD_RECT.get_center().x,720),"main view spans the screen and is centered without a sidebar")
	check(game.HEADER_RECT.end.y < game.WORLD_RECT.position.y and game.WORLD_RECT.end.y < game.FOOTER_RECT.position.y,"header, scene and footer occupy separate regions")
	for dimensions in [Vector2i(960,628),Vector2i(1440,940),Vector2i(1280,720),Vector2i(1024,768),Vector2i(1920,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		print("WINDOW GEOMETRY: ",dimensions," actual=",root.size," minimum=",root.min_size," transform=",root.get_final_transform())
		check(root.size == dimensions,"requested native window size is active "+str(dimensions))
		var stretch = root.get_final_transform()
		check(absf(stretch.x.length()-minf(float(root.size.x)/1440,float(root.size.y)/940))*1440 <= 1.01 and absf(stretch.y.length()-minf(float(root.size.x)/1440,float(root.size.y)/940))*940 <= 1.01,"aspect is preserved within one framebuffer pixel "+str(dimensions))
		game.open_menu(true)
		await click_logical(game.menu.actions[0].get_rect().get_center())
		check(not game.menu.visible,"scaled title play click "+str(dimensions))
		var footer_only = true
		var controls: Array = []
		for child in game.get_children():
			if child is Button and child.visible:
				footer_only = footer_only and game.FOOTER_RECT.encloses(child.get_rect())
				for other in controls: footer_only = footer_only and not child.get_rect().intersects(other)
				controls.append(child.get_rect())
		check(footer_only,"all visible gameplay controls and tabs fit the footer without overlap "+str(dimensions))
		var layout_before = game.factory.layout()
		await click_logical(Vector2(1096,45))
		check(not game.factory.running and game.factory.layout() == layout_before,"header is display-only "+str(dimensions))
		game.toggle_battle()
		if game.battle_mode: game.toggle_battle()
		var target = Vector2i(6,6)
		game.factory.edit(target,"erase",0)
		game.selected = "belt"
		var point = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(target))
		await click_logical(point)
		check(game.factory.cells.has(target),"scaled 3D floor placement "+str(dimensions))
		await key(KEY_TAB)
		check(game.world.roof_closed,"Tab closes armor "+str(dimensions))
		game.factory.edit(target,"erase",0)
		await click_logical(point)
		check(not game.factory.cells.has(target),"closed roof prevents hidden edits "+str(dimensions))
		await key(KEY_TAB)
		game._process(0)
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview-layout-interior-%d.png" % dimensions.x)
		await click_logical(Vector2(830,888))
		check(game.battle_mode,"scaled B-view icon click "+str(dimensions))
		await click_logical(Vector2(1341,888))
		check(game.menu.visible,"footer menu button opens modal "+str(dimensions))
		await key(KEY_ESCAPE)
		await key(KEY_ESCAPE)
		check(game.menu.visible,"Esc menu works after resize "+str(dimensions))
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview-window-%d-%d.png" % [dimensions.x,dimensions.y])
		game.close_menu()
		game.reset_battle()
		game._process(0)
	root.size = Vector2i(600,400)
	await process_frame
	await process_frame
	check(root.size.x >= 960 and root.size.y >= 628,"native window enforces usable minimum size")
	print("WINDOW RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
