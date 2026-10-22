extends RefCounted
## Adapts the game to the menu. All commands and permission checks stay outside the view.
const MenuState = preload("res://scripts/run_menu_state.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
var game: Node
var menu: Control

func _init(context: Node):
	game = context

func bind(view: Control, ui):
	menu = view
	menu.configure(ui,snapshot)
	menu.action_selected.connect(game.menu_action)
	menu.blueprint_selected.connect(game.apply_blueprint)
	menu.layout_selected.connect(layout_action)
	menu.utility_selected.connect(utility_action)
	menu.difficulty_selected.connect(game.set_difficulty)
	menu.volume_changed.connect(set_volume)

func snapshot():
	var state = MenuState.new()
	state.title = game.menu_title
	state.status = game.menu_status
	state.difficulty = game.expedition.difficulty
	state.difficulty_locked = game.started or game.expedition.sector != 1
	state.can_continue = FileAccess.file_exists(game.checkpoint_path) or FileAccess.file_exists(game.checkpoint_path+".bak")
	state.can_manage_layout = game.can_manage_layout()
	state.can_undo = not game.factory.undo_stack.is_empty()
	state.can_load_layout = FileAccess.file_exists(game.layout_path)
	state.can_retreat = game.expedition.phase in ["prepare","travel"]
	state.can_apply_blueprint = game.can_apply_blueprint()
	state.roof_closed = game.world.roof_closed
	state.volume = game.sound.volume
	state.audio_error = game.sound.settings_error
	state.history_error = game.history.error
	state.researched_count = game.history.researched_blocks.size()
	state.unlocked_blueprints = game.history.unlocked.duplicate()
	var layout = game.factory.layout()
	for id in Blueprints.IDS:
		if Blueprints.matches(layout,id): state.selected_blueprints.append(id)
	state.entries = game.history.entries.slice(0,2).duplicate(true)
	return state

func set_volume(value: float):
	game.sound.set_volume(value)

func layout_action(kind: String):
	# Layout management is available in preparation and during live travel.
	if not game.can_manage_layout(): return
	var success = true
	match kind:
		"save": success = game.save_layout()
		"load": success = game.load_layout()
		"erase": game.factory.clear_layout()
		"undo":
			if game.factory.undo_stack.is_empty(): return
			game.factory.undo()
		_: return
	game.menu_status = "victory" if success else "defeat"
	menu.refresh()
	game.queue_redraw()

func utility_action(kind: String):
	match kind:
		"camera": game.reset_camera()
		"roof": game.world.toggle_roof()
		"retreat":
			if game.expedition.phase not in ["prepare","travel"]: return
			game.menu_was_running = false
			game.retreat_run()
			game.close_menu()
		_: return
	menu.refresh()
	game.queue_redraw()
