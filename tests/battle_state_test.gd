extends SceneTree
const Score = preload("res://scripts/battle_score.gd")
const Progress = preload("res://scripts/battle_progress.gd")
const Motion = preload("res://scripts/battle_motion.gd")
const Observation = preload("res://scripts/audio_observation.gd")
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
class ObservedBattle extends RefCounted:
	var score = Score.new()
	var progress = Progress.new()
	var impact_serial = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS battle state: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var score = Score.new()
	score.record_kill()
	check(score.kills == 1 and score.combo == 1 and not score.combo_visible(),"first kill counts without a combo notification")
	score.advance(2.79)
	score.record_kill()
	check(score.kills == 2 and score.combo == 2 and score.best_combo == 2 and score.combo_visible() and score.combo_time == 2.8,"kill just before expiry renews the full combo window")
	score.advance(2.8)
	check(score.combo == 0 and score.combo_time == 0 and score.kills == 2 and score.best_combo == 2,"exact window boundary clears current combo but retains kills and peak")
	score.record_kill()
	check(score.combo == 1 and score.best_combo == 2,"a kill after expiry starts a new chain")
	for sample in [{"rate":0.0,"expected":[]},{"rate":1.0/3,"expected":[3,6,9]},{"rate":0.4,"expected":[3,5,8,10]},{"rate":0.75,"expected":[2,3,4,6,7,8,10]}]:
		var counter = Score.new()
		var awarded: Array = []
		for i in range(10):
			counter.record_kill()
			if counter.earned_salvage(sample.rate): awarded.append(counter.kills)
		check(awarded == sample.expected,"fractional salvage cadence: "+str(sample.rate))
	var saved_score = score.snapshot()
	score.total = 24
	score.restore(saved_score)
	check(score.kills == 3 and score.total == 24 and score.combo == 0 and score.combo_time == 0 and score.best_combo == 0,"restore preserves durable kills and keeps legacy transient-combo reset")
	score.record_kill()
	check(score.kills == 4 and score.combo == 1,"first post-load kill starts a fresh combo")
	var progress = Progress.new()
	progress.advance(1.25)
	progress.take_damage(7.1)
	check(progress.hull == 92 and progress.elapsed == 1.25 and not progress.is_finished(),"hull damage rounds up once and clock advances")
	progress.take_damage(100)
	progress.resolve(1)
	check(progress.hull == 0 and progress.has_lost() and progress.arrived_destination == -1,"lethal damage takes priority over same-frame arrival")
	progress.resolve(0)
	progress.advance(10)
	check(progress.has_lost() and progress.elapsed == 1.25,"terminal outcome and clock cannot advance again")
	progress = Progress.new()
	progress.resolve(2)
	check(progress.has_won() and progress.arrived_destination == 2,"arrival records its destination and victory together")
	progress.resolve(1)
	check(progress.arrived_destination == 2,"later arrival cannot overwrite a terminal destination")
	var saved_progress = progress.snapshot()
	progress.restore(saved_progress)
	check(progress.has_won() and progress.hull == 100 and progress.arrived_destination == -1,"restore leaves derived destination for the course adapter")
	var motion = Motion.new()
	var plan = {"position":Vector3(13,0,4),"poses":[{"position":Vector3(10,0,0),"yaw":0.0},{"position":Vector3(13,0,4),"yaw":0.1}]}
	motion.command = Vector3.RIGHT
	motion.record_plan(Vector3(10,0,0),plan,0.5,12)
	check(motion.velocity == Vector3(6,0,8) and motion.speed == 10 and motion.distance == 12 and motion.poses == plan.poses,"telemetry uses actual applied motion, including clamped course progress")
	motion.clear_command()
	check(motion.command == Vector3.ZERO and motion.poses.size() == 2,"releasing input keeps the last applied path available to pickup checks")
	var saved_motion = motion.snapshot()
	motion.command = Vector3.BACK
	motion.restore(saved_motion)
	check(motion.speed == 10 and motion.distance == 12 and motion.command == Vector3.ZERO and motion.velocity == Vector3.ZERO and motion.poses.is_empty() and plan.poses.size() == 2,"restore clears transient input and sweep without mutating the source plan")
	motion.record_plan(Vector3.ZERO,{"position":Vector3.ZERO,"poses":[]},0,100)
	check(motion.velocity.is_finite() and motion.speed == 0,"zero-duration stationary updates remain finite")
	var factory = Factory.new()
	var battle = ObservedBattle.new()
	var baseline = Observation.new(factory,battle)
	check(baseline.changed_source(Observation.new()),"initial observation establishes a new sound baseline")
	check(not Observation.new(factory,battle).has_impact_since(baseline),"unchanged state cannot replay impact audio")
	battle.score.record_kill()
	check(Observation.new(factory,battle).has_impact_since(baseline),"new kill is detected independently of frame rate")
	baseline = Observation.new(factory,battle)
	battle.progress.take_damage(1)
	check(Observation.new(factory,battle).has_impact_since(baseline),"new hull damage is detected")
	baseline = Observation.new(factory,battle)
	battle.impact_serial += 1
	check(Observation.new(factory,battle).has_impact_since(baseline),"non-damaging impact is also detected")
	check(Observation.new(Factory.new(),battle).changed_source(baseline) and Observation.new(factory,ObservedBattle.new()).changed_source(baseline),"factory or battlefield replacement suppresses old cues")
	factory.ticks = 10
	baseline = Observation.new(factory,battle)
	factory.ticks = 0
	check(Observation.new(factory,battle).changed_source(baseline),"rewinding simulation resets the sound baseline")
	await integration()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func integration():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"battle_state_test",2)
	game.expedition = preload("res://scripts/run_state.gd").new(42)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.toggle_running()
	var b = game.battlefield
	for enemy in b.enemies.slice(0,2): b.kill_enemy(enemy,game.factory,enemy.node.position)
	b.kill_enemy(b.enemies[0],game.factory,b.enemies[0].node.position)
	check(b.score.kills == 2 and b.score.combo == 2,"real kills update score once, including duplicate-hit protection")
	game.factory.running = false
	var time = b.score.combo_time
	b.tick_battle(game.factory,10)
	check(b.score.combo_time == time and b.progress.elapsed == 0,"paused encounter freezes score and progress together")
	var saved = game.checkpoint.snapshot(game)
	check(saved.battle.kills == 2 and saved.battle.has_all(["hull","elapsed","result","distance","speed"]) and not saved.battle.has("score") and not saved.battle.has("motion") and game.checkpoint.validate(saved),"structured runtime state preserves the flat, data-only checkpoint contract")
	check(game.checkpoint.apply(game,saved),"existing checkpoint adapter restores the new state objects")
	b = game.battlefield
	check(b.score.kills == 2 and b.score.combo == 0 and b.score.total == b.enemies.size() and b.motion.command == Vector3.ZERO,"reload restores kills and roster without reviving combo or held controls")
	game.reset_battle(43)
	game.ensure_battle()
	b = game.battlefield
	check(b.score.kills == 0 and b.score.best_combo == 0 and not b.progress.is_finished() and b.motion.poses.is_empty(),"a new encounter receives independent clean state")
	game.queue_free()
	await process_frame
	Fixture.clean("battle_state_test")
