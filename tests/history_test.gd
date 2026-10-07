extends SceneTree
const History = preload("res://scripts/run_history.gd")
const PATH = "user://history_test_fixture.json"
var failures = 0
var checks = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func cleanup():
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
func run():
	cleanup()
	var h = History.new()
	h.load_file(PATH)
	check(h.entries.is_empty() and not h.error,"empty first launch")
	check(not h.record(PATH,1,"travel",0,0),"no unfinished outcomes")
	check(h.record(PATH,9223372036854775807,"won",5,230),"write victory")
	check(h.record(PATH,9223372036854775807,"lost",0,3) and h.entries.size() == 1 and h.entries[0].phase == "won","first outcome wins after replay")
	var loaded = History.new()
	loaded.load_file(PATH)
	check(loaded.entries == h.entries,"roundtrip exact 64 bit seed")
	check(h.record(PATH,2,"lost",2,90) and h.record(PATH,3,"retreated",1,45),"all terminal outcomes")
	var file = FileAccess.open(PATH,FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	loaded.load_file(PATH)
	check(loaded.entries.size() == 2 and not loaded.error,"backup recovery")
	check(not h.valid([{"seed":"1","phase":"won","cleared":6,"shells":2}]),"invalid schema rejected")
	check(not h.record("user://missing_history_directory/file",4,"lost",0,0) and h.entries.size() == 3,"failed write retains memory")
	for i in range(4,105): h.record(PATH,i,"retreated",0,0)
	check(h.entries.size() == 100 and h.entries[0].seed == "104","bounded newest first")
	cleanup()
	var game = load("res://main.tscn").instantiate()
	game.history_path = PATH
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.factory.manufactured = 17
	game.retreat_run()
	check(game.history.entries.size() == 1 and game.history.entries[0].shells == 17,"real retreat records production")
	game.record_result()
	check(game.history.entries.size() == 1,"repeat callback idempotent")
	game.history.record(PATH,123,"won",5,240)
	game.history.record(PATH,456,"lost",3,150)
	game.open_menu()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-history.png")
	cleanup()
	print("HISTORY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
