extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS responsive menu: ",label)
	else:
		failures += 1
		push_error(label)
func settle():
	await process_frame
	await process_frame
func click(button: Button, frame):
	frame.scroll.ensure_control_visible(button)
	await settle()
	var point = root.get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
	await settle()
func capture(label: String):
	await settle()
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/responsive-menu/"+label+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/responsive-menu")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"responsive_menu_test",2)
	game.show_start_menu = false
	game.touch_enabled = true
	root.add_child(game)
	game.set_process(false)
	var menu = game.menu
	var frame = menu.get_parent().get_parent().get_parent()
	for dimensions in [Vector2i(1440,940),Vector2i(844,390),Vector2i(390,844),Vector2i(768,1024),Vector2i(320,568)]:
		root.size = dimensions
		await settle()
		game.open_menu()
		await settle()
		var visual_scale = game.UIStyle.effective_scale(menu)
		check(menu.text_size(18)*visual_scale >= 16 and menu.text_size(14)*visual_scale >= 14 and menu.text_size(28)*visual_scale >= 24,"body, captions and headings respect visible pixel minimums")
		check(game.UIStyle.icon_size(menu)*visual_scale >= 24-0.001,"menu icons respect the visible 24 pixel minimum")
		check(menu.actions[0].position.x == 520 and menu.actions[2].position.x == 520 and menu.actions[4].position.x == 520,"same original single-column menu at "+str(dimensions))
		check(menu.actions[0].size == Vector2(400,44),"original icon-row design is shared across input devices")
		check(Rect2(Vector2.ZERO,frame.size).encloses(frame.scroll.get_rect()),"menu viewport stays within the available screen")
		await capture("pause-%dx%d" % [dimensions.x,dimensions.y])
		await click(menu.navigation.settings,frame)
		check(menu.page == "settings","settings remains reachable by scrolling")
		check(menu.back_button.get_theme_font_size("font_size")*visual_scale >= 16 and menu.difficulty_select.get_theme_font_size("font_size")*visual_scale >= 16,"native menu buttons share the text minimum")
		await capture("minimum-settings-%dx%d" % [dimensions.x,dimensions.y])
		await click(menu.difficulty_select,frame)
		check(menu.difficulty_popup.visible,"responsive layout preserves difficulty input coordinates")
		menu.go_back()
		await click(menu.back_button,frame)
		check(menu.page == "pause","back returns to the same menu design")
		await click(menu.navigation.history,frame)
		check(menu.page == "history","lower menu entries remain reachable")
		await capture("history-%dx%d" % [dimensions.x,dimensions.y])
		menu.show_home()
		await settle()
		await click(menu.actions[0],frame)
		check(not menu.visible and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP,"closing restores the gameplay viewport")
		game.toggle_inventory()
		await settle()
		check(game.inventory_panel.page_size >= 1 and game.inventory_panel.page_size <= 6 and game.inventory_panel.size.y <= 716,"inventory pages fit available height without scrolling: %s at %s" % [game.inventory_panel.size,dimensions])
		await capture("inventory-%dx%d" % [dimensions.x,dimensions.y])
		game.inventory_panel.hide()
	# Rotate with the settings page still open, rather than reopening it.
	game.equipment_workspace.close_all()
	game.open_menu()
	menu.show_page("settings")
	for dimensions in [Vector2i(844,390),Vector2i(390,844),Vector2i(844,390)]:
		root.size = dimensions
		await settle()
		await settle()
		frame.reflow()
		var rendered = root.get_final_transform()*frame.scroll.get_global_rect()
		check(rendered.size.x >= minf(432,dimensions.x-32)-1,"open settings retains readable width after rotation: "+str(rendered))
		await capture("rotate-settings-%dx%d" % [dimensions.x,dimensions.y])
	game.free()
	var title = load("res://scenes/start_screen.tscn").instantiate()
	title.audio_enabled = false
	title.history_path = Fixture.path_for("responsive_menu_test")
	title.audio_settings_path = "user://responsive_menu_test_audio_fixture.json"
	root.add_child(title)
	root.min_size = Vector2i(320,320)
	for dimensions in [Vector2i(1440,940),Vector2i(844,390),Vector2i(390,844)]:
		root.size = dimensions
		await settle()
		check(title.menu.actions[0].position.x == 60,"title keeps its left-aligned frameless menu")
		var actual: Rect2 = title.menu.actions[0].get_global_rect()
		check(Rect2(Vector2.ZERO,title.menu.size).encloses(actual),"title action stays within screen bounds")
		check(title.display.size == title.get_viewport_rect().size,"tank display follows the viewport aspect ratio")
		await capture("title-%dx%d" % [dimensions.x,dimensions.y])
	title.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("responsive_menu_test")
