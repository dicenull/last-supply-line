extends "res://scripts/tank_world.gd"
## Moving encounter: coal-derived fuel powers travel; enemy shells target marked ground.
const RunState = preload("res://scripts/run_state.gd")
var reload_multiplier = 1.0
const ROUTE_LENGTH = 100.0
const FUEL_PER_METER = 0.12
var sector_config: Dictionary = {}
var route_length = ROUTE_LENGTH
var fuel_multiplier = 1.0
var resource_sites: Array = []
var player: Node3D
var enemies: Array = []
var bolts: Array = []
var impacts: Array = []
var trails: Array = []
var hull = 100
var kills = 0
var total = 6
var elapsed = 0.0
var cooldown = 0.0
var result = 0
var distance = 0.0
var speed = 0.0
var trail_clock = 0.0
var shake = 0.0
var target_marker: MeshInstance3D

func tank():
	var before = get_children()
	super.tank()
	player = Node3D.new()
	var parts = get_children()
	add_child(player)
	for part in parts:
		if part not in before: part.reparent(player)

func terrain():
	box(self,Vector3(65,-0.3,0),Vector3(260,0.4,160),"mud")
	var ground = sector_config.get("terrain","road")
	material("route_ground","39342d" if ground == "mud" else "54544a" if ground == "rubble" else "4b4b40")
	box(self,Vector3(65,-0.065,0),Vector3(230,0.035,15),"route_ground")
	if ground == "mud":
		for x in range(-20,145,9):
			var pool = cylinder(self,Vector3(x,-0.035,0),4.0,0.02,"dark",8)
			pool.scale.z = 1.5
	elif ground == "rubble":
		for x in range(-20,145,8):
			for z in [-6,6]: box(self,Vector3(x,0.08,z),Vector3(1.5,0.3,0.7),"stone")
	var rng = RandomNumberGenerator.new()
	rng.seed = int(sector_config.get("seed",1918))
	for i in range(85):
		var x = rng.randf_range(-25,145)
		var z = rng.randf_range(-36,36)
		if absf(z) < 8: continue
		if i % 3 == 0:
			cylinder(self,Vector3(x,-0.04,z),rng.randf_range(1.0,2.6),0.04,"dark",8)
		else:
			var ruin = box(self,Vector3(x,0.6,z),Vector3(0.5,1.3,rng.randf_range(1,3)),"stone")
			ruin.rotation.y = rng.randf()*PI
	for x in range(-20,150,12):
		for z in [-10,10]:
			box(self,Vector3(x,0,z),Vector3(3.5,0.06,1.2),"coal")
			for k in range(3): box(self,Vector3(x+k,0.12,z),Vector3(0.22,0.20,1.3),"wood")
	for z in [-10,10]:
		box(self,Vector3(route_length,2,z),Vector3(0.3,4,0.3),"steel")
		box(self,Vector3(route_length,3.6,z+1),Vector3(0.12,0.8,2),"brass")

func update_camera():
	if camera == null: return
	var at = player.position if player != null else Vector3.ZERO
	var target = at+Vector3(3,1.7,0)
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*42
	camera.position += Vector3(sin(elapsed*71),cos(elapsed*59),0)*shake
	camera.look_at(target,Vector3.UP)
	camera.size = zoom

func _ready():
	route_length = float(sector_config.get("length",ROUTE_LENGTH))
	super._ready()
	zoom = 39.0
	pitch = 1.03
	update_camera()
	toggle_roof()
	material("enemy","875444")
	material("warning","e66a45",0,0.4)
	target_marker = MeshInstance3D.new()
	var target_ring = TorusMesh.new()
	target_ring.inner_radius = 2.5
	target_ring.outer_radius = 2.65
	target_ring.rings = 16
	target_ring.ring_segments = 6
	target_marker.mesh = target_ring
	target_marker.material_override = mats.brass
	target_marker.scale.y = 0.15
	target_marker.visible = false
	add_child(target_marker)
	if not sector_config.is_empty():
		for i in range(3):
			var site = Node3D.new()
			add_child(site)
			site.position = Vector3(18+i*34,0,8 if i%2 == 0 else -8)
			for offset in [-0.8,0.8]:
				box(site,Vector3(offset,0.5,0),Vector3(1.3,1,1.3),"rust" if i%2 == 0 else "coal")
			cylinder(site,Vector3(0,2,0),0.1,4,"brass",6)
			resource_sites.append({"node":site,"distance":18+i*34,"taken":false,"shells":int(sector_config.get("shells",0)/3),"scrap":int(sector_config.scrap/3)+(1 if i < int(sector_config.scrap)%3 else 0),"coal":int(sector_config.coal/3)+(1 if i < int(sector_config.coal)%3 else 0)})
	for i in range(total):
		var unit = Node3D.new()
		add_child(unit)
		unit.visible = false
		var boss = bool(sector_config.get("boss",false)) and i == total-1
		var hp = RunState.enemy_health(sector_config,i)
		var role = RunState.enemy_role(sector_config,i)
		var heavy = role == 2
		if boss: unit.scale = Vector3.ONE*1.7
		elif role == 1: unit.scale = Vector3(0.85,0.8,0.85)
		box(unit,Vector3(0,0.8,0),Vector3(4.0 if heavy else 3.0,1.1,2.1),"enemy")
		for side in [-1,1]: box(unit,Vector3(0,0.5,side*1.15),Vector3(3.8,0.8,0.55),"dark")
		var health: Array = []
		for pip in range(hp): health.append(box(unit,Vector3(-0.7+pip*0.7,2.5,0),Vector3(0.5,0.07,0.25),"brass"))
		var pivot = Node3D.new()
		unit.add_child(pivot)
		cylinder(pivot,Vector3(0,1.65,0),0.9 if heavy else 0.65,0.8,"enemy",6)
		beam(pivot,Vector3(0,1.7,0),Vector3(3.1 if heavy else 2.2,1.7,0),0.13,"dark")
		var mark = MeshInstance3D.new()
		var ring = TorusMesh.new()
		ring.inner_radius = 5.8
		ring.outer_radius = 6.0
		ring.rings = 16
		ring.ring_segments = 6
		mark.mesh = ring
		mark.material_override = mats.warning
		mark.scale.y = 0.12
		mark.visible = false
		add_child(mark)
		enemies.append({"node":unit,"health":health,"pivot":pivot,"hp":hp,"max_hp":hp,"cooldown":7.0+i,"active":false,"role":role,"wave":int(i/2),"mark":mark,"locked":false,"aim":Vector3.ZERO})

func nearest_enemy():
	var nearest = null
	var best = INF
	for enemy in enemies:
		if enemy.hp <= 0 or not enemy.active: continue
		var d = turret.global_position.distance_squared_to(enemy.node.position)
		if d < best:
			best = d
			nearest = enemy
	return nearest

func launch_enemy(enemy):
	var origin: Vector3 = enemy.node.position+Vector3(0,1.7,0)
	var target: Vector3 = enemy.aim+Vector3(0,0.3,0)
	var node = Node3D.new()
	add_child(node)
	node.position = origin
	beam(node,Vector3.ZERO,(origin-target).normalized()*1.5,0.11,"fire")
	bolts.append({"node":node,"origin":origin,"target":target,"age":0.0,"duration":maxf(0.8,origin.distance_to(target)/15.0),"mark":enemy.mark})

func impact(pos: Vector3):
	var flash = cylinder(self,pos,1.3,1.8,"fire",6,0.25)
	impacts.append({"node":flash,"life":0.4})

func tick_battle(factory, delta: float):
	if not factory.running or result != 0: return
	elapsed += delta
	var heading = Vector3.RIGHT
	var surface = RunState.condition(sector_config)
	var requested = minf(delta*surface.speed,maxf(0,route_length-distance))
	var consumption = FUEL_PER_METER*fuel_multiplier*surface.fuel
	var travel = factory.consume_fuel(requested*consumption)/consumption
	if travel > 0: player.rotation.y = rotate_toward(player.rotation.y,atan2(-heading.z,heading.x),delta*1.6)
	player.position += heading*travel
	speed = travel/maxf(delta,0.001)
	distance = maxf(distance,player.position.x)
	for site in resource_sites:
		if not site.taken and distance >= site.distance:
			site.taken = true
			factory.collect("scrap",site.scrap)
			factory.collect("coal",site.coal)
			factory.ammo = mini(factory.ammo_capacity,factory.ammo+site.shells)
			site.node.visible = false
	# Small pitch motion and tracks make actual world movement readable.
	player.rotation.z = sin(elapsed*9)*0.006*minf(speed,1)
	trail_clock -= delta
	if travel > 0 and trail_clock <= 0:
		trail_clock = 0.4
		for side in [-1,1]:
			var tread = box(self,player.to_global(Vector3(-7,0.02,side*5.1)),Vector3(0.65,0.025,1.0),"dark")
			tread.rotation.y = player.rotation.y
			trails.append(tread)
		while trails.size() > 90: trails.pop_front().queue_free()
	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i]
		if not enemy.active and (distance >= enemy.wave*28 or elapsed >= enemy.wave*30):
			enemy.active = true
			enemy.node.visible = true
			enemy.node.position = player.position+Vector3(24 if i%2 == 0 else 12,0,-19 if i%2 == 0 else 19)
		if enemy.hp <= 0 or not enemy.active: continue
		var offset: Vector3 = player.position-enemy.node.position
		var move = offset.normalized()*maxf(0,offset.length()-17)*0.3
		if enemy.role == 1: move += Vector3(-offset.z,0,offset.x).normalized()*2.3
		if enemy.role == 2: move *= 0.55
		enemy.node.position += move.limit_length(4.0)*delta
		enemy.node.rotation.y = rotate_toward(enemy.node.rotation.y,atan2(-move.z,move.x),delta*1.5)
		enemy.pivot.rotation.y = atan2(-offset.z,offset.x)-enemy.node.rotation.y
		enemy.cooldown -= delta
		if enemy.cooldown <= 1.8 and not enemy.locked:
			enemy.locked = true
			enemy.aim = player.position
			enemy.mark.position = enemy.aim+Vector3(0,0.1,0)
			enemy.mark.visible = true
		if enemy.cooldown <= 0:
			enemy.cooldown = float(sector_config.get("attack_period",8.0))+(3 if enemy.role == 2 else 0)
			enemy.locked = false
			launch_enemy(enemy)
	update_gun(factory,delta)
	for bolt in bolts.duplicate():
		bolt.age += delta
		var t = minf(1,bolt.age/bolt.duration)
		bolt.node.position = bolt.origin.lerp(bolt.target,t)+Vector3(0,sin(t*PI)*3,0)
		if t >= 1:
			if Vector2(player.position.x-bolt.target.x,player.position.z-bolt.target.z).length() < 6:
				hull = maxi(0,hull-int(sector_config.get("damage",10)))
				shake = 0.3
			impact(bolt.target)
			bolt.mark.visible = false
			bolt.node.queue_free()
			bolts.erase(bolt)
	for flash in impacts.duplicate():
		flash.life -= delta
		flash.node.scale = Vector3.ONE*maxf(0.05,flash.life*3)
		if flash.life <= 0:
			flash.node.queue_free()
			impacts.erase(flash)
	shake = maxf(0,shake-delta)
	update_camera()
	if hull <= 0: result = -1
	elif kills == total and distance >= route_length: result = 1
	if result != 0:
		factory.running = false
		target_marker.visible = false

func update_gun(factory, delta: float):
	cooldown = maxf(0,cooldown-delta)
	recoil = maxf(0,recoil-delta*0.95)
	barrel.position.x = BARREL_REST-recoil
	shot_time = maxf(0,shot_time-delta)
	var target = nearest_enemy()
	target_marker.visible = target != null
	if target != null:
		target_marker.position = target.node.position+Vector3(0,0.12,0)
		var offset: Vector3 = target.node.position-turret.global_position
		target_angle = atan2(-offset.z,offset.x)-player.rotation.y
		turret.rotation.y = rotate_toward(turret.rotation.y,target_angle,delta*2.4)
		if cooldown <= 0 and absf(angle_difference(turret.rotation.y,target_angle)) < 0.025 and factory.ammo > 0:
			factory.fire_round()
			fire_visual()
			var shot: Dictionary = projectiles.back()
			shot.target = target
			shot.duration = shot.origin.distance_to(target.node.position+Vector3(0,1.3,0))/30.0
			cooldown = 60.0/factory.rate*reload_multiplier
	muzzle.visible = shot_time > 0
	for shot in projectiles.duplicate():
		shot.age += delta
		var destination: Vector3 = shot.target.node.position+Vector3(0,1.3,0)
		shot.node.position = shot.origin.lerp(destination,minf(1,shot.age/shot.duration))
		if shot.age >= shot.duration:
			if shot.target.hp > 0:
				shot.target.hp -= 1
				shot.target.health[shot.target.hp].visible = false
				impact(destination)
				if shot.target.hp == 0:
					kills += 1
					if not sector_config.is_empty(): factory.collect("scrap",2)
					shot.target.mark.visible = false
					shot.target.node.scale.y = 0.35
			shot.node.queue_free()
			projectiles.erase(shot)

func fire_visual():
	var heading = turret.global_basis.x.normalized()
	var origin = muzzle.global_position
	var shot = Node3D.new()
	add_child(shot)
	shot.position = origin
	beam(shot,Vector3.ZERO,-heading*1.8,0.085,"fire")
	projectiles.append({"node":shot,"origin":origin,"dir":heading,"age":0.0})
	recoil = 0.25
	shot_time = 0.14
	visual_shots += 1
