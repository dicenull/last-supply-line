extends "res://scripts/tank_world.gd"
## One bounded encounter. Factory inventory is the only source of player rounds.
var enemies: Array = []
var bolts: Array = []
var impacts: Array = []
var hull = 100
var kills = 0
var total = 6
var elapsed = 0.0
var cooldown = 0.0
var result = 0 # 0: fighting, 1: victory, -1: defeat

func _ready():
	super._ready()
	zoom = 42.0
	pitch = 1.05
	update_camera()
	toggle_roof()
	material("enemy","875444")
	for i in range(total):
		var angle = float(i)/total*TAU+0.3
		var unit = Node3D.new()
		add_child(unit)
		unit.position = Vector3(cos(angle)*22,0,sin(angle)*22)
		unit.rotation.y = -angle+PI
		box(unit,Vector3(0,0.8,0),Vector3(3.4,1.1,2.1),"enemy")
		for side in [-1,1]:
			box(unit,Vector3(0,0.5,side*1.15),Vector3(3.8,0.8,0.55),"dark")
		cylinder(unit,Vector3(0.2,1.65,0),0.85,0.8,"enemy",6)
		beam(unit,Vector3(0.2,1.7,0),Vector3(2.5,1.7,0),0.13,"dark")
		enemies.append({"node":unit,"hp":3,"cooldown":12.0+i*1.2})

func nearest_enemy():
	var nearest = null
	var distance = INF
	for enemy in enemies:
		if enemy.hp <= 0: continue
		var d = turret.global_position.distance_squared_to(enemy.node.position)
		if d < distance:
			distance = d
			nearest = enemy
	return nearest

func launch_enemy(enemy):
	var origin: Vector3 = enemy.node.position+Vector3(0,1.7,0)
	var target = Vector3(0,3,0)
	var node = Node3D.new()
	add_child(node)
	node.position = origin
	beam(node,Vector3.ZERO,(origin-target).normalized()*1.2,0.09,"fire")
	bolts.append({"node":node,"origin":origin,"target":target,"age":0.0,"duration":origin.distance_to(target)/22.0})

func impact(pos: Vector3):
	var flash = cylinder(self,pos,0.8,1.1,"fire",6,0.25)
	impacts.append({"node":flash,"life":0.25})

func tick_battle(factory, delta: float):
	if not factory.running or result != 0: return
	elapsed += delta
	for enemy in enemies:
		if enemy.hp <= 0: continue
		var pos: Vector3 = enemy.node.position
		if pos.length() > 16.0: enemy.node.position -= pos.normalized()*delta*0.45
		enemy.cooldown -= delta
		if enemy.cooldown <= 0:
			enemy.cooldown = 10.0
			launch_enemy(enemy)
	update_gun(factory,delta)
	for bolt in bolts.duplicate():
		bolt.age += delta
		bolt.node.position = bolt.origin.lerp(bolt.target,minf(1,bolt.age/bolt.duration))
		if bolt.age >= bolt.duration:
			hull = maxi(0,hull-6)
			impact(bolt.target)
			bolt.node.queue_free()
			bolts.erase(bolt)
	for flash in impacts.duplicate():
		flash.life -= delta
		flash.node.scale = Vector3.ONE*maxf(0.05,flash.life*4)
		if flash.life <= 0:
			flash.node.queue_free()
			impacts.erase(flash)
	if hull <= 0: result = -1
	elif kills == total: result = 1
	if result != 0: factory.running = false

func update_gun(factory, delta: float):
	cooldown = maxf(0,cooldown-delta)
	recoil = maxf(0,recoil-delta*0.95)
	barrel.position.x = BARREL_REST-recoil
	shot_time = maxf(0,shot_time-delta)
	var target = nearest_enemy()
	if target != null:
		var offset: Vector3 = target.node.position-turret.global_position
		target_angle = atan2(-offset.z,offset.x)
		turret.rotation.y = rotate_toward(turret.rotation.y,target_angle,delta*2.4)
		if cooldown <= 0 and absf(angle_difference(turret.rotation.y,target_angle)) < 0.025 and factory.ammo > 0:
			factory.fire_round()
			fire_visual()
			var shot: Dictionary = projectiles.back()
			shot.target = target
			shot.duration = shot.origin.distance_to(target.node.position+Vector3(0,1.3,0))/24.0
			cooldown = 60.0/factory.rate
	muzzle.visible = shot_time > 0
	for shot in projectiles.duplicate():
		shot.age += delta
		var destination: Vector3 = shot.target.node.position+Vector3(0,1.3,0)
		shot.node.position = shot.origin.lerp(destination,minf(1,shot.age/shot.duration))
		if shot.age >= shot.duration:
			if shot.target.hp > 0:
				shot.target.hp -= 1
				impact(destination)
				if shot.target.hp == 0:
					kills += 1
					shot.target.node.scale.y = 0.35
			shot.node.queue_free()
			projectiles.erase(shot)
