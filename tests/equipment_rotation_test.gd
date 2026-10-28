extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Models = preload("res://scripts/item_model.gd")
var game
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment rotation: ",label)
	else:
		failures += 1
		push_error(label)
func press(code):
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event,false)
	game._process(0)
func capture(name):
	game._process(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/equipment-rotation/"+name+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/equipment-rotation")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_rotation_test",2)
	game.touch_enabled = true
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.factory.clear_layout(false,false)
	var gun_uid: int = game.expedition.gear_items[0].uid
	var armor_uid: int = game.expedition.gear_items[1].uid
	check(game.place_item(gun_uid,Vector2i.ZERO),"mount a gun for four-direction rotation")
	game.factory.cells[Vector2i.ZERO].items = ["shell","shell"]
	game.select_equipment(gun_uid)
	game.ensure_battle()
	game.refresh_view()
	for direction in [1,2,3,0]:
		press(KEY_R)
		var gun: Dictionary = game.battlefield.auxiliary_guns[0]
		var heading = Vector3.RIGHT.rotated(Vector3.UP,-direction*PI/2)
		check(Inventory.find_item(game.expedition,gun_uid).direction == direction and game.factory.equipment_rotations.left_gun == direction and game.factory.auxiliary_ammo("left_gun") == 2,"R rotates installed gun without losing ammunition: "+str(direction))
		check(game.battlefield.within_gun_arc(gun,gun.pivot.global_position+heading*20) and not game.battlefield.within_gun_arc(gun,gun.pivot.global_position-heading*20),"firing arc follows the installed direction")
		var contained = true
		var origin: Vector3 = game.world.cell_position(Vector2i.ZERO)
		var local_gun: Dictionary = game.world.auxiliary_guns[0]
		for relative in [-gun.half_arc,0.0,gun.half_arc]:
			local_gun.pivot.rotation.y = -direction*PI/2+relative
			for vertex in Models.vertices(local_gun.pivot,local_gun.pivot.transform):
				contained = contained and vertex.x >= origin.x-1.5 and vertex.x <= origin.x+2.5 and vertex.z >= origin.z-1.5 and vertex.z <= origin.z+2.5
		check(contained,"rotated enlarged gun retains its intended orientation and scale")
	game.clear_equipment_selection()
	check(game.place_item(armor_uid,Vector2i(3,0)),"mount rectangular armor")
	game.select_equipment(armor_uid)
	press(KEY_R)
	check(game.factory.mounted_at(Vector2i(3,1)) == "armor" and game.factory.mounted_at(Vector2i(4,0)) == "","90 degrees swaps occupied width and height")
	check(is_equal_approx(game.world.mounted_models.armor.rotation.y,-PI/2),"installed 3D armor follows the saved orientation")
	game.factory.edit(Vector2i(4,0),"belt",0)
	var before = game.checkpoint.snapshot(game)
	press(KEY_R)
	check(Inventory.find_item(game.expedition,armor_uid).direction == 1 and game.factory.equipment_rotations.armor == 1 and game.factory.cells.has(Vector2i(4,0)),"blocked rotation is atomic and preserves the neighboring conveyor")
	game.factory.edit(Vector2i(4,0),"erase",0)
	game._process(0)
	check(game.world.equipment_marks.visible and game.world.equipment_marks.get_child_count() == 2 and game.selected_item_uid == armor_uid,"installed footprints and selected equipment remain visibly marked")
	await capture("selected-installed")
	game.toggle_inventory()
	check(game.inventory_panel.state.selected_uid == armor_uid and game.inventory_panel.row_buttons[1].tooltip_text.contains("設置済み") and game.inventory_panel.row_buttons[2].tooltip_text.contains("未設置"),"inventory distinguishes selected, installed and stored items")
	await capture("inventory-state")
	game.inventory_panel.hide()
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved) and game.factory.equipment_rotations.armor == 1 and Inventory.find_item(game.expedition,armor_uid).direction == 1,"orientation survives checkpoint and reconstructs both worlds")
	var bad = saved.duplicate(true)
	bad.run.gear_items[1].direction = 2
	check(not game.checkpoint.validate(bad),"checkpoint rejects disagreement between item and mounted orientation")
	bad = saved.duplicate(true)
	bad.factory.equipment_rotations.armor = 4
	check(not game.checkpoint.validate(bad),"checkpoint rejects out-of-range orientation")
	game.select_equipment(gun_uid)
	press(KEY_R)
	check(game.stow_item(gun_uid) and Inventory.find_item(game.expedition,gun_uid).direction == 1 and Inventory.find_item(game.expedition,gun_uid).ammo == 2,"storage preserves rotation and loaded rounds")
	check(game.place_item(gun_uid,Vector2i.ZERO) and game.factory.equipment_rotations.left_gun == 1 and game.factory.auxiliary_ammo("left_gun") == 2,"reinstall restores stored orientation and ammunition")
	game.touch_enabled = true
	game.touch_controls.select_item(armor_uid)
	game.touch_controls.action("rotate")
	check(game.factory.equipment_rotations.armor == 2 and game.selected_item_uid == armor_uid,"touch selection uses the same installed rotation command")
	root.size = Vector2i(844,390)
	await process_frame
	await capture("touch-selected")
	game.touch_controls.cancel_placement()
	game.begin_item_drag(armor_uid)
	press(KEY_R)
	check(game.item_direction == 3 and game.factory.equipment_rotations.armor == 2,"rotation during drag previews without changing the original installation")
	press(KEY_ESCAPE)
	check(game.selected_item_uid == -1 and game.factory.equipment_rotations.armor == 2,"cancelling drag leaves the installed orientation unchanged")
	# Version 11 had no orientation fields and must still load facing forward.
	game.select_equipment(gun_uid)
	for i in range(3): game.rotate_selection()
	game.select_equipment(armor_uid)
	for i in range(2): game.rotate_selection()
	var legacy = game.checkpoint.snapshot(game)
	legacy.version = 11
	legacy.factory.erase("equipment_rotations")
	for item in legacy.run.gear_items: item.erase("direction")
	check(game.checkpoint.validate(legacy) and game.checkpoint.apply(game,legacy) and game.factory.equipment_rotations.is_empty(),"version 11 saves load with the original forward orientation")
	game.toggle_running()
	var snapshot = game.checkpoint.snapshot(game)
	check(not game.select_equipment(gun_uid) and not Inventory.place(game.expedition,game.factory,gun_uid,Vector2i.ZERO,1) and game.checkpoint.validate(snapshot),"departure locks rotation and placement and remains saveable")
	game.free()
	Fixture.clean("equipment_rotation_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
