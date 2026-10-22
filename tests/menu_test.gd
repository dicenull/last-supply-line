extends SceneTree
var game
var checks = 0
var failures = 0
const PATH = "user://menu_test_fixture.mfv"
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS menu: ",label)
	else:
		failures += 1
		push_error(label)
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
func key(code: int):
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame
func run():
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"menu_test")
	game.checkpoint_path = PATH
	root.add_child(game)
	await create_timer(0.3).timeout
	check(game.menu.visible and game.menu_title and not game.factory.running,"startup menu pauses prepared factory")
	check(game.menu.actions[1].disabled and game.menu.actions[2].disabled,"missing continue and premature save are disabled")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-menu.png")
	var layout = game.factory.layout()
	await click_at(Vector2(250,600))
	check(game.factory.layout() == layout,"modal background blocks construction clicks")
	await click_at(game.menu.actions[0].get_rect().get_center())
	check(not game.menu.visible and not game.started,"play in title enters preparation")
	await key(KEY_ESCAPE)
	check(game.menu.layout_buttons.load.disabled and game.menu.layout_buttons.undo.disabled,"missing layout and empty undo are disabled")
	await click_at(game.menu.layout_buttons.save.get_rect().get_center())
	check(FileAccess.file_exists(game.layout_path) and game.menu_status == "victory" and not game.menu.layout_buttons.load.disabled,"layout save writes isolated file and enables load")
	await click_at(game.menu.layout_buttons.erase.get_rect().get_center())
	check(game.factory.layout().is_empty() and not game.menu.layout_buttons.undo.disabled,"menu clears layout and enables undo")
	await click_at(game.menu.layout_buttons.undo.get_rect().get_center())
	check(game.factory.layout() == layout,"menu undo restores cleared layout")
	await click_at(game.menu.layout_buttons.erase.get_rect().get_center())
	await click_at(game.menu.layout_buttons.load.get_rect().get_center())
	check(game.factory.layout() == layout and game.menu_status == "victory","layout load restores saved equipment through real click")
	var broken = FileAccess.open(game.layout_path,FileAccess.WRITE)
	broken.store_string("{}")
	broken.close()
	await click_at(game.menu.layout_buttons.load.get_rect().get_center())
	check(game.factory.layout() == layout and game.menu_status == "defeat","invalid layout reports failure without changing equipment")
	game.world.yaw += 0.5
	await click_at(game.menu.utility_buttons.camera.get_rect().get_center())
	check(is_equal_approx(game.world.yaw,0.65),"menu camera control restores view")
	await click_at(game.menu.utility_buttons.roof.get_rect().get_center())
	check(game.world.roof_closed,"menu armor control closes cutaway")
	await click_at(game.menu.utility_buttons.roof.get_rect().get_center())
	await key(KEY_ESCAPE)
	await key(KEY_SPACE)
	check(game.factory.running and game.started,"Space starts expedition after title")
	await key(KEY_ESCAPE)
	check(game.menu.visible and not game.factory.running,"Escape pauses active expedition")
	var editable = true
	for button in game.menu.layout_buttons.values(): editable = editable and not button.disabled
	var cargo_before = game.factory.ammo
	await click_at(game.menu.layout_buttons.erase.get_rect().get_center())
	game.menu.layout_action("erase")
	check(editable and game.factory.layout() != layout and game.factory.ammo == cargo_before,"paused travel allows layout management and preserves cargo")
	await click_at(game.menu.actions[2].get_rect().get_center())
	check(FileAccess.file_exists(PATH) and game.menu_status == "victory","save button writes checkpoint and shows success icon")
	await key(KEY_ESCAPE)
	check(game.factory.running and not game.menu.visible,"Escape resumes previous playback")
	await key(KEY_ESCAPE)
	await click_at(game.menu.actions[1].get_rect().get_center())
	check(not game.menu.visible and not game.factory.running and game.started,"continue loads active run in paused state")
	await key(KEY_ESCAPE)
	await click_at(game.menu.actions[3].get_rect().get_center())
	check(not game.menu.visible and not game.started and game.factory.fuel == 0,"new-run button resets run to preparation")
	await key(KEY_SPACE)
	await key(KEY_ESCAPE)
	await click_at(game.menu.utility_buttons.retreat.get_rect().get_center())
	check(game.expedition.phase == "retreated" and not game.menu.visible and not game.factory.running,"menu retreat ends run without resuming simulation")
	await key(KEY_ESCAPE)
	check(game.menu.utility_buttons.retreat.disabled,"finished run disables retreat")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print("MENU RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("menu_test")
