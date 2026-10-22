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
	e.position = root.get_final_transform()*pos
	root.push_input(e,false)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e,false)
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
	game.expedition.current.erase("field_version") # Legacy route-modal input coverage.
	game.expedition.current.erase("encounters_version")
	game.toggle_running()
	for i in range(1600):
		preload("res://tests/profile_fixture.gd").drive(game,0.1)
		if game.expedition.phase == "reward": break
	game.finish_crafting()
	game.expedition.reward_options = ["production","economy","magazine"]
	check(game.expedition.phase == "reward" and game.choice_buttons[2].visible,"clear displays all three reward buttons")
	await capture("res://preview-reward.png")
	check(game.choice_popup.visible and game.choice_popup.PANEL_RECT.get_center().is_equal_approx(Vector2(720,470)) and game.battle_container.size == game.WORLD_RECT.size and game.footer_rect() == game.FOOTER_RECT,"reward opens centered modal without nesting choices in footer or shrinking scene")
	var phase_before = game.expedition.phase
	await click_at(game.start_button.get_rect().get_center())
	await click_at(Vector2(200,300))
	check(game.expedition.phase == phase_before and not game.factory.running,"modal blocks footer and background clicks")
	game.open_menu()
	# Click the covered reward card outside the pause menu's own buttons.
	await click_at(Vector2(game.choice_rect(0).position.x+4,game.choice_rect(0).get_center().y))
	check(game.menu.visible and game.expedition.phase == "reward","Esc menu overlays and blocks pending reward choices")
	game.close_menu()
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,saved) and game.choice_popup.visible and not game.factory.running,"checkpoint restore immediately reopens pending reward modal")
	root.size = Vector2i(960,628)
	await process_frame
	await process_frame
	await capture("res://preview-reward-960.png")
	await click_at(game.choice_rect(2).get_center())
	check(game.factory.ammo_capacity == 16 and game.expedition.phase == "route","clicking magazine reward changes actual capacity")
	check(game.choice_buttons[0].visible and game.choice_buttons[1].visible and not game.choice_buttons[2].visible,"route screen displays exactly two choices")
	check(game.choice_popup.visible and game.choice_popup.PANEL_RECT.encloses(game.choice_rect(1)),"route choices stay inside the centered modal")
	await capture("res://preview-route-960.png")
	root.size = Vector2i(1440,940)
	await process_frame
	await process_frame
	await capture("res://preview-route.png")
	var stock = game.factory.reserves.duplicate()
	await click_at(game.choice_rect(0).get_center())
	check(game.expedition.sector == 2 and not game.battle_mode and not game.factory.running,"route click returns to next-sector preparation")
	check(game.factory.reserves == stock,"route transition does not refill or erase stocks")
	check(game.factory_container.size == game.WORLD_RECT.size,"next-sector preparation restores the expanded central view")
	check(not game.choice_popup.visible,"choosing route closes modal")
	await click_at(game.start_button.get_rect().get_center())
	check(game.factory.running and game.expedition.phase == "travel","play starts selected sector")
	game.open_menu()
	await click_at(game.menu.utility_buttons.retreat.get_rect().get_center())
	check(game.expedition.phase == "retreated" and not game.factory.running,"flag button retreats from active run")
	print("RUN UI RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("run_ui_test")
