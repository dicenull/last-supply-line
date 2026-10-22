extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var results: Array = []
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS balance: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func connect_auxiliary(game):
	var f = game.factory
	if f.auxiliary_ids.is_empty(): return
	var id: String = f.auxiliary_ids[0]
	f.move_auxiliary(id,Vector2i(9,5))
	# Use the material-built splitter: up to main gun, right to the earned gun.
	f.edit(Vector2i(8,5),"splitter",3)
func protect_lines(game):
	# Buy armor through the same finite-material editing path as the player.
	# Protect the fuel branch first, then presses and exposed ammunition pipes.
	for p in [Vector2i(2,6),Vector2i(4,1),Vector2i(7,1),Vector2i(4,6),Vector2i(7,4),Vector2i(9,1),Vector2i(2,1),Vector2i(10,3)]:
		if not game.factory.cells.has(p): game.factory.edit(p,"armor_block",0)
func run():
	for mode in Run.Content.DIFFICULTIES:
		for upgraded in [false,true]:
			for seed in [7,42,1918]:
				var game = load("res://main.tscn").instantiate()
				Fixture.assign(game,"balance_test")
				game.show_start_menu = false
				root.add_child(game)
				game.set_process(false)
				game.expedition = Run.new(seed)
				game.set_difficulty(mode)
				if upgraded: game.factory.restore(preload("res://scripts/blueprints.gd").layout("parallel"))
				var damage = 0
				var all_resources_valid = true
				for stage in range(1,6):
					if upgraded:
						connect_auxiliary(game)
						protect_lines(game)
					game.toggle_running()
					var stranded_time = 0.0
					for tick in range(2400):
						var prior = game.battlefield.hull
						preload("res://tests/profile_fixture.gd").drive(game,0.1)
						# Clear service heals the hull, so sample damage during travel.
						damage += maxi(0,prior-game.battlefield.hull)
						all_resources_valid = all_resources_valid and game.factory.reserves.scrap >= 0 and game.factory.reserves.coal >= 0
						for kind in game.Factory.LIMITS: all_resources_valid = all_resources_valid and game.factory.count_kind(kind) <= game.Factory.LIMITS[kind]
						if game.expedition.phase != "travel": break
						# An immobilized tank may remain alive. The pilot uses
						# the existing retreat action after its fuel line is cut.
						var fuel_line_broken = game.factory.wrecks.keys().any(func(p): return p.y == 7)
						stranded_time = stranded_time+0.1 if fuel_line_broken and game.factory.fuel < 0.000001 else 0.0
						if stranded_time >= 30:
							game.retreat_run()
							break
					if game.expedition.phase != "reward": break
					var pick = 0
					for id in (["gear:armor","gear:skirts","gear:left_gun","gear:right_gun","gear:long_gun","gear:rapid_gun","gear:economizer","gear:salvage_arm"] if upgraded else []):
						if id in game.expedition.reward_options:
							pick = game.expedition.reward_options.find(id)
							break
					game.choose_run_option(pick)
					if game.expedition.phase == "won": break
					var route_index = 0
					for i in range(game.expedition.route_options.size()):
						if game.expedition.route_options[i].kind == "coalfield": route_index = i
					game.choose_run_option(route_index)
					await process_frame
				if game.expedition.phase == "travel":
					print("BALANCE STOP position=",game.battlefield.player.position," yaw=",game.battlefield.player.rotation.y," fuel=",game.factory.fuel," wrecks=",game.factory.wrecks)
				var result = {"mode":mode,"upgraded":upgraded,"seed":seed,"phase":game.expedition.phase,"cleared":game.expedition.cleared,"hull":game.battlefield.hull,"damage":damage,"scrap":game.factory.reserves.scrap,"coal":game.factory.reserves.coal,"equipment":game.expedition.equipment}
				results.append(result)
				print("BALANCE COHORT ",JSON.stringify(result))
				check(all_resources_valid and game.expedition.phase in ["won","lost","retreated"],"finite materials resolve through arrival, defeat or fuel-line retreat: "+mode+" "+str(upgraded)+" "+str(seed))
				game.queue_free()
				await process_frame
	for mode in Run.Content.DIFFICULTIES:
		var wins = 0
		var basic_damage = 0
		var built_damage = 0
		var basic_courses = 0
		var built_courses = 0
		for result in results:
			if result.mode != mode: continue
			if result.upgraded:
				built_damage += result.damage
				built_courses += mini(5,result.cleared+1)
				if result.phase == "won": wins += 1
			else:
				basic_damage += result.damage
				basic_courses += mini(5,result.cleared+1)
		check(wins >= 2,"protected parallel factory with drafted equipment wins at least two of three seeds: "+mode)
		# Compare exposure per entered course, so five-stage survivors are not
		# penalized for accumulating more damage than first-stage defeats.
		check(float(built_damage)/built_courses <= float(basic_damage)/basic_courses,"equipment and auxiliary supply reduce damage per entered course: "+mode)
	var file = FileAccess.open("/tmp/mfv-balance-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	file.close()
	print("BALANCE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("balance_test")
