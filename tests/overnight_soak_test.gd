extends SceneTree
## Real elapsed-time soak. --duration=seconds and --speed=steps per 100 ms.
## Use headless for CPU/state longevity; this does not claim GPU coverage.
const Fixture = preload("res://tests/profile_fixture.gd")
const Run = preload("res://scripts/run_state.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
var suite = "overnight_soak_test"
var save_path = "user://overnight_soak_test.mfv"
var game
var duration = 28800.0
var steps_per_tick = 1
var start_ms = 0
var runs = 0
var wins = 0
var restores = 0
var steps = 0
var peak_nodes = 0
var peak_objects = 0
var peak_resources = 0
var retired_resources: Array = []
var failed = false
var last_report = -60.0
var last_restore = 0.0
var last_capture = -600.0
var stuck_time = 0.0
var result_file = "/tmp/last-supply-line-overnight-soak.json"
func _initialize(): call_deferred("run")
func fail(label: String):
	if failed: return
	failed = true
	push_error("OVERNIGHT: "+label)
func prepare():
	var f = game.factory
	if game.expedition.sector == 1:
		if not f.restore(Blueprints.layout("parallel")): fail("could not buy parallel starting line")
	if not f.auxiliary_ids.is_empty():
		var id = f.auxiliary_ids[0]
		if f.auxiliary_position(id) != Vector2i(9,5): f.move_auxiliary(id,Vector2i(9,5))
		f.edit(Vector2i(8,5),"splitter",3)
	for p in [Vector2i(2,6),Vector2i(4,1),Vector2i(7,1),Vector2i(4,6),Vector2i(7,4),Vector2i(9,1),Vector2i(2,1),Vector2i(10,3)]:
		if not f.cells.has(p): f.edit(p,"armor_block",0)
	game.toggle_running()
	stuck_time = 0
func new_game():
	if game != null:
		if game.expedition.phase == "won": wins += 1
		print("OVERNIGHT RUN ",JSON.stringify({"run":runs,"seed":game.expedition.run_seed,"mode":game.expedition.difficulty,"phase":game.expedition.phase,"cleared":game.expedition.cleared,"equipment":game.expedition.equipment}))
		game.queue_free()
		await process_frame
		await process_frame
		if get_node_count() > 5: fail("scene nodes survived disposal: "+str(get_node_count()))
		retired_resources.append(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
		if retired_resources.size() > 10 and retired_resources.back() > retired_resources.slice(0,5).max()+64:
			fail("resources accumulate after complete run disposal")
	runs += 1
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,suite)
	game.show_start_menu = false
	game.expedition = Run.new(41+runs*17)
	root.add_child(game)
	game.set_process(false)
	game.set_difficulty(Run.Content.DIFFICULTIES.keys()[(runs-1)%3])
	await process_frame
	prepare()
func step():
	var phase = game.expedition.phase
	if phase == "travel":
		Fixture.drive(game,0.1)
		steps += 1
		var f = game.factory
		var b = game.battlefield
		if f.reserves.scrap < 0 or f.reserves.coal < 0 or f.fuel < 0 or f.ammo < 0: fail("negative real inventory")
		if f.feedback_events.size() > 64 or b.projectiles.size() > 128 or b.bolts.size() > 128 or b.trails.size() > 90: fail("unbounded gameplay/event pool")
		for world in [game.world,b]:
			if world.feedback != null and (world.feedback.active.size() > 48 or world.feedback.get_child_count() > 48): fail("unbounded cosmetic pool")
		stuck_time = stuck_time+0.1 if f.fuel < 0.000001 and not f.wrecks.is_empty() else 0.0
		if stuck_time > 30 or b.elapsed > 240: game.retreat_run()
	elif phase == "reward":
		var priorities = ["scatter_gun","arc_gun","blast_fuse","drum_loader","armor","skirts","left_gun","right_gun","long_gun","rapid_gun","economizer"]
		var pick = 0
		for offset in range(priorities.size()):
			var id = priorities[(offset+runs)%priorities.size()]
			if "gear:"+id in game.expedition.reward_options:
				pick = game.expedition.reward_options.find("gear:"+id)
				break
		preload("res://tests/profile_fixture.gd").claim_reward(game,pick)
	elif phase == "route":
		var pick = (runs+game.expedition.sector)%game.expedition.route_options.size()
		preload("res://tests/profile_fixture.gd").claim_reward(game,pick)
	elif phase == "prepare": prepare()
func inspect(elapsed: float):
	peak_nodes = maxi(peak_nodes,get_node_count())
	peak_objects = maxi(peak_objects,int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	peak_resources = maxi(peak_resources,int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
	var snapshot = game.checkpoint.snapshot(game)
	if not game.checkpoint.validate(snapshot):
		fail("invalid live checkpoint: "+game.checkpoint.error+" phase="+game.expedition.phase)
	if elapsed-last_restore >= 60 and game.expedition.phase == "travel":
		if not game.checkpoint.write_file(save_path,snapshot): fail("checkpoint write")
		var restored = game.checkpoint.read_file(save_path)
		if restored.is_empty() or not game.checkpoint.apply(game,restored): fail("checkpoint disk restore")
		else:
			restores += 1
			if game.factory.running: fail("restore must pause before resuming")
			game.toggle_running()
		last_restore = elapsed
	# Replacement viewports are freed at the frame boundary. Include the
	# transient overlap in the peak rather than reporting a lower peak.
	peak_nodes = maxi(peak_nodes,get_node_count())
	peak_objects = maxi(peak_objects,int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	peak_resources = maxi(peak_resources,int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
	var report = {"elapsed_seconds":elapsed,"target_seconds":duration,"runs":runs,"wins":wins,"restores":restores,"steps":steps,"phase":game.expedition.phase,"sector":game.expedition.sector,"seed":game.expedition.run_seed,"peak_nodes":peak_nodes,"peak_objects":peak_objects,"peak_resources":peak_resources,"nodes":get_node_count(),"retired_resources":retired_resources,"failed":failed,"display":DisplayServer.get_name(),"pid":OS.get_process_id(),"fps":Engine.get_frames_per_second(),"window":str(root.size)}
	print("OVERNIGHT HEARTBEAT ",JSON.stringify(report))
	var file = FileAccess.open(result_file,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	else: fail("could not persist progress report")
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="): duration = maxf(1,float(arg.trim_prefix("--duration=")))
		if arg.begins_with("--speed="): steps_per_tick = clampi(int(arg.trim_prefix("--speed=")),1,100)
		if arg.begins_with("--report="): result_file = arg.trim_prefix("--report=")
		if arg.begins_with("--suite="): suite = arg.trim_prefix("--suite=")
	save_path = "user://"+suite+".mfv"
	Engine.max_fps = 30
	start_ms = Time.get_ticks_msec()
	await new_game()
	while not failed:
		var elapsed = (Time.get_ticks_msec()-start_ms)/1000.0
		if elapsed >= duration: break
		for i in range(steps_per_tick):
			if game.expedition.phase in ["won","lost","retreated"]: await new_game()
			step()
			if failed: break
		if elapsed-last_report >= 60:
			inspect(elapsed)
			last_report = elapsed
		if DisplayServer.get_name() != "headless" and elapsed-last_capture >= 600:
			root.size = [Vector2i(1440,940),Vector2i(960,628),Vector2i(1920,1080)][int(elapsed/600)%3]
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(result_file.get_base_dir()+"/frame-%05d.png" % int(elapsed))
			last_capture = elapsed
		await create_timer(0.1).timeout
	inspect((Time.get_ticks_msec()-start_ms)/1000.0)
	game.queue_free()
	await process_frame
	await process_frame
	if get_node_count() > 5: fail("final disposal leaked scene nodes")
	print("OVERNIGHT RESULT: elapsed=", (Time.get_ticks_msec()-start_ms)/1000.0," runs=",runs," wins=",wins," disk_restores=",restores," failed=",failed)
	quit(1 if failed else 0)
func _finalize():
	Fixture.clean(suite)
	for suffix in ["",".bak",".tmp"]:
		var path = save_path+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
