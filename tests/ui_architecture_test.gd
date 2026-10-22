extends SceneTree
## The menu must be usable without the main scene, and detached data must stay detached.
const Menu = preload("res://scripts/run_menu.gd")
const MenuState = preload("res://scripts/run_menu_state.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
var checks = 0
var failures = 0
var events: Array = []
var state = MenuState.new()

func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS UI architecture: ",title)
	else:
		failures += 1
		push_error(title)

func _initialize(): call_deferred("run")

func run():
	var menu = Menu.new()
	menu.configure(UIStyle.new(),func(): return state)
	menu.action_selected.connect(func(index): events.append(["action",index]))
	menu.layout_selected.connect(func(kind): events.append(["layout",kind]))
	menu.utility_selected.connect(func(kind): events.append(["utility",kind]))
	menu.blueprint_selected.connect(func(id): events.append(["blueprint",id]))
	menu.difficulty_selected.connect(func(id): events.append(["difficulty",id]))
	menu.volume_changed.connect(func(value):
		events.append(["volume",value])
		state.volume = value)
	root.add_child(menu)
	menu.refresh()
	check(menu.actions.size() == 5 and menu.blueprint_buttons.size() == 3,"menu initializes without game, audio, world, or profile services")
	check(menu.actions[1].disabled and menu.actions[2].disabled and menu.layout_buttons.erase.disabled,"unavailable commands are disabled from presentation state")
	state.title = false
	state.can_continue = true
	state.can_manage_layout = true
	state.can_undo = true
	state.can_load_layout = true
	state.unlocked_blueprints = ["standard","parallel"]
	state.roof_closed = true
	menu.refresh()
	check(not menu.actions[1].disabled and not menu.actions[2].disabled and not menu.layout_buttons.undo.disabled,"refresh reads the latest supplied snapshot")
	check(not menu.blueprint_buttons[1].disabled and menu.blueprint_buttons[2].disabled and menu.utility_label("roof") == "装甲を開く","view derives blueprint and roof presentation without live game references")
	menu.actions[0].pressed.emit()
	menu.layout_buttons.erase.pressed.emit()
	menu.utility_buttons.retreat.pressed.emit()
	menu.blueprint_buttons[1].pressed.emit()
	menu.difficulty_buttons[2].pressed.emit()
	check(events == [["action",0],["layout","erase"],["utility","retreat"],["blueprint","parallel"],["difficulty","hard"]],"buttons emit commands without changing the supplied game state")
	menu.volume_slider.value = 60
	check(is_equal_approx(state.volume,0.6),"slider delegates volume changes through its signal")
	menu.mute_button.pressed.emit()
	check(state.volume == 0 and menu.volume_slider.value == 0,"mute reflects the handler's updated state")
	menu.mute_button.pressed.emit()
	check(is_equal_approx(state.volume,0.6),"unmute restores the preceding volume through the same contract")
	menu.free()
	var choices = preload("res://scripts/run_choice_popup.gd").new()
	root.add_child(choices)
	check(not choices.visible and choices.buttons.size() == 3,"choice popup initializes on its own in preparation")
	choices.free()

	var game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"ui_architecture_test")
	root.add_child(game)
	game.set_process(false)
	var snapshot = game.menu_presenter.snapshot()
	snapshot.unlocked_blueprints.clear()
	snapshot.entries.append({"seed":"isolated"})
	check(game.history.unlocked.has("standard") and game.history.entries.is_empty(),"presentation collections cannot mutate the player's history")
	game.close_menu()
	game.toggle_running()
	game.open_menu()
	var layout = game.factory.layout()
	var saved = game.checkpoint.snapshot(game)
	game.retreat_run()
	game.open_menu()
	game.menu.layout_selected.emit("erase")
	check(game.factory.layout() == layout,"command handler rejects layout changes after retreat even when a disabled view is bypassed")
	var old_run = game.expedition
	check(game.checkpoint.apply(game,saved) and game.expedition != old_run and game.choice_popup.expedition == game.expedition and game.choice_popup.factory == game.factory,"choice providers follow replacement models after restoring a checkpoint")
	var presenter = weakref(game.menu_presenter)
	game.free()
	check(presenter.get_ref() == null,"freeing the scene releases its presenter and signal bindings")
	preload("res://tests/profile_fixture.gd").clean("ui_architecture_test")
	print("UI ARCHITECTURE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
