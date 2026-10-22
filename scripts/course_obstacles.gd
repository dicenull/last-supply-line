extends Node3D
## Deterministic staggered roadblocks. Geometry and collision share one plan.
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
