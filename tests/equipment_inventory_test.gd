extends SceneTree
const F = preload("res://scripts/factory.gd")
const Run = preload("res://scripts/run_state.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_inventory_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot),"new inventory checkpoint validates: "+game.checkpoint.error)
	check(game.place_item(game.expedition.gear_items[0].uid,Vector2i(0,0)),"controller mounts stowed equipment")
	snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot),"installed footprint checkpoint validates: "+game.checkpoint.error)
	var bad = snapshot.duplicate(true)
	bad.run.gear_items[1].uid = bad.run.gear_items[0].uid
	check(not game.checkpoint.validate(bad),"duplicate item identity is rejected")
	bad = snapshot.duplicate(true)
	bad.factory.equipment_mounts.left_gun = Vector2i(9,3)
	check(not game.checkpoint.validate(bad),"overlapping checkpoint footprint is rejected")
	bad = snapshot.duplicate(true)
	bad.run.gear_items[0].rarity = "mythic"
	check(not game.checkpoint.validate(bad),"unknown saved rarity is rejected")
	check(game.checkpoint.apply(game,snapshot),"new inventory checkpoint round-trips")
	game.toggle_running()
	var inventory_count = game.expedition.gear_items.size()
	var reserves = game.factory.reserves.duplicate()
	var enemy = game.battlefield.enemies[0]
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	check(game.expedition.gear_items.size() == inventory_count+1 and game.factory.reserves == reserves,"enemy awards equipment instead of raw resources")
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	check(game.expedition.gear_items.size() == inventory_count+1,"same enemy cannot award twice")
	snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot),"travel checkpoint includes loot and locked loadout: "+game.checkpoint.error)
	check(game.checkpoint.apply(game,snapshot) and game.factory.loadout_locked,"reload preserves departure lock")
	check(not game.place_item(game.expedition.gear_items[1].uid,Vector2i(2,0)),"paused checkpoint cannot install equipment")
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_inventory_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
