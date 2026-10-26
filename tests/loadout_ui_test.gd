extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
var game
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS loadout UI: ",label)
	else:
		failures += 1
		push_error(label)
func click(button):
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await process_frame
		parent = parent.get_parent()
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
		if pressed:
			for frame in range(6):
				game._process(0.016)
	game._process(0)
	await process_frame
func capture(name):
	game._process(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/loadout-ui/"+name+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/loadout-ui")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"loadout_ui_test",2)
	game.touch_enabled = true
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	game.refresh_view()
	var kinds = {"gear":"vehicle_gear_torque","engine":"vehicle_engine_power","tracks":"vehicle_tracks_wide","cannon":"vehicle_cannon_howitzer"}
	for kind in kinds.values(): game.expedition.add_item({"kind":kind,"rarity":"rare"})
	game.expedition.add_item({"kind":"vehicle_engine_efficient","rarity":"legendary"})
	check(game.checkpoint.write_file("res://build/loadout-ui/web-fixture.mfv",game.checkpoint.snapshot(game)),"browser fixture passes save validation")
	for dimensions in [Vector2i(1440,940),Vector2i(844,390),Vector2i(390,844)]:
		root.size = dimensions
		await process_frame
		if game.menu.visible: game.close_menu()
		game.inventory_panel.show()
		game._process(0)
		await process_frame
		game._process(0)
		var panel = game.inventory_panel
		await click(panel.tabs[0])
		check(panel.rows.size() == 3 and panel.rows.all(func(item): return Inventory.Catalog.part_slot(item.kind).is_empty()),"placed objects share one tab and exclude chassis equipment: "+str(dimensions))
		for slot in kinds:
			await click(panel.tabs[panel.TAB_LABELS.keys().find(slot)])
			check(not panel.rows.is_empty() and panel.rows.all(func(item): return Inventory.Catalog.part_slot(item.kind) == slot),"slot tab contains only "+slot)
			var current: Dictionary = Inventory.vehicle_parts(game.expedition).get(slot,{})
			if not current.is_empty(): await click(panel.loadout_panel.remove_buttons[slot])
			await click(panel.row_buttons[0])
			check(not Inventory.vehicle_parts(game.expedition).has(slot),"selecting a part does not accidentally equip or undo the swap")
			await click(panel.stow_buttons[0])
			current = Inventory.vehicle_parts(game.expedition).get(slot,{})
			check(current.get("kind","") == kinds[slot] and panel.stow_buttons[0].disabled,"actual swap button installs exactly once: "+slot)
			check(panel.loadout_panel.state.vehicle_parts.get(slot,{}).get("kind","") == kinds[slot] and game.world.vehicle_parts.get(slot,{}).get("kind","") == kinds[slot] and game.battlefield.vehicle_parts.get(slot,{}).get("kind","") == kinds[slot],"left pane and both tank models update immediately: "+slot)
		var engine_uid = Inventory.vehicle_parts(game.expedition).engine.uid
		var old_parameters = game.vehicle_parameters()
		await click(panel.tabs[2])
		await click(panel.stow_buttons[1])
		check(Inventory.vehicle_parts(game.expedition).engine.kind == "vehicle_engine_efficient" and Inventory.find_item(game.expedition,engine_uid).position == Inventory.STOWED,"swapping a populated slot returns the previous engine to storage")
		check(game.vehicle_parameters() != old_parameters and panel.loadout_panel.state.parameters == game.vehicle_parameters(),"parameters recalculate on the same swap")
		check(panel.stacked == (dimensions.x < dimensions.y),"left pane stacks below inventory on a narrow portrait screen")
		if not panel.stacked:
			var left = (root.get_final_transform()*panel.loadout_panel.get_global_transform()).origin.x
			check(absf(left-16) < 1.0,"equipped panel sits at the left screen edge")
		await capture("warehouse-%d" % dimensions.x)
		panel.hide()
		game.refresh_view()
		await process_frame
		await capture("equipped-tank-%d" % dimensions.x)
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved) and Inventory.vehicle_parts(game.expedition).size() == 4,"swapped slots, performance and appearance restore from save")
	root.size = Vector2i(1440,940)
	await process_frame
	game.inventory_panel.show()
	game._process(0)
	await process_frame
	for slot in kinds:
		await click(game.inventory_panel.loadout_panel.remove_buttons[slot])
		check(slot in game.expedition.empty_part_slots and game.inventory_panel.loadout_panel.remove_buttons[slot].disabled,"remove button leaves an empty slot: "+slot)
	await capture("empty-warehouse")
	game.inventory_panel.hide()
	game.refresh_view()
	await capture("empty-tank")
	game.world.toggle_roof()
	await capture("empty-exterior")
	check(game.checkpoint.apply(game,saved),"reequip saved parts after empty-state screenshots")
	game.toggle_running()
	game.factory.running = false
	game.inventory_panel.show()
	game.inventory_panel.select_tab("engine")
	check(game.inventory_panel.stow_buttons.all(func(b): return not b.visible or b.disabled),"departed tanks show disabled swap actions")
	game.free()
	Fixture.clean("loadout_ui_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
