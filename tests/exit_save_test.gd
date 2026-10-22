extends SceneTree
const Save = preload("res://scripts/run_save.gd")
const PATH = "user://exit_save_test_fixture.mfv"
func _initialize(): call_deferred("run")
func run():
	if "--verify" in OS.get_cmdline_user_args():
		var codec = Save.new()
		var data = codec.read_file(PATH)
		var ok = not data.is_empty() and data.started and data.run.phase == "travel" and data.factory.elapsed > 0
		for suffix in ["",".tmp",".bak"]:
			if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
		print("EXIT SAVE RESULT: ","PASS" if ok else "FAIL")
		quit(0 if ok else 1)
		return
	var game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"exit_save_test")
	game.audio_enabled = true
	game.show_start_menu = false
	game.checkpoint_path = PATH
	root.add_child(game)
	game.set_process(false)
	game.menu_title = false
	game.toggle_running()
	for i in range(140): preload("res://tests/profile_fixture.gd").drive(game,0.1)
	game._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("exit_save_test")
