extends RefCounted
## Seeded road graph shared by scenery, navigation, destinations and the map.
const KINDS = ["scrapyard","coalfield","arsenal"]
const NAMES = {"scrapyard":"車両墓場","coalfield":"炭鉱","arsenal":"兵器庫"}
const ROAD_HALF_WIDTH = 12.0
var trunk: Array = []
var branches: Array = []
var destinations: Array = []
var bounds: Rect2
var segments: Array = []

func _init(route: Dictionary):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.get("seed",0))
	var length = float(route.get("length",110))
	var count = int(route.get("destination_count",2))
	var fork = Vector3(length*0.53,0,rng.randf_range(-37,-25))
	trunk = [Vector3.ZERO,Vector3(length*0.17,0,rng.randf_range(-13,8)),Vector3(length*0.34,0,rng.randf_range(-26,-8)),fork]
	var first = rng.randi_range(0,2)
	var order = [first,(first+rng.randi_range(1,2))%3]
	if count == 3: order.append(3-order[0]-order[1])
	for i in range(count):
		var end = Vector3(length+rng.randf_range(-3,3),0,-12.0-(count-1-i)*48.0)
		var bend = Vector3(length*0.78,0,lerpf(fork.z,end.z,0.65)+rng.randf_range(-7,7))
		var path = [fork,bend,end,end+Vector3(8,0,0)]
		branches.append(path)
		var site = {"position":end,"kind":KINDS[order[i]]}
		if route.get("encounters_version",0) == 1:
			# Rotate three distinct types independently of the saved road geometry.
			site.encounter = ["rich","hostile","shop"][posmod(int(route.seed)+i,3)]
		destinations.append(site)
	bounds = Rect2(-12,-12.0-(count-1)*48.0-26,length+52,64.0+(count-1)*48.0)
	for path in [trunk]+branches:
		for i in range(path.size()-1): segments.append([path[i],path[i+1]])

func road_distance(at: Vector3) -> float:
	var result = INF
	var point = Vector2(at.x,at.z)
	for segment in segments:
		var a = Vector2(segment[0].x,segment[0].z)
		var b = Vector2(segment[1].x,segment[1].z)
		result = minf(result,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
	return result

func navigation_points(index: int = 0) -> Array:
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
		for other in result:
			if at.distance_to(Vector3(other.x,0,other.z)) < 12: occupied = true
		for fraction in [0.14,0.30,0.46]:
			var center = center_at(destinations[0].position.x*fraction)
			if absf(at.x-center.x) < 9 and absf(absf(at.z-center.z)-20) < 9: occupied = true
		if occupied: continue
		result.append({"x":at.x,"z":at.z,"open_side":1,"kind":["hedgehog","fence","wreck"][rng.randi_range(0,2)],"yaw":rng.randf_range(-PI,PI),"scale":rng.randf_range(0.8,1.25)})
		if result.size() == count: break
	return result
