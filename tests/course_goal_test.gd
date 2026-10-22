extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS course goal: ",label)
	else:
		failures += 1
		push_error(label)

func capture(game, path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run():
	root.size = Vector2i(1440,940)
	var model_counts = {}
	for stage in [1,5]:
		for kind in Run.ROUTES:
			var game = load("res://main.tscn").instantiate()
			Fixture.assign(game,"course_goal_test")
			game.show_start_menu = false
			game.expedition = Run.new(42)
			game.expedition.sector = stage
			game.expedition.cleared = stage-1
			game.expedition.current = game.expedition.make_route(kind)
			game.expedition.current.erase("field_version") # Legacy straight-yard checkpoint coverage.
			game.expedition.current.erase("encounters_version")
			root.add_child(game)
			game.set_process(false)
			game.toggle_battle()
			var b = game.battlefield
			var f = game.factory
			var length: float = b.route_length
			var label = kind+" stage "+str(stage)
			check(b.goal.route_kind == kind and b.goal.stage == stage and b.goal.position.x == length,"route-specific facility is placed at actual course end: "+label)
			var meshes = b.goal.find_children("*","MeshInstance3D",true,false).size()
			check(meshes > 35,"destination has a modeled receiving yard and machinery: "+label)
			check(b.goal.has_node({"scrapyard":"SalvageGantry","coalfield":"CoalHopper","arsenal":"AmmunitionMagazine"}[kind]),"route has its own distinctive industrial landmark: "+label)
			if stage == 1: model_counts[kind] = meshes
			else: check(meshes > model_counts[kind],"final-stage facility includes added fortifications: "+kind)
			check(game.destination_text() == "あと%dm" % int(length),"starting distance measures gate threshold: "+label)
			b.player.position = Vector3(length-25,0,0)
			b.update_camera()
			await capture(game,"res://preview-goal-"+kind+"-"+str(stage)+".png")
			game.toggle_running()
			b.player.position = Vector3(length+4,0,10)
			game._process(0)
			check(b.result == 0 and game.destination_text() == "あと2m","passing end distance beside the yard does not clear: "+label)
			check(not b.goal.contains_position(Vector3(length-0.01,0,0)) and not b.goal.contains_position(Vector3(length+17,0,0)),"arrival requires being inside the bounded yard: "+label)
			b.player.position = Vector3(length-0.1,0,0)
			b.distance = b.player.position.x
			b.hull = 61
			var destroyed = Vector2i(4,2)
			f.cells[destroyed].dir = 3
			f.damage_at(Vector2(destroyed.x-6.5,destroyed.y-3.5))
			var saved = game.checkpoint.snapshot(game)
			check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"approach save recreates the same goal and damage: "+label)
			b = game.battlefield
			f = game.factory
			check(b.goal.route_kind == kind and b.goal.position.x == length and b.result == 0,"restored approach does not grant early victory: "+label)
			f.fuel = 12
			game.toggle_running()
			b.movement_direction = Vector3.RIGHT
			game._process(0.1)
			check(b.result == 1 and b.goal.contains_position(b.player.position) and b.kills < b.total,"driving into facility clears with surviving enemies: "+label)
			check(game.expedition.phase == "reward" and b.hull == 100 and f.wrecks.is_empty() and f.cells[destroyed].dir == 3,"entry triggers reward and full repair once: "+label)
			check(not f.running and game.destination_text() == "あと0m" and game.checkpoint.validate(game.checkpoint.snapshot(game)),"arrival stops combat and saves with enemies still alive: "+label)
			var final_position = b.player.position
			game._process(1.0)
			check(b.player.position == final_position and b.hull == 100,"combat remains stopped while choosing rewards: "+label)
			# Killing every enemy outside the yard is insufficient.
			b.result = 0
			b.player.position = Vector3(length+4,0,12)
			b.kills = b.total
			for enemy in b.enemies: enemy.hp = 0
			f.running = true
			b.movement_direction = Vector3.ZERO
			b.tick_battle(f,0)
			check(b.result == 0,"destroying the entire roster does not replace reaching the yard: "+label)
			b.player.position = Vector3(length+4,0,7.9)
			b.tick_battle(f,0)
			check(b.result == 1,"entering the side of the marked yard also counts: "+label)
			b.result = 0
			b.hull = 0
			f.running = true
			b.tick_battle(f,0)
			check(b.result == -1,"destroyed vehicle cannot win by entering the yard: "+label)
			game.queue_free()
			await process_frame
	print("COURSE GOAL RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize(): Fixture.clean("course_goal_test")
