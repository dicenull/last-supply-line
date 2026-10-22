extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
var game
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS item rewards: ",label)
	else:
		failures += 1
		push_error(label)
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func click(index: int):
	if DisplayServer.get_name() == "headless":
		preload("res://tests/profile_fixture.gd").claim_reward(game,index)
		return
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = root.get_final_transform()*game.choice_rect(index).get_center()
	event.pressed = true
	root.push_input(event,false)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,false)
	await process_frame
func run():
	var f = Factory.new()
	f.example(false)
	check(f.reserves == {"scrap":48,"coal":32} and f.available("auto_press") == 0,"starter layout is free once and advanced designs are locked")
	var stock = f.reserves.duplicate()
	f.edit(Vector2i(10,1),"furnace",0)
	check(f.reserves == {"scrap":42,"coal":31},"construction pays both raw materials")
	f.rotate(Vector2i(10,1))
	check(f.cells[Vector2i(10,1)].dir == 1 and f.reserves == {"scrap":42,"coal":31},"rotation does not charge again")
	f.edit(Vector2i(10,1),"erase",0)
	check(f.reserves == stock,"demolition refunds construction cost")
	f.undo()
	check(f.reserves == {"scrap":42,"coal":31} and f.count_kind("furnace") == 2,"undo repays construction cost")
	f.edit(Vector2i(10,1),"depot",0)
	check(f.reserves == {"scrap":44,"coal":32},"replacement pays only net difference")
	var before = f.layout()
	stock = f.reserves.duplicate()
	f.edit(Vector2i(10,1),"auto_press",0)
	check(f.layout() == before and f.reserves == stock,"locked blueprint cannot replace an installed block")
	check(not f.restore([[1,1,"auto_press",0]]) and f.layout() == before and f.reserves == stock,"layout import cannot bypass research")
	f.unlocked_blocks.append("auto_press")
	f.edit(Vector2i(10,1),"auto_press",0)
	check(f.reserves == {"scrap":38,"coal":30} and f.count_kind("auto_press") == 1,"learned blueprint builds with materials")
	f.layout_locked = true
	f.edit(Vector2i(10,1),"erase",0)
	check(f.count_kind("auto_press") == 1,"combat lock still protects construction")
	f.layout_locked = false
	f.reserves = {"scrap":0,"coal":0}
	check(f.can_place(Vector2i(10,1),"belt"),"replacement can use salvage even with no stored materials")
	f.edit(Vector2i(10,1),"belt",0)
	check(f.reserves == {"scrap":9,"coal":2},"replacement refunds exact difference")
	f.reserves = {"scrap":0,"coal":0}
	before = f.layout()
	var undo_size = f.undo_stack.size()
	f.undo()
	check(f.layout() == before and f.undo_stack.size() == undo_size and f.reserves.scrap == 0,"unaffordable undo fails atomically and retains history")
	f.edit(Vector2i(12,1),"furnace",0)
	check(f.layout() == before and f.undo_stack.size() == undo_size,"unaffordable placement does not change layout or undo")
	f.reserves = {"scrap":48,"coal":32}
	stock = f.reserves.duplicate()
	for i in range(4):
		f.clear_layout()
		check(f.restore(before),"rebuild cleared layout")
	check(f.reserves == stock,"clear and rebuild cannot multiply materials")
	f.example()
	stock = f.reserves.duplicate()
	f.example()
	check(f.reserves == stock,"reapplying starter template never grants another starter kit")
	var seen = {}
	var distinct = {}
	var seeded = true
	for seed in range(100):
		var a = Run.new(seed)
		var b = Run.new(seed)
		a.start_sector()
		b.start_sector()
		a.finish_sector(true,90,f.inventory)
		b.finish_sector(true,90,f.inventory)
		seeded = seeded and a.reward_options == b.reward_options and a.reward_options.size() == 3
		distinct[str(a.reward_options)] = true
		var unique = {}
		for id in a.reward_options:
			unique[id] = true
			seen[id] = true
		seeded = seeded and unique.size() == 3
	check(seeded and distinct.size() > 50 and seen.size() == Run.EQUIPMENT.size(),"full equipment pool draws three distinct reproducible choices and varies across seeds")
	var run_state = Run.new(42)
	run_state.equipment = ["armor","left_gun"]
	var capped = Factory.LIMITS.duplicate()
	var pool = run_state.reward_pool(capped,false)
	check("gear:armor" not in pool and "gear:left_gun" not in pool and "gear:rapid_gun" not in pool and not pool.any(func(id): return id.begins_with("block:")),"owned gear and mounts without space are excluded")
	run_state.start_sector()
	check(run_state.recover_recipe(0) == "" and run_state.recipes.is_empty(),"individual kills no longer grant equipment recipes")
	run_state.sector = 5
	run_state.cleared = 4
	run_state.rewards_taken = 4
	run_state.finish_sector(true,80)
	check(run_state.phase == "reward" and run_state.cleared == 5,"final stage also offers an item reward")
	run_state.choose_reward(0)
	if run_state.phase == "shop": run_state.finish_shopping()
	check(run_state.phase == "won" and run_state.rewards_taken == 5 and not run_state.choose_reward(0),"final reward is granted once before victory")
	var exhausted = Run.new(1)
	exhausted.equipment = Run.EQUIPMENT.keys()
	exhausted.offer_rewards()
	check(exhausted.phase == "prepare" and exhausted.reward_options.is_empty(),"legacy all-owned state advances without an empty modal")
	exhausted = Run.new(1)
	exhausted.equipment = Run.EQUIPMENT.keys().slice(0,Run.EQUIPMENT.size()-1)
	exhausted.offer_rewards()
	check(exhausted.reward_options.size() == 1,"legacy near-exhausted equipment pool remains selectable")
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"item_rewards_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	game.set_difficulty("easy")
	game.toggle_running()
	for tick in range(1800):
		Fixture.drive(game,0.1)
		if game.expedition.phase != "travel": break
	check(game.expedition.phase == "reward" and game.choice_popup.visible and not game.choice_popup.continue_button.visible,"actual stage clear opens the random item draft directly")
	check(game.expedition.recipes.is_empty() and game.expedition.equipment.is_empty(),"battle kills grant no free gear before the clear choice")
	var clear_save = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(clear_save) and clear_save.version == 9,"new save stores construction materials and pending equipment draft")
	var choices = game.expedition.reward_options.duplicate()
	game.open_menu()
	game.close_menu()
	game.refresh_view()
	check(game.expedition.reward_options == choices and game.checkpoint.apply(game,clear_save) and game.expedition.reward_options == choices,"menu refresh and reload do not reroll pending choices")
	# Verify every award through the actual game controller.
	var all_items = Run.new(1).reward_pool(Factory.new().inventory)
	for id in all_items:
		check(game.checkpoint.apply(game,clear_save),"restore clean reward fixture: "+id)
		var alternatives = all_items.filter(func(other): return other != id).slice(0,2)
		game.expedition.reward_options = [id]+alternatives
		game.refresh_view()
		var award_stock = game.factory.reserves.duplicate()
		preload("res://tests/profile_fixture.gd").claim_reward(game,0)
		var gear = id.trim_prefix("gear:")
		check(gear in game.expedition.equipment and (gear not in Factory.AUXILIARY or game.factory.auxiliary_position(gear).x >= 0) and game.factory.reserves == award_stock,"gear award installs without recipes or resource payment: "+gear)
		check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"awarded state is saveable: "+id)
	game.checkpoint.apply(game,clear_save)
	game.expedition.reward_options = ["gear:armor","gear:mortar_gun","gear:servo"]
	game.refresh_view()
	root.size = Vector2i(960,628)
	await process_frame
	await capture("res://preview-item-rewards-960.png")
	await click(0)
	check(game.expedition.phase in ["prepare","shop"] and "armor" in game.expedition.equipment,"minimum-window real click selects equipment")
	if game.expedition.phase == "shop": game.leave_shop()
	await click(0)
	game.cycle_tools()
	game.cycle_tools()
	game._process(0)
	check(not game.available_tools().has("auto_press") and not game.tool_buttons.has("auto_press"),"footer omits unknown blueprint")
	await capture("res://preview-construction-locked-960.png")
	var construction_save = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,construction_save) and game.factory.reserves == construction_save.factory.reserves,"construction funds survive checkpoint without another charge")
	var bad = construction_save.duplicate(true)
	bad.factory.reserves.scrap = -1
	check(not game.checkpoint.validate(bad),"negative construction balance is rejected")
	var old_reward = clear_save.duplicate(true)
	old_reward.version = 4
	old_reward.factory.inventory = Factory.new().inventory
	old_reward.run.reward_options = ["block:belt","block:auto_press","gear:armor"]
	check(game.checkpoint.apply(game,old_reward) and game.expedition.reward_options.all(func(id): return id.begins_with("gear:")),"old mixed draft migrates to equipment only")
	var migrated = game.expedition.reward_options.duplicate()
	check(game.checkpoint.apply(game,old_reward) and game.expedition.reward_options == migrated,"legacy draft migration is deterministic")
	var old_workshop = clear_save.duplicate(true)
	old_workshop.version = 3
	old_workshop.factory.erase("inventory")
	old_workshop.run.phase = "craft"
	old_workshop.run.reward_options = []
	check(game.checkpoint.apply(game,old_workshop) and game.expedition.phase == "reward","old workshop saves migrate directly to the new item draft")
	choices = game.expedition.reward_options.duplicate()
	check(game.checkpoint.apply(game,old_workshop) and game.expedition.reward_options == choices,"workshop migration is deterministic")
	game.reset_battle()
	check(game.factory.reserves == {"scrap":64,"coal":44} and game.expedition.equipment.is_empty(),"new run resets earned gear and construction resources")
	print("ITEM REWARDS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("item_rewards_test")
