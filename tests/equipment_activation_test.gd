extends SceneTree
const F = preload("res://scripts/factory.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Activation = Inventory.Activation
const Params = preload("res://scripts/vehicle_parameters.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS activation: ",label)
	else:
		failures += 1
		push_error(label)
func active(f, kind: String, at: Vector2i, direction: int = 0) -> bool:
	return Activation.status(f,{"kind":kind,"position":at,"direction":direction},Activation.ammo_network(f)).active
func run():
	var f = F.new(2)
	f.example(false)
	check(active(f,"armor",Vector2i(0,1)) and not active(f,"armor",Vector2i(2,2)),"armour activates only on the outer hull edge")
	check(active(f,"skirts",Vector2i(13,2),1) and not active(f,"skirts",Vector2i(12,2),1),"rotated footprint determines the outer edge")
	check(active(f,"supercharger",Vector2i(0,3)) and not active(f,"supercharger",Vector2i(1,3)),"engine equipment needs side adjacency, not diagonal proximity")
	check(active(f,"economizer",Vector2i(1,4),1),"rotated engine equipment can share an engine side")
	check(active(f,"drum_loader",Vector2i(8,0)),"loader beside a production-to-main-magazine pipe activates")
	check(not active(f,"blast_fuse",Vector2i(4,3)),"fuel supply does not activate shell processing")
	f.cells[Vector2i(9,2)].dir = 3
	check(not active(f,"drum_loader",Vector2i(8,0)),"wrong pipe direction breaks the actual shell route")
	f.cells[Vector2i(9,2)].dir = 1
	f.cells.erase(Vector2i(8,1))
	check(not active(f,"drum_loader",Vector2i(8,0)),"broken upstream pipe disables the loader even beside downstream pipe")
	f.cells[Vector2i(8,1)] = f.make_cell("belt",0)
	check(active(f,"drum_loader",Vector2i(8,0)),"repair reconnects the effect without reinstalling equipment")
	f.cells[Vector2i(8,1)] = f.make_cell("fuel_filter",0)
	check(not active(f,"drum_loader",Vector2i(8,0)),"fuel-only filter cannot conduct an ammunition effect")
	f.cells[Vector2i(8,1)] = f.make_cell("shell_filter",0)
	check(active(f,"drum_loader",Vector2i(8,0)),"shell filter preserves ammunition connectivity")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_activation_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	f = game.factory
	var uid = game.expedition.add_item({"kind":"drum_loader","rarity":"normal"})
	check(game.place_item(uid,Vector2i(0,0)),"inactive location is allowed and remains visible for redesign")
	check(Inventory.effects(game.expedition,f).reload == 1 and game.battlefield.equipment_effect("shot_fuel",0) == 0,"wrong location grants neither reload bonus nor operating cost")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"inactive installed equipment survives save and reload")
	f = game.factory
	check(game.stow_item(uid),"inactive equipment can be put away")
	var no_site = Params.compare(game.expedition,f,uid)
	var preview = Params.compare(game.expedition,f,uid,Vector2i(8,0))
	check(not no_site.activation.active and preview.activation.active and preview.rows.reload.change < 0,"comparison uses the proposed placement, not a global unconditional bonus")
	check(game.place_item(uid,Vector2i(8,0)),"loader can be installed next to the shell route")
	check(is_equal_approx(game.battlefield.equipment_effect("reload",1),0.55) and is_equal_approx(game.battlefield.equipment_effect("shot_fuel",0),0.16),"active location changes actual battle modifiers")
	check(is_equal_approx(Params.compare(game.expedition,f).rows.reload.current,preview.rows.reload.after),"preview agrees with installed performance")
	var moved_preview = Params.compare(game.expedition,f,uid,Vector2i.ZERO)
	check(not moved_preview.activation.active and moved_preview.rows.reload.change > 0,"moving installed equipment previews loss of its location-dependent bonus")
	f.cells.erase(Vector2i(9,2))
	game.sync_equipment()
	check(game.battlefield.equipment_effect("reload",1) == 1 and not game.inventory_state().activation[uid].active,"line destruction immediately disables combat and inventory indicators")
	f.cells[Vector2i(9,2)] = f.make_cell("belt",1)
	game.sync_equipment()
	check(game.inventory_state().activation[uid].active,"repair restores the same mounted equipment")
	# A connected ammunition reserve may feed a secondary from any perimeter socket.
	var secondary = game.expedition.gear_items[0].uid
	check(game.place_item(secondary,Vector2i.ZERO),"secondary mounted for independent route check")
	f.edit(Vector2i(3,1),"depot",2)
	f.edit(Vector2i(2,1),"belt",2)
	check(active(f,"blast_fuse",Vector2i(2,0)),"buffered supply to an auxiliary perimeter also activates processing")
	game.free()
	await process_frame
	Fixture.clean("equipment_activation_test")
	print("ACTIVATION RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
