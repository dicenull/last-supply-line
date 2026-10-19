extends SceneTree
var game
var checks = 0
var failures = 0
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS run UI: ",title)
	else:
		failures += 1
		push_error(title)
func _initialize(): call_deferred("run")
func click_at(pos: Vector2):
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame
	game._process(0.0)
func capture(path: String):
	game.queue_redraw()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"run_ui_test")
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.toggle_running()
	for i in range(1600):
		game._process(0.1)
		if game.expedition.phase == "reward": break
	check(game.expedition.phase == "reward" and game.choice_buttons[2].visible,"clear displays all three reward buttons")
	await capture("res://preview-reward.png")
	check(game.battle_container.position.y+game.battle_container.size.y < game.choice_rect(0).position.y and game.battle_container.get_child(0).size == Vector2i(game.battle_container.size),"choice footer has reserved space outside the resized 3D viewport")
	await click_at(game.choice_rect(2).get_center())
	check(game.factory.ammo_capacity == 16 and game.expedition.phase == "route","clicking magazine reward changes actual capacity")
	check(game.choice_buttons[0].visible and game.choice_buttons[1].visible and not game.choice_buttons[2].visible,"route screen displays exactly two choices")
	await capture("res://preview-route.png")
	var stock = game.factory.reserves.duplicate()
	await click_at(game.choice_rect(0).get_center())
	check(game.expedition.sector == 2 and not game.battle_mode and not game.factory.running,"route click returns to next-sector preparation")
	check(game.factory.reserves == stock,"route transition does not refill or erase stocks")
	check(game.factory_container.size == game.WORLD_RECT.size,"next-sector preparation restores the expanded central view")
	await click_at(game.start_button.get_rect().get_center())
	check(game.factory.running and game.expedition.phase == "travel","play starts selected sector")
	game.open_menu()
	await click_at(game.menu.utility_buttons.retreat.get_rect().get_center())
	check(game.expedition.phase == "retreated" and not game.factory.running,"flag button retreats from active run")
	print("RUN UI RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("run_ui_test")
