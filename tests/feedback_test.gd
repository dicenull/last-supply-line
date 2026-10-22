extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS feedback: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var f = Factory.new()
	f.example(false)
	check(f.feedback_events.is_empty(),"initial layout and resets do not celebrate old work")
	f.edit(Vector2i(6,6),"belt",0)
	check(f.feedback_events.size() == 1 and f.feedback_events[0].kind == "place","successful build emits a placement event")
	f.feedback_events.clear()
	f.edit(Vector2i(7,6),"belt",0)
	check(f.feedback_events.any(func(e): return e.kind == "connect"),"actual compatible connection produces a distinct event")
	f.feedback_events.clear()
	f.reserves.scrap = 0
	f.edit(Vector2i(8,6),"furnace",0)
	check(f.feedback_events.is_empty(),"unaffordable build has no success feedback")
	f.reserves.scrap = 100
	f.running = true
	for i in range(160): f.step(0.25)
	check(f.feedback_events.any(func(e): return e.kind == "production") and f.feedback_events.any(func(e): return e.kind == "load") and f.feedback_events.any(func(e): return e.kind == "fuel"),"real production, ammunition delivery and fuel delivery have separate feedback")
	check(f.feedback_events.size() <= 64,"factory event backlog is bounded")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"feedback_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	game.factory.edit(Vector2i(7,6),"armor_block",0)
	game._process(0.01)
	var fx = game.world.feedback
	check(fx != null and fx.emitted.get("place",0) == 1 and game.factory.feedback_events.is_empty(),"UI consumes successful events once into 3D feedback")
	game._process(0.01)
	check(fx.emitted.place == 1,"unchanged frame does not repeat placement")
	var effect = fx.active[0]
	var frozen = effect.age
	game.open_menu()
	game._process(1)
	check(effect.age == frozen,"menu freezes construction feedback")
	game.close_menu()
	game._process(0.1)
	check(effect.age > frozen,"closing menu resumes the effect")
	var snapshot = game.checkpoint.snapshot(game)
	check(not snapshot.factory.has("feedback_events") and game.checkpoint.apply(game,snapshot) and fx.active.is_empty(),"save restore clears cosmetic feedback without replaying it")
	for i in range(100): game.world.feedback_effect("place",Vector3.ZERO)
	check(fx.active.size() == fx.LIMIT and fx.get_child_count() == fx.LIMIT,"burst storms obey a hard live-node limit")
	game.world.tick_feedback(2)
	check(fx.active.is_empty() and fx.get_child_count() == 0,"expired effects release their scene nodes")
	for event in ["place","connect","production","load","fuel","armor"]:
		var at = Vector3(-4+(fx.serial%6)*1.5,3.8,-1)
		game.world.feedback_effect(event,at)
	game.world.tick_feedback(0.14)
	await capture(game,"res://preview-feedback-construction.png")
	game.factory.edit(Vector2i(7,1),"armor_block",0)
	game.toggle_running()
	var b = game.battlefield
	game.factory.damage_at(Vector2(0.5,-1.5))
	game._process(0)
	var armor_effects = b.feedback.active.filter(func(e): return e.kind == "armor")
	check(game.factory.last_damage_blocked and not armor_effects.is_empty() and armor_effects.back().node.position.y >= b.TURRET_CENTER.y+2.5,"exterior armor sparks remain above the turret instead of being hidden inside it")
	b.tick_feedback(0.14)
	await capture(game,"res://preview-feedback-armor.png")
	for enemy in b.enemies:
		enemy.active = true
		enemy.node.visible = true
	for i in range(3):
		var enemy = b.enemies[i]
		enemy.node.position = Vector3(20+i*7,0,(i-1)*6)
		b.kill_enemy(enemy,game.factory,enemy.node.position)
	check(b.combo == 3 and b.best_combo == 3 and b.feedback.emitted.kill == 3,"separate real kills build a short combo and spawn distinct debris")
	b.kill_enemy(b.enemies[0],game.factory,b.enemies[0].node.position)
	check(b.combo == 3,"dead enemies cannot award combo twice")
	b.tick_feedback(0.18)
	game.logistics.queue_redraw()
	await capture(game,"res://preview-feedback-combat.png")
	game.factory.running = true
	b.tick_battle(game.factory,3)
	check(b.combo == 0,"combo expires when kills stop")
	check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"live feedback leaves gameplay checkpoint valid")
	print("FEEDBACK RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func capture(game, path: String):
	if DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1440,940)
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func _finalize(): Fixture.clean("feedback_test")
