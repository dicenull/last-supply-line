extends SceneTree
const Blueprints = preload("res://scripts/blueprints.gd")
const Factory = preload("res://scripts/factory.gd")
const History = preload("res://scripts/run_history.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
const SUITE = "blueprint_test"
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS blueprint: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean(SUITE)
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
func run():
	Fixture.clean(SUITE)
	var path = Fixture.path_for(SUITE)
	var h = History.new()
	h.load_file(path)
	check(h.unlocked == ["standard"],"first profile starts with original example")
	check(h.unlock_for_clear(path,1) and h.unlocked == ["standard","parallel"],"first clear grants parallel blueprint")
	check(h.unlock_for_clear(path,2) and h.unlocked.size() == 2,"second clear does not grant third-clear design")
	check(h.unlock_for_clear(path,3) and h.unlocked.size() == 3,"third clear grants buffered blueprint")
	for i in range(105): h.record(path,i,"retreated",0,0)
	var loaded = History.new()
	loaded.load_file(path)
	check(loaded.unlocked.size() == 3 and loaded.entries.size() == 100,"unlock persists after history retention expires")
	var broken = FileAccess.open(path,FileAccess.WRITE)
	broken.store_string(JSON.stringify({"version":2,"entries":[],"unlocked":["unknown"]}))
	broken.close()
	loaded.load_file(path)
	check(loaded.unlocked.size() == 3 and not loaded.error,"invalid blueprint metadata recovers valid backup")

	check(not h.unlock_for_clear("user://no_blueprint_directory/file",6),"out-of-range progress rejected")
	var fresh = History.new()
	check(not fresh.unlock_for_clear("user://no_blueprint_directory/file",1) and fresh.unlocked == ["standard"],"write failure does not claim persistent unlock")
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"entries":[{"seed":"17","phase":"retreated","cleared":3,"shells":30}]}))
	file.close()
	loaded.load_file(path)
	check(loaded.unlocked.size() == 3 and loaded.entries[0].seed == "17","old profile migrates unlocks from recorded progress")
	var produced = {}
	for id in Blueprints.IDS:
		var f = Factory.new()
		f.auto_fire = false
		f.finite_resources = true
		check(f.restore(Blueprints.layout(id)),"valid equipment limits and fixed ports: "+id)
		for tick in range(320):
			f.simulate_tick()
			if tick%4 == 0: f.fire_round()
			f.consume_fuel(0.1)
		produced[id] = f.manufactured
		check(f.supplied > 0 and f.fuel_used > 0 and f.reserves.scrap < 48 and f.reserves.coal < 32,"real ammo and fuel supplied from finite material: "+id)
	check(produced.parallel > produced.standard,"parallel design has greater actual output")
	var stock = Factory.new()
	stock.auto_fire = false
	stock.finite_resources = true
	stock.restore(Blueprints.layout("buffered"))
	for tick in range(400): stock.simulate_tick()
	check(stock.ammo == 12 and stock.cells[Vector2i(7,2)].items.size() == 8 and stock.cells[Vector2i(8,2)].items.size() == 8,"buffered design accumulates two real magazines behind full turret")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,SUITE)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	check(game.menu.blueprint_buttons[1].disabled and game.menu.blueprint_buttons[2].disabled,"unearned designs are visibly disabled")
	var before = game.factory.layout()
	await click_at(Vector2(690,180))
	check(game.factory.layout() == before and not game.apply_blueprint("parallel"),"locked click and direct call leave layout unchanged")
	game.history.unlock_for_clear(path,3)
	game.menu.refresh()
	await click_at(Vector2(690,180))
	check(Blueprints.matches(game.factory.layout(),"parallel") and game.factory.ammo == 0 and game.factory.reserves == {"scrap":48,"coal":32},"actual card click applies layout without free products")
	game.factory.undo()
	check(game.factory.layout() == before,"blueprint placement can be undone")
	await click_at(Vector2(950,180))
	check(Blueprints.matches(game.factory.layout(),"buffered"),"actual buffered card selects storage layout")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-blueprints.png")
	game.close_menu()
	game.toggle_running()
	game.open_menu()
	check(game.menu.blueprint_buttons[0].disabled and not game.apply_blueprint("standard"),"paused travel cannot erase cargo with a blueprint")
	game.close_menu()
	game.expedition.phase = "prepare"
	game.expedition.sector = 2
	game.started = false
	check(not game.apply_blueprint("standard"),"later sector preparation preserves carried cargo")
	game.reset_battle()
	check(game.apply_blueprint("parallel"),"new run retains unlocked designs")
	game.history.unlocked = ["standard"]
	game.toggle_running()
	for tick in range(1600):
		game._process(0.1)
		if game.expedition.phase != "travel": break
	check(game.expedition.phase == "reward" and "parallel" in game.history.unlocked and "parallel" in game.new_blueprints,"real first-sector win unlocks design before ending run")
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-blueprint-reward.png")
	game.history = History.new()
	game.history.load_file(path)
	check("parallel" in game.history.unlocked,"sector unlock survives profile reload")
	game.choose_run_option(0)
	game.choose_run_option(0)
	check(game.new_blueprints.is_empty(),"unlock notice clears when departing for next sector")
	game.record_result()
	check(game.new_blueprints.is_empty(),"existing unlock does not create another notification")
	print("BLUEPRINT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
