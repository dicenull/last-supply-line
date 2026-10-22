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
	for sample in [
		{"seed":1333,"sector":5,"kind":"coalfield","encounter":"rich","route_seed":872583036,"at":Vector3(26.97793,0,14.86048),"yaw":0.005510688,"taken":1,"variant":76,"terrain":"mud"},
		{"seed":2251,"sector":3,"kind":"arsenal","encounter":"hostile","route_seed":1660790971,"at":Vector3(76.91239,0,-25.97725),"yaw":-0.365832716,"taken":3,"variant":130,"terrain":"mud"},
		{"seed":3577,"sector":5,"kind":"coalfield","encounter":"shop","route_seed":1098885777,"at":Vector3(26.93572,0,16.04033),"yaw":-0.057107095,"taken":1,"variant":208,"terrain":"road"},
		{"seed":3662,"sector":1,"kind":"scrapyard","encounter":"standard","route_seed":1531326520,"at":Vector3(41.75213,0,-25.59912),"yaw":0.292945951,"taken":2,"variant":213,"terrain":"road","mode":"hard"}
	]: await scenario(sample)
	print("EQUIPMENT PILOT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func scenario(sample: Dictionary):
	print("PILOT SCENARIO: ",sample.seed)
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_pilot_test",2)
	game.show_start_menu = false
	game.expedition = preload("res://scripts/run_state.gd").new(sample.seed,sample.get("mode","easy"))
	game.expedition.sector = sample.sector
	game.expedition.current = game.expedition.make_route(sample.kind,false,sample.encounter)
	game.expedition.current.seed = sample.route_seed
	game.expedition.current.terrain = sample.terrain
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.factory.reserves = {"scrap":100,"coal":100}
	Pilot.prepare(game,sample.variant)
	game.toggle_running()
	var b = game.battlefield
	for enemy in b.enemies: enemy.hp = 0
	b.kills = b.total
	# Recorded poses from overnight runs 76, 130, 208 and 213, after supply collection.
	b.player.position = sample.at
	b.player.rotation.y = sample.yaw
	for i in range(sample.taken):
		b.resource_sites[i].taken = true
		b.resource_sites[i].node.set_taken(true)
	var next_uid = game.expedition.next_item_uid
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
	check(b.resource_sites.all(func(site): return site.taken) and game.expedition.next_item_uid-next_uid == (3-sample.taken)*(6 if sample.encounter == "rich" else 3),"recovery collects remaining areas exactly once without replaying collected supplies")
	check(game.factory.fuel_used > 0 and game.factory.injected > 0,"recovery consumes fuel supplied by real production")
	game.reset_battle(1333)
	game.toggle_running()
	game.open_menu()
	at = game.battlefield.player.position
	Pilot.drive(game,0.1,1)
	check(game.battlefield.player.position == at,"pilot cannot move the vehicle through a paused menu")
	game.queue_free()
	await process_frame
