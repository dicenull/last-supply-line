extends SceneTree
const History = preload("res://scripts/run_history.gd")
const Content = preload("res://scripts/content.gd")
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
const SUITE = "research_test"
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS research: ",label)
	else:
		failures += 1
		push_error(label)
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	Fixture.clean(SUITE)
	var path = Fixture.path_for(SUITE)
	var h = History.new()
	h.load_file(path)
	check(h.researched_blocks.is_empty(),"first profile knows only the basic facilities")
	check(h.unlock_for_clear(path,3) and h.researched_blocks.is_empty(),"stage clears unlock layout templates but no new facilities")
	check(h.record(path,1,"won",5,30) and h.record(path,2,"retreated",2,20) and h.researched_blocks.is_empty(),"winning and retreating do not grant research")
	check(h.record(path,3,"lost",0,1) and h.researched_blocks.size() == 1,"first death grants exactly one advanced blueprint")
	var first = h.researched_blocks.duplicate()
	check(h.record(path,3,"lost",0,1) and h.researched_blocks == first,"repeat death callback grants nothing twice")
	var loaded = History.new()
	loaded.load_file(path)
	check(loaded.researched_blocks == first and loaded.research_receipts == h.research_receipts,"research and death receipt survive disk reload")
	check(not h.record("user://no_research_directory/file",4,"lost",0,0) and h.researched_blocks == first,"failed write grants no phantom research")
	for i in range(100,201): h.record(path,i,"retreated",0,0)
	check(h.entries.size() == 100 and h.entries.all(func(row): return row.seed != "3"),"old death leaves bounded result journal")
	check(h.record(path,3,"lost",0,0) and h.researched_blocks == first,"receipt prevents duplicate research even after journal eviction")
	for i in range(10,19):
		check(h.record(path,i,"lost",0,0) and h.researched_blocks.size() == i-8,"each distinct death adds one unseen facility")
	check(h.researched_blocks.size() == Content.BLOCKS.size() and h.record(path,19,"lost",0,0) and h.researched_blocks.size() == 10,"all ten facilities reachable and research stops at completion")
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	loaded.load_file(path)
	check(loaded.researched_blocks.size() == 10 and not loaded.error,"backup recovery retains permanent research")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":2,"entries":[{"seed":"4","phase":"lost","cleared":2,"shells":20}],"unlocked":["standard","parallel"]}))
	file.close()
	loaded.load_file(path)
	check(loaded.unlocked.size() == 2 and loaded.researched_blocks.is_empty(),"old profile preserves templates without retroactive grants")
	check(loaded.record(path,4,"lost",2,20) and loaded.researched_blocks.is_empty(),"old recorded death cannot be replayed for a grant")
	# Exercise actual battle loss, persistence, new-run construction and old checkpoints.
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,SUITE)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(960,628)
	var before_death = game.checkpoint.snapshot(game)
	game.toggle_running()
	game.battlefield.hull = 0
	game.battlefield.result = -1
	game._process(0.1)
	check(game.expedition.phase == "lost" and game.history.researched_blocks.size() == 1,"actual combat death permanently unlocks one facility")
	var id: String = game.history.researched_blocks[0]
	check(id in game.new_blueprints,"loss header announces the newly unlocked facility")
	game.queue_redraw()
	await capture("res://preview-research-loss-960.png")
	loaded.load_file(path)
	check(loaded.researched_blocks == [id],"actual death is persisted immediately")
	var death_save = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,death_save) and game.record_result() and game.history.researched_blocks == [id],"reloading a dead run cannot grant another blueprint")
	check(game.checkpoint.apply(game,before_death) and id in game.factory.unlocked_blocks,"older run checkpoint cannot revoke permanent research")
	game.ensure_battle()
	game.reset_battle()
	check(id in game.factory.unlocked_blocks and game.factory.count_kind(id) == 0 and game.expedition.equipment.is_empty(),"new run keeps designs but resets built items and equipment")
	var stock = game.factory.reserves.duplicate()
	game.factory.edit(Vector2i(12,7),id,0)
	check(game.factory.count_kind(id) == 1 and game.factory.reserves.scrap == stock.scrap-Content.BUILD_COSTS[id].scrap and game.factory.reserves.coal == stock.coal-Content.BUILD_COSTS[id].coal,"new run can construct unlocked design using its materials")
	game.tool_page = 0
	while not game.tool_buttons.has(id): game.cycle_tools()
	game._process(0)
	check(not game.tool_buttons[id].disabled,"unlocked facility becomes selectable in footer")
	await capture("res://preview-research-build-960.png")
	game.open_menu()
	await capture("res://preview-research-menu-960.png")
	game.close_menu()
	# Switching difficulty starts a fresh kit rather than preserving paid blocks for free.
	game.set_difficulty("hard")
	check(game.factory.count_kind(id) == 0 and game.factory.reserves.scrap == Content.DIFFICULTIES.hard.scrap,"difficulty changes reset construction and budget together")
	print("RESEARCH RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean(SUITE)
