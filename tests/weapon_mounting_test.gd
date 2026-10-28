extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS mounting: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"weapon_mounting_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	var f = game.factory
	var first = game.expedition.gear_items[0].uid
	var second = game.expedition.add_item({"kind":"long_gun","rarity":"rare"})
	check(game.place_item(first,Vector2i.ZERO) and game.place_item(second,Vector2i(1,0)),"secondary footprints may overlap")
	check(not game.place_item(second,Vector2i.ZERO),"independent ammunition anchors cannot overwrite one another")
	var guns = game.battlefield.auxiliary_guns
	check(guns.size() == 2 and guns[0].tier != guns[1].tier and absf(guns[0].pivot.position.y-guns[1].pivot.position.y) >= 4.8,"overlapping guns use separated lower and upper decks")
	check(guns.all(func(g): return is_equal_approx(g.pivot.scale.x,g.mount_scale*2.0)),"both guns are twice the old interior width")
	f.cells[Vector2i.ZERO].items = ["shell"]
	f.cells[Vector2i(1,0)].items = ["shell","shell"]
	var snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot) and game.checkpoint.apply(game,snapshot),"overlapping mounts survive checkpoint validation and restore")
	f = game.factory
	check(f.auxiliary_ammo("left_gun") == 1 and f.auxiliary_ammo("long_gun") == 2,"each overlapping gun retains its own rounds")
	check(game.stow_item(first) and f.auxiliary_ammo("long_gun") == 2 and f.mounted_at(Vector2i(1,0)) == "long_gun","stowing lower gun cannot remove upper gun or its ammunition")
	check(game.place_item(first,Vector2i(11,0)),"main turret proximity no longer prevents placement")
	check(game.battlefield.auxiliary_guns.filter(func(g): return g.id == "left_gun")[0].tier == 1,"main turret interference raises the secondary")
	var cannon: Dictionary = Inventory.vehicle_parts(game.expedition).cannon
	f.ammo = 5
	f.fuel = 6
	var reserves = f.reserves.duplicate()
	check(game.place_item(cannon.uid,Vector2i(11,5)),"installed main cannon can move with its 2x2 magazine")
	check(f.main_gun_anchor == Vector2i(11,5) and f.ports[Vector2i(12,6)] == "gun" and not f.cells.has(Vector2i(9,3)),"old magazine cells clear and all four new cells receive ammunition")
	check(f.ammo == 5 and f.fuel == 6 and f.reserves == reserves and cannon.position == Inventory.Catalog.part_position(cannon.kind),"moving preserves supplies and the equipped slot")
	check(game.world.turret.position == Vector3(5,4.08,2) and game.battlefield.turret.position == game.world.turret.position,"interior and combat main turret follow the same new anchor")
	check(not game.place_item(cannon.uid,Vector2i(13,7)) and not game.place_item(cannon.uid,Vector2i(6,3)) and f.main_gun_anchor == Vector2i(11,5),"out-of-bounds and occupied moves are rejected atomically")
	f.cells[Vector2i(10,5)] = f.make_cell("belt",0)
	f.cells[Vector2i(10,5)].items = ["shell"]
	f.auto_fire = false
	f.running = true
	f.step(0.25)
	f.running = false
	check(f.ammo == 6,"pipe delivers a real round at the relocated main inlet")
	snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot) and game.checkpoint.apply(game,snapshot),"moved main gun and overlapping secondaries round-trip together")
	check(game.factory.main_gun_anchor == Vector2i(11,5) and game.battlefield.turret.position == Vector3(5,4.08,2),"saved main location restores in the combat model")
	var bad = snapshot.duplicate(true)
	bad.factory.main_gun_anchor = Vector2i(99,99)
	check(not game.checkpoint.validate(bad),"save rejects an off-hull main anchor")
	game.reset_battle(42)
	var legacy = game.checkpoint.snapshot(game)
	legacy.version = 19
	legacy.factory.erase("main_gun_anchor")
	check(game.checkpoint.apply(game,legacy) and game.factory.main_gun_anchor == Vector2i(9,3),"version 19 migrates to the original main gun location")
	game.toggle_running()
	check(not game.place_item(Inventory.vehicle_parts(game.expedition).cannon.uid,Vector2i(11,5)),"departure locks main relocation like other equipment")
	game.free()
	await process_frame
	Fixture.clean("weapon_mounting_test")
	print("WEAPON MOUNTING RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
