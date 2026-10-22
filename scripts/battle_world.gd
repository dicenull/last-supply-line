extends "res://scripts/tank_world.gd"
## Moving encounter: coal-derived fuel powers travel; enemy shells target marked ground.
const RunState = preload("res://scripts/run_state.gd")
const FieldCourse = preload("res://scripts/field_course.gd")
const CourseGoal = preload("res://scripts/course_goal.gd")
const SupplyPoint = preload("res://scripts/supply_point.gd")
const CourseObstacles = preload("res://scripts/course_obstacles.gd")
const SUPPLY_DISTANCES = [18.0,52.0,86.0]
signal enemy_destroyed(role: int)
signal item_dropped(item: Dictionary)
var item_mode = false
const Gear = preload("res://scripts/equipment_catalog.gd")
var reload_multiplier = 1.0
var combat_modifiers: Dictionary = {}
const ROUTE_LENGTH = 100.0
const FUEL_PER_METER = 0.12
const ENGAGEMENT_RANGE = 36.0
# Readable heavy-shell pacing for this compressed battlefield.
const BALLISTICS = RunState.Content.BALLISTICS
const VEHICLE_CLEARANCE = 0.35
var sector_config: Dictionary = {}
var route_length = ROUTE_LENGTH
var goal: Node3D
var goals: Array = []
var field_course
var arrived_destination = -1
var obstacles: Node3D
var drive_poses: Array = []
var fuel_multiplier = 1.0
var resource_sites: Array = []
var collection_events: Array = []
var player: Node3D
var enemies: Array = []
var bolts: Array = []
var impacts: Array = []
var impact_serial = 0
var trails: Array = []
var hull = 100
var kills = 0
var total = 6
var elapsed = 0.0
var cooldown = 0.0
var result = 0
var distance = 0.0
var speed = 0.0
const BATTLE_HALF_WIDTH = 18.0
# Input axes: X is forward/reverse throttle; Z is right/left steering.
const TURN_SPEED = 1.2
const TRACK_HALF_WIDTH = 5.05
var movement_direction = Vector3.ZERO
var velocity = Vector3.ZERO
var trail_clock = 0.0
var shake = 0.0
var target_marker: MeshInstance3D
var combo = 0
var combo_time = 0.0
var best_combo = 0

func tank():
	var before = get_children()
	super.tank()
	player = Node3D.new()
	var parts = get_children()
	add_child(player)
	for part in parts:
		if part not in before: part.reparent(player)

func terrain():
	if field_course != null:
		var scenery = preload("res://scripts/field_scenery.gd").new()
		add_child(scenery)
		scenery.build(self,field_course)
		var icons = preload("res://scripts/pixel_icons.gd").new()
		for i in range(field_course.destinations.size()):
			var site: Dictionary = field_course.destinations[i]
			var yard = CourseGoal.new()
			add_child(yard)
			yard.position = site.position
			var config = sector_config.duplicate()
			config.kind = site.kind
			yard.build(self,config)
			var marker = Sprite3D.new()
			marker.name = "DestinationIcon"
			marker.texture = icons.texture(RunState.Services.icon(site))
			marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			marker.pixel_size = 0.16
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.position = Vector3(0,11,0)
			yard.add_child(marker)
			goals.append(yard)
		goal = goals[0]
		obstacles = CourseObstacles.new()
		add_child(obstacles)
		obstacles.build(self,sector_config)
		return
	box(self,Vector3(route_length/2,-0.3,0),Vector3(route_length+100,0.4,160),"mud")
	var ground = sector_config.get("terrain","road")
	material("route_ground","39342d" if ground == "mud" else "54544a" if ground == "rubble" else "4b4b40")
	box(self,Vector3(route_length/2,-0.065,0),Vector3(route_length+30,0.035,15),"route_ground")
	if ground == "mud":
		for x in range(-20,int(route_length),9):
			var pool = cylinder(self,Vector3(x,-0.035,0),4.0,0.02,"dark",8)
			pool.scale.z = 1.5
	elif ground == "rubble":
		for x in range(-20,int(route_length),8):
			for z in [-6,6]:
				if not near_supply_point(x,z): box(self,Vector3(x,0.08,z),Vector3(1.5,0.3,0.7),"stone")
	var rng = RandomNumberGenerator.new()
	rng.seed = int(sector_config.get("seed",1918))
	for i in range(85):
		var x = rng.randf_range(-25,route_length+28)
		var z = rng.randf_range(-36,36)
		if absf(z) < 8: continue
		if x >= route_length-10 and absf(z) < 24: continue
		if near_supply_point(x,z): continue
		if i % 3 == 0:
			cylinder(self,Vector3(x,-0.04,z),rng.randf_range(1.0,2.6),0.04,"dark",8)
		else:
			var ruin = box(self,Vector3(x,0.6,z),Vector3(0.5,1.3,rng.randf_range(1,3)),"stone")
			ruin.rotation.y = rng.randf()*PI
	for x in range(-20,int(route_length)-5,12):
		for z in [-10,10]:
			if near_supply_point(x,z): continue
			box(self,Vector3(x,0,z),Vector3(3.5,0.06,1.2),"coal")
			for k in range(3): box(self,Vector3(x+k,0.12,z),Vector3(0.22,0.20,1.3),"wood")
	goal = CourseGoal.new()
	add_child(goal)
	goal.position.x = route_length
	goal.build(self,sector_config)
	goals.append(goal)
	obstacles = CourseObstacles.new()
	add_child(obstacles)
	obstacles.build(self,sector_config)

func remaining_distance() -> float:
	var remaining = INF
	for yard in goals: remaining = minf(remaining,yard.remaining_distance(player.position))
	return remaining

func supply_position(index: int) -> Vector3:
	if field_course != null:
		return field_course.center_at(route_length*[0.14,0.30,0.46][index])+Vector3(0,0,20 if index%2 == 0 else -20)
	# Keep the loading platforms outside the full hull's slalom/pivot envelope.
	var shoulder = 22.0 if sector_config.get("obstacles_version",0) == 1 else 8.0
	return Vector3(SUPPLY_DISTANCES[index],0,shoulder if index%2 == 0 else -shoulder)

func near_supply_point(x: float, z: float) -> bool:
	if sector_config.is_empty(): return false
	for i in range(SUPPLY_DISTANCES.size()):
		var at = supply_position(i)
		if absf(x-at.x) < 5 and absf(z-at.z) < 4: return true
	return false

func update_camera():
	if camera == null: return
	var at = player.position if player != null else Vector3.ZERO
	var target = at+Vector3(24,1.7,0)
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*42
	camera.position += Vector3(sin(elapsed*71),cos(elapsed*59),0)*shake
	camera.look_at(target,Vector3.UP)
	camera.size = zoom

func _ready():
	route_length = float(sector_config.get("length",ROUTE_LENGTH))
	if sector_config.get("field_version",0) == 1: field_course = FieldCourse.new(sector_config)
	total = RunState.enemy_count(sector_config)
	super._ready()
	zoom = 52.0
	yaw = -0.65
	pitch = 1.12
	update_camera()
	toggle_roof()
	material("enemy","875444")
	material("warning","e66a45",0,0.4)
	material("shell_body","bca375")
	material("shell_tracer","f7b764",0,0.6)
	material("electric_flash","8fb8aa",0,0.6)
	material("impact_dust","756951")
	material("impact_fire","e76b24",0,0.3).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
			var site = SupplyPoint.new()
			add_child(site)
			site.position = supply_position(i)
			var shells = int(sector_config.get("shells",0)/3)
			site.build(self,sector_config.get("kind","scrapyard"),i,shells)
			resource_sites.append({"node":site,"distance":route_length*[0.14,0.30,0.46][i] if field_course != null else SUPPLY_DISTANCES[i],"taken":false,"shells":shells,"scrap":int(sector_config.scrap/3)+(1 if i < int(sector_config.scrap)%3 else 0),"coal":int(sector_config.coal/3)+(1 if i < int(sector_config.coal)%3 else 0)})
	for i in range(total):
		var unit = Node3D.new()
		add_child(unit)
		unit.visible = false
		var boss = bool(sector_config.get("boss",false)) and i == total-1
		var hp = RunState.enemy_health(sector_config,i)
		var role = RunState.enemy_role(sector_config,i)
		var profile = RunState.Content.ENEMIES[role]
		var paint = "enemy_"+str(role)
		material(paint,profile.color)
		var heavy = role == 2
		if boss: unit.scale = Vector3.ONE*1.7
		elif role == 1: unit.scale = Vector3(0.85,0.8,0.85)
		else: unit.scale = Vector3.ONE*float(profile.get("scale",1.0))
		var length = 2.0 if heavy else 1.5
		var outline = PackedVector2Array([Vector2(-length,-0.7),Vector2(-length+0.35,-1.05),Vector2(length-0.35,-1.05),Vector2(length,-0.65),Vector2(length,0.65),Vector2(length-0.35,1.05),Vector2(-length+0.35,1.05),Vector2(-length,0.7)])
		prism(unit,outline,0.3,1.35,paint)
		box(unit,Vector3(0.25,1.4,0),Vector3(2.2,0.18,1.65),paint)
		for side in [-1,1]:
			box(unit,Vector3(0,0.5,side*1.15),Vector3(3.8,0.8,0.55),"dark")
			var tread_profile = PackedVector2Array([Vector2(-2,0.4),Vector2(-1.6,0.95),Vector2(1.6,0.95),Vector2(2,0.4),Vector2(1.65,0.1),Vector2(-1.65,0.1)])
			track_links(unit,tread_profile,side*1.15,0.62,0.28)
			for wheel_index in range(5):
				var wheel = cylinder(unit,Vector3(-1.4+wheel_index*0.7,0.48,side*1.46),0.31,0.08,"steel",12)
				wheel.rotation.x = PI/2
		for vent in range(4): box(unit,Vector3(-length+0.2+vent*0.18,1.37,0),Vector3(0.08,0.05,1.1),"dark")
		var health: Array = []
		for pip in range(hp): health.append(box(unit,Vector3(-0.7+pip*0.7,2.5,0),Vector3(0.5,0.07,0.25),"brass"))
		var pivot = Node3D.new()
		unit.add_child(pivot)
		cylinder(pivot,Vector3(0,1.65,0),0.9 if heavy else 0.65,0.8,paint,12,0.78 if heavy else 0.55)
		cylinder(pivot,Vector3(-0.15,2.1,0),0.34,0.12,"dark",12)
		beam(pivot,Vector3(0,1.7,0),Vector3(3.1 if heavy else 2.2,1.7,0),0.13,"dark",12)
		beam(pivot,Vector3(0.45,1.7,0),Vector3(1.0,1.7,0),0.23,paint,12)
		if role == 4: beam(pivot,Vector3(2,1.7,0),Vector3(3.8,1.7,0),0.1,"steel",12)
		if role == 5: beam(pivot,Vector3(0,1.6,0),Vector3(1,3.0,0),0.25,"dark",12)
		if role == 8:
			for z in [-0.5,0.5]: cylinder(unit,Vector3(-0.6,1.8,z),0.25,0.9,"rust",12)
		if role == 9: box(unit,Vector3(-0.8,1.8,0),Vector3(1.5,0.9,1.5),"wood")
		if role == 10:
			for z in [-0.4,0.4]: beam(pivot,Vector3(0,1.7,z),Vector3(2.4,1.7,z),0.1,"dark",12)
		if role == 11:
			beam(unit,Vector3(-1,1.4,0),Vector3(-1,3.0,0),0.055,"brass",8)
			cylinder(unit,Vector3(-1,3,0),0.65,0.08,"brass",12)
		if role == 12: box(unit,Vector3(1.8,0.8,0),Vector3(0.3,0.7,2.5),"steel")
		if role == 13:
			for x in [-0.8,0.0,0.8]:
				for z in [-0.55,0.55]:
					cylinder(unit,Vector3(x,1.75,z),0.26,0.85,"rust",12)
					cylinder(unit,Vector3(x,2.1,z),0.28,0.12,"dark",12)
		if role == 14:
			for z in [-0.65,0,0.65]:
				for y in [2.0,2.5]:
					beam(unit,Vector3(-1.4,y,z),Vector3(0.9,y+0.55,z),0.24,"dark",12)
					beam(unit,Vector3(0.8,y+0.52,z),Vector3(1.1,y+0.6,z),0.28,"steel",12)
		if role == 15:
			for z in [-0.75,0,0.75]:
				beam(unit,Vector3(1.3,0.9,z),Vector3(3.2,0.9,z),0.18,"rust",12)
				cylinder(unit,Vector3(-0.7,1.8,z),0.22,0.55,"machine_hot",8)
		var mark = MeshInstance3D.new()
		var ring = TorusMesh.new()
		ring.inner_radius = float(profile.radius)-0.2
		ring.outer_radius = float(profile.radius)
		ring.rings = 16
		ring.ring_segments = 6
		mark.mesh = ring
		mark.material_override = mats.warning
		mark.scale.y = 0.12
		mark.visible = false
		add_child(mark)
		# Show the complete salvo footprint before firing, using the same
		# centered offsets as launch_enemy. Children follow saved parent state.
		for burst in range(int(profile.get("burst",1))):
			var spread = (burst-(float(profile.get("burst",1))-1)/2)*4.0
			if is_zero_approx(spread): continue
			var footprint = MeshInstance3D.new()
			footprint.mesh = ring
			footprint.material_override = mats.warning
			footprint.position.z = spread
			mark.add_child(footprint)
		var warmup = float(profile.warning)*float(sector_config.get("warning_scale",1.0))+0.3+(i%int(sector_config.get("wave_size",2)))*0.3
		if sector_config.get("opening",false) and i < int(sector_config.get("wave_size",2)): warmup += 3.0
		var collision_radius = (4.2 if role == 4 else 3.5 if heavy else 3.0)*maxf(unit.scale.x,unit.scale.z)
		enemies.append({"node":unit,"collision_radius":collision_radius,"health":health,"pivot":pivot,"hp":hp,"max_hp":hp,"cooldown":warmup if sector_config.has("enemies") else 7.0+i,"active":false,"role":role,"wave":int(i/int(sector_config.get("wave_size",2))),"mark":mark,"locked":false,"aim":Vector3.ZERO})

func enemy_position_clear(enemy: Dictionary, at: Vector3, allow_escape: bool = false) -> bool:
	var terrain_clear = obstacles.clear_enemy_path(enemy.node.position,at,float(enemy.collision_radius)) if allow_escape else obstacles.circle_clear(at,float(enemy.collision_radius))
	if not terrain_clear: return false
	for other in enemies:
		if other.node == enemy.node or not other.active: continue
		var separation = Vector2(at.x-other.node.position.x,at.z-other.node.position.z).length()
		var clearance = float(enemy.collision_radius)+float(other.collision_radius)+VEHICLE_CLEARANCE
		if separation >= clearance:
			if allow_escape:
				var from = Vector2(enemy.node.position.x,enemy.node.position.z)
				var to = Vector2(at.x,at.z)
				var center = Vector2(other.node.position.x,other.node.position.z)
				var nearest = Geometry2D.get_closest_point_to_segment(center,from,to)
				if from.distance_to(center) >= clearance and nearest.distance_to(center) < clearance: return false
			continue
		# Old saves can contain overlapping vehicles; permit steps out of contact.
		var previous = Vector2(enemy.node.position.x-other.node.position.x,enemy.node.position.z-other.node.position.z).length()
		if allow_escape and separation > previous+0.00001: continue
		return false
	return true

func move_enemy(enemy: Dictionary, wanted: Vector3, max_distance: float) -> Vector3:
	var at: Vector3 = enemy.node.position
	var step = wanted.limit_length(max_distance)
	if enemy_position_clear(enemy,at+step,true): return step
	# Slide around occupied ground instead of pushing another hull or teleporting.
	var side = Vector3(-step.z,0,step.x)
	for candidate in [(step+side).normalized()*step.length(),(step-side).normalized()*step.length(),side,-side]:
		if enemy_position_clear(enemy,at+candidate,true): return candidate
	return Vector3.ZERO

static func shell_flight_time(origin: Vector3, target: Vector3, style: String = "heavy") -> float:
	return maxf(0.001,origin.distance_to(target)/float(BALLISTICS[style].speed))

func enemy_screen_bounds(enemy: Dictionary, at: Vector3) -> Rect2:
	# Include the turret, gun and boss scale so no part pops into the viewport.
	var scale_value: Vector3 = enemy.node.scale.abs()
	var bounds = Rect2(camera.unproject_position(at),Vector2.ZERO)
	for x in [-4.0,4.0]:
		for y in [0.0,3.0]:
			for z in [-4.0,4.0]:
				bounds = bounds.expand(camera.unproject_position(at+Vector3(x,y,z)*scale_value))
	return bounds

func entry_position(enemy: Dictionary, index: int) -> Vector3:
	var lane = [-9.0,-3.0,3.0,9.0][index%4]
	var at = player.position+Vector3(28+(index%4)*5,0,lane)
	var screen = camera.get_viewport().get_visible_rect().grow(24)
	while enemy_screen_bounds(enemy,at).intersects(screen) or not enemy_position_clear(enemy,at): at.x += 2.0
	return at

func can_engage(enemy: Dictionary, reach: float = ENGAGEMENT_RANGE, origin: Vector3 = Vector3.INF) -> bool:
	if origin == Vector3.INF: origin = player.position+Vector3(0,1.7,0)
	if origin.distance_squared_to(enemy.node.position) > reach*reach: return false
	var center = enemy.node.position+Vector3(0,1.3,0)
	return not camera.is_position_behind(center) and camera.get_viewport().get_visible_rect().grow(-32).has_point(camera.unproject_position(center))

func nearest_enemy(origin: Vector3 = Vector3.INF, reach: float = ENGAGEMENT_RANGE):
	if origin == Vector3.INF: origin = turret.global_position
	var nearest = null
	var best = INF
	for enemy in enemies:
		if enemy.hp <= 0 or not enemy.active or not can_engage(enemy,reach,origin): continue
		# An in-flight round already guarantees this kill; aim at the next opponent.
		var reserved = false
		for shot in projectiles:
			if shot.target.node == enemy.node:
				reserved = true
				break
		if reserved: continue
		var d = origin.distance_squared_to(enemy.node.position)
		if d < best:
			best = d
			nearest = enemy
	return nearest

func launch_enemy(enemy, spread: float = 0.0):
	var profile = RunState.Content.ENEMIES[enemy.role]
	var origin: Vector3 = enemy.node.position+Vector3(0,1.7,0)
	var target: Vector3 = enemy.aim+Vector3(0,0.3,spread)
	var node = Node3D.new()
	add_child(node)
	node.position = origin
	build_shell(node,(target-origin).normalized(),profile.ballistics)
	bolts.append({"node":node,"origin":origin,"target":target,"age":0.0,"duration":shell_flight_time(origin,target,profile.ballistics),"style":profile.ballistics,"mark":enemy.mark,"radius":float(profile.radius),"damage":hit_damage()*float(profile.damage)})

func receive_shell(factory, target: Vector3, radius: float, damage: float) -> bool:
	if damage <= 0 or Vector2(player.position.x-target.x,player.position.z-target.z).length() >= radius: return false
	# Ignore decorative pitch/roll: X/Z grid follows the vehicle's current yaw.
	var local_hit = Basis(Vector3.UP,player.rotation.y).inverse()*(target-player.position)
	factory.damage_at(Vector2(local_hit.x,local_hit.z))
	hull = maxi(0,hull-ceili(damage*(factory.ARMOR_DAMAGE_MULTIPLIER if factory.last_damage_blocked else 1.0)))
	shake = 0.3
	sync_damage(factory)
	return true

func build_shell(node: Node3D, heading: Vector3, style: String = "heavy"):
	var spec = BALLISTICS[style]
	# A short solid round with a warm tail, rather than a long luminous streak.
	beam(node,Vector3.ZERO,-heading*0.65,spec.width,"shell_body",12)
	beam(node,-heading*0.65,-heading*(0.65+spec.tail),spec.width*0.65,"electric_flash" if style == "electric" else "shell_tracer",8)

func impact(pos: Vector3, style: String = "heavy", feedback: bool = true):
	impact_serial += 1
	var spec = BALLISTICS[style]
	var node = Node3D.new()
	add_child(node)
	node.position = pos
	var flash = Node3D.new()
	node.add_child(flash)
	cylinder(flash,Vector3(0,0.5,0),0.7,1.8,"electric_flash" if style == "electric" else "fire",10,0.25)
	for i in range(5):
		var angle = TAU*i/5.0
		var flame = SphereMesh.new()
		flame.radius = 0.55
		flame.height = 1.1
		flame.radial_segments = 12
		flame.rings = 6
		mesh_node(flash,flame,Vector3(cos(angle)*0.45,0.3+(i%2)*0.35,sin(angle)*0.45),"electric_flash" if style == "electric" else "impact_fire")
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	var ring = mesh_node(node,ring_mesh,Vector3(0,-pos.y+0.08,0),"impact_dust")
	var dust = Node3D.new()
	node.add_child(dust)
	for i in range(6):
		var angle = TAU*i/6.0
		var mesh = SphereMesh.new()
		mesh.radius = 0.8
		mesh.height = 1.6
		mesh.radial_segments = 12
		mesh.rings = 6
		var puff = mesh_node(dust,mesh,Vector3(cos(angle)*0.8,0.3+(i%2)*0.35,sin(angle)*0.8),"impact_dust")
		puff.scale = Vector3(1.0,1.3,1.0)
	# Material alpha also works in the Compatibility renderer.
	for visual in flash.get_children()+dust.get_children()+[ring]:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.material_override = visual.material_override.duplicate()
		visual.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	impacts.append({"node":node,"flash":flash,"dust":dust,"ring":ring,"life":spec.life,"style":style})
	update_impact(impacts.back())
	if feedback: shake = maxf(shake,spec.blast*0.065/(1.0+player.position.distance_to(pos)/35.0))

func update_impact(effect: Dictionary):
	var spec = BALLISTICS[effect.style]
	var age: float = spec.life-effect.life
	var progress = clampf(age/spec.life,0,1)
	effect.flash.visible = age < spec.fire_time
	var burst = spec.blast*(0.35+0.65*minf(1,age/0.09))
	effect.flash.scale = Vector3(burst,burst*spec.column,burst)
	for flame in effect.flash.get_children():
		flame.material_override.albedo_color.a = 1.0-clampf((age/spec.fire_time-0.5)*2,0,1)
	effect.dust.visible = age > 0.07
	effect.dust.scale = Vector3.ONE*spec.blast*(0.25+progress*0.65)
	effect.dust.position.y = progress*spec.column*1.8
	var ring_size = spec.blast*(0.3+minf(age/0.45,1.0)*1.2)
	effect.ring.scale = Vector3(ring_size,0.15,ring_size)
	effect.ring.visible = age < 0.45
	effect.ring.material_override.albedo_color.a = 1.0-clampf(age/0.45,0,1)
	# Fade the expanding dust instead of shrinking an explosion to a point.
	for puff in effect.dust.get_children():
		puff.material_override.albedo_color.a = 1.0-clampf((progress-0.3)/0.7,0,1)

func drive_plan(travel: float, turn: float) -> Dictionary:
	var at = player.position
	var yaw_value = player.rotation.y
	var effort = 0.0
	var poses = [{"position":at,"yaw":yaw_value}]
	var steps = maxi(1,ceili(maxf(absf(travel)/0.25,absf(turn)/0.02)))
	var step_travel = travel/steps
	var step_turn = turn/steps
	for i in range(steps):
		var candidate = drive_step(at,yaw_value,step_travel,step_turn)
		if not obstacles.clear_pose(candidate.position,yaw_value+step_turn):
			# A stationary pivot remains available when forward motion is blocked.
			if absf(step_turn) > 0 and obstacles.clear_pose(at,yaw_value+step_turn):
				yaw_value += step_turn
				effort += absf(step_turn)*TRACK_HALF_WIDTH
				poses.append({"position":at,"yaw":yaw_value})
				continue
			break
		at = candidate.position
		yaw_value += step_turn
		effort += candidate.effort
		poses.append({"position":at,"yaw":yaw_value})
	return {"position":at,"yaw":yaw_value,"effort":effort,"poses":poses}

func drive_step(at: Vector3, yaw_value: float, travel: float, turn: float) -> Dictionary:
	# Integrate the arc, so driving while steering is independent of frame rate.
	var offset = Vector3(travel,0,0)
	if absf(turn) > 0.000001:
		var radius = travel/turn
		offset = Vector3(sin(turn)*radius,0,(cos(turn)-1)*radius)
	var unbounded = at+Basis(Vector3.UP,yaw_value)*offset
	var destination = Vector3(clampf(unbounded.x,0,route_length+CourseGoal.DEPTH+2),at.y,clampf(unbounded.z,-BATTLE_HALF_WIDTH,BATTLE_HALF_WIDTH))
	if field_course != null:
		var point = Vector2(unbounded.x,unbounded.z).clamp(field_course.bounds.position,field_course.bounds.end)
		destination = Vector3(point.x,at.y,point.y)
	var actual = destination.distance_to(at)
	var arc = absf(travel)*actual/offset.length() if offset.length() > 0.000001 else 0.0
	# Mean absolute travel of the two tracks. Pivoting costs fuel even when
	# the hull center stays still; blocked translation alone costs nothing.
	return {"position":destination,"effort":maxf(arc,absf(turn)*TRACK_HALF_WIDTH)}

func move_player(factory, delta: float) -> float:
	var surface = RunState.condition(sector_config)
	var engine_speed = combat_modifiers.get("speed",1.0)*equipment_effect("speed",(1.0+0.2*equipment_power("supercharger") if "supercharger" in installed_equipment else 1.0))
	var road_factor = 0.65 if field_course != null and field_course.road_distance(player.position) > FieldCourse.ROAD_HALF_WIDTH else 1.0
	var travel = road_factor*clampf(movement_direction.x,-1,1)*delta*surface.speed*engine_speed
	var turn = -clampf(movement_direction.z,-1,1)*delta*TURN_SPEED*engine_speed*surface.speed/3.3
	var consumption = FUEL_PER_METER*fuel_multiplier*surface.fuel*equipment_effect("fuel",(1.0-0.2*equipment_power("economizer") if "economizer" in installed_equipment else 1.0)*(1.1 if "supercharger" in installed_equipment else 1.0))
	var plan = drive_plan(travel,turn)
	var fraction = minf(1.0,factory.fuel/(plan.effort*consumption)) if plan.effort > 0 else 1.0
	travel *= fraction
	turn *= fraction
	plan = drive_plan(travel,turn)
	if plan.effort*consumption > factory.fuel+0.0000001:
		# Clipping against a wall makes effort non-linear in requested travel.
		var low = 0.0
		var high = 1.0
		for i in range(24):
			var mid = (low+high)/2
			if drive_plan(travel*mid,turn*mid).effort*consumption <= factory.fuel: low = mid
			else: high = mid
		plan = drive_plan(travel*low,turn*low)
	factory.consume_fuel(plan.effort*consumption)
	velocity = (plan.position-player.position)/maxf(delta,0.001)
	player.position = plan.position
	player.rotation.y = wrapf(plan.yaw,-PI,PI)
	drive_poses = plan.poses
	speed = velocity.length()
	distance = clampf(player.position.x,0,route_length)
	return plan.effort

func tick_battle(factory, delta: float):
	if not factory.running or result != 0: return
	combo_time = maxf(0,combo_time-delta)
	if combo_time == 0: combo = 0
	elapsed += delta
	var travel = move_player(factory,delta)
	for pose in drive_poses:
		for index in obstacles.triggered(pose.position,pose.yaw):
			obstacles.set_spent(index,true)
			var at: Vector3 = obstacles.mines[index].position
			var local_hit = Basis(Vector3.UP,pose.yaw).inverse()*(at-pose.position)
			factory.damage_at(Vector2(clampf(local_hit.x,-6.5,6.5),clampf(local_hit.z,-3.5,3.5)))
			hull = maxi(0,hull-ceili(hit_damage()*1.4*(factory.ARMOR_DAMAGE_MULTIPLIER if factory.last_damage_blocked else 1.0)))
			impact(at,"demolition")
			shake = 0.45
	sync_damage(factory)
	for site in resource_sites:
		if not site.taken and site.node.crossed_by(drive_poses):
			site.taken = true
			if item_mode:
				var count = 6 if sector_config.get("encounter","") == "rich" else 3
				var role = {"scrapyard":0,"coalfield":9,"arsenal":2}.get(sector_config.kind,0)
				for i in range(count): item_dropped.emit(Gear.roll(sector_config.seed,1000+resource_sites.find(site)*10+i,role,false,int(sector_config.sector)*2))
				feedback_effect("pickup",site.node.position,1.2)
			else: recover(factory,{"scrap":site.scrap,"coal":site.coal,"shell":site.shells})
			site.node.set_taken(true)
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
	# Spawn against this frame's camera, including movement before the wave trigger.
	update_camera()
	var wave_count = ceili(float(total)/int(sector_config.get("wave_size",2)))
	var wave_spacing = route_length/(wave_count+1) if sector_config.has("enemies") else 28.0
	var commanded = false
	var flying_bolts = bolts.duplicate()
	for unit in enemies:
		if unit.role == 11 and unit.active and unit.hp > 0: commanded = true
	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i]
		var profile = RunState.Content.ENEMIES[enemy.role]
		if not enemy.active and (distance >= enemy.wave*wave_spacing or elapsed >= enemy.wave*float(sector_config.get("wave_delay",30.0))):
			enemy.active = true
			enemy.node.visible = true
			# Enter along the road from beyond the forward edge, then approach normally.
			enemy.node.position = entry_position(enemy,i)
			enemy.node.rotation = Vector3(0,PI,0)
		if enemy.hp <= 0 or not enemy.active: continue
		var offset: Vector3 = player.position-enemy.node.position
		var lane = [-9.0,-3.0,3.0,9.0][i%4]
		if profile.get("flank",false): lane = -12.0 if i%2 == 0 else 12.0
		var intercept = player.position+Vector3(float(profile.intercept),0,lane)
		if profile.get("ram",false): intercept = player.position
		var move = (intercept-enemy.node.position)*0.4
		var max_speed = float(profile.speed)
		var enemy_step = move_enemy(enemy,move*delta,max_speed*delta)
		enemy.node.position += enemy_step
		# A restored basis can have an equivalent Euler decomposition with flipped X/Z.
		# Derive the planar heading directly and replace the complete rotation.
		var enemy_yaw = atan2(-enemy.node.basis.x.z,enemy.node.basis.x.x)
		if enemy_step.length_squared() > 0.000001: enemy_yaw = rotate_toward(enemy_yaw,atan2(-enemy_step.z,enemy_step.x),delta*1.5)
		enemy.node.rotation = Vector3(0,enemy_yaw,0)
		enemy.pivot.rotation.y = atan2(-offset.z,offset.x)-enemy_yaw
		if profile.get("ram",false):
			enemy.mark.visible = true
			enemy.mark.position = enemy.node.position+Vector3(0,0.1,0)
			var local_enemy = player.basis.inverse()*(enemy.node.position-player.position)
			if absf(local_enemy.x) < 9.5 and absf(local_enemy.z) < 6.5:
				var contact = player.position+player.basis*Vector3(clampf(local_enemy.x,-6.5,6.5),0,clampf(local_enemy.z,-3.5,3.5))
				receive_shell(factory,contact,12,hit_damage()*float(profile.damage))
				kill_enemy(enemy,factory,enemy.node.position,"demolition")
			continue
		if not enemy.locked and not can_engage(enemy,48.0 if enemy.role in [4,5,11] else 42.0): continue
		enemy.cooldown -= delta
		var warning = float(profile.warning)*float(sector_config.get("warning_scale",1.0))
		if enemy.cooldown <= warning and not enemy.locked:
			enemy.locked = true
			enemy.cooldown = warning
			enemy.aim = player.position
			if profile.get("lead",0.0) > 0:
				var flight = shell_flight_time(enemy.node.position,player.position+velocity*warning,profile.ballistics)
				enemy.aim += velocity*(warning+flight)*minf(1.0,float(profile.lead))
			enemy.mark.position = enemy.aim+Vector3(0,0.1,0)
			enemy.mark.visible = true
		if enemy.cooldown <= 0:
			enemy.cooldown = float(sector_config.get("attack_period",8.0))*float(profile.period)*(0.85 if commanded else 1.0)
			enemy.locked = false
			for burst in range(int(profile.get("burst",1))): launch_enemy(enemy,(burst-(float(profile.get("burst",1))-1)/2)*4.0)
			if profile.get("burst",1) > 1: feedback_effect("salvo",enemy.node.position+Vector3(0,2,0),0.5)
	update_gun(factory,delta)
	# A round fired at this frame's boundary starts flying on the next step.
	for bolt in flying_bolts:
		bolt.age += delta
		var t = minf(1,bolt.age/bolt.duration)
		bolt.node.position = bolt.origin.lerp(bolt.target,t)
		if t >= 1:
			receive_shell(factory,bolt.target,float(bolt.get("radius",6.0)),float(bolt.get("damage",hit_damage())))
			impact(bolt.target,bolt.get("style","heavy"))
			bolt.mark.visible = false
			bolt.node.queue_free()
			bolts.erase(bolt)
	for flash in impacts.duplicate():
		flash.life -= delta
		update_impact(flash)
		if flash.life <= 0:
			flash.node.queue_free()
			impacts.erase(flash)
	shake = maxf(0,shake-delta)
	update_camera()
	if hull <= 0: result = -1
	else:
		for i in range(goals.size()):
			if goals[i].contains_position(player.position):
				arrived_destination = i
				result = 1
				break
	if result != 0:
		factory.running = false
		target_marker.visible = false

func update_gun(factory, delta: float):
	var flying_shots = projectiles.duplicate()
	cooldown = maxf(0,cooldown-delta)
	recoil = maxf(0,recoil-delta*0.75)
	barrel.position.x = BARREL_REST-recoil
	shot_time = maxf(0,shot_time-delta)
	var target = nearest_enemy(turret.global_position,weapon_range(ENGAGEMENT_RANGE))
	target_marker.visible = target != null
	if target != null:
		target_marker.position = target.node.position+Vector3(0,0.12,0)
		var offset: Vector3 = target.node.position-turret.global_position
		target_angle = atan2(-offset.z,offset.x)-player.rotation.y
		turret.rotation.y = rotate_toward(turret.rotation.y,target_angle,delta*2.4*equipment_effect("turn",(1.0+0.6*equipment_power("servo") if "servo" in installed_equipment else 1.0)))
		if cooldown <= 0 and absf(angle_difference(turret.rotation.y,target_angle)) < 0.025 and factory.ammo > 0:
			factory.fire_round()
			fire_visual()
			var shot: Dictionary = projectiles.back()
			shot.target = target
			shot.duration = shell_flight_time(shot.origin,target.node.position+Vector3(0,1.3,0))
			cooldown = 60.0/factory.rate*reload_multiplier*equipment_effect("reload",(1.0-0.2*equipment_power("drum_loader") if "drum_loader" in installed_equipment else 1.0))
	muzzle.visible = shot_time > 0
	update_auxiliary_guns(factory,delta)
	for shot in flying_shots:
		shot.age += delta
		var destination: Vector3 = shot.target.node.position+Vector3(0,1.3,0)
		shot.node.position = shot.origin.lerp(destination,minf(1,shot.age/shot.duration))
		if shot.age >= shot.duration:
			kill_enemy(shot.target,factory,destination,shot.get("style","heavy"))
			if shot.get("chain",0) > 0: chain_hit(factory,destination,int(shot.chain))
			if shot.get("splash",0.0) > 0:
				for enemy in enemies:
					if enemy.active and enemy.hp > 0 and Vector2(enemy.node.position.x-destination.x,enemy.node.position.z-destination.z).length() <= shot.splash+enemy.collision_radius:
						kill_enemy(enemy,factory,enemy.node.position+Vector3(0,1.3,0),shot.get("style","heavy"))
			shot.node.queue_free()
			projectiles.erase(shot)

func kill_enemy(enemy: Dictionary, factory, at: Vector3, style: String = "heavy"):
	if enemy.hp <= 0: return
	enemy.hp = 0
	for pip in enemy.health: pip.visible = false
	impact(at,style)
	feedback_effect("kill",at,1.2 if enemy.role in [2,7] else 0.8)
	combo += 1
	combo_time = 2.8
	best_combo = maxi(best_combo,combo)
	kills += 1
	enemy_destroyed.emit(int(enemy.role))
	if item_mode:
		var index = enemies.find(enemy)
		item_dropped.emit(Gear.roll(sector_config.seed,index,int(enemy.role),sector_config.get("boss",false) and index == enemies.size()-1,int(sector_config.sector)*2))
		var recovery_rate = equipment_effect("salvage_rate",1.0/maxi(2,roundi(3/equipment_power("salvage_arm"))) if "salvage_arm" in installed_equipment else 0.0)
		if floori(kills*recovery_rate+0.0000001) > floori((kills-1)*recovery_rate+0.0000001): item_dropped.emit(Gear.roll(sector_config.seed,2000+index,9,false,int(sector_config.sector)*2))
	elif not sector_config.is_empty():
		var profile = RunState.Content.ENEMIES[enemy.role]
		recover(factory,{"scrap":int(profile.get("loot",2))+int(combat_modifiers.get("salvage",0))+(2 if "salvage_arm" in installed_equipment else 0),"coal":int(profile.get("coal",0))})
	enemy.mark.visible = false
	enemy.node.scale.y = 0.35
	var detonation = float(RunState.Content.ENEMIES[enemy.role].get("detonate",0))
	if detonation > 0:
		impact(at,"demolition")
		feedback_effect("salvo",at,1.4)
		for nearby in enemies:
			if nearby.active and nearby.hp > 0 and nearby.node.position.distance_to(at) <= detonation:
				kill_enemy(nearby,factory,nearby.node.position+Vector3(0,1,0),"demolition")

func chain_hit(factory, origin: Vector3, count: int):
	var from = origin
	for hop in range(count):
		var target = null
		var closest = 9.0*9.0
		for enemy in enemies:
			if not enemy.active or enemy.hp <= 0: continue
			var distance = from.distance_squared_to(enemy.node.position+Vector3(0,1.3,0))
			if distance < closest:
				closest = distance
				target = enemy
		if target == null: break
		var to: Vector3 = target.node.position+Vector3(0,1.3,0)
		feedback_effect("armor",from,0.35)
		feedback.arc(from,to)
		kill_enemy(target,factory,to,"electric")
		from = to

func weapon_range(base: float) -> float:
	return base+float(combat_modifiers.get("range",0.0))+equipment_effect("range",(6.0*equipment_power("rangefinder") if "rangefinder" in installed_equipment else 0.0))

func hit_damage() -> int:
	return ceili(float(sector_config.get("damage",10))*equipment_effect("damage",(1.0-0.25*equipment_power("armor") if "armor" in installed_equipment else 1.0)*(1.0-0.2*equipment_power("skirts") if "skirts" in installed_equipment else 1.0))*float(combat_modifiers.get("damage",1.0)))

func update_auxiliary_guns(factory, delta: float):
	for gun in auxiliary_guns:
		var spec = RunState.EQUIPMENT[gun.id]
		gun.cooldown = maxf(0,gun.cooldown-delta)
		gun.flash = maxf(0,gun.flash-delta)
		gun.recoil = maxf(0,gun.recoil-delta*0.5)
		var target = nearest_enemy(gun.pivot.global_position,weapon_range(float(spec.range)))
		if target != null:
			var offset: Vector3 = target.node.position-gun.pivot.global_position
			var angle = atan2(-offset.z,offset.x)-player.rotation.y
			gun.pivot.rotation.y = rotate_toward(gun.pivot.rotation.y,angle,delta*float(spec.get("turn",3.2))*equipment_effect("turn",(1.0+0.6*equipment_power("servo") if "servo" in installed_equipment else 1.0)))
			if gun.cooldown <= 0 and absf(angle_difference(gun.pivot.rotation.y,angle)) < 0.025 and factory.auxiliary_ammo(gun.id) >= int(spec.ammo):
				for round_index in range(int(spec.ammo)): factory.fire_round(gun.id)
				var origin: Vector3 = gun.muzzle.global_position
				var heading: Vector3 = gun.pivot.global_basis.x.normalized()
				var targets = [target]
				if spec.get("pellets",1) > 1:
					var candidates: Array = []
					for candidate in enemies:
						if candidate == target or not candidate.active or candidate.hp <= 0: continue
						if not can_engage(candidate,weapon_range(float(spec.range)),origin): continue
						if projectiles.any(func(p): return p.target == candidate): continue
						if heading.dot((candidate.node.position+Vector3(0,1.3,0)-origin).normalized()) < 0.8: continue
						candidates.append(candidate)
					candidates.sort_custom(func(a,b): return origin.distance_squared_to(a.node.position) < origin.distance_squared_to(b.node.position))
					targets.append_array(candidates.slice(0,int(spec.pellets)-1))
				for victim in targets:
					var shot = Node3D.new()
					add_child(shot)
					shot.position = origin
					var direction = (victim.node.position+Vector3(0,1.3,0)-origin).normalized()
					build_shell(shot,direction,spec.ballistics)
					projectiles.append({"node":shot,"origin":origin,"dir":direction,"age":0.0,"duration":shell_flight_time(origin,victim.node.position+Vector3(0,1.3,0),spec.ballistics),"style":spec.ballistics,"target":victim,"splash":float(spec.get("splash",0.0))+equipment_effect("splash",(4.0*equipment_power("blast_fuse") if "blast_fuse" in installed_equipment else 0.0)),"chain":int(spec.get("chain",0))})
				gun.cooldown = float(spec.interval)/float(combat_modifiers.get("equipment_power",{}).get(gun.id,1.0))*reload_multiplier*equipment_effect("reload",(1.0-0.2*equipment_power("drum_loader") if "drum_loader" in installed_equipment else 1.0))
				gun.flash = 0.14
				gun.recoil = 0.2
				feedback_effect("shot",origin,0.55 if spec.ballistics == "rapid" else 0.9)
				visual_shots += 1
		gun.muzzle.visible = gun.flash > 0
		gun.barrel.position.x = 0.6-gun.recoil

func fire_visual():
	var heading = turret.global_basis.x.normalized()
	var origin = muzzle.global_position
	var shot = Node3D.new()
	add_child(shot)
	shot.position = origin
	build_shell(shot,heading)
	projectiles.append({"node":shot,"origin":origin,"dir":heading,"age":0.0,"style":"heavy","splash":equipment_effect("splash",4.0*equipment_power("blast_fuse") if "blast_fuse" in installed_equipment else 0.0)})
	recoil = 0.65
	barrel.position.x = BARREL_REST-recoil
	shot_time = 0.1
	shake = maxf(shake,0.1)
	feedback_effect("shot",origin,1.1)
	visual_shots += 1

func recover(factory, items: Dictionary):
	for kind in items:
		var amount = int(items[kind])
		if amount <= 0: continue
		var accepted = 0
		if kind == "shell":
			accepted = mini(amount,factory.ammo_capacity-factory.ammo)
			factory.ammo += accepted
		else: accepted = factory.collect(kind,amount)
		collection_events.append({"item":kind,"accepted":accepted,"lost":amount-accepted})
	while collection_events.size() > 12: collection_events.pop_front()

func equipment_power(id: String) -> float:
	return float(combat_modifiers.get("equipment_power",{}).get(id,1.0))

func equipment_effect(key: String, legacy: float) -> float:
	return float(combat_modifiers.get("equipment_effects",{}).get(key,legacy))
