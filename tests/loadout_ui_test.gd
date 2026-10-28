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
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
		if pressed:
			for frame in range(6): game._process(0.016)
	game._process(0)
	await process_frame
func find_row(kind: String, include_stock: bool = false) -> int:
	var panel = game.inventory_panel
	panel.page = 0
	panel.refresh()
	while true:
		for i in range(panel.rows.size()):
			if panel.rows[i].kind == kind and (include_stock or not panel.rows[i].get("stock",false)): return i
		if panel.next.disabled: return -1
		panel.page += 1
		panel.refresh()
	return -1

func key(code):
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event,false)
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
	var kinds = {"gear":"vehicle_gear_torque","engine":"vehicle_engine_power","tracks":"vehicle_tracks_wide","cannon":"vehicle_cannon_howitzer"}
	for kind in kinds.values(): game.expedition.add_item({"kind":kind,"rarity":"rare"})
	game.expedition.add_item({"kind":"vehicle_engine_efficient","rarity":"legendary"})
	check(game.checkpoint.write_file("res://build/loadout-ui/web-fixture.mfv",game.checkpoint.snapshot(game)),"browser fixture validates")
	var geometry = {}
	var panel = game.inventory_panel
	var left = panel.loadout_panel
	for dimensions in [Vector2i(1440,940),Vector2i(1920,1080),Vector2i(1280,1024),Vector2i(844,390),Vector2i(390,844),Vector2i(320,320)]:
		root.min_size = Vector2i(320,320)
		root.size = dimensions
		await process_frame
		if game.menu.visible: game.close_menu()
		game.equipment_workspace.close_all()
		game._process(0)
		var original_transform = root.get_final_transform()
		var original_aspect = root.content_scale_aspect
		var original_world = game.world_rect()
		var original_camera = game.world.camera.global_transform
		for repeat in range(2):
			await key(KEY_I)
			check(panel.visible,"I opens inventory at "+str(dimensions))
			check(root.content_scale_aspect == original_aspect and root.get_final_transform().is_equal_approx(original_transform) and game.world_rect() == original_world and game.world.camera.global_transform == original_camera,"opening I preserves game position, scale and camera")
			var stable = panel.get_global_rect()
			await process_frame
			await process_frame
			check(panel.get_global_rect().is_equal_approx(stable),"inventory position stays stable after opening")
			await key(KEY_I)
			check(not panel.visible and root.get_final_transform().is_equal_approx(original_transform),"closing I preserves game position")
		game.equipment_workspace.close_all()
		game.touch_controls.refresh()
		await click(game.touch_controls.buttons.loadout)
		check(left.visible,"footer Q opens the left pane with a real click")
		await click(game.touch_controls.buttons.warehouse)
		check(panel.visible,"footer E remains clickable while a pane is open")
		await click(game.touch_controls.buttons.warehouse)
		check(not panel.visible,"footer E closes the right pane")
		game.equipment_workspace.close_all()
		await key(KEY_E)
		check(panel.visible,"E opens warehouse")
		await key(KEY_Q)
		check(left.visible and (not panel.visible if game.equipment_workspace.narrow else panel.visible),"Q opens independent left pane, narrow screens switch panes")
		await key(KEY_Q)
		check(not left.visible,"Q closes only the left pane")
		game.equipment_workspace.open_right()
		game._process(0)
		var visible_count = 0
		panel.select_tab("")
		while true:
			visible_count += panel.rows.size()
			if panel.next.disabled: break
			await click(panel.next)
		check(visible_count == 3,"all starting objects reachable through pages without scrolling")
		for slot in kinds:
			game.equipment_workspace.open_right()
			panel.select_tab(slot)
			var current = Inventory.vehicle_parts(game.expedition).get(slot,{})
			if not current.is_empty():
				var equipped_row = find_row(current.kind,true)
				check((panel.equip_buttons[equipped_row].visible == (slot == "cannon")) and "しまう" in panel.action_buttons[equipped_row].tooltip_text,"equipped part has one stow action")
				await click(panel.action_buttons[equipped_row])
			game.equipment_workspace.open_right()
			panel.select_tab(slot)
			var target_row = find_row(kinds[slot])
			await click(panel.row_buttons[target_row])
			check(not Inventory.vehicle_parts(game.expedition).has(slot),"selection leaves the slot unchanged")
			await click(panel.equip_buttons[target_row])
			check(Inventory.vehicle_parts(game.expedition).get(slot,{}).get("kind","") == kinds[slot],"held swap installs "+slot)
		panel.select_tab("engine")
		var row_index = find_row("vehicle_engine_efficient")
		await click(panel.row_buttons[row_index])
		game.equipment_workspace.open_left()
		var predicted: Dictionary = left.state.comparison.rows
		check(predicted.speed.after < predicted.speed.current and predicted.fuel.after < predicted.fuel.current,"comparison includes performance loss and fuel improvement")
		check(left.delta_color("fuel",predicted.fuel.after,predicted.fuel.current) == left.GOOD and left.delta_color("speed",predicted.speed.after,predicted.speed.current) == left.BAD,"improvements are green and penalties red")
		check(left.visible_metrics().size() == 14 and left.get_child_count() == 1,"Q shows all fourteen parameters with no tabs or equipment controls")
		var cards_fit = true
		for i in range(14):
			var rect = left.metric_rect(i)
			cards_fit = cards_fit and Rect2(Vector2.ZERO,left.size).encloses(rect) and rect.size.y >= 30
		check(cards_fit,"every parameter fits simultaneously without scrolling")
		check(left.delta_text("range",3.0) == "(+3.0)","selection changes use signed parentheses")
		for pane in [panel,left]:
			var rect: Rect2 = root.get_final_transform()*pane.get_global_rect()
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).grow(0.1).encloses(rect),"pane bounds stay on screen "+str(dimensions))
			check((root.get_final_transform()*game.world_rect()).grow(0.1).encloses(rect),"pane never covers the header or footer")
			var controls_fit = true
			for child in pane.get_children():
				if child is Control and child.visible: controls_fit = controls_fit and Rect2(Vector2.ZERO,pane.size).grow(0.1).encloses(child.get_rect())
			check(controls_fit,"all pane buttons stay inside its bounds")
		await capture("comparison-%d" % dimensions.x)
		await capture("firing-cost-%d" % dimensions.x)
		# Record real button positions for browser smoke tests; no runtime test bridge.
		var footer_points = {}
		game.touch_controls.refresh()
		for id in ["inventory","loadout","warehouse","menu","play"]:
			var point = root.get_final_transform()*game.touch_controls.buttons[id].get_global_rect().get_center()
			footer_points[id] = [point.x,point.y]
		var origin = root.get_final_transform()*panel.get_global_rect().position
		var panel_scale = (root.get_final_transform()*panel.get_global_transform()).get_scale().x
		var left_close = root.get_final_transform()*left.close_button.get_global_rect().get_center()
		geometry[str(dimensions.x)] = {"footer":footer_points,"right":{"origin":[origin.x,origin.y],"scale":panel_scale,"height":panel.size.y,"page_size":panel.page_size},"narrow":game.equipment_workspace.narrow,"left_close":[left_close.x,left_close.y]}
		# Placement leaves the comparison visible after closing the warehouse.
		var uid = game.expedition.gear_items[1].uid
		game.equipment_workspace.open_right()
		game.touch_controls.select_item(uid)
		game._process(0)
		check(left.visible and not panel.visible and left.state.comparison.item.uid == uid,"selected placement keeps live comparison open")
		await key(KEY_Q)
		check(not left.visible and game.selected_item_uid == uid,"Q hides comparison without cancelling placement")
		await key(KEY_Q)
		check(left.visible and game.selected_item_uid == uid,"Q restores comparison during placement")
		await capture("placement-comparison-%d" % dimensions.x)
		game.clear_equipment_selection()
		game.equipment_workspace.open_right()
		await key(KEY_B)
		game.touch_controls.refresh()
		var travel_points = {}
		for id in ["inventory","loadout","warehouse","menu","play"]:
			var point = root.get_final_transform()*game.touch_controls.buttons[id].get_global_rect().get_center()
			travel_points[id] = [point.x,point.y]
		geometry[str(dimensions.x)].travel_footer = travel_points
		check(game.battle_mode and not left.visible and not panel.visible and not game.equipment_workspace.visible,"switching to battle closes both panes")
		await key(KEY_Q)
		await key(KEY_E)
		check(game.equipment_workspace.visible,"panes can be reopened on the destination screen")
		await key(KEY_B)
		check(not game.battle_mode and not left.visible and not panel.visible,"returning to construction closes both panes")
	# The combined button must preserve its pressed action across state updates.
	game.equipment_workspace.open_right()
	panel.select_tab("gear")
	var action_row = find_row("vehicle_gear_torque")
	var action_uid = panel.rows[action_row].uid
	var action_button = panel.action_buttons[action_row]
	action_button.button_down.emit()
	check(game.stow_item(action_uid),"installed gear can be stowed while its action is held")
	var stock_before = game.factory.reserves.duplicate()
	panel.refresh()
	action_button.pressed.emit()
	check(not Inventory.find_item(game.expedition,action_uid).is_empty() and game.factory.reserves == stock_before,"held stow action never changes into scrap after refresh")
	game.equipment_workspace.open_left()
	game.equipment_workspace.open_right()
	game.toggle_running()
	check(game.started and not left.visible and not panel.visible,"departure closes both panes")
	var file = FileAccess.open("res://build/loadout-ui/geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(geometry))
	game.free()
	Fixture.clean("loadout_ui_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
