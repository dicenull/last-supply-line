extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS weapon arc: ",label)
	else:
		failures += 1
		push_error(label)
func target_at(b, gun, angle: float, distance: float) -> Vector3:
	var position: Vector3 = gun.pivot.global_position+b.player.basis*Vector3(cos(angle),0,-sin(angle))*distance
	position.y = 0
	return position
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"weapon_arc_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var uid = game.expedition.add_item({"kind":"scatter_gun","rarity":"normal"})
	check(game.place_item(uid,Vector2i.ZERO),"mount limited-traverse weapon")
	game.ensure_battle()
	var b = game.battlefield
	var f = game.factory
	var gun: Dictionary = b.auxiliary_guns[0]
	f.cells[Vector2i.ZERO].items = ["shell","shell"]
	var saved = game.checkpoint.snapshot(game)
	b.player.position = Vector3(20,0,0)
	b.update_camera()
	for enemy in b.enemies:
		enemy.active = true
		enemy.hp = 0
	for yaw in [0.0,PI/2,-PI/2,PI-0.05,-PI+0.05]:
		b.player.rotation.y = yaw
		check(b.within_gun_arc(gun,target_at(b,gun,gun.half_arc,20)) and b.within_gun_arc(gun,target_at(b,gun,-gun.half_arc,20)),"both arc endpoints are reachable at hull yaw "+str(yaw))
		check(not b.within_gun_arc(gun,target_at(b,gun,gun.half_arc+0.01,20)) and not b.within_gun_arc(gun,target_at(b,gun,PI,20)),"side and rear targets excluded in hull-local coordinates")
		check(is_equal_approx(b.clamp_gun_angle(gun,TAU+0.1),0.1) and is_equal_approx(absf(b.clamp_gun_angle(gun,PI)),gun.half_arc),"wrapped saved angles clamp into the physical arc")
	b.player.rotation.y = 0
	var outside = b.enemies[0]
	var inside = b.enemies[1]
	var outside_pellet = b.enemies[2]
	outside.hp = 1
	outside.node.position = target_at(b,gun,0.85,12)
	inside.hp = 1
	inside.node.position = target_at(b,gun,0.42,20)
	outside_pellet.hp = 1
	outside_pellet.node.position = target_at(b,gun,0.56,22)
	check(b.auxiliary_target(gun,27) == inside,"nearer out-of-arc enemy cannot prevent selection of a reachable enemy")
	f.cells[Vector2i.ZERO].items = ["shell","shell"]
	gun.pivot.rotation.y = 0.42
	b.update_auxiliary_guns(f,0.001)
	check(b.projectiles.size() == 1 and b.projectiles[0].target == inside and f.auxiliary_ammo(gun.id) == 0,"scatter volley excludes targets outside its physical traverse")
	for shot in b.projectiles: shot.node.queue_free()
	b.projectiles.clear()
	inside.hp = 0
	f.cells[Vector2i.ZERO].items = ["shell","shell"]
	gun.cooldown = 0
	gun.pivot.rotation.y = PI
	b.update_auxiliary_guns(f,10)
	check(absf(gun.pivot.rotation.y) <= gun.half_arc+0.000001 and b.projectiles.is_empty() and f.auxiliary_ammo(gun.id) == 2,"unreachable enemies cannot rotate the model past stops or consume ammo")
	# Turning the hull brings a previously unreachable target into the same local arc.
	b.player.rotation.y = 0.8
	b.update_camera()
	check(b.within_gun_arc(gun,outside.node.position),"hull steering brings a side target into traverse")
	b.player.rotation.y = 0
	saved.battle.auxiliary[0].angle = PI
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"old full-traverse checkpoint remains loadable: "+game.checkpoint.error)
	gun = game.battlefield.auxiliary_guns[0]
	check(absf(gun.pivot.rotation.y) <= gun.half_arc+0.000001 and game.factory.auxiliary_ammo(gun.id) == 2,"restore clamps old gun yaw before first draw without firing")
	check(game.world.EquipmentModels.Catalog.description({"kind":"scatter_gun","rarity":"normal"}).contains("±30°"),"inventory explains the limited firing arc")
	game.queue_free()
	await process_frame
	Fixture.clean("weapon_arc_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
