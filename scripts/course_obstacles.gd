extends Node3D
## Deterministic staggered roadblocks. Geometry and collision share one plan.
const Defenses = preload("res://scripts/destination_defenses.gd")
const HULL_HALF = Vector2(8.8,5.6)
const MINE_RADIUS = 0.85
var barriers: Array = []
var mines: Array = []
var rows: Array = []

static func layout(route: Dictionary) -> Array:
	var result: Array = []
	if route.get("obstacles_version",0) != 1: return result
	if route.get("field_version",0) == 1: return preload("res://scripts/field_course.gd").new(route).hazard_sites()
	var first_side = 1 if posmod(int(route.get("seed",0)),2) == 0 else -1
	for x in range(34,int(route.get("length",100))-22,36):
		var index = result.size()
		result.append({"x":float(x),"open_side":first_side*(1 if index%2 == 0 else -1),"kind":"fence" if index%2 == 0 else "hedgehog"})
	return result

func build(world, route: Dictionary):
	rows = layout(route)
	name = "CourseObstacles"
	world.material("mine_accent","934b42")
	if route.get("field_version",0) == 1:
		build_field(world)
		if route.get("defenses_version",0) == 1: build_destination_defenses(world)
		for plan in world.field_course.landmarks:
			barriers.append(Rect2(Vector2(plan.position.x,plan.position.z)-Vector2.ONE*plan.radius,Vector2.ONE*plan.radius*2))
		return
	for row in rows:
		for i in range(9):
			var z = -row.open_side*(i+1)*3.0
			var at = Vector3(row.x,0,z)
			var node = Node3D.new()
			add_child(node)
			node.position = at
			if row.kind == "fence":
				for side in [-1,1]:
					world.box(node,Vector3(0,1.6,side*1.5),Vector3(0.35,3.2,0.35),"machine_iron")
					world.box(node,Vector3(0,0.3,side*1.5),Vector3(2.6,0.6,0.8),"stone")
				for y in [0.65,2.8]:
					world.box(node,Vector3(0,y,0),Vector3(0.22,0.22,3),"pipe_joint")
				for zbar in [-1.0,-0.5,0.0,0.5,1.0]:
					world.box(node,Vector3(0,1.75,zbar),Vector3(0.18,2.1,0.18),"machine_iron")
				world.beam(node,Vector3(0,0.7,-1.4),Vector3(0,2.8,1.4),0.09,"pipe_joint",6)
			else:
				for angle in [0.0,PI/2]:
					var leg = world.box(node,Vector3(0,1.25,0),Vector3(3.6,0.48,0.48),"machine_hot")
					leg.rotation = Vector3(0,angle,PI/4)
					var brace = world.box(node,Vector3(0,1.25,0),Vector3(3.6,0.48,0.48),"machine_iron")
					brace.rotation = Vector3(0,angle,-PI/4)
				world.box(node,Vector3(0,1.25,0),Vector3(0.7,0.7,0.7),"pipe_joint")
			barriers.append(Rect2(Vector2(at.x-1.5,at.z-1.5),Vector2(3,3)))
		for dx in [-6.0,6.0]:
			add_mine(world,Vector3(row.x+dx,0,row.open_side*0.5))
		add_mine(world,Vector3(row.x,0,-row.open_side*8.0))
		# A small physical warning plate beside the mine strip.
		var sign = Node3D.new()
		add_child(sign)
		sign.position = Vector3(row.x-9,0,row.open_side*4.5)
		world.box(sign,Vector3(0,0.7,0),Vector3(0.1,1.4,0.1),"wood")
		var plate = world.box(sign,Vector3(0,1.4,0),Vector3(0.12,0.65,0.65),"machine_hot")
		plate.rotation.x = PI/4
		world.box(sign,Vector3(-0.08,1.4,0),Vector3(0.035,0.25,0.12),"mark")

func add_mine(world, at: Vector3):
	var node = Node3D.new()
	add_child(node)
	node.position = at
	var live = Node3D.new()
	node.add_child(live)
	world.cylinder(live,Vector3(0,0.12,0),MINE_RADIUS,0.24,"pipe_joint",12)
	world.cylinder(live,Vector3(0,0.28,0),0.48,0.12,"machine_hot",8)
	world.cylinder(live,Vector3(0,0.35,0),0.32,0.025,"mine_accent",8)
	for angle in [0.0,PI/2,PI,PI*1.5]:
		var paint = world.box(live,Vector3(cos(angle)*0.77,0.245,sin(angle)*0.77),Vector3(0.14,0.025,0.26),"mine_accent")
		paint.rotation.y = -angle
		world.box(live,Vector3(cos(angle)*0.62,0.26,sin(angle)*0.62),Vector3(0.14,0.08,0.14),"edge")
	var crater = world.cylinder(node,Vector3(0,0.015,0),1.25,0.04,"dark",10)
	crater.visible = false
	mines.append({"position":at,"live":live,"crater":crater,"spent":false})

func set_spent(index: int, value: bool):
	mines[index].spent = value
	mines[index].live.visible = not value
	mines[index].crater.visible = value

static func overlaps(at: Vector3, yaw: float, rect: Rect2) -> bool:
	# Separating-axis test of the complete rotated hull against a world box.
	var forward = Vector2(cos(yaw),-sin(yaw))
	var side = Vector2(sin(yaw),cos(yaw))
	var offset = rect.get_center()-Vector2(at.x,at.z)
	var half = rect.size/2
	for axis in [Vector2.RIGHT,Vector2.DOWN,forward,side]:
		var hull_radius = absf(axis.dot(forward))*HULL_HALF.x+absf(axis.dot(side))*HULL_HALF.y
		var block_radius = absf(axis.x)*half.x+absf(axis.y)*half.y
		if absf(offset.dot(axis)) >= hull_radius+block_radius: return false
	return true

func clear_pose(at: Vector3, yaw: float) -> bool:
	for rect in barriers:
		if overlaps(at,yaw,rect): return false
	return true

func sweep_hull(at: Vector3, yaw: float, movement: Vector3) -> Dictionary:
	# Sweep the complete oriented footprint, using the same SAT axes as overlaps.
	var forward = Vector2(cos(yaw),-sin(yaw))
	var side = Vector2(sin(yaw),cos(yaw))
	var step = Vector2(movement.x,movement.z)
	var first: Dictionary = {}
	for rect in barriers:
		var offset: Vector2 = Vector2(at.x,at.z)-rect.get_center()
		var half: Vector2 = rect.size/2
		var enter = -INF
		var leave = INF
		var normal = Vector2.ZERO
		var missed = false
		for axis in [Vector2.RIGHT,Vector2.DOWN,forward,side]:
			var radius: float = absf(axis.dot(forward))*HULL_HALF.x+absf(axis.dot(side))*HULL_HALF.y+absf(axis.x)*half.x+absf(axis.y)*half.y
			var distance: float = offset.dot(axis)
			var speed: float = step.dot(axis)
			if absf(speed) < 0.0000001:
				if absf(distance) >= radius: missed = true; break
				continue
			var near_time = (-radius-distance)/speed
			var far_time = (radius-distance)/speed
			if near_time > far_time:
				var swap = near_time
				near_time = far_time
				far_time = swap
			if near_time > enter:
				enter = near_time
				normal = -axis*signf(speed)
			leave = minf(leave,far_time)
		if missed or enter > leave or leave <= 0 or enter < -0.000001 or enter > 1: continue
		if first.is_empty() or enter < first.time:
			first = {"time":maxf(0,enter),"normal":Vector3(normal.x,0,normal.y),"rect":rect}
	return first

static func contact_point(at: Vector3, yaw: float, rect: Rect2) -> Vector3:
	# Closest hull/obstacle features also cover a box corner hitting a hull side.
	var corners: Array[Vector2] = []
	var basis = Basis(Vector3.UP,yaw)
	for corner in [Vector3(-HULL_HALF.x,0,-HULL_HALF.y),Vector3(HULL_HALF.x,0,-HULL_HALF.y),Vector3(HULL_HALF.x,0,HULL_HALF.y),Vector3(-HULL_HALF.x,0,HULL_HALF.y)]:
		var point: Vector3 = at+basis*corner
		corners.append(Vector2(point.x,point.z))
	var nearest = Vector2.ZERO
	var best = INF
	var matches = 0
	for point in corners:
		var other = point.clamp(rect.position,rect.end)
		var distance = point.distance_squared_to(other)
		if distance < best-0.000001:
			best = distance
			nearest = (point+other)/2
			matches = 1
		elif absf(distance-best) < 0.000001:
			nearest += (point+other)/2
			matches += 1
	for point in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		for i in range(4):
			var other = Geometry2D.get_closest_point_to_segment(point,corners[i],corners[(i+1)%4])
			var distance: float = point.distance_squared_to(other)
			if distance < best-0.000001:
				best = distance
				nearest = (point+other)/2
				matches = 1
			elif absf(distance-best) < 0.000001:
				nearest += (point+other)/2
				matches += 1
	nearest /= maxi(1,matches)
	# Upper hull edge keeps the sparks visible above tracks and low barricades.
	return Vector3(nearest.x,2.65,nearest.y)

func slide_hull(at: Vector3, yaw: float, movement: Vector3) -> Dictionary:
	var remaining = movement
	var contacts: Array = []
	var distance = 0.0
	var positions: Array = []
	for attempt in range(3):
		if remaining.length_squared() < 0.00000001: break
		var hit = sweep_hull(at,yaw,remaining)
		if hit.is_empty():
			if clear_pose(at+remaining,yaw):
				at += remaining
				distance += remaining.length()
				positions.append(at)
			break
		# A small skin prevents round-off from turning a resting contact into overlap.
		var fraction = maxf(0,hit.time-0.001/remaining.length())
		if remaining.length()*fraction < 0.00001: fraction = 0
		var advance = remaining*fraction
		at += advance
		distance += advance.length()
		positions.append(at)
		contacts.append({"position":contact_point(at,yaw,hit.rect),"normal":hit.normal})
		remaining = (remaining*(1-fraction)).slide(hit.normal)
	return {"position":at,"distance":distance,"positions":positions,"contacts":contacts}

func circle_clear(at: Vector3, radius: float) -> bool:
	var point = Vector2(at.x,at.z)
	for rect in barriers:
		var nearest = point.clamp(rect.position,rect.end)
		if point.distance_squared_to(nearest) < radius*radius: return false
	return true

func clear_enemy_path(from: Vector3, to: Vector3, radius: float) -> bool:
	var steps = maxi(1,ceili(from.distance_to(to)/0.3))
	for i in range(1,steps+1):
		if not circle_clear(from.lerp(to,float(i)/steps),radius): return false
	return true

func triggered(at: Vector3, yaw: float) -> Array:
	var result: Array = []
	for i in range(mines.size()):
		if mines[i].spent: continue
		var p: Vector3 = mines[i].position
		if overlaps(at,yaw,Rect2(Vector2(p.x,p.z)-Vector2.ONE*MINE_RADIUS,Vector2.ONE*MINE_RADIUS*2)):
			result.append(i)
	return result

func navigation_points(length: float) -> Array:
	# A clear route for regression pilots: pivot between rows, then cross the gap.
	var points: Array = []
	for row in rows:
		var z = row.open_side*9.0
		points.append(Vector3(row.x-18,0,z))
		points.append(Vector3(row.x+18,0,z))
	if not rows.is_empty(): points.append(Vector3(rows.back().x+18,0,0))
	points.append(Vector3(length+1,0,0))
	return points

func build_field(world):
	for row in rows:
		var at = Vector3(row.x,0,row.z)
		var cluster = Node3D.new()
		add_child(cluster)
		cluster.position = at
		cluster.rotation.y = row.yaw
		cluster.scale = Vector3.ONE*row.scale
		match row.kind:
			"fence":
				for x in [-3.0,0.0,3.0]:
					world.box(cluster,Vector3(x,1.4,0),Vector3(0.4,2.8,0.4),"machine_iron")
					world.box(cluster,Vector3(x,0.25,0),Vector3(1.5,0.5,1.2),"stone")
				for y in [0.8,2.3]: world.box(cluster,Vector3(0,y,0),Vector3(6.4,0.25,0.25),"pipe_joint")
				world.beam(cluster,Vector3(-3,0.8,0),Vector3(3,2.3,0),0.1,"machine_hot",6)
			"wreck":
				world.box(cluster,Vector3(0,0.65,0),Vector3(5.5,1.3,3.2),"machine_hot")
				var roof_plate = world.box(cluster,Vector3(0.4,1.7,0),Vector3(2.7,1.2,2.4),"machine_iron")
				roof_plate.rotation.z = 0.2
				for z in [-1.8,1.8]: world.box(cluster,Vector3(0,0.4,z),Vector3(6,0.8,0.5),"dark")
				world.beam(cluster,Vector3(1,2,0),Vector3(4,1.1,0),0.23,"pipe_joint",8)
			_:
				for offset in [Vector3(-1.6,0,-1),Vector3(1.6,0,1)]:
					for angle in [0.0,PI/2]:
						var leg = world.box(cluster,offset+Vector3(0,1.25,0),Vector3(3.6,0.48,0.48),"machine_hot")
						leg.rotation = Vector3(0,angle,PI/4)
						var brace = world.box(cluster,offset+Vector3(0,1.25,0),Vector3(3.6,0.48,0.48),"machine_iron")
						brace.rotation = Vector3(0,angle,-PI/4)
		# A conservative footprint encloses the rotated cluster, including its debris.
		var half = 4.3*row.scale
		barriers.append(Rect2(Vector2(at.x,at.z)-Vector2.ONE*half,Vector2.ONE*half*2))
		for offset in [Vector3(-5,0,0),Vector3(5,0,0),Vector3(0,0,5)]: add_mine(world,at+offset)

static func mine_count(route: Dictionary) -> int:
	var count = layout(route).size()*3
	if route.get("defenses_version",0) == 1:
		count += int(route.destination_count)*Defenses.mines(Vector3.ZERO,route.get("final_base_version",0) == 1).size()
	return count

func build_destination_defenses(world):
	for site in world.field_course.destinations:
		var perimeter = Node3D.new()
		perimeter.name = "DestinationPerimeter"
		add_child(perimeter)
		for rect in Defenses.fences(site.position,site.get("final_base",false)):
			barriers.append(rect)
			var center: Vector2 = rect.get_center()
			var along_x = rect.size.x > rect.size.y
			var length: float = maxf(rect.size.x,rect.size.y)
			var direction = Vector3.RIGHT if along_x else Vector3.BACK
			var start = Vector3(center.x,0,center.y)-direction*length/2
			var finish = start+direction*length
			for y in [0.8,2.5]:
				world.box(perimeter,Vector3(center.x,y,center.y),Vector3(rect.size.x,0.24,rect.size.y),"pipe_joint")
			for i in range(ceili(length/2)+1):
				var at = start.lerp(finish,float(i)/ceili(length/2))
				world.box(perimeter,at+Vector3(0,1.5,0),Vector3(0.35,3,0.35),"machine_iron")
				world.box(perimeter,at+Vector3(0,0.3,0),Vector3(1,0.6,1),"stone")
			world.beam(perimeter,start+Vector3(0,0.8,0),finish+Vector3(0,2.5,0),0.09,"machine_hot",6)
		for at in Defenses.mines(site.position,site.get("final_base",false)): add_mine(world,at)
