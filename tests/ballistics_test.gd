extends SceneTree
const Battle = preload("res://scripts/battle_world.gd")
const Run = preload("res://scripts/run_state.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS ballistics: ",label)
	else:
		failures += 1
		push_error(label)
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	game.battlefield.camera.get_viewport().get_texture().get_image().save_png(path)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"ballistics_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	game.toggle_running()
	var battle = game.battlefield
	battle.zoom = 70
	battle.update_camera()
	var index = 0
	for style in Battle.BALLISTICS:
		var spec = Battle.BALLISTICS[style]
		battle.impact(Vector3(14+(index%3)*16,0,(int(index/3)*2-1)*10),style)
		var effect = battle.impacts.back()
		effect.life = spec.life-0.1
		battle.update_impact(effect)
		check(effect.flash.visible and effect.ring.scale.x > spec.blast*0.3,"explosion blooms with a ground shockwave: "+style)
		index += 1
	check(Battle.shell_flight_time(Vector3.ZERO,Vector3(30,0,0),"mortar") > Battle.shell_flight_time(Vector3.ZERO,Vector3(30,0,0),"heavy") and Battle.shell_flight_time(Vector3.ZERO,Vector3(30,0,0),"heavy") > Battle.shell_flight_time(Vector3.ZERO,Vector3(30,0,0),"sniper"),"mortar heavy and sniper have distinct readable flight times")
	await capture("res://preview-ballistics-burst.png")
	var snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,snapshot),"all live explosion profiles validate and restore")
	battle = game.battlefield
	var restored = true
	for i in range(snapshot.battle.impacts.size()):
		restored = restored and battle.impacts[i].style == snapshot.battle.impacts[i].style and is_equal_approx(battle.impacts[i].life,snapshot.battle.impacts[i].life)
	check(restored and is_equal_approx(battle.shake,snapshot.battle.shake),"restore preserves explosion age and camera shake without retriggering")
	var invalid = snapshot.duplicate(true)
	invalid.battle.impacts[0].style = "unknown"
	check(not game.checkpoint.validate(invalid),"unknown effect profiles are rejected before restore")
	for effect in battle.impacts:
		var spec = Battle.BALLISTICS[effect.style]
		effect.life = spec.life*0.35
		battle.update_impact(effect)
		check(not effect.flash.visible and effect.dust.visible and effect.dust.get_child(0).material_override.albedo_color.a < 1,"fire ends and expanding smoke fades: "+effect.style)
	battle.zoom = 70
	battle.update_camera()
	await capture("res://preview-ballistics-smoke.png")
	# Old saves without a style remain readable.
	var legacy = snapshot.duplicate(true)
	for effect in legacy.battle.impacts:
		effect.erase("style")
		effect.life = 0.3
	check(game.checkpoint.validate(legacy),"legacy impacts without profiles remain compatible")
	game.factory.running = true
	battle.tick_battle(game.factory,2)
	check(battle.impacts.is_empty(),"expired explosions clean up their scene nodes")
	game.factory.ammo = 1
	battle.cooldown = 0
	var enemy = battle.enemies[0]
	enemy.active = true
	enemy.node.position = Vector3(28,0,0)
	battle.turret.rotation.y = 0
	battle.update_gun(game.factory,0.001)
	check(battle.projectiles.size() == 1 and battle.projectiles[0].style == "heavy" and battle.recoil > 0.6 and battle.barrel.position.x < battle.BARREL_REST-0.6,"main gun fires a heavy round with immediate deep recoil")
	var airborne = game.checkpoint.snapshot(game)
	var bad_shot = airborne.duplicate(true)
	bad_shot.battle.projectiles[0].style = "unknown"
	check(not game.checkpoint.validate(bad_shot),"invalid projectile profiles cannot enter a save")
	check(game.checkpoint.apply(game,airborne) and game.battlefield.projectiles[0].style == "heavy","heavy projectile and recoil survive saving in flight")
	print("BALLISTICS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("ballistics_test")
