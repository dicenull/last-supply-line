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
	await click_at(Vector2(600,600))
	check(game.factory.layout() == layout,"modal background blocks construction clicks")
	await click_at(Vector2(460,478))
	check(not game.menu.visible and not game.started,"play in title enters preparation")
	await key(KEY_SPACE)
	check(game.factory.running and game.started,"Space starts expedition after title")
	await key(KEY_ESCAPE)
	check(game.menu.visible and not game.factory.running,"Escape pauses active expedition")
	await click_at(Vector2(720,478))
	check(FileAccess.file_exists(PATH) and game.menu_status == "victory","save button writes checkpoint and shows success icon")
	await key(KEY_ESCAPE)
	check(game.factory.running and not game.menu.visible,"Escape resumes previous playback")
	await key(KEY_ESCAPE)
	await click_at(Vector2(590,478))
	check(not game.menu.visible and not game.factory.running and game.started,"continue loads active run in paused state")
	await key(KEY_ESCAPE)
	await click_at(Vector2(850,478))
	check(not game.menu.visible and not game.started and game.factory.fuel == 0,"new-run button resets run to preparation")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print("MENU RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("menu_test")
