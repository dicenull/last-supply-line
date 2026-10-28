extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS combo loot: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"combo_loot_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.toggle_running()
	var b = game.battlefield
	var stock = game.factory.reserves.duplicate()
	var expected = {"scrap":0,"coal":0}
	for i in range(4):
		var enemy = b.enemies[i]
		enemy.node.position = Vector3(35+i*30,0,20)
		var profile = game.RunState.Content.ENEMIES[enemy.role]
		b.kill_enemy(enemy,game.factory,enemy.node.position)
		var bonus = [0,1,1,2][i]
		for kind in ["scrap","coal"]:
			var amount = int(profile.get("loot",2) if kind == "scrap" else profile.get("coal",1))+bonus
			expected[kind] += amount
			check(b.ground_items[i*2+(0 if kind == "scrap" else 1)].item.amount == amount,"kill %d physical %s includes +%d" % [i+1,kind,bonus])
	check(game.factory.reserves == stock,"combo material rewards remain on the field until collected")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"uncollected combo loot survives checkpoint")
	b = game.battlefield
	check(b.ground_item_snapshot() == saved.battle.ground_items and b.score.combo_drop_bonus() == 0,"saved loot retains its bonus while a loaded combo resets")
	for entry in b.ground_items.duplicate():
		b.drive_poses = [{"position":entry.position,"yaw":0.0}]
		b.update_ground_items(game.factory)
	check(game.factory.reserves.scrap == stock.scrap+expected.scrap and game.factory.reserves.coal == stock.coal+expected.coal,"pickup grants exact accumulated bonus amounts")
	stock = game.factory.reserves.duplicate()
	b.update_ground_items(game.factory)
	check(game.factory.reserves == stock,"collected combo loot cannot be awarded twice")
	game.queue_free()
	await process_frame
	Fixture.clean("combo_loot_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
