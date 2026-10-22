extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS menu pages: ",label)
	else:
		failures += 1
		push_error(label)
func click(button: Button):
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = root.get_final_transform()*button.get_rect().get_center()
	root.push_input(e,false)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e,false)
	await process_frame
func escape():
	var e = InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)
	await process_frame
func capture(label: String):
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/menu-audit/"+label+".png")
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"menu_pages_test")
	root.add_child(game)
	game.set_process(false)
	var menu = game.menu
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		await process_frame
		game.open_menu(true)
		check(menu.page == "start" and menu.actions[0].visible and not menu.actions[2].visible and not menu.navigation.workshop.visible,"start screen contains entry points without save or construction controls")
		await escape()
		check(menu.visible and game.menu_title and not game.started,"Esc on start screen does not accidentally start or resume a run")
		await capture("start-"+str(dimensions.x))
		await click(menu.navigation.settings)
		check(menu.page == "settings" and menu.volume_slider.visible and menu.difficulty_select.visible and not menu.actions[0].visible,"real click opens separate settings screen")
		var volume = game.sound.volume
		await click(menu.mute_button)
		check(game.sound.volume == 0,"settings mute changes actual audio")
		await click(menu.mute_button)
		check(is_equal_approx(game.sound.volume,volume),"settings unmute restores previous level")
		await capture("settings-"+str(dimensions.x))
		await click(menu.difficulty_select)
		check(menu.difficulty_popup.visible,"settings opens difficulty choice")
		await escape()
		check(menu.page == "settings" and not menu.difficulty_popup.visible,"Esc first closes difficulty choice")
		await escape()
		check(menu.page == "start" and menu.visible,"Esc returns settings to start")
		await click(menu.navigation.history)
		check(menu.page == "history" and not menu.volume_slider.visible and not menu.layout_buttons.save.visible,"history screen excludes settings and layout controls")
		await capture("history-"+str(dimensions.x))
		await click(menu.back_button)
		await click(menu.actions[0])
		check(not menu.visible and not game.started,"start enters preparation")
		game.toggle_running()
		game.open_menu()
		check(menu.page == "pause" and menu.actions[2].visible and not menu.volume_slider.visible,"pause screen offers run actions without settings clutter")
		await capture("pause-"+str(dimensions.x))
		await click(menu.navigation.workshop)
		check(menu.page == "workshop" and menu.layout_buttons.save.visible and menu.blueprint_buttons[0].visible and not menu.actions[3].visible,"workshop groups layout, templates and vehicle display")
		await capture("workshop-"+str(dimensions.x))
		await escape()
		check(menu.visible and menu.page == "pause" and not game.factory.running,"back from workshop keeps paused simulation")
		await click(menu.navigation.settings)
		check(menu.difficulty_select.disabled,"in-run settings preserve difficulty lock")
		await click(menu.back_button)
		await escape()
		check(not menu.visible and game.factory.running,"Esc from pause restores prior running state")
		game.reset_battle(42)
	game.queue_free()
	await process_frame
	print("MENU PAGES RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("menu_pages_test")
