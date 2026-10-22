extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var failures = 0
var checks = 0
var dangerous_routes = "--dangerous" in OS.get_cmdline_user_args()
var terrain_seen = {}
var formation_seen = {}
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("campaign_variety_test")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func second_ammo(f):
	for x in [1,3,5,6,7]: f.edit(Vector2i(x,5),"belt",0)
	f.edit(Vector2i(2,5),"furnace",0)
	f.edit(Vector2i(4,5),"press",0)
	f.edit(Vector2i(8,5),"belt",3)
	f.edit(Vector2i(8,4),"belt",0)
func second_fuel(f):
	f.edit(Vector2i(1,7),"splitter",3)
	f.edit(Vector2i(1,6),"refinery",0)
	f.edit(Vector2i(2,6),"belt",0)
	f.edit(Vector2i(3,6),"belt",1)
func protect_and_connect(f):
	if not f.auxiliary_ids.is_empty():
		if f.count_kind("furnace") < 2: second_ammo(f)
		f.move_auxiliary(f.auxiliary_ids[0],Vector2i(9,5))
		f.edit(Vector2i(8,5),"splitter",3)
	for p in [Vector2i(2,6),Vector2i(4,1),Vector2i(7,1),Vector2i(4,6),Vector2i(0,6),Vector2i(2,1),Vector2i(7,4),Vector2i(9,1)]:
		if not f.cells.has(p): f.edit(p,"armor_block",0)
func run():
	for build in ["parallel","buffered"]:
		var wins = 0
		for seed in [4,17,42,99,128,256]:
			var game = load("res://main.tscn").instantiate()
			Fixture.assign(game,"campaign_variety_test")
			game.show_start_menu = false
			root.add_child(game)
			game.set_process(false)
			game.expedition = Run.new(seed)
			game.factory.restore(Blueprints.layout(build))
			var stalls = false
			for sector in range(1,6):
				if sector == 2: second_fuel(game.factory)
				if sector == 3 and build == "buffered": second_ammo(game.factory)
				protect_and_connect(game.factory)
				terrain_seen[game.expedition.current.get("terrain","road")] = true
				formation_seen[game.expedition.current.get("formation","patrol")] = true
				game.toggle_running()
				var stranded_time = 0.0
				for tick in range(2400):
					preload("res://tests/profile_fixture.gd").drive(game,0.1)
					if tick%200 == 199: await process_frame
					if game.expedition.phase != "travel": break
					# Either a destroyed line or exhausted coal can strand a
					# tank. Give queued production 30 seconds before retreat.
					stranded_time = stranded_time+0.1 if game.factory.fuel < 0.000001 else 0.0
					if stranded_time >= 30:
						game.retreat_run()
						break
				if game.expedition.phase == "travel":
					stalls = true
					break
				game.finish_crafting()
				if game.expedition.phase in ["won","lost","retreated"]: break
				# Current clear rewards are actual equipment, not the retired
				# production/economy modifier pool.
				var priority = ["gear:armor","gear:skirts","gear:economizer","gear:drum_loader","gear:blast_fuse","gear:arc_gun","gear:scatter_gun","gear:left_gun","gear:right_gun"]
				for id in priority:
					if id in game.expedition.reward_options:
						game.choose_run_option(game.expedition.reward_options.find(id))
						break
				if game.expedition.phase == "reward": game.choose_run_option(0)
				if game.expedition.phase == "won": break
				var best = 0
				var best_cost = -INF if dangerous_routes else INF
				for i in range(2):
					var route = game.expedition.route_options[i]
					var cost = Run.total_health(route)+10*Run.condition(route).fuel
					if not dangerous_routes and game.factory.reserves.coal < 15: cost -= route.coal
					if not dangerous_routes and game.factory.reserves.scrap < 15: cost -= route.scrap
					if (dangerous_routes and cost > best_cost) or (not dangerous_routes and cost < best_cost):
						best_cost = cost
						best = i
				game.choose_run_option(best)
				await process_frame
			if game.expedition.phase == "won": wins += 1
			print("CAMPAIGN ","dangerous " if dangerous_routes else "safe ",build," seed=",seed," result=",game.expedition.phase," cleared=",game.expedition.cleared," hull=",game.battlefield.hull," stock=",game.factory.reserves," shots=",game.factory.shots)
			check(not stalls,"campaign resolves without permanent stall: "+build+" "+str(seed))
			check(game.expedition.cleared >= 2,"build reaches third-sector decisions: "+build+" "+str(seed))
			game.queue_free()
			await process_frame
		check(wins >= 3,"at least half of fixed seed cohort can win with "+build)
	check(terrain_seen.size() == 3,"cohort traverses all three terrain types")
	check(formation_seen.size() == 3,"cohort fights all three formations")
	print("CAMPAIGN VARIETY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
