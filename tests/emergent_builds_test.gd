extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
var game
var b
var f
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS emergent builds: ",label)
	else:
		failures += 1
		push_error(label)
func effects(kinds: Array) -> Dictionary:
	var items: Array = []
	for kind in kinds: items.append({"kind":kind,"rarity":"normal","position":Vector2i.ZERO})
	return Inventory.effects_for(items)
func isolate(kinds: Array, cannon: String = "vehicle_cannon"):
	for shot in b.projectiles: shot.node.queue_free()
	b.projectiles.clear()
	for bolt in b.bolts: bolt.node.queue_free()
	b.bolts.clear()
	b.combat_modifiers.equipment_effects = effects(kinds+[cannon])
	b.vehicle_parts = {"cannon":{"kind":cannon,"rarity":"normal"}}
	b.player.position = Vector3.ZERO
	b.player.rotation = Vector3.ZERO
	b.turret.rotation.y = 0
	b.cooldown = 0
	b.sector_config.final_base_version = 1
	b.sector_config.damage = 20
	for enemy in b.enemies:
		enemy.active = false
		enemy.hp = 0
	var boss = b.enemies.back()
	boss.active = true
	boss.hp = 24
	boss.node.position = Vector3(28,0,0)
	f.ammo = 12
	f.fuel = 12
	b.hull = 100
func fire_once():
	var enemy = b.enemies.back()
	var offset: Vector3 = enemy.node.position-b.turret.global_position
	b.turret.rotation.y = atan2(-offset.z,offset.x)
	b.update_gun(f,0.001)
func resolve_shots():
	f.ammo = 0
	b.update_gun(f,2.0)
func production(kind: String, fuel: float) -> Factory:
	var line = Factory.new()
	line.auto_fire = false
	line.cells.clear()
	line.fuel = fuel
	line.cells[Vector2i(1,1)] = line.make_cell(kind,0)
	line.cells[Vector2i(1,1)].items = ["steel"]
	line.cells[Vector2i(2,1)] = line.make_cell("depot",0)
	for i in range(12): line.simulate_tick()
	return line
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"emergent_builds_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.expedition.sector = 5
	game.expedition.cleared = 4
	game.expedition.current = game.expedition.make_route("arsenal")
	for key in ["obstacles_version","encounters_version"]: game.expedition.current.erase(key)
	game.ensure_battle()
	b = game.battlefield
	f = game.factory
	# 1. Motorized barrage: faster firing needs both real shells and shared fuel.
	isolate(["drum_loader"])
	f.fuel = 0.15
	fire_once()
	check(b.projectiles.is_empty() and f.ammo == 12 and is_equal_approx(f.fuel,0.15) and b.cooldown == 0,"starved loader consumes neither shells nor cooldown")
	f.fuel = 0.16
	fire_once()
	check(b.projectiles.size() == 1 and f.ammo == 11 and is_zero_approx(f.fuel),"fuel delivery immediately enables a powered shot")
	check(is_equal_approx(b.cooldown,60.0/f.rate*0.55*0.92),"powered loader shortens the real main-gun cooldown")
	var normal = production("press",0)
	var powered = production("auto_press",0.30)
	var starved = production("auto_press",0.29)
	check(normal.manufactured == 1 and powered.manufactured == 2 and powered.cells[Vector2i(2,1)].items == ["shell","shell"],"powered line actually delivers twice the shells per steel")
	check(starved.manufactured == 0 and starved.cells[Vector2i(1,1)].items == ["steel"] and is_equal_approx(starved.fuel,0.29),"fuel shortage stalls production without consuming its input")
	check(is_zero_approx(powered.fuel) and is_equal_approx(powered.fuel_used,0.3),"batch output pays fuel exactly once")
	# 2. Long-range hunter: precision damage works against armour, not as a set bonus.
	isolate(["rangefinder","vehicle_tracks_light"],"vehicle_cannon_long")
	check(b.weapon_range(b.ENGAGEMENT_RANGE)+b.equipment_effect("main_range",0) == b.ENGAGEMENT_RANGE+22,"optic and long barrel independently extend engagement range")
	check(b.equipment_effect("turn",1) < 1 and b.equipment_effect("speed",1) > 1,"range costs tracking while light tracks improve repositioning")
	fire_once()
	check(b.projectiles.size() == 1 and b.projectiles[0].damage == 4 and f.ammo == 10,"long cannon spends two shells for a four-damage projectile")
	resolve_shots()
	check(b.enemies.back().hp == 20,"armoured boss loses the actual projectile damage")
	# 3. Area saturation: blast fuse changes ordinary shots and increases every volley cost.
	isolate(["blast_fuse"],"vehicle_cannon_howitzer")
	var nearby = b.enemies[0]
	nearby.active = true
	nearby.hp = 1
	nearby.node.position = Vector3(33,0,4)
	f.ammo = 3
	fire_once()
	check(b.projectiles.is_empty() and f.ammo == 3,"insufficient four-shell volley is atomic")
	f.ammo = 4
	fire_once()
	check(b.projectiles.size() == 1 and f.ammo == 0 and b.projectiles[0].splash == 8,"howitzer and fuse produce an eight-metre blast at four shells per shot")
	resolve_shots()
	check(nearby.hp == 0 and b.enemies.back().hp == 21,"one actual impact damages armour and destroys nearby infantry tank")
	isolate(["blast_fuse","drum_loader"],"vehicle_cannon_howitzer")
	f.fuel = 0.63
	fire_once()
	check(b.projectiles.is_empty() and f.ammo == 12,"powered loading charges per consumed shell, including blast-fuse ammo")
	f.fuel = 0.64
	fire_once()
	check(b.projectiles.size() == 1 and f.ammo == 8 and is_zero_approx(f.fuel),"the same independent costs apply when mechanisms combine")
	# 4. Armoured fortress: protection trades mobility; interception needs arc and supply.
	isolate(["armor","skirts"])
	check(b.equipment_effect("speed",1) < 0.83 and b.hit_damage() == 15,"armour makes the real vehicle slower and reduces ordinary hits")
	b.receive_shell(f,b.player.position,6,20,false)
	var direct = 100-b.hull
	b.hull = 100
	b.receive_shell(f,b.player.position,6,20,true)
	check(100-b.hull < direct*0.6,"blast screens reduce explosive damage separately from direct hits")
	var uid = game.expedition.add_item({"kind":"rear_gun","rarity":"normal"})
	check(game.place_item(uid,Vector2i(0,0)),"interceptor mounts through the real inventory command")
	isolate([])
	var gun = b.auxiliary_guns[0]
	var incoming = Node3D.new()
	b.add_child(incoming)
	incoming.position = gun.pivot.global_position+Vector3(8,0,0)
	var mark = Node3D.new()
	b.add_child(mark)
	b.bolts.append({"node":incoming,"origin":incoming.position,"target":b.player.position,"age":0.0,"duration":1.0,"mark":mark})
	gun.pivot.rotation.y = 0
	b.update_auxiliary_guns(f,0.01)
	check(b.bolts.size() == 1,"unfed interceptor cannot destroy incoming rounds")
	f.cells[Vector2i(0,0)].items = ["shell"]
	incoming.position = gun.pivot.global_position-Vector3(8,0,0)
	b.update_auxiliary_guns(f,0.01)
	check(b.bolts.size() == 1 and f.auxiliary_ammo("rear_gun") == 1,"rearward rounds stay outside the forward interception arc")
	incoming.position = gun.pivot.global_position+Vector3(8,0,0)
	b.update_auxiliary_guns(f,0.01)
	check(b.bolts.is_empty() and f.auxiliary_ammo("rear_gun") == 0 and b.projectiles.is_empty(),"supplied interceptor destroys the real incoming round without attacking tanks")
	mark.queue_free()
	check(game.stow_item(uid),"interceptor can be stowed after the test")
	# 5. Salvage economy: lower movement consumption supports actual recovered resources.
	isolate(["salvage_arm","economizer","vehicle_engine_efficient"])
	check(b.equipment_effect("fuel",1) < 0.54 and b.equipment_effect("speed",1) < 0.85,"sustain equipment lowers driving fuel and sacrifices mobility")
	b.score.kills = 0
	b.restore_ground_items([])
	for i in range(3):
		var enemy = b.enemies[i]
		enemy.hp = 1
		enemy.active = true
		enemy.node.position = Vector3(40,0,i*12)
		b.kill_enemy(enemy,f,enemy.node.position)
	check(b.ground_items.size() == 8,"three kills drop normal loot plus one physical scrap-and-coal salvage bonus")
	var before: Dictionary = f.collected.duplicate()
	b.motion.poses = [{"position":Vector3(40,0,24),"yaw":0}]
	b.update_ground_items(f)
	check(f.collected.scrap > before.scrap and f.collected.coal > before.coal,"salvage must be picked up before it feeds reserves")
	# Saved output batches and projectile payloads are part of the live checkpoint contract.
	game.reset_battle(42)
	b = game.battlefield
	f = game.factory
	f.inventory.auto_press = 1
	f.unlocked_blocks.append("auto_press")
	f.edit(Vector2i(0,0),"auto_press",0)
	f.cells[Vector2i(0,0)].items = ["shell","shell"]
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"two-shell output batch survives checkpoint validation and reload")
	var bad = saved.duplicate(true)
	bad.factory.cells[Vector2i(0,0)].items = ["steel","shell"]
	check(not game.checkpoint.validate(bad),"mixed batch cannot bypass machine input validation")
	game.free()
	await process_frame
	Fixture.clean("emergent_builds_test")
	print("EMERGENT BUILDS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
