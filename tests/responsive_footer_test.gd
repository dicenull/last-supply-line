extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
var game
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS responsive footer: ",label)
	else:
		failures += 1
		push_error(label)
func click(button):
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.pressed = pressed
		event.button_index = MOUSE_BUTTON_LEFT
		root.push_input(event,false)
	game._process(0)
	game.touch_controls.refresh()
	await process_frame
func capture(label):
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/responsive-footer/"+label+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/responsive-footer")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"responsive_footer_test",2)
	game.show_start_menu = false
	game.touch_enabled = true
	root.add_child(game)
	game.set_process(false)
	game.factory.unlocked_blocks = game.RunState.Content.BLOCK_LIMITS.keys()
	for dimensions in [Vector2i(1440,940),Vector2i(960,628),Vector2i(844,390)]:
		root.size = dimensions
		await process_frame
		game._process(0)
		game.touch_controls.refresh()
		check(game.footer_layout.compact == (dimensions.y < 628),"layout responds to available screen space")
		for index in game.TOOL_TABS.size():
			await click(game.tool_tabs[index])
			check(game.tool_page == index,"mouse click selects category "+str(index))
			var controls: Array = []
			var clear = true
			for entry in game.icon_buttons:
				if not entry.button.visible: continue
				var rect: Rect2 = entry.button.get_rect()
				clear = clear and game.footer_rect().encloses(rect) and not game.world_rect().intersects(rect)
				for other in controls: clear = clear and not rect.intersects(other)
				controls.append(rect)
			check(clear,"all category "+str(index)+" icons fit without overlapping the world or each other")
			check(game.tool_buttons.keys() == game.tool_kinds(),"every available building remains reachable")
		var before = game.direction
		await click(game.touch_controls.buttons.rotate)
		check(game.direction == (before+1)%4,"real mouse works on the same footer even on a touch-capable device")
		await click(game.touch_controls.buttons.stow)
		check(game.touch_controls.mode == "stow","shared storage icon selects storage mode")
		await click(game.tool_tabs[0])
		check(game.touch_controls.mode == "build","choosing a category cancels storage mode")
		await capture("prepare-%d" % dimensions.x)
		if dimensions.x == 844:
			var cell: Vector2 = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(Vector2i.ZERO))
			print("FOOTER WEB CELL: ",cell)
			for id in ["inventory","stow","play","menu"]: print("FOOTER WEB ",id,": ",game.touch_controls.buttons[id].get_rect().get_center())
		game.toggle_running()
		game._process(0)
		game.touch_controls.refresh()
		check(game.touch_controls.stick_center.y+game.touch_controls.STICK_RADIUS < game.footer_rect().position.y,"driving stick stays above the footer")
		await capture("travel-%d" % dimensions.x)
		game.reset_battle(42)
		game.factory.unlocked_blocks = game.RunState.Content.BLOCK_LIMITS.keys()
	game.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("responsive_footer_test")
