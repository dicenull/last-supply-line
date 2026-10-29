extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
var game
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS responsive footer: ",label)
	else:
		failures += 1
		push_error(label)
func click(button):
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.pressed = pressed
		event.button_index = MOUSE_BUTTON_LEFT
		root.push_input(event,false)
	game._process(0)
	game.touch_controls.refresh()
	await process_frame
func capture(label):
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/responsive-footer/"+label+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/responsive-footer")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"responsive_footer_test",2)
	game.show_start_menu = false
	game.touch_enabled = true
	root.add_child(game)
	game.set_process(false)
	game.factory.unlocked_blocks = game.RunState.Content.BLOCK_LIMITS.keys()
	for dimensions in [Vector2i(1440,940),Vector2i(960,628),Vector2i(844,390)]:
		root.size = dimensions
		await process_frame
		game._process(0)
		game.touch_controls.refresh()
		check(game.footer_layout.compact == (dimensions.y < 628),"layout responds to available screen space")
		var scale = game.UIStyle.screen_scale(game)
		check(is_equal_approx(game.world_rect().end.y,928),"world reaches the bottom without a reserved footer band")
		var primary: Rect2 = game.start_button.get_global_rect()
		check(not primary.intersects(game.footer_rect()) and game.world_rect().encloses(primary) and primary.size.x*scale >= 71.9,"floating sortie action stays outside the dock with a touch-sized target")
		var actions_fit = true
		for entry in game.icon_buttons:
			if entry.icon in game.footer_layout.ACTIONS:
				actions_fit = actions_fit and game.footer_layout.controls_rect.grow(0.01).encloses(entry.rect)
		check(actions_fit,"management actions form an independent right-side rail")
		var before_layout = game.factory.layout()
		var before_stock = game.factory.reserves.duplicate()
		for index in game.TOOL_TABS.size():
			await click(game.tool_tabs[index])
			check(game.tool_page == index,"mouse click selects category "+str(index))
			var controls: Array = []
			var clear = true
			for entry in game.icon_buttons:
				if not entry.button.visible: continue
				if entry.icon == "play": continue
				var rect: Rect2 = entry.button.get_rect()
				clear = clear and game.world_rect().encloses(rect) and entry.button.icon != null and entry.button.text.is_empty() and rect.size.x*scale >= 43.9 and not entry.button.tooltip_text.is_empty()
				for other in controls: clear = clear and not rect.intersects(other)
				controls.append(rect)
			check(clear,"all category "+str(index)+" icons have touch-sized hit areas and descriptions, and never overlap each other")
			check(game.tool_buttons.keys() == game.tool_kinds(),"every available building remains reachable")
		check(game.factory.layout() == before_layout and game.factory.reserves == before_stock,"floating icon clicks never paint or spend resources through the UI")
		check(game.touch_controls.buttons.loadout.visible and game.touch_controls.buttons.warehouse.visible,"Q and E are visible in the shared footer")
		check(not game.icon_buttons.any(func(entry): return entry.icon in ["rotate","stow","erase"]),"construction action buttons are removed")
		check(game.start_button.get_theme_font("font") == game.UIStyle.HEADING_FONT,"large sortie action uses the display font")
		var before = game.world.roof_closed
		await click(game.touch_controls.buttons.roof)
		check(game.world.roof_closed != before,"right-side exterior button toggles armor through real pointer input")
		await click(game.touch_controls.buttons.roof)
		game.factory.cells.erase(Vector2i(1,0))
		game.factory.wrecks[Vector2i(1,0)] = "belt"
		game.factory.wreck_directions[Vector2i(1,0)] = 0
		game.field_actions.refresh()
		var repair: Rect2 = game.field_actions.button.get_global_rect()
		check(not repair.intersects(game.footer_layout.controls_rect) and not repair.intersects(primary) and not repair.intersects(game.footer_rect()),"repair stays clear of exterior rail, larger sortie and construction dock")
		game.factory.wrecks.clear()
		game.factory.wreck_directions.clear()
		await click(game.tool_tabs[0])
		await capture("prepare-%d" % dimensions.x)
		if dimensions.x == 844:
			var cell: Vector2 = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(Vector2i.ZERO))
			print("FOOTER WEB CELL: ",cell)
			for id in ["inventory","roof","play","menu"]: print("FOOTER WEB ",id,": ",game.touch_controls.buttons[id].get_rect().get_center())
		await click(game.start_button)
		check(game.started and game.factory.running and game.start_button.text == "停止","floating action starts combat through real pointer input")
		game._process(0)
		game.touch_controls.refresh()
		check(not game.footer_rect().has_area(),"construction dock disappears in driving mode")
		check(game.touch_controls.stick_center.y+game.touch_controls.STICK_RADIUS < game.footer_rect().position.y,"driving stick stays above the footer")
		await click(game.touch_controls.buttons.loadout)
		check(game.equipment_workspace.loadout.visible,"footer Q works while travelling")
		await click(game.touch_controls.buttons.warehouse)
		check(game.inventory_panel.visible,"footer E works while travelling")
		check(not game.start_button.get_global_rect().intersects(game.inventory_panel.get_global_rect()),"floating action moves aside for the warehouse")
		await click(game.start_button)
		check(not game.factory.running and game.start_button.text == "再開","floating action pauses while the warehouse is open")
		game.equipment_workspace.close_all()
		await capture("travel-%d" % dimensions.x)
		game.reset_battle(42)
		game.factory.unlocked_blocks = game.RunState.Content.BLOCK_LIMITS.keys()
	game.battle_mode = true
	game.expedition.phase = "lost"
	game._process(0)
	check(game.battle_retry.visible and game.battle_retry.icon != null and game.battle_retry.text == "再挑戦","defeat keeps a labeled retry action above the world")
	await click(game.battle_retry)
	check(game.expedition.phase == "prepare" and not game.started,"floating retry starts a new preparation through real pointer input")
	game.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("responsive_footer_test")
