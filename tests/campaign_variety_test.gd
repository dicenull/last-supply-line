extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var failures = 0
var checks = 0
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
				game.toggle_running()
				for tick in range(2400):
					game._process(0.1)
					if tick%200 == 199: await process_frame
					if game.expedition.phase != "travel": break
				if game.expedition.phase == "travel":
					stalls = true
					break
				if game.expedition.phase in ["won","lost"]: break
				var priority = ["production","economy","autoload","magazine","cargo"] if game.factory.work_multiplier > 0.65 else ["economy","autoload","production","cargo","magazine"]
				for id in priority:
					if id in game.expedition.reward_options:
						game.choose_run_option(game.expedition.reward_options.find(id))
						break
				var best = 0
				var best_cost = INF
				for i in range(2):
					var route = game.expedition.route_options[i]
					var cost = Run.total_health(route)+10*Run.condition(route).fuel
					if game.factory.reserves.coal < 15: cost -= route.coal
					if game.factory.reserves.scrap < 15: cost -= route.scrap
					if cost < best_cost:
						best_cost = cost
						best = i
				game.choose_run_option(best)
				await process_frame
			if game.expedition.phase == "won": wins += 1
			print("CAMPAIGN ",build," seed=",seed," result=",game.expedition.phase," cleared=",game.expedition.cleared," hull=",game.battlefield.hull," stock=",game.factory.reserves," shots=",game.factory.shots)
			check(not stalls,"campaign resolves without permanent stall: "+build+" "+str(seed))
			check(game.expedition.cleared >= 2,"build reaches third-sector decisions: "+build+" "+str(seed))
			game.queue_free()
			await process_frame
		check(wins >= 3,"at least half of fixed seed cohort can win with "+build)
	print("CAMPAIGN VARIETY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
