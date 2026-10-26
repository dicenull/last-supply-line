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
	check(game.factory.reserves == reserves and game.battlefield.ground_items.size() == 1,"kill leaves materials on the ground without granting them")
	collect_near(game,enemy.node.position)
	check(game.expedition.gear_items.size() == inventory_count and game.factory.reserves.scrap == reserves.scrap+2 and game.factory.reserves.coal == reserves.coal,"ordinary enemy awards scrap without equipment")
	reserves = game.factory.reserves.duplicate()
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	check(game.expedition.gear_items.size() == inventory_count and game.factory.reserves == reserves,"same enemy cannot award twice")
	snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot),"travel checkpoint includes loot and locked loadout: "+game.checkpoint.error)
	check(game.checkpoint.apply(game,snapshot) and game.factory.loadout_locked,"reload preserves departure lock")
	check(not game.place_item(game.expedition.gear_items[1].uid,Vector2i(2,0)),"paused checkpoint cannot install equipment")
	enemy = game.battlefield.enemies[0]
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	check(game.factory.reserves == reserves and game.expedition.gear_items.size() == inventory_count,"reload preserves materials and prevents duplicate drops")
	var b = game.battlefield
	b.sector_config.boss = true
	var transport = b.enemies[1]
	transport.role = 9
	b.kill_enemy(transport,game.factory,transport.node.position)
	collect_near(game,transport.node.position)
	check(game.factory.reserves.scrap == reserves.scrap+8 and game.factory.reserves.coal == reserves.coal+4 and game.expedition.gear_items.size() == inventory_count,"ordinary transport in a boss sector drops its scrap and coal")
	reserves = game.factory.reserves.duplicate()
	b.combat_modifiers.equipment_effects = {"salvage_rate":1.0/3.0}
	var third = b.enemies[2]
	third.role = 0
	b.kill_enemy(third,game.factory,third.node.position)
	collect_near(game,third.node.position)
	check(game.factory.reserves.scrap == reserves.scrap+4 and game.factory.reserves.coal == reserves.coal+1 and game.expedition.gear_items.size() == inventory_count,"crane adds materials on the third kill without equipment")
	reserves = game.factory.reserves.duplicate()
	var boss = b.enemies.back()
	b.kill_enemy(boss,game.factory,boss.node.position)
	check(game.expedition.gear_items.size() == inventory_count and b.ground_items.size() == 1,"boss equipment remains at its death location")
	collect_near(game,boss.node.position)
	check(game.expedition.gear_items.size() == inventory_count+1 and game.expedition.gear_items.back().rarity != "normal" and game.factory.reserves == reserves,"boss keeps its equipment reward")
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_inventory_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func collect_near(game, at: Vector3):
	game.battlefield.drive_poses = [{"position":at,"yaw":0.0}]
	game.battlefield.update_ground_items(game.factory)
