extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Content = preload("res://scripts/content.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS content UI: ",title)
	else:
		failures += 1
		push_error(title)
func _initialize(): call_deferred("run")
func click_at(pos: Vector2):
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = root.get_final_transform()*pos
	root.push_input(e,false)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e,false)
	game._process(0)
	await process_frame
func capture(path: String):
	game.queue_redraw()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"content_ui_test")
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for index in range(3):
		await click_at(game.menu.difficulty_select.get_rect().get_center())
		await click_at(game.menu.difficulty_buttons[index].get_rect().get_center())
		var id: String = Content.DIFFICULTIES.keys()[index]
		check(game.expedition.difficulty == id and game.factory.reserves.scrap == Content.DIFFICULTIES[id].scrap,"menu difficulty selection changes actual starting supplies: "+id)
	await capture("res://preview-difficulty.png")
	await click_at(game.menu.difficulty_select.get_rect().get_center())
	await capture("res://preview-difficulty-options.png")
	await click_at(game.menu.difficulty_buttons[2].get_rect().get_center())
	game.close_menu()
	# Isolated interaction fixture knows all designs and can afford one of each.
	game.factory.unlocked_blocks = Content.BLOCK_LIMITS.keys()
	game.factory.reserves = {"scrap":100,"coal":100}
	game._process(0)
	await click_at(game.icon_buttons[11].button.get_rect().get_center())
	check(game.tool_page == 1 and game.tool_buttons.has("router"),"equipment-page footer button reveals advanced routing blocks")
	var placed = 0
	for page in [1,2]:
		if game.tool_page != page: await click_at(game.icon_buttons[11].button.get_rect().get_center())
		for id in Content.BLOCKS:
			if not game.tool_buttons.has(id): continue
			await click_at(game.tool_buttons[id].get_rect().get_center())
			var cell = Vector2i(placed+1,0)
			var at = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(cell)+Vector3(0,0.03,0))
			await click_at(at)
			check(game.factory.cells.has(cell) and game.factory.cells[cell].kind == id,"real footer selection and grid click place new block: "+id)
			placed += 1
	check(placed == 10,"every added line block is reachable in the UI")
	await capture("res://preview-expanded-line.png")
	game.expedition.current.erase("field_version") # Legacy equipment/route-card migration coverage.
	game.expedition.current.erase("encounters_version")
	game.toggle_running()
	check(not game.set_difficulty("easy"),"difficulty cannot be changed during a run")
	game.factory.running = false
	game.expedition.phase = "reward"
	game.factory.layout_locked = false
	game.expedition.cleared = 1
	game.expedition.reward_options = ["block:belt","gear:left_gun","gear:armor"]
	game.battlefield.result = 1
	game.battlefield.kills = game.battlefield.total
	for enemy in game.battlefield.enemies: enemy.hp = 0
	game.refresh_view()
	root.size = Vector2i(960,628)
	await process_frame
	await process_frame
	for index in range(Run.ENEMY_RECIPES.size()):
		var id: String = Run.ENEMY_RECIPES[index]
		game.expedition.phase = "reward"
		game.expedition.sector = 1
		game.expedition.rewards_taken = 0
		game.expedition.route_options.clear()
		game.expedition.reward_options = ["gear:"+id,"block:belt","block:splitter"]
		if id == "scatter_gun": game.expedition.reward_options = ["gear:scatter_gun","gear:arc_gun","gear:blast_fuse"]
		game.factory.reserves = {"scrap":100,"coal":100}
		game.choice_popup.refresh()
		if id == "scatter_gun": await capture("res://preview-new-equipment-rewards-960.png")
		await click_at(game.choice_rect(0).get_center())
		check(id in game.expedition.equipment and game.factory.reserves.scrap == 100,"minimum-window draft directly installs equipment: "+id)
	check(game.world.auxiliary_guns.size() == Content.GUNS.size() and game.factory.auxiliary_ids.size() == Content.GUNS.size(),"all eight weapons have independent output cells")
	check(not game.choice_popup.continue_button.visible,"item draft never shows a paid workshop continuation")
	await capture("res://preview-expanded-items-960.png")
	for c in game.factory.cells.values():
		match c.kind:
			"router": c.turn = 2
			"fuel_depot": c.items = ["fuel","fuel","fuel","fuel","fuel","fuel","fuel","fuel"]
			"overflow_gate":
				c.items = ["scrap","steel","shell"]
				c.turn = 1
			"blast_furnace":
				c.items = ["scrap"]
				c.work = 2
			"auto_press":
				c.items = ["steel"]
				c.work = 2
	var snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,snapshot) and game.expedition.difficulty == "hard" and game.factory.auxiliary_ids.size() == Content.GUNS.size(),"save restores difficulty all equipment and all new blocks")
	check(game.factory.cells == snapshot.factory.cells,"new block buffers routing cursor and paid processing progress survive restore exactly")
	check(game.expedition.phase == "route","item selection continues directly to the route")
	root.size = Vector2i(1440,940)
	await process_frame
	await process_frame
	for reward in Run.REWARDS:
		game.reset_battle()
		game.expedition.current.erase("field_version")
		game.expedition.current.erase("encounters_version")
		game.release_battle()
		game.ensure_battle()
		game.started = true
		game.expedition.phase = "reward"
		game.expedition.cleared = 1
		game.expedition.hull = 60
		game.battlefield.hull = 60
		game.factory.reserves = {"scrap":20,"coal":10}
		game.expedition.reward_options = [reward,"production","economy"]
		preload("res://tests/profile_fixture.gd").claim_reward(game,0)
		var m = game.expedition.modifiers
		var applied = false
		match reward:
			"production": applied = game.factory.work_multiplier < 1
			"economy": applied = m.fuel < 1
			"magazine": applied = game.factory.ammo_capacity == 16
			"autoload": applied = m.reload < 1
			"cargo": applied = game.factory.reserve_capacity == 125
			"scrap_cache": applied = game.factory.reserves.scrap == 44
			"coal_cache": applied = game.factory.reserves.coal == 28
			"shell_cache": applied = game.factory.ammo == 8
			"field_repair": applied = game.expedition.hull == 80 and game.battlefield.hull == 80
			"scout_maps": applied = game.expedition.route_options.size() == 3
			"craft_discount": applied = game.expedition.craft_cost("left_gun").scrap == 13
			"salvage_boost": applied = m.salvage == 1
			"range_training": applied = m.range == 4
			"reinforcement": applied = m.damage < 1
			"engine_tuning": applied = m.speed > 1
		check(applied and game.expedition.phase == "route" and game.checkpoint.validate(game.checkpoint.snapshot(game)),"reward changes real state and saves: "+reward)
		if reward == "scout_maps":
			await capture("res://preview-three-routes.png")
			await click_at(game.choice_rect(2).get_center())
			check(game.expedition.phase == "prepare","third scouted route is clickable")
	for id in ["rapid_gun","long_gun","mortar_gun","rear_gun"]:
		game.reset_battle()
		game.expedition.recipes = [id]
		game.expedition.equipment = [id]
		game.factory.install_auxiliary(id)
		game.factory.move_auxiliary(id,Vector2i(12,4))
		game.sync_equipment()
		game.toggle_running()
		game.factory.running = false
		game.factory.ammo = 7
		var spec = Content.EQUIPMENT[id]
		var c = game.factory.cells[game.factory.auxiliary_position(id)]
		for i in range(int(spec.ammo)): c.items.append("shell")
		var battle = game.battlefield
		battle.cooldown = 100
		for i in range(2):
			battle.enemies[i].active = true
			battle.enemies[i].node.visible = true
			battle.enemies[i].node.position = Vector3((42 if id == "long_gun" else 20)+i,0,0)
		for tick in range(160):
			battle.update_gun(game.factory,0.025)
			if not battle.projectiles.is_empty(): break
		check(battle.projectiles.size() == 1 and game.factory.auxiliary_ammo(id) == 0 and game.factory.ammo == 7,"new weapon fires only its own paid ammunition: "+id)
		var flying = game.checkpoint.snapshot(game)
		check(game.checkpoint.apply(game,flying),"new weapon projectile and cooldown restore: "+id)
		battle = game.battlefield
		for tick in range(160): battle.update_gun(game.factory,0.025)
		check(battle.kills == (2 if id == "mortar_gun" else 1),"new weapon has actual impact including mortar splash: "+id)
	game.reset_battle()
	var battle = game.battlefield
	var f = game.factory
	var baseline_damage = battle.hit_damage()
	battle.configure_equipment(["armor","skirts","rangefinder","salvage_arm","supercharger","economizer"])
	check(battle.hit_damage() == ceili(baseline_damage*0.75*0.8) and battle.weapon_range(36) == 42,"armor modules stack and rangefinder increases actual engagement reach")
	f.running = true
	f.fuel = 2
	battle.movement_direction = Vector3.RIGHT
	battle.tick_battle(f,0.1)
	check(is_equal_approx(battle.distance,3.3*1.2*0.1) and is_equal_approx(f.fuel_used,battle.distance*0.12*0.8*1.1),"engine modules alter actual movement and fuel consumption")
	var scrap = f.reserves.scrap
	battle.kill_enemy(battle.enemies[0],f,Vector3.ZERO)
	var loot = Content.ENEMIES[battle.enemies[0].role].get("loot",2)
	check(f.reserves.scrap == scrap+loot+2,"salvage arm increases actual kill recovery")
	print("CONTENT UI RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("content_ui_test")
