extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const SUITE = "start_screen_test"
const SAVE = "user://start_screen_test.mfv"
var checks = 0
var failures = 0

func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS start screen: ",label)
	else:
		failures += 1
		push_error(label)

func new_title():
	var title = load("res://scenes/start_screen.tscn").instantiate()
	title.checkpoint_path = SAVE
	title.history_path = Fixture.path_for(SUITE)
	title.audio_settings_path = "user://"+SUITE+"_audio_fixture.json"
	title.layout_path = "user://"+SUITE+"_layout_fixture.json"
	title.audio_enabled = false
	root.add_child(title)
	current_scene = title
	return title

func click(button: Button):
	await process_frame
	await process_frame
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion,false)
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
	await process_frame

func escape():
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event,false)
	await process_frame

func capture(label: String):
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/start-screen/"+label+".png")

func run():
	Fixture.clean(SUITE)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix): DirAccess.remove_absolute(SAVE+suffix)
	DirAccess.make_dir_recursive_absolute("res://build/start-screen")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/start_screen.tscn","project starts in a separate title scene")
	var title = new_title()
	await process_frame
	check(title.get("factory") == null and title.get("expedition") == null and root.get_child_count() == 1,"title owns no live factory, expedition, or gameplay scene")
	check(title.tank.roof_closed and title.tank.layout_version == 2,"large display uses the current tank with closed armor")
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		await process_frame
		var menu = title.menu
		check(menu.standalone_title and menu.actions[0].position.x == 60 and menu.actions[0].size.x == 320,"start actions sit at the left edge at "+str(dimensions.x))
		check(menu.actions[1].disabled,"continue is disabled when no checkpoint exists")
		check(menu.actions[0].get_theme_stylebox("normal").bg_color.a == 0,"title actions have no window or button background")
		await escape()
		check(current_scene == title and menu.page == "start","Escape cannot start gameplay from title")
		await capture("title-"+str(dimensions.x))
		await click(menu.navigation.settings)
		check(menu.page == "settings" and menu.volume_slider.visible,"settings opens from the left menu")
		await click(menu.difficulty_select)
		await click(menu.difficulty_buttons[2])
		check(title.difficulty == "hard" and not menu.difficulty_popup.visible,"difficulty selection stays available before creating gameplay")
		menu.volume_slider.value = 40
		check(is_equal_approx(title.sound.volume,0.4),"title settings persist volume through the existing audio service")
		await escape()
		check(menu.page == "start","settings returns to the independent title")
		await click(menu.navigation.history)
		check(menu.page == "history" and menu.state.entries.is_empty(),"history opens without creating gameplay")
		await click(menu.back_button)
		check(menu.page == "start","history back returns to the left menu")
	var old_title = weakref(title)
	await click(title.menu.actions[0])
	var game = current_scene
	check(old_title.get_ref() == null and game.scene_file_path == "res://main.tscn","starting replaces and frees the title scene")
	check(not game.menu.visible and not game.started and game.expedition.phase == "prepare" and game.expedition.difficulty == "hard","start enters preparation with selected difficulty")
	check(game.expedition.item_mode and game.factory.layout_version == 2 and is_equal_approx(game.sound.volume,0.4),"current equipment layout and audio settings reach gameplay")
	game.toggle_running()
	game.factory.running = false
	var seed = game.expedition.run_seed
	check(game.checkpoint.write_file(SAVE+".bak",game.checkpoint.snapshot(game)),"create an isolated resume fixture")
	game.free()
	current_scene = null
	var broken = FileAccess.open(SAVE,FileAccess.WRITE)
	broken.store_string("broken checkpoint")
	broken.close()
	title = new_title()
	await process_frame
	check(not title.menu.actions[1].disabled,"backup checkpoint enables continue")
	await click(title.menu.actions[1])
	game = current_scene
	check(game.scene_file_path == "res://main.tscn" and game.started and game.expedition.run_seed == seed and not game.factory.running,"continue recovers the backup into paused gameplay")
	game.free()
	current_scene = null
	DirAccess.remove_absolute(SAVE+".bak")
	title = new_title()
	await process_frame
	await click(title.menu.actions[1])
	check(current_scene == title and not title.transitioning and root.get_child_count() == 1 and title.status != "","invalid checkpoint keeps title usable and releases the failed game")
	await click(title.menu.actions[0])
	check(current_scene.scene_file_path == "res://main.tscn" and not current_scene.started,"a new game still works after a failed resume")
	current_scene.free()
	current_scene = null
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	Fixture.clean(SUITE)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix): DirAccess.remove_absolute(SAVE+suffix)
