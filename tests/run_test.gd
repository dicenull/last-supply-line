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
	a.finish_crafting()
	b.finish_crafting()
	check(a.hull == 87 and a.phase == "reward","clear preserves remaining hull before offering rewards")
	var defeated = RunState.new(42)
	defeated.start_sector()
	defeated.finish_sector(true,0)
	check(defeated.phase == "lost" and defeated.hull == 0,"destroyed hull cannot be revived by a simultaneous clear")
	# Test all five clear transitions independently of the combat pilot.
	var progression = RunState.new(42)
	for stage in range(1,6):
		progression.sector = stage
		progression.phase = "travel"
		progression.current = progression.make_route("scrapyard")
		progression.finish_sector(true,90-stage*10)
		check(progression.hull == 90-stage*10 and progression.phase != "lost","stage clear retains damage including the final sector: "+str(stage))
	check(not a.choose_reward(9),"invalid reward is rejected")
	var chosen_item = a.reward_options[0]
	a.choose_reward(0)
	if a.phase == "shop": a.finish_shopping()
	b.choose_reward(0)
	if b.phase == "shop": b.finish_shopping()
	check((chosen_item.begins_with("block:") or chosen_item.trim_prefix("gear:") in a.equipment) and a.rewards_taken == 1 and not a.choose_reward(0),"reward applies once")
	check(a.current == b.current and a.phase == "prepare" and a.route_options.is_empty(),"seeded field arrival advances directly to reproducible preparation")
	var arsenal = a.make_route("arsenal")
	check(arsenal.shells == 12 and RunState.total_health(arsenal) == RunState.enemy_count(arsenal),"arsenal grants manufactured rounds with one-hit defenders")
	var f = Factory.new()
	f.finite_resources = true
	f.reserves = {"scrap":1,"coal":0}
	f.running = true
	for i in range(16): f.step(0.25)
	check(f.injected == 1 and f.reserves.scrap == 0,"finite sources cannot create uncollected resources")
	check(f.collect("coal",1000) == 1000 and f.collect("coal",1) == 1 and f.reserves.coal == 1001,"raw resource collection has no cargo capacity")
	var game = load("res://main.tscn").instantiate()
	preload("res://tests/profile_fixture.gd").assign(game,"run_test")
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.expedition = RunState.new(42)
	# This suite checks five-sector progression; supply both main-gun lines for
	# the longer obstacle route. Difficulty cohorts are covered by balance_test.
	game.factory.restore(preload("res://scripts/blueprints.gd").layout("parallel"))
	for sector in range(1,6):
		# The physical supply detours expose the tank longer. Buy protection for
		# this progression fixture; unprotected outcomes remain in balance_test.
		for p in [Vector2i(2,6),Vector2i(4,1),Vector2i(7,1),Vector2i(4,6)]:
			if not game.factory.cells.has(p): game.factory.edit(p,"armor_block",0)
		if sector == 3:
			for x in [1,3,5,6,7,8]: game.factory.edit(Vector2i(x,5),"belt",0)
			game.factory.edit(Vector2i(2,5),"furnace",0)
			game.factory.edit(Vector2i(4,5),"press",0)
			game.factory.edit(Vector2i(8,5),"belt",3)
			game.factory.edit(Vector2i(8,4),"belt",0)
		game.toggle_running()
		check(game.expedition.sector == sector and game.expedition.phase == "travel","start sector "+str(sector))
		var arrival_hull = game.battlefield.hull
		for tick in range(2200):
			arrival_hull = game.battlefield.hull
			preload("res://tests/profile_fixture.gd").drive(game,0.1)
			if game.expedition.phase != "travel": break
		if game.expedition.phase == "lost":
			check(game.battlefield.hull == 0 and game.expedition.hull == 0 and game.battlefield.result == -1,"accumulated hull damage ends the pilot campaign without automatic healing")
			break
		check(game.battlefield.result == 1,"built factory completes sector "+str(sector))
		check(game.expedition.hull == game.battlefield.hull and game.battlefield.hull <= arrival_hull and game.factory.wrecks.is_empty(),"every successful sector restores the line without increasing hull HP")
		if game.battlefield.result != 1:
			print("FAILED SECTOR STATE ", {"sector":sector,"hp":game.battlefield.hull,"kills":game.battlefield.kills,"distance":game.battlefield.distance,"position":game.battlefield.player.position,"yaw":game.battlefield.player.rotation.y,"wrecks":game.factory.wrecks,"reserves":game.factory.reserves,"ammo":game.factory.ammo,"fuel":game.factory.fuel,"shots":game.factory.shots})
			break
		check(game.factory.collected.coal > 0 and game.factory.collected.scrap > 0,"roadside recovery feeds factory")
		game.finish_crafting()
		if sector == 5:
			preload("res://tests/profile_fixture.gd").claim_reward(game,0)
			check(game.expedition.phase == "won" and game.battlefield.enemies.back().max_hp == 1 and is_equal_approx(game.battlefield.enemies.back().node.scale.x,1.7),"one-hit large final boss ends full run")
			break
		var hull = game.battlefield.hull
		preload("res://tests/profile_fixture.gd").claim_reward(game,0 if sector%2 == 1 else 1)
		check(game.expedition.phase == "prepare" and not game.choice_popup.visible,"reward advances to the destination already reached on the field")
		var stock = [game.factory.ammo,game.factory.fuel,game.factory.reserves.duplicate(),game.factory.layout()]
		preload("res://tests/profile_fixture.gd").claim_reward(game,0)
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
