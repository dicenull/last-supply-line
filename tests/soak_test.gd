extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Save = preload("res://scripts/run_save.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("soak_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS soak: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var f = Factory.new()
	f.example()
	f.auto_fire = true
	f.rate = 90
	f.running = true
	# Accelerated logical-time test; deliberately unlimited input for steady production.
	for i in range(57600):
		f.step(0.25)
		f.consume_fuel(0.1)
	check(f.elapsed == 14400 and f.manufactured > 5000,"four simulated hours continue producing ammunition")
	check(f.history.size() <= 46 and f.moves.size() <= 112 and f.completed.size() <= 112,"rolling history and per-tick effects remain bounded")
	check(f.ammo <= f.ammo_capacity and f.fuel <= 12 and f.fuel >= 0,"four-hour inventory stays within capacity")
	for i in range(1000): f.edit(Vector2i(6,6),"belt",i%4)
	check(f.undo_stack.size() == 50,"repeated construction retains only fifty undo layouts")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"soak_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	game.toggle_running()
	for i in range(120): game._process(0.1)
	var codec = Save.new()
	var checkpoint = codec.snapshot(game)
	check(codec.validate(checkpoint),"soak checkpoint contains valid active production")
	game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0)
	await process_frame
	await process_frame
	var baseline_nodes = get_node_count()
	var max_nodes = baseline_nodes
	var good = true
	var resource_counts: Array = []
	var object_counts: Array = []
	var node_counts: Array = []
	for cycle in range(60):
		if cycle%2 == 0:
			game.retreat_run()
			game.reset_battle()
			game.toggle_running()
		else:
			good = codec.apply(game,checkpoint) and good
			game.toggle_running()
		for i in range(60): game._process(0.1)
		game.toggle_battle()
		game._process(0)
		game.toggle_battle()
		await process_frame
		await process_frame
		max_nodes = maxi(max_nodes,get_node_count())
		node_counts.append(get_node_count())
		resource_counts.append(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
		object_counts.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
		good = good and game.battlefield.trails.size() <= 90 and game.battlefield.projectiles.size() <= 128 and game.battlefield.collection_events.size() <= 12
	check(good,"sixty retreat restart and restore cycles preserve valid bounded encounters")
	check(max_nodes <= baseline_nodes+64,"scene nodes plateau across repeated viewport replacement")
	check(node_counts.slice(50).max() <= node_counts.slice(0,10).max()+32 and resource_counts.slice(50).max() <= resource_counts.slice(0,10).max()+64 and object_counts.slice(50).max() <= object_counts.slice(0,10).max()+200,"late cycles do not accumulate nodes objects or cached resources compared with early cycles")
	check(game.sound.get_child_count() == 9 and game.logistics.notices.size() <= 3,"feedback pools do not grow across runs")
	var paused = codec.snapshot(game)
	game.factory.running = false
	for i in range(10000): game._process(0.1)
	check(codec.snapshot(game) == paused,"one thousand paused simulated seconds do not advance saved game state")
	game.queue_free()
	await process_frame
	await process_frame
	check(get_node_count() < 10,"disposing game releases all owned scene nodes")
	print("SOAK NODES: baseline=",baseline_nodes," max=",max_nodes," remaining=",get_node_count()," resources first/last=",resource_counts.slice(0,10).max(),"/",resource_counts.slice(50).max()," objects first/last=",object_counts.slice(0,10).max(),"/",object_counts.slice(50).max())
	print("SOAK RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
