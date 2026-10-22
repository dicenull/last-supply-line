extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
const Battle = preload("res://scripts/battle_world.gd")
const Save = preload("res://scripts/run_save.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
var game
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS variety: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func _finalize():
	Fixture.clean("variety_test")
	for suffix in ["",".bak",".tmp"]:
		var path = "user://variety_test_fixture.mfv"+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
func click_at(pos: Vector2):
	var e = InputEventMouseButton.new()
	e.position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame
	game._process(0)
func capture(path: String):
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	var seen_terrain = {}
	var seen_formation = {}
	var seen_reward = {}
	var deterministic = true
	var unique = true
	for seed in range(1,33):
		var a = Run.new(seed)
		var b = Run.new(seed)
		for sector in range(1,5):
			a.start_sector()
			b.start_sector()
			a.finish_sector(true,50 if seed%4 == 0 else 100)
			b.finish_sector(true,50 if seed%4 == 0 else 100)
			a.finish_crafting()
			b.finish_crafting()
			deterministic = deterministic and a.reward_options == b.reward_options
			unique = unique and a.reward_options.size() == 3 and a.reward_options[0] != a.reward_options[1] and a.reward_options[1] != a.reward_options[2] and a.reward_options[0] != a.reward_options[2]
			for id in a.reward_options: seen_reward[id] = true
			a.choose_reward(0)
			if a.phase == "shop": a.finish_shopping()
			b.choose_reward(0)
			if b.phase == "shop": b.finish_shopping()
			deterministic = deterministic and a.current == b.current
			for route in [a.current]:
				seen_terrain[route.terrain] = true
				seen_formation[route.formation] = true
			a.choose_route(0)
			b.choose_route(0)
	check(deterministic,"32 seeds reproduce all reward and route choices")
	check(unique and seen_reward.size() == Run.EQUIPMENT.size() and seen_reward.keys().all(func(id): return id.begins_with("gear:")),"three distinct offers cover the equipment-only reward pool")
	check(seen_terrain.size() == 3 and seen_formation.size() == 3,"all terrain and formation variants appear")
	var first = Run.new(77)
	check(first.current.terrain == "road" and first.current.formation == "patrol","opening encounter retains baseline conditions")
	for terrain in Run.CONDITIONS:
		var b = Battle.new()
		b.sector_config = Run.new(77).current
		b.sector_config.terrain = terrain
		root.add_child(b)
		var f = Factory.new()
		f.fuel = 2
		f.running = true
		b.movement_direction = Vector3.RIGHT
		b.tick_battle(f,0.1)
		var condition = Run.CONDITIONS[terrain]
		check(is_equal_approx(b.distance,0.1*condition.speed) and is_equal_approx(f.fuel_used,b.distance*0.12*condition.fuel),"actual speed and fuel consumption: "+terrain)
		b.queue_free()
		await process_frame
	for formation in Run.FORMATIONS:
		var b = Battle.new()
		b.sector_config = Run.new(81).current
		b.sector_config.formation = formation
		b.sector_config.erase("enemies")
		b.sector_config.combat_version = 2
		b.sector_config.boss = true
		root.add_child(b)
		var hp = 0
		var roles: Array = []
		for enemy in b.enemies:
			hp += enemy.hp
			roles.append(enemy.role)
		check(roles == Run.FORMATIONS[formation] and hp == Run.total_health(b.sector_config),"spawned roles and total health match card: "+formation)
		check(is_equal_approx(b.enemies[5].node.scale.x,1.7),"formation preserves final boss: "+formation)
		b.queue_free()
		await process_frame
	var r = Run.new(1)
	r.start_sector()
	r.finish_sector(true,100)
	r.finish_crafting()
	r.reward_options = ["autoload","cargo","production"]
	check(r.choose_reward(0) and is_equal_approx(r.modifiers.reload,0.8) and not r.choose_reward(0),"autoload reward applies only once")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"variety_test")
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.expedition.current.erase("field_version") # Legacy route-modal save compatibility.
	game.expedition.current.erase("encounters_version")
	game.toggle_running()
	for i in range(1600):
		preload("res://tests/profile_fixture.gd").drive(game,0.1)
		if game.expedition.phase != "travel": break
	game.finish_crafting()
	check(game.expedition.phase == "reward","real factory reaches first reward screen")
	game.expedition.reward_options = ["autoload","cargo","magazine"]
	game._process(0)
	await capture("res://preview-expanded-reward.png")
	var before = game.factory.reserves.duplicate()
	await click_at(game.choice_rect(1).get_center())
	check(game.factory.reserve_capacity == 125 and game.factory.reserves == before,"legacy cargo card remains readable without changing raw resource stock")
	game.factory.collect("coal",200)
	check(game.factory.reserves.coal == before.coal+200,"legacy capacity no longer limits salvage acceptance")
	game.expedition.route_options[0].terrain = "mud"
	game.expedition.route_options[0].formation = "battery"
	game.expedition.route_options[1].terrain = "road"
	game.expedition.route_options[1].formation = "raiders"
	var codec = Save.new()
	var data = codec.snapshot(game)
	check(codec.validate(data),"expanded cargo and route options checkpoint validates")
	check(codec.write_file("user://variety_test_fixture.mfv",data) and not codec.read_file("user://variety_test_fixture.mfv").is_empty(),"new route fields and over-100 inventory survive disk roundtrip")
	var duplicate_offer = data.duplicate(true)
	duplicate_offer.run.phase = "reward"
	duplicate_offer.run.route_options = []
	duplicate_offer.run.reward_options = ["cargo","cargo","autoload"]
	check(not codec.validate(duplicate_offer),"duplicate reward offers rejected")
	await capture("res://preview-expanded-routes.png")
	await click_at(game.choice_rect(1).get_center())
	check(game.expedition.current.terrain == "road" and game.expedition.current.formation == "raiders","wide second route card selects its displayed encounter")
	check(codec.apply(game,data) and game.factory.reserve_capacity == 125 and game.factory.reserves.coal == before.coal+200,"checkpoint restores uncapped cargo alongside legacy metadata")
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	game.expedition.modifiers.reload = 0.8
	game.battlefield.reload_multiplier = 0.8
	game.toggle_running()
	for i in range(85): preload("res://tests/profile_fixture.gd").drive(game,0.1)
	var moving = codec.snapshot(game)
	check(codec.validate(moving),"mud and heavy formation validate during real battle")
	check(codec.apply(game,moving) and game.battlefield.reload_multiplier == 0.8 and game.expedition.current.terrain == "mud" and game.battlefield.enemies[0].role == Run.enemy_role(game.expedition.current,0),"resume restores terrain formation and reload modifier")
	var bad = moving.duplicate(true)
	bad.run.current.terrain = "unknown"
	check(not codec.validate(bad),"unknown terrain rejected")
	bad = moving.duplicate(true)
	bad.run.current.formation = "unknown"
	check(not codec.validate(bad),"unknown formation rejected")
	bad = moving.duplicate(true)
	bad.run.modifiers.cargo = 225
	check(not codec.validate(bad),"out-of-range capacity modifier rejected")
	bad = moving.duplicate(true)
	bad.run.modifiers.reload = 0
	check(not codec.validate(bad),"invalid reload multiplier rejected")
	game.reset_battle()
	var legacy = codec.snapshot(game)
	legacy.run.modifiers.erase("reload")
	legacy.run.modifiers.erase("cargo")
	legacy.run.current.erase("terrain")
	legacy.run.current.erase("formation")
	check(codec.apply(game,legacy) and game.factory.reserve_capacity == 100 and game.battlefield.reload_multiplier == 1,"older checkpoints retain baseline defaults")
	game.toggle_running()
	game.factory.ammo = 12
	game.battlefield.reload_multiplier = 0.8
	var enemy = game.battlefield.enemies[0]
	enemy.active = true
	enemy.node.position = Vector3(25,0,0)
	var offset = enemy.node.position-game.battlefield.turret.global_position
	game.battlefield.turret.rotation.y = atan2(-offset.z,offset.x)
	game.battlefield.update_gun(game.factory,0.001)
	check(game.factory.shots == 1 and is_equal_approx(game.battlefield.cooldown,0.8),"autoload changes actual firing interval and consumes one round")
	print("VARIETY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
