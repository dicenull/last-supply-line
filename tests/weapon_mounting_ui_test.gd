extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS mounting UI: ",label)
	else:
		failures += 1
		push_error(label)
func click(at: Vector2):
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = root.get_final_transform()*at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
	game._process(0)
	await process_frame
func cell_screen(at: Vector2i) -> Vector2:
	return game.factory_container.position+game.world.camera.unproject_position(game.world.cell_position(at)+Vector3(0,0.03,0))
func capture(name: String):
	game._process(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/weapon-mounting-ui/"+name+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/weapon-mounting-ui")
	root.min_size = Vector2i(320,320)
	for dimensions in [Vector2i(1440,940),Vector2i(844,390)]:
		root.size = dimensions
		game = load("res://main.tscn").instantiate()
		Fixture.assign(game,"weapon_mounting_ui_test",2)
		game.touch_enabled = dimensions.x == 844
		game.show_start_menu = false
		root.add_child(game)
		game.set_process(false)
		await process_frame
		game.ensure_battle()
		game.equipment_workspace.open_right()
		game.inventory_panel.select_tab("cannon")
		game._process(0)
		await process_frame
		var button = game.inventory_panel.equip_buttons[0]
		check(button.visible and not button.disabled and "移動" in button.tooltip_text,"equipped main cannon has a relocation button")
		await click(button.get_global_rect().get_center())
		check(game.equipment_placement_uid() >= 0 and not game.inventory_panel.visible and game.touch_controls.mode == "place","real button enters main relocation mode")
		# Q remains independently closable so the new location is easy to reach.
		game.equipment_workspace.close_all()
		game.hover = Vector2i(11,5)
		await capture("main-preview-"+str(dimensions.x))
		check(game.world.equipment_preview.visible,"main relocation shows a visible two-by-two preview")
		await click(cell_screen(Vector2i(11,5)))
		check(game.factory.main_gun_anchor == Vector2i(11,5) and game.touch_controls.mode == "build","clicking the deck moves the equipped main cannon and exits placement")
		var first = game.expedition.gear_items[0].uid
		var second = game.expedition.add_item({"kind":"long_gun","rarity":"rare"})
		check(game.place_item(first,Vector2i.ZERO) and game.place_item(second,Vector2i(1,0)),"overlapping guns mount in the displayed game")
		game.clear_equipment_selection()
		game.equipment_workspace.close_all()
		await capture("stacked-interior-"+str(dimensions.x))
		game.world.toggle_roof()
		await capture("stacked-exterior-"+str(dimensions.x))
		var guns = game.world.auxiliary_guns
		check(guns[0].tier != guns[1].tier and guns.any(func(g): return g.riser.visible),"raised gun has a visible support column")
		check(game.checkpoint.write_file("res://build/weapon-mounting-ui/web-fixture.mfv",game.checkpoint.snapshot(game)),"relocated stack is saveable")
		game.free()
		await process_frame
	Fixture.clean("weapon_mounting_ui_test")
	print("WEAPON MOUNTING UI RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
