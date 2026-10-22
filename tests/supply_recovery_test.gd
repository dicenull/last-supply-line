extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("supply_recovery_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS recovery: ",label)
	else:
		failures += 1
		push_error(label)
func create_game():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"supply_recovery_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	return game
func advance(game, ticks: int):
	for i in range(ticks):
		preload("res://tests/profile_fixture.gd").drive(game,0.1)
		if i%100 == 99: await process_frame
func run():
	for link in [Vector2i(3,7),Vector2i(9,3)]:
		var game = create_game()
		game.paint(link,true)
		game.toggle_running()
		game.toggle_battle()
		await advance(game,120)
		var fuel_case = link.y == 7
		check(game.factory.running and game.expedition.phase == "travel","disconnected supply keeps automatic simulation active")
		check(game.battlefield.distance == 0 if fuel_case else game.factory.shots == 0,"missing link prevents movement or firing without free supplies")
		var stock = game.factory.reserves.duplicate()
		game.last_paint = Vector2i(-1,-1)
		game.selected = "belt"
		game.direction = 0 if fuel_case else 1
		game.paint(link,false)
		check(game.factory.running and game.factory.reserves.scrap == stock.scrap-1 and game.factory.reserves.coal == stock.coal and game.factory.cells.has(link),"combat reconnection pays materials and keeps production running")
		await advance(game,180)
		check(game.battlefield.distance > 0 and game.factory.shots > 0,"live reconnection restores real fuel and ammunition")
		game.retreat_run()
		check(game.expedition.phase == "retreated" and not game.factory.running,"disconnected run remains retreatable")
		game.reset_battle()
		game.last_paint = Vector2i(-1,-1)
		game.paint(link,false)
		game.toggle_running()
		await advance(game,180)
		check(game.battlefield.distance > 0 and game.factory.shots > 0,"rebuilding before departure restores real fuel and ammunition supply")
		check(game.factory.manufactured > 0 and game.factory.fuel_used > 0,"recovery uses manufactured consumables")
		game.queue_free()
		await process_frame
	var empty = create_game()
	empty.factory.reserves = {"scrap":0,"coal":0}
	empty.toggle_running()
	await advance(empty,100)
	check(empty.factory.injected == 0 and empty.factory.shots == 0 and empty.battlefield.distance == 0,"empty reserves do not manufacture or move")
	empty.retreat_run()
	check(empty.expedition.phase == "retreated" and empty.expedition.cleared == 0,"starvation permits retreat without rewards")
	empty.reset_battle()
	check(empty.expedition.phase == "prepare" and empty.factory.reserves.scrap == 48 and empty.factory.reserves.coal == 32,"new run recovers from starvation with normal starting stock")
	empty.queue_free()
	await process_frame
	print("SUPPLY RECOVERY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
