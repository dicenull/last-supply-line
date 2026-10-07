extends SceneTree
const RunState = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS run: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func run():
	var a = RunState.new(42)
	var b = RunState.new(42)
	check(a.current == b.current,"seed reproduces initial sector")
	check(not a.choose_reward(0) and not a.choose_route(0),"choices cannot be taken outside their phase")
	check(a.start_sector() and not a.start_sector(),"sector starts only once")
	b.start_sector()
	a.finish_sector(true,87)
	b.finish_sector(true,87)
	check(a.hull == 87 and a.phase == "reward","clear retains damage and offers rewards")
	check(not a.choose_reward(9),"invalid reward is rejected")
	a.choose_reward(0)
	b.choose_reward(0)
	check(a.modifiers.work < 1 and a.rewards_taken == 1 and not a.choose_reward(0),"reward applies once")
	check(a.route_options == b.route_options and a.route_options[0].kind != a.route_options[1].kind,"seeded route alternatives are distinct and reproducible")
	var arsenal = a.make_route("arsenal")
	check(arsenal.shells == 12 and arsenal.enemy_hp > a.make_route("scrapyard").enemy_hp,"arsenal trades tougher defenders for manufactured rounds")
	var f = Factory.new()
	f.finite_resources = true
	f.reserves = {"scrap":1,"coal":0}
	f.running = true
	for i in range(16): f.step(0.25)
	check(f.injected == 1 and f.reserves.scrap == 0,"finite sources cannot create uncollected resources")
	check(f.collect("coal",1000) == 100 and f.collect("coal",1) == 0,"collection respects cargo capacity")
	var game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"run_test")
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.expedition = RunState.new(42)
	for sector in range(1,6):
		if sector == 3:
			for x in [1,3,5,6,7,8]: game.factory.edit(Vector2i(x,5),"belt",0)
			game.factory.edit(Vector2i(2,5),"furnace",0)
			game.factory.edit(Vector2i(4,5),"press",0)
			game.factory.edit(Vector2i(8,5),"belt",3)
			game.factory.edit(Vector2i(8,4),"belt",0)
		game.toggle_running()
		check(game.expedition.sector == sector and game.expedition.phase == "travel","start sector "+str(sector))
		for tick in range(2200):
			game._process(0.1)
			if game.expedition.phase != "travel": break
		check(game.battlefield.result == 1,"built factory completes sector "+str(sector))
		if game.battlefield.result != 1:
			print("FAILED SECTOR STATE ", {"sector":sector,"hp":game.battlefield.hull,"kills":game.battlefield.kills,"distance":game.battlefield.distance,"reserves":game.factory.reserves,"ammo":game.factory.ammo,"fuel":game.factory.fuel,"shots":game.factory.shots})
			break
		check(game.factory.collected.coal > 0 and game.factory.collected.scrap > 0,"roadside recovery feeds factory")
		if sector == 5:
			check(game.expedition.phase == "won" and game.battlefield.enemies.back().max_hp > 3,"final boss ends full run")
			break
		var stock = [game.factory.ammo,game.factory.fuel,game.factory.reserves.duplicate(),game.factory.layout()]
		var hull = game.battlefield.hull
		game.choose_run_option(0 if sector%2 == 1 else 1)
		check(game.expedition.phase == "route","reward advances to route choice")
		game.choose_run_option(0)
		check(game.expedition.phase == "prepare" and not game.factory.running,"next sector waits for playback")
		check([game.factory.ammo,game.factory.fuel,game.factory.reserves,game.factory.layout()] == stock and game.battlefield.hull == hull,"next sector preserves cargo layout and hull")
		await process_frame
	game.reset_battle()
	game.toggle_running()
	game.retreat_run()
	check(game.expedition.phase == "retreated" and not game.factory.running,"retreat ends and stops run")
	check(not game.expedition.finish_sector(true,100),"retreat cannot grant a clear reward")
	print("RUN RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	preload("res://tests/profile_fixture.gd").clean("run_test")
