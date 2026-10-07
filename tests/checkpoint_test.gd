extends SceneTree
const Save = preload("res://scripts/run_save.gd")
const PATH = "user://checkpoint_test_fixture.mfv"
var checks = 0
var failures = 0
var games: Array = []
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS checkpoint: ",title)
	else:
		failures += 1
		push_error(title)
func _initialize(): call_deferred("run")
func make_game():
	var game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"checkpoint_test")
	game.show_start_menu = false
	game.checkpoint_path = PATH
	root.add_child(game)
	game.set_process(false)
	games.append(game)
	return game
func advance(game, seconds: float):
	for i in range(int(seconds/0.025)): game._process(0.025)
func same(a, b) -> bool:
	if a is float or b is float: return absf(float(a)-float(b)) < 0.0001
	if a is Vector3: return a.is_equal_approx(b)
	if a is Transform3D: return a.is_equal_approx(b)
	if a is Dictionary:
		if not b is Dictionary or a.size() != b.size(): return false
		for key in a:
			if key in ["pivot","turret","target_angle"] and b.has(key) and absf(angle_difference(a[key],b[key])) < 0.0001: continue
			if not b.has(key) or not same(a[key],b[key]):
				print("DIFFERENT KEY ",key)
				return false
		return true
	if a is Array:
		if not b is Array or a.size() != b.size(): return false
		for i in range(a.size()):
			if not same(a[i],b[i]): return false
		return true
	return a == b
func run():
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	var codec = Save.new()
	var original = make_game()
	var resumed = make_game()
	var prepared = codec.snapshot(original)
	check(codec.validate(prepared),"preparation snapshot validates")
	check(codec.write_file(PATH,prepared) and not codec.read_file(PATH).is_empty(),"preparation snapshot round-trips to disk")
	original.toggle_running()
	advance(original,8.5)
	check(original.battlefield.projectiles.size()+original.battlefield.bolts.size() > 0,"fixture contains live projectiles")
	var travelling = codec.snapshot(original)
	check(codec.validate(travelling),"live factory and encounter snapshot validates: "+codec.error)
	check(codec.write_file(PATH,travelling),"atomic write replaces prior checkpoint")
	check(FileAccess.file_exists(PATH+".bak"),"previous checkpoint retained as backup")
	var loaded = codec.read_file(PATH)
	check(not loaded.is_empty() and codec.apply(resumed,loaded),"restore creates factory run and encounter")
	check(not resumed.factory.running,"restore is paused")
	check(same(travelling,codec.snapshot(resumed)),"restore preserves manufacturing cargo enemies and all in-flight shots")
	resumed.toggle_running()
	advance(original,6)
	advance(resumed,6)
	check(same(codec.snapshot(original),codec.snapshot(resumed)),"continued simulation matches uninterrupted trajectory")
	original.open_menu()
	var frozen = codec.snapshot(original)
	advance(original,1)
	check(same(frozen,codec.snapshot(original)),"menu freezes factory and battle")
	original.close_menu()
	check(original.factory.running,"closing pause menu restores prior playback")
	advance(original,90)
	check(original.expedition.phase == "reward","fixture reaches reward selection")
	var reward = codec.snapshot(original)
	check(codec.apply(resumed,reward),"reward phase restores without granting twice")
	original.choose_run_option(1)
	resumed.choose_run_option(1)
	check(original.expedition.route_options == resumed.expedition.route_options,"restored random generator produces identical next routes")
	var routes = codec.snapshot(original)
	check(codec.validate(routes) and codec.apply(resumed,routes),"route selection checkpoint restores upgraded modifiers")
	var bad = routes.duplicate(true)
	bad.factory.cells[Vector2i(1,2)].items = ["unknown_item"]
	var prior = codec.snapshot(resumed)
	check(not codec.apply(resumed,bad) and same(prior,codec.snapshot(resumed)),"invalid state is rejected without touching current game")
	bad = routes.duplicate(true)
	bad.battle.projectiles = [{"target":100}]
	check(not codec.validate(bad),"malformed projectile reference rejected")
	var packet = FileAccess.get_file_as_bytes(PATH)
	packet[packet.size()-1] ^= 1
	var tampered = FileAccess.open(PATH,FileAccess.WRITE)
	tampered.store_buffer(packet)
	tampered.close()
	check(codec.read_file(PATH).is_empty() and codec.error == "checksum","payload bit flip detected by checksum")
	bad = routes.duplicate(true)
	bad.factory.work_multiplier = "wrong type"
	check(not codec.validate(bad),"wrong numeric type rejected without exceptions")
	var file = FileAccess.open(PATH,FileAccess.WRITE)
	file.store_string("broken save")
	file.close()
	check(codec.read_file(PATH).is_empty(),"truncated or corrupt file rejected")
	check(resumed.load_checkpoint() and resumed.expedition.phase == "prepare","load recovers the previous valid backup")
	DirAccess.remove_absolute(PATH+".bak")
	var before_bad_load = codec.snapshot(resumed)
	check(not resumed.load_checkpoint() and same(before_bad_load,codec.snapshot(resumed)),"missing backup leaves current run intact on load failure")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print("CHECKPOINT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("checkpoint_test")
