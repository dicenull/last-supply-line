extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Pilot = preload("res://tests/equipment_pilot.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("equipment_pilot_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment pilot: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_pilot_test",2)
	game.show_start_menu = false
	game.expedition = preload("res://scripts/run_state.gd").new(1333,"easy")
	game.expedition.sector = 5
	game.expedition.current = game.expedition.make_route("coalfield",false,"rich")
	game.expedition.current.seed = 872583036
	game.expedition.current.terrain = "mud"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.factory.reserves = {"scrap":100,"coal":100}
	Pilot.prepare(game,76)
	game.toggle_running()
	var b = game.battlefield
	for enemy in b.enemies: enemy.hp = 0
	b.kills = b.total
	# Recorded pose from the 76th overnight run, immediately after supply 1.
	b.player.position = Vector3(26.97793,0,14.86048)
	b.player.rotation.y = 0.005510688
	b.resource_sites[0].taken = true
	b.resource_sites[0].node.set_taken(true)
	game.factory.fuel = 12
	var at: Vector3 = b.player.position
	for i in range(60): Fixture.drive(game,0.1,1)
	check(b.player.position.distance_to(at) < 0.01 and game.expedition.phase == "travel","original turn-only pilot reproduces the blocked roadside pivot")
	for i in range(60): Pilot.drive(game,0.1,1)
	check(b.player.position.distance_to(at) > 1,"recovery creates turning room with ordinary movement")
	for i in range(1800):
		Pilot.drive(game,0.1,1)
		if i%20 == 0: Pilot.maintain(game)
		if game.expedition.phase != "travel": break
	check(game.expedition.phase == "reward" and b.arrived_destination == 1 and b.hull == 100,"recovered pilot reaches the selected destination without removing scenery")
	check(b.resource_sites.all(func(site): return site.taken),"recovery still enters both remaining supply areas")
	check(game.factory.fuel_used > 0 and game.factory.injected > 0,"recovery consumes fuel supplied by real production")
	game.reset_battle(1333)
	game.toggle_running()
	game.open_menu()
	at = game.battlefield.player.position
	Pilot.drive(game,0.1,1)
	check(game.battlefield.player.position == at,"pilot cannot move the vehicle through a paused menu")
	game.queue_free()
	await process_frame
	print("EQUIPMENT PILOT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
