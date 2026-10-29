extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS construction selection: ",label)
	else:
		failures += 1
		push_error(label)
func key(code):
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event,false)
	game._process(0)
	await process_frame
func weapon_meshes(node):
	return node.find_children("*","MeshInstance3D",true,false).filter(func(mesh): return not mesh.get_meta("weapon_effect",false))
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"construction_selection_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.hover = Vector2i(2,0)
	var layout = game.factory.layout()
	var reserves = game.factory.reserves.duplicate()
	await key(KEY_1)
	game.paint(Vector2i(2,0),false)
	check(game.selected.is_empty() and not game.world.placement_preview.visible and game.factory.layout() == layout and game.factory.reserves == reserves,"repeated key enters idle and world clicks spend nothing")
	await key(KEY_1)
	check(game.selected == "belt" and game.world.placement_preview.visible,"same key restores placement after idle")
	game.tool_buttons.belt.pressed.emit()
	game._process(0)
	check(game.selected.is_empty(),"same equipment button toggles placement off")
	game.select_tool_tab(1)
	game.select_tool_tab(1)
	game._process(0)
	check(game.selected.is_empty(),"same category toggles placement off")
	var uid = game.expedition.gear_items[0].uid
	game.begin_item_drag(uid)
	game.hover = Vector2i(-1,-1)
	game._process(0)
	check(game.world.placement_range.visible and Vector2i(2,0) in game.world.placement_range_cells and Vector2i(13,7) not in game.world.placement_range_cells,"drag highlights valid anchors even when pointer is outside the deck")
	game.factory.wrecks[Vector2i(2,0)] = "belt"
	game._process(0)
	check(Vector2i(2,0) not in game.world.placement_range_cells,"newly blocked cells leave the highlighted range")
	game.factory.wrecks.clear()
	game._process(0)
	check(game.place_item(uid,Vector2i(2,0)),"highlighted cell accepts the dropped equipment")
	game._process(0)
	check(game.world.placement_range.visible,"selected installed item retains its possible relocation range")
	var gun = game.world.auxiliary_guns[0]
	check(weapon_meshes(gun.pivot).all(func(mesh): return is_equal_approx(mesh.material_override.albedo_color.a,0.01)),"interior secondary including fittings uses one-percent opacity")
	check(is_equal_approx(game.world.mats.turret_armor.albedo_color.a,0.01),"interior main turret uses one-percent opacity")
	var library = game.world.equipment_models.build(gun.id,"normal")
	check(weapon_meshes(library).all(func(mesh): return mesh.material_override.albedo_color.a == 1),"cutaway never fades shared library models")
	library.free()
	game.world.toggle_roof()
	game._process(0)
	check(not game.world.placement_range.visible and weapon_meshes(gun.pivot).all(func(mesh): return mesh.material_override.albedo_color.a == 1),"exterior restores solid secondary models and hides range")
	game.world.toggle_roof()
	game._process(0)
	check(game.world.placement_range.visible and weapon_meshes(gun.pivot).all(func(mesh): return is_equal_approx(mesh.material_override.albedo_color.a,0.01)),"reopening restores cutaway and selected range")
	game.inventory_panel.item_selected.emit(uid)
	game._process(0)
	check(game.selected.is_empty() and game.selected_item_uid < 0 and not game.world.placement_range.visible,"reselecting the inventory item clears placement and range")
	game.free()
	Fixture.clean("construction_selection_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
