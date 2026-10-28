extends Control
## Owns the title scene. The gameplay scene is created only on start/continue.
const UIStyle = preload("res://scripts/ui_style.gd")
const MenuState = preload("res://scripts/run_menu_state.gd")
var checkpoint_path = "user://run_save.mfv"
var history_path = "user://run_history.json"
var layout_path = "user://ammo_layout.json"
var audio_settings_path = "user://audio_settings.json"
var audio_enabled = true
var difficulty = "normal"
var status = ""
var transitioning = false
var menu
var catalog
var tank
var display: SubViewportContainer
var sound
var history = preload("res://scripts/run_history.gd").new()

func _ready():
	get_window().min_size = Vector2i(320,320) if DisplayServer.is_touchscreen_available() else Vector2i(960,628)
	get_tree().auto_accept_quit = false
	history.load_file(history_path)
	display = preload("res://scenes/world_viewport.tscn").instantiate()
	display.name = "TankDisplay"
	display.size = Vector2(1440,940)
	add_child(display)
	tank = preload("res://scripts/title_tank.gd").new()
	display.get_node("Viewport").add_child(tank)
	sound = preload("res://scripts/game_audio.gd").new()
	sound.settings_path = audio_settings_path
	sound.enabled = audio_enabled
	add_child(sound)
	var ui = UIStyle.new()
	ui.font = UIStyle.create_font()
	menu = preload("res://scripts/run_menu.gd").new()
	menu.standalone_title = true
	menu.configure(ui,snapshot)
	menu.action_selected.connect(select_action)
	menu.catalog_requested.connect(open_catalog)
	menu.volume_changed.connect(func(value): sound.set_volume(value))
	menu.difficulty_selected.connect(func(value): difficulty = value)
	menu.framed = true
	var menu_frame = preload("res://scripts/responsive_frame.gd").new()
	menu_frame.expand_viewport = true
	menu_frame.shade = true
	add_child(menu_frame)
	menu_frame.mount(menu,menu.frame_bounds)
	menu.show()
	menu.refresh()
	catalog = preload("res://scripts/item_catalog_page.gd").new()
	add_child(catalog)
	catalog.closed.connect(func(): menu.show(); menu.refresh())

func open_catalog():
	menu.hide()
	catalog.open()

func _process(_delta):
	if display != null: display.size = get_viewport_rect().size

func snapshot():
	var state = MenuState.new()
	state.title = true
	state.status = status
	state.difficulty = difficulty
	state.can_continue = FileAccess.file_exists(checkpoint_path) or FileAccess.file_exists(checkpoint_path+".bak")
	state.volume = sound.volume
	state.audio_error = sound.settings_error
	state.history_error = history.error
	state.entries = history.entries.slice(0,2).duplicate(true)
	return state

func select_action(index: int):
	if transitioning: return
	match index:
		0, 1:
			transitioning = true
			# Finish the input dispatch before replacing the scene and its controls.
			launch_game.call_deferred(index == 1)
		4:
			if not OS.has_feature("web"): get_tree().quit()

func launch_game(continue_run: bool):
	menu.hide()
	var game = load("res://main.tscn").instantiate()
	game.show_start_menu = false
	game.menu_title = false
	game.checkpoint_path = checkpoint_path
	game.history_path = history_path
	game.layout_path = layout_path
	game.audio_settings_path = audio_settings_path
	game.audio_enabled = audio_enabled
	get_tree().root.add_child(game)
	if continue_run and not game.load_checkpoint():
		game.free()
		transitioning = false
		status = "保存データを読み込めませんでした。"
		menu.show()
		menu.refresh()
		return
	if not continue_run: game.set_difficulty(difficulty)
	get_tree().current_scene = game
	queue_free()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if catalog.visible: catalog.close()
		else: menu.go_back()
		get_viewport().set_input_as_handled()

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not transitioning: get_tree().quit()
