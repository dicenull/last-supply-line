extends RefCounted
## Seeded road graph shared by scenery, navigation, destinations and the map.
const Shapes = preload("res://scripts/map_shapes.gd")
const Defenses = preload("res://scripts/destination_defenses.gd")
const SHOP_FIELD_CHANCE = 0.20
const KINDS = ["scrapyard","coalfield","arsenal"]
const NAMES = {"scrapyard":"車両墓場","coalfield":"炭鉱","arsenal":"兵器庫"}
const ROAD_HALF_WIDTH = 12.0
const DESTINATION_MIN_SPACING = 90.0
var trunk: Array = []
var branches: Array = []
var destinations: Array = []
var bounds: Rect2
var segments: Array = []
var connectors: Array = []
var landmarks: Array = []
var patches: Array = []
var landscape = ""
var pattern = 0
var supply_length = 0.0

func _init(route: Dictionary):
	if route.get("final_base_version",0) == 1:
		build_final_base(route)
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.get("seed",0))
	var length = float(route.get("length",110))
	var count = int(route.get("destination_count",2))
	var fork = Vector3(length*0.53,0,rng.randf_range(-37,-25))
	trunk = [Vector3.ZERO,Vector3(length*0.17,0,rng.randf_range(-13,8)),Vector3(length*0.34,0,rng.randf_range(-26,-8)),fork]
	var first = rng.randi_range(0,2)
	var order = [first,(first+rng.randi_range(1,2))%3]
	if count == 3: order.append(3-order[0]-order[1])
	var encounter_rng = RandomNumberGenerator.new()
	encounter_rng.seed = int(route.get("seed",0))+31013
	var shop_slot = encounter_rng.randi_range(0,count-1) if encounter_rng.randf() < SHOP_FIELD_CHANCE else -1
	for i in range(count):
		var end = Vector3(length+rng.randf_range(-3,3),0,-12.0-(count-1-i)*48.0)
		var bend = Vector3(length*0.78,0,lerpf(fork.z,end.z,0.65)+rng.randf_range(-7,7))
		var path = [fork,bend,end,end+Vector3(8,0,0)]
		branches.append(path)
		var site = {"position":end,"kind":KINDS[order[i]]}
		if route.get("encounters_version",0) == 2:
			site.encounter = "shop" if i == shop_slot else ["rich","hostile","standard"][posmod(int(route.seed)+i,3)]
		elif route.get("encounters_version",0) == 1:
			# Rotate three distinct types independently of the saved road geometry.
			site.encounter = ["rich","hostile","shop"][posmod(int(route.seed)+i,3)]
		destinations.append(site)
	bounds = Rect2(-12,-12.0-(count-1)*48.0-26,length+52,64.0+(count-1)*48.0)
	if route.get("landscape_version",0) == 1: vary_roads(route)
	if route.get("destination_layout_version",0) == 1:
		supply_length = length
		scatter_destinations(route)
	if route.get("defenses_version",0) == 1:
		for i in range(branches.size()):
			var end: Vector3 = destinations[i].position
			branches[i][1].x = minf(branches[i][1].x,end.x-44)
			branches[i].insert(2,end-Vector3(24,0,0))
	if route.get("map_shape_version",0) == 1: Shapes.build(self,route)
	for path in [trunk]+branches+connectors:
		for i in range(path.size()-1): segments.append([path[i],path[i+1]])
	if landscape != "": preload("res://scripts/field_landscape.gd").populate(self,route)

func build_final_base(route: Dictionary):
	var length = float(route.length)
	var end = Vector3(length+40,0,-28)
	supply_length = length
	trunk = [Vector3.ZERO,Vector3(length*0.25,0,10),Vector3(length*0.5,0,-28)]
	branches = [[trunk.back(),end-Vector3(64,0,0),end-Vector3(24,0,0),end+Vector3(16,0,0)]]
	destinations = [{"position":end,"kind":"arsenal","encounter":"hostile","final_base":true}]
	bounds = Rect2(-26,-94,end.x+132,152)
	for path in [trunk]+branches:
		for i in range(path.size()-1): segments.append([path[i],path[i+1]])

func scatter_destinations(route: Dictionary):
	# A versioned, independent stream preserves existing saves and site rewards.
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.seed)+68317
	var depth_order = range(destinations.size())
	for i in range(depth_order.size()-1,0,-1):
		var other = rng.randi_range(0,i)
		var swap = depth_order[i]
		depth_order[i] = depth_order[other]
		depth_order[other] = swap
	var fork: Vector3 = trunk.back()
	var z = fork.z-rng.randf_range(50,75)*(destinations.size()-1)
	var staging_x = INF
	for i in range(destinations.size()):
		var end = Vector3(float(route.length)+depth_order[i]*40+rng.randf_range(5,25),0,z)
		destinations[i].position = end
		staging_x = minf(staging_x,end.x-50)
		z += rng.randf_range(DESTINATION_MIN_SPACING+5,135)
	# Spread the roads before any fortification, then approach every gate head-on.
	# This keeps a farther branch from cutting through a nearer yard or minefield.
	for i in range(branches.size()):
		var end: Vector3 = destinations[i].position
		branches[i] = [fork,Vector3(staging_x,0,end.z),end,end+Vector3(8,0,0)]
	if connectors.size() > 1: connectors[1] = [branches[0][1],branches[1][1]]
	bounds = Rect2(-12,-12,24,24)
	for path in [trunk]+branches+connectors:
		for point in path:
			bounds = bounds.expand(Vector2(point.x,point.z)-Vector2(12,24))
			bounds = bounds.expand(Vector2(point.x,point.z)+Vector2(12,24))
	for site in destinations:
		bounds = bounds.expand(Vector2(site.position.x+48,site.position.z-36))
		bounds = bounds.expand(Vector2(site.position.x+48,site.position.z+36))

func vary_roads(route: Dictionary):
	# A separate stream keeps old roads and encounter assignments reproducible.
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.seed)+4589
	var length = float(route.length)
	pattern = rng.randi_range(0,3)
	landscape = ["quarry","wetland","ruins","rail_yard"][rng.randi_range(0,3)]
	var fork = Vector3(length*rng.randf_range(0.51,0.57),0,rng.randf_range(-35,-25))
	match pattern:
		0: trunk = [Vector3.ZERO,Vector3(length*0.17,0,6),Vector3(length*0.34,0,-24),fork]
		1: trunk = [Vector3.ZERO,Vector3(length*0.16,0,-22),Vector3(length*0.34,0,-38),fork]
		2: trunk = [Vector3.ZERO,Vector3(length*0.20,0,0),Vector3(length*0.20,0,-25),Vector3(length*0.39,0,-25),fork]
		3: trunk = [Vector3.ZERO,Vector3(length*0.14,0,8),Vector3(length*0.28,0,-22),Vector3(length*0.42,0,-14),fork]
	for i in range(1,trunk.size()-1): trunk[i].z += rng.randf_range(-3,3)
	for i in range(branches.size()):
		var end: Vector3 = destinations[i].position+Vector3(rng.randf_range(0,9),0,rng.randf_range(-5,5))
		destinations[i].position = end
		var bend = Vector3(length*rng.randf_range(0.73,0.80),0,lerpf(fork.z,end.z,0.65)+rng.randf_range(-10,10))
		branches[i] = [fork,bend,end,end+Vector3(8,0,0)]
	var split: Vector3 = trunk[1]
	var side = -1.0 if pattern == 1 else 1.0
	var detour_z = maxf(split.z,fork.z)+46 if side > 0 else minf(split.z,fork.z)-46
	connectors.append([split,Vector3(split.x+length*0.10,0,detour_z),Vector3(fork.x-length*0.07,0,detour_z),fork])
	if pattern in [1,2]: connectors.append([branches[0][1],branches[1][1]])
	for path in [trunk]+branches+connectors:
		for point in path:
			bounds = bounds.expand(Vector2(point.x,point.z)+Vector2(0,-24))
			bounds = bounds.expand(Vector2(point.x,point.z)+Vector2(0,24))
	bounds = Rect2(bounds.position-Vector2(0,16),bounds.size+Vector2(0,32))

func road_distance(at: Vector3) -> float:
	var result = INF
	var point = Vector2(at.x,at.z)
	for segment in segments:
		var a = Vector2(segment[0].x,segment[0].z)
		var b = Vector2(segment[1].x,segment[1].z)
		result = minf(result,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
	return result

func navigation_points(index: int = 0, detour: bool = false) -> Array:
	if detour and not connectors.is_empty() and connectors[0][0] == trunk[1] and connectors[0][-1] == trunk[-1]: return [trunk[1]]+connectors[0].slice(1)+branches[clampi(index,0,branches.size()-1)].slice(1)
	return trunk.slice(1)+branches[clampi(index,0,branches.size()-1)].slice(1)

func center_at(x: float) -> Vector3:
	# The shared approach contains all three supply stations, before the fork.
	for i in range(trunk.size()-1):
		if x <= trunk[i+1].x: return trunk[i].lerp(trunk[i+1],clampf((x-trunk[i].x)/(trunk[i+1].x-trunk[i].x),0,1))
	return trunk.back()

func hazard_sites() -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = int(destinations[0].position.x*10000+trunk[1].z*100)
	var result: Array = []
	var count = rng.randi_range(5,8)
	for i in range(160):
		var at = Vector3(rng.randf_range(22,bounds.end.x-24),0,rng.randf_range(bounds.position.y+5,bounds.end.y-5))
		# Leave room for the complete hull, pivoting, and each destination apron.
		if road_distance(at) < ROAD_HALF_WIDTH+11: continue
		var near_goal = false
		for site in destinations:
			if at.distance_to(site.position+Vector3(8,0,0)) < 29: near_goal = true
		if near_goal: continue
		var occupied = false
		for landmark in landmarks:
			if at.distance_to(landmark.position) < landmark.radius+12: occupied = true
		for other in result:
			if at.distance_to(Vector3(other.x,0,other.z)) < 12: occupied = true
		for fraction in [0.14,0.30,0.46]:
			var center = center_at((supply_length if supply_length > 0 else destinations[0].position.x)*fraction)
			if absf(at.x-center.x) < 9 and absf(absf(at.z-center.z)-20) < 9: occupied = true
		if occupied: continue
		result.append({"x":at.x,"z":at.z,"open_side":1,"kind":["hedgehog","fence","wreck"][rng.randi_range(0,2)],"yaw":rng.randf_range(-PI,PI),"scale":rng.randf_range(0.8,1.25)})
		if result.size() == count: break
	return result
