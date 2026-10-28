extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Run = preload("res://scripts/run_state.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS finale: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"final_base_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var r = game.expedition
	r.sector = 5
	r.cleared = 4
	r.current = r.make_route("arsenal")
	game.toggle_running()
	var b = game.battlefield
	var at: Vector3 = b.goal.position
	check(b.goals.size() == 1 and b.goal.final_base and b.goal.has_node("Headquarters"),"final sector has one large headquarters")
	check(b.enemies.back().hp == 24 and b.enemies.back().active and b.enemies.back().node.position.x < at.x and b.enemies.back().has("guard_home"),"armored boss guards the entrance from the start")
	check(b.enemies.filter(func(e): return e.has("guard_home")).size() == 7,"six nearby defenders surround the boss")
	var open = true
	for x in range(-12,65): open = open and b.obstacles.clear_pose(at+Vector3(x,0,0),0)
	check(not open and b.goal.gate.visible,"boss keeps the single entrance visibly locked")
	check(not b.obstacles.clear_pose(at+Vector3(40,0,42),PI/2) and not b.obstacles.clear_pose(at+Vector3(82,0,0),0),"large base side and rear fences block entry")
	check(b.obstacles.mines.size() == b.CourseObstacles.mine_count(r.current),"large perimeter mines match the checkpoint schema")
	b.kill_enemy(b.enemies[0],game.factory,b.enemies[0].node.position)
	b.kill_enemy(b.enemies[1],game.factory,b.enemies[1].node.position)
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"final boss, guards and peak combo survive checkpoint")
	b = game.battlefield
	r = game.expedition
	check(b.score.best_combo == 2 and b.enemies.back().hp == 24,"load preserves peak and boss health")
	b.player.position = at+Vector3(12,0,0)
	game.factory.running = true
	b.tick_battle(game.factory,0.01)
	check(not b.progress.has_won(),"arrival cannot skip a living boss")
	var boss = b.enemies.back()
	for i in range(23): b.hit_enemy(boss,game.factory,boss.node.position)
	check(boss.hp == 1 and b.score.kills == 2,"boss takes repeated actual hits without counting early kills")
	b.hit_enemy(boss,game.factory,boss.node.position)
	check(boss.hp == 0 and b.score.kills == 3 and not b.goal.gate.visible,"last hit counts the boss once and opens the gate")
	open = true
	for x in range(-12,65): open = open and b.obstacles.clear_pose(at+Vector3(x,0,0),0)
	check(open,"full hull can pass through the opened entrance")
	b.tick_battle(game.factory,0.01)
	game._process(0)
	check(r.phase == "won" and game.airdrop.active and not game.result_page.visible,"final arrival plays support flyover before results")
	game.airdrop.advance(7)
	check(game.result_page.visible and not game.airdrop.active,"flyover completes into clear results")
	check(r.results.kills == 3 and r.results.best_combo == 2 and r.results.settled == [5],"result records the whole sector once")
	var score = r.results.points(r.cleared)
	game._process(0)
	saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved) and game.expedition.results.points(5) == score and game.result_page.visible,"clear result is stable across ticks and reload")
	var bad = saved.duplicate(true)
	bad.run.results.settled = [5,5]
	check(not game.checkpoint.validate(bad),"duplicate settlement receipts are rejected")
	var totals = preload("res://scripts/run_results.gd").new()
	for sector in range(1,6):
		totals.settle(sector,b.score,b.progress,sector*10)
		totals.settle(sector,b.score,b.progress,sector*10)
	check(totals.kills == 15 and totals.shells == 50 and totals.best_combo == 2,"five-stage totals accumulate without duplicate settlement")
	game.free()
	Fixture.clean("final_base_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
