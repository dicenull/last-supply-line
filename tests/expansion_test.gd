extends SceneTree
const Content = preload("res://scripts/content.gd")
const Factory = preload("res://scripts/factory.gd")
const Run = preload("res://scripts/run_state.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS expansion: ",title)
	else:
		failures += 1
		push_error(title)
func _initialize(): call_deferred("run")
func factory_with(kind: String):
	var f = Factory.new()
	f.auto_fire = false
	f.cells.clear()
	f.cells[Vector2i(4,4)] = f.make_cell(kind,0)
	f.cells[Vector2i(5,4)] = f.make_cell("belt",0)
	f.cells[Vector2i(4,5)] = f.make_cell("belt",0)
	f.cells[Vector2i(4,3)] = f.make_cell("belt",0)
	return f
func blocks():
	check(Content.EQUIPMENT.size() == 300 and Content.BASE_EQUIPMENT.size() == 17 and Content.ENEMIES.size() == 16 and Factory.LIMITS.size() == 17 and Run.REWARDS.size() == 15,"expanded catalogs include new weapons, enemy roles and defense block")
	for kind in Factory.FILTERS:
		var f = factory_with(kind)
		var c = f.cells[Vector2i(4,4)]
		var expected = Factory.FILTERS[kind]
		var accepted = []
		for item in ["scrap","steel","shell","coal","fuel"]:
			if f.accepts_kind(c,item): accepted.append(item)
		c.items = [expected]
		f.simulate_tick()
		check(accepted == [expected] and f.cells[Vector2i(5,4)].items == [expected],"filter accepts and transports only its selected material: "+kind)
	for item in ["shell","fuel","coal"]:
		var f = factory_with("smart_splitter")
		f.cells[Vector2i(4,4)].items = [item]
		f.simulate_tick()
		check(f.cells[Vector2i(5,4) if item == "shell" else Vector2i(4,5)].items == [item],"material splitter chooses correct exit: "+item)
	var f = factory_with("priority_splitter")
	f.cells[Vector2i(4,4)].items = ["shell"]
	f.cells[Vector2i(5,4)].items = ["coal"]
	f.simulate_tick()
	check(f.cells[Vector2i(4,5)].items == ["shell"],"priority splitter overflows when primary output is full")
	f = factory_with("router")
	var outputs = []
	for i in range(3):
		f.cells[Vector2i(4,4)].items = ["shell"]
		f.simulate_tick()
		outputs.append(f.moves[0].to)
		for p in [Vector2i(5,4),Vector2i(4,5),Vector2i(4,3)]: f.cells[p].items.clear()
	check(outputs == [Vector2i(5,4),Vector2i(4,5),Vector2i(4,3)],"router fairly cycles all three outputs")
	f = factory_with("overflow_gate")
	f.cells[Vector2i(4,4)].items = ["shell","shell","shell"]
	f.simulate_tick()
	check(f.moves.is_empty(),"batch buffer holds partial batch")
	f.cells[Vector2i(4,4)].items.append("shell")
	f.simulate_tick()
	f.simulate_tick()
	check(f.cells[Vector2i(5,4)].items == ["shell"] and f.cells[Vector2i(4,4)].items.size() == 3,"full batch starts releasing actual stored materials")
	f = factory_with("blast_furnace")
	f.reserves.coal = 1
	f.cells[Vector2i(4,4)].items = ["scrap"]
	for i in range(3): f.simulate_tick()
	check(f.cells[Vector2i(4,4)].items == ["steel"] and f.reserves.coal == 0,"blast furnace converts in three ticks and consumes coal exactly once")
	f.cells[Vector2i(4,4)].items = ["scrap"]
	for i in range(8): f.simulate_tick()
	check(f.cells[Vector2i(4,4)].items == ["scrap"],"coal-starved blast furnace cannot manufacture for free")
	f = factory_with("auto_press")
	f.cells[Vector2i(4,4)].items = ["steel"]
	for i in range(4): f.simulate_tick()
	check(f.manufactured == 0,"powered press waits for real fuel")
	f.fuel = 0.08
	for i in range(4): f.simulate_tick()
	check(f.manufactured == 1 and is_zero_approx(f.fuel) and f.cells[Vector2i(4,4)].items == ["shell"],"powered press consumes fuel to produce one real shell")
	f = factory_with("fuel_depot")
	var depot = f.cells[Vector2i(4,4)]
	depot.items = ["fuel","fuel","fuel","fuel","fuel","fuel","fuel","fuel"]
	check(not f.can_receive(depot,"fuel") and not f.accepts_kind(depot,"shell"),"fuel store is fuel-only and capped at eight")
	f.simulate_tick()
	check(depot.items.size() == 7 and f.cells[Vector2i(5,4)].items == ["fuel"],"fuel store supplies a downstream fuel line")
func roster_checks():
	var roles = {}
	for difficulty in Content.DIFFICULTIES:
		var r = Run.new(42,difficulty)
		var duplicate = Run.new(42,difficulty)
		check(r.current == duplicate.current,"seeded level generation is repeatable: "+difficulty)
		for stage in range(1,6):
			r.sector = stage
			var route = r.make_route("arsenal")
			check(route.enemies.size() == 12+(stage-1)*3+int(Content.DIFFICULTIES[difficulty].enemies),"increased roster scales across every stage: "+difficulty+" "+str(stage))
			check(route.wave_size == {"easy":3,"normal":4,"hard":5}[difficulty] and is_equal_approx(route.wave_delay,18.0*Content.DIFFICULTIES[difficulty].period),"larger waves arrive more frequently: "+difficulty+" "+str(stage))
			for role in route.enemies: roles[role] = true
			check(Run.total_health(route) == route.enemies.size(),"all enemy variants remain one-shot: "+difficulty+" "+str(stage))
	check(roles.size() == Content.ENEMIES.size(),"five-stage progression reaches every enemy archetype")
func run():
	blocks()
	roster_checks()
	for mode in Content.DIFFICULTIES:
		var game = load("res://main.tscn").instantiate()
		Fixture.assign(game,"expansion_test")
		game.show_start_menu = false
		root.add_child(game)
		game.set_process(false)
		game.expedition = Run.new(42)
		game.set_difficulty(mode)
		for stage in range(1,6):
			game.toggle_running()
			for tick in range(2400):
				Fixture.drive(game,0.1,Fixture.preferred_destination(game.battlefield,"coalfield"))
				if game.expedition.phase != "travel": break
			print("BALANCE ",mode," stage=",stage," phase=",game.expedition.phase," hull=",game.battlefield.hull," kills=",game.battlefield.kills,"/",game.battlefield.total," seconds=",game.battlefield.elapsed," raw=",game.factory.reserves)
			check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"expanded encounter checkpoint validates: "+mode+" "+str(stage)+" "+game.checkpoint.error)
			if game.expedition.phase != "reward": break
			game.finish_crafting()
			if game.expedition.phase == "won": break
			var pick = 0
			for id in ["field_repair","economy","production","coal_cache"]:
				if id in game.expedition.reward_options:
					pick = game.expedition.reward_options.find(id)
					break
			preload("res://tests/profile_fixture.gd").claim_reward(game,pick)
			if game.expedition.phase == "won": break
			await process_frame
		game.queue_free()
		await process_frame
	print("EXPANSION RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("expansion_test")
