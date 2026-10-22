extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Battle = preload("res://scripts/battle_world.gd")
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
var battle
var factory
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS enemy roles: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func isolate(role: int):
	for bolt in battle.bolts: bolt.node.queue_free()
	battle.bolts.clear()
	for enemy in battle.enemies:
		enemy.active = true
		enemy.hp = 0
		enemy.node.position = Vector3(500+battle.enemies.find(enemy)*20,0,100)
		enemy.mark.visible = false
	battle.hull = 100
	battle.result = 0
	battle.kills = 0
	battle.distance = 0
	battle.player.position = Vector3.ZERO
	battle.player.rotation = Vector3.ZERO
	battle.movement_direction = Vector3.ZERO
	factory.fuel = 0
	factory.ammo = 0
	factory.running = true
	var enemy = battle.enemies[role]
	enemy.hp = 1
	enemy.node.position = Vector3(30,0,0)
	enemy.cooldown = 0.01
	enemy.locked = true
	enemy.aim = Vector3.ZERO
	battle.update_camera()
	return enemy
func run():
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1408,752)
	root.add_child(viewport)
	battle = Battle.new()
	battle.sector_config = Run.new(42).current.duplicate(true)
	battle.sector_config.enemies = range(13)
	viewport.add_child(battle)
	factory = Factory.new()
	factory.auto_fire = false
	for role in range(13):
		var enemy = isolate(role)
		var profile = Run.Content.ENEMIES[role]
		battle.tick_battle(factory,0.05)
		check(enemy.role == role and is_equal_approx(enemy.mark.mesh.outer_radius,profile.radius) and battle.bolts.size() == int(profile.get("burst",1)),"spawned archetype has its actual warning radius and shot count: "+profile.name)
		var expected = ceili(battle.hit_damage()*float(profile.damage))
		var bolt = battle.bolts[int(battle.bolts.size()/2)]
		check(bolt.style == profile.ballistics and is_equal_approx(bolt.radius,profile.radius) and is_equal_approx(bolt.duration,bolt.origin.distance_to(bolt.target)/Run.Content.BALLISTICS[profile.ballistics].speed),"projectile carries blast radius and flight duration: "+profile.name)
		# Resolve one real projectile while suppressing other shots.
		for other in battle.bolts:
			if other != bolt: other.node.queue_free()
		battle.bolts = [bolt]
		enemy.hp = 0
		bolt.age = bolt.duration-0.01
		battle.tick_battle(factory,0.05)
		check(battle.hull == 100-expected,"impact applies role-specific damage: "+profile.name)
		check(battle.impacts.back().style == profile.ballistics and battle.impacts.back().flash.get_child_count() > 1,"actual impact keeps the vehicle's explosion profile: "+profile.name)
	var normal = isolate(0)
	battle.tick_battle(factory,0.05)
	var ordinary_period = normal.cooldown
	normal = isolate(0)
	battle.enemies[11].hp = 1
	battle.enemies[11].node.position = Vector3(100,0,0)
	battle.tick_battle(factory,0.05)
	check(is_equal_approx(normal.cooldown,ordinary_period*0.85),"living commander accelerates allied attacks")
	normal = isolate(0)
	battle.tick_battle(factory,0.05)
	check(is_equal_approx(normal.cooldown,ordinary_period),"destroyed commander no longer grants attack bonus")
	var sniper = isolate(4)
	sniper.locked = false
	sniper.cooldown = Run.Content.ENEMIES[4].warning+0.01
	factory.fuel = 2
	battle.movement_direction = Vector3.RIGHT
	battle.tick_battle(factory,0.05)
	check(sniper.locked and sniper.aim.x > battle.player.position.x+5 and sniper.mark.visible,"sniper visibly predicts the moving player's future position")
	var breakthrough = isolate(6)
	breakthrough.cooldown = 1000
	breakthrough.locked = false
	for i in range(250): battle.tick_battle(factory,0.1)
	check(breakthrough.node.position.x < -5 and absf(breakthrough.node.position.z) > 5,"breakthrough tank actually reaches the rear flank")
	var convoy = isolate(9)
	factory.reserves = {"scrap":10,"coal":10}
	battle.kill_enemy(convoy,factory,convoy.node.position)
	check(factory.reserves == {"scrap":18,"coal":14},"destroyed convoy yields distinct real salvage")
	var target = isolate(0)
	target.node.position = Vector3(20,0,5)
	battle.configure_equipment([])
	battle.turret.rotation.y = 1
	battle.update_gun(factory,0.01)
	var baseline_turn = 1-battle.turret.rotation.y
	battle.configure_equipment(["servo"])
	battle.turret.rotation.y = 1
	battle.update_gun(factory,0.01)
	check(is_equal_approx(1-battle.turret.rotation.y,baseline_turn*1.6),"servo increases actual main turret rotation by 60 percent")
	factory.install_auxiliary("left_gun")
	battle.configure_equipment(["left_gun"],factory.auxiliary_positions())
	battle.auxiliary_guns[0].pivot.rotation.y = 1
	battle.update_auxiliary_guns(factory,0.01)
	baseline_turn = 1-battle.auxiliary_guns[0].pivot.rotation.y
	battle.configure_equipment(["left_gun","servo"],factory.auxiliary_positions())
	battle.auxiliary_guns[0].pivot.rotation.y = 1
	battle.update_auxiliary_guns(factory,0.01)
	check(is_equal_approx(1-battle.auxiliary_guns[0].pivot.rotation.y,baseline_turn*1.6),"servo also changes actual auxiliary turret rotation")
	print("ENEMY ROLES RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
