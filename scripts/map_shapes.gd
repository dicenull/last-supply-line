extends RefCounted
## Versioned modern road layouts; existing saves keep their original generator.
const IDS = ["fan","serpentine","switchback","ring","braid","long_route"]
const NAMES = {"fan":"扇状分岐","serpentine":"S字街道","switchback":"折れ曲がり道","ring":"環状路","braid":"二重迂回路","long_route":"横長街道"}

static func assign(route: Dictionary, run_seed: int):
	if route.get("final_base_version",0) == 1: return
	route.map_shape_version = 1
	# Four ordinary sectors use different shapes within each new expedition.
	route.map_shape = IDS[posmod(run_seed+int(route.sector)-1,IDS.size())]

static func build(course, route: Dictionary):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.seed)+819173
	var length = float(route.length)
	var mirror = -1.0 if rng.randi()%2 == 0 else 1.0
	var amplitude = rng.randf_range(0.9,1.1)
	var old_fork: Vector3 = course.trunk.back()
	var shape: String = route.map_shape
	var points: Array = []
	match shape:
		"fan": points = [Vector2.ZERO,Vector2(0.16,4),Vector2(0.34,-8),Vector2(0.53,0)]
		"serpentine": points = [Vector2.ZERO,Vector2(0.16,26),Vector2(0.34,-32),Vector2(0.56,20)]
		"switchback": points = [Vector2.ZERO,Vector2(0.18,0),Vector2(0.18,-44),Vector2(0.38,-44),Vector2(0.38,12),Vector2(0.58,12)]
		"ring": points = [Vector2.ZERO,Vector2(0.15,-12),Vector2(0.30,-46),Vector2(0.46,-46),Vector2(0.60,0)]
		"braid": points = [Vector2.ZERO,Vector2(0.16,0),Vector2(0.35,0),Vector2(0.60,0)]
		"long_route": points = [Vector2.ZERO,Vector2(0.20,5),Vector2(0.40,14),Vector2(0.64,8)]
	course.trunk.clear()
	for point in points: course.trunk.append(Vector3(point.x*length,0,point.y*mirror*amplitude))
	var fork: Vector3 = course.trunk.back()
	var spread = 1.25 if shape == "fan" else 1.0
	var stretch = 1.35 if shape == "long_route" else 1.0
	var staging_x = INF
	for site in course.destinations:
		var old: Vector3 = site.position
		site.position = Vector3(fork.x+(old.x-old_fork.x)*stretch,0,fork.z+(old.z-old_fork.z)*spread*mirror)
		staging_x = minf(staging_x,site.position.x-50)
	course.branches.clear()
	for site in course.destinations:
		var end: Vector3 = site.position
		var staging = Vector3(staging_x,0,end.z)
		var path: Array = [fork]
		if shape == "fan": path.append(fork.lerp(staging,0.5))
		elif shape in ["switchback","long_route"]: path.append(Vector3(staging_x,0,fork.z))
		elif shape == "serpentine": path.append(Vector3(lerpf(fork.x,staging_x,0.5),0,lerpf(fork.z,end.z,0.75)))
		path.append_array([staging,end-Vector3(24,0,0),end,end+Vector3(8,0,0)])
		course.branches.append(without_duplicates(path))
	course.connectors.clear()
	var split: Vector3 = course.trunk[1]
	match shape:
		"ring":
			course.connectors.append([split,Vector3(length*0.27,0,48*mirror),Vector3(length*0.46,0,48*mirror),fork])
		"braid":
			for side in [-1,1]: course.connectors.append([split,Vector3(length*0.28,0,side*42),Vector3(length*0.46,0,side*42),fork])
		"serpentine": course.connectors.append([split,Vector3(length*0.43,0,38*mirror),fork])
		"long_route": course.connectors.append([split,Vector3(length*0.33,0,-34*mirror),Vector3(length*0.53,0,-34*mirror),fork])
	# A cross-road joins the branch approaches, always before every minefield.
	if shape in ["fan","braid"]:
		course.connectors.append([Vector3(staging_x,0,course.destinations[0].position.z),Vector3(staging_x,0,course.destinations[-1].position.z)])
	course.bounds = Rect2(-24,-24,48,48)
	for path in [course.trunk]+course.branches+course.connectors:
		for point in path:
			course.bounds = course.bounds.expand(Vector2(point.x,point.z)-Vector2(24,32))
			course.bounds = course.bounds.expand(Vector2(point.x,point.z)+Vector2(24,32))
	for site in course.destinations:
		course.bounds = course.bounds.expand(Vector2(site.position.x+48,site.position.z-36))
		course.bounds = course.bounds.expand(Vector2(site.position.x+48,site.position.z+36))

static func without_duplicates(points: Array) -> Array:
	var result: Array = []
	for point in points:
		if result.is_empty() or result.back().distance_to(point) > 0.01: result.append(point)
	return result
