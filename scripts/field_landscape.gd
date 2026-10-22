extends RefCounted
## Seeded district plan. Scenery, collision and minimap consume the same data.
const PALETTES = {
	"quarry":{"ground":"5d5948","road":"4b483b","patch":"716957","detail":"827968"},
	"wetland":{"ground":"394b3c","road":"55503e","patch":"314944","detail":"596859"},
	"ruins":{"ground":"514936","road":"3c3a32","patch":"645640","detail":"775d49"},
	"rail_yard":{"ground":"444a40","road":"56503f","patch":"353e38","detail":"667168"}
}

static func outline(patch: Dictionary) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(12):
		var angle = TAU*i/12.0
		var radius = 0.90+0.1*cos(angle*3)
		var offset = (Vector2(cos(angle),sin(angle))*patch.size*radius).rotated(patch.yaw)
		points.append(Vector2(patch.position.x,patch.position.z)+offset)
	return points

static func populate(course, route: Dictionary):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.seed)+97531
	for i in range(10):
		var at = Vector3(rng.randf_range(course.bounds.position.x+24,course.bounds.end.x-24),0,rng.randf_range(course.bounds.position.y+24,course.bounds.end.y-24))
		course.patches.append({"position":at,"size":Vector2(rng.randf_range(10,23),rng.randf_range(7,15)),"yaw":rng.randf_range(-PI,PI)})
	var dominant = {"quarry":"rocks","wetland":"deadwood","ruins":"ruin","rail_yard":"rail_depot"}[course.landscape]
	# Place clusters alongside roads, with open stretches between them.
	for segment in course.segments:
		var forward: Vector3 = (segment[1]-segment[0]).normalized()
		var normal = Vector3(-forward.z,0,forward.x)
		for side in [-1,1]:
			var at: Vector3 = segment[0].lerp(segment[1],rng.randf_range(0.25,0.75))+normal*side*rng.randf_range(23,34)
			if not available(course,route,at,6): continue
			var kind = dominant if rng.randf() < 0.75 else ["rocks","ruin","tower"][rng.randi_range(0,2)]
			course.landmarks.append({"position":at,"radius":6.0,"kind":kind,"yaw":atan2(-forward.z,forward.x),"variant":rng.randi_range(0,2)})
			if course.landmarks.size() >= 14: return
	# Fill wider districts without crowding intersections or supply platforms.
	for i in range(256):
		if course.landmarks.size() >= 10: break
		var at = Vector3(rng.randf_range(10,course.bounds.end.x-10),0,rng.randf_range(course.bounds.position.y+10,course.bounds.end.y-10))
		if available(course,route,at,6):
			course.landmarks.append({"position":at,"radius":6.0,"kind":dominant,"yaw":rng.randf_range(-PI,PI),"variant":rng.randi_range(0,2)})

static func available(course, route: Dictionary, at: Vector3, radius: float) -> bool:
	if not course.bounds.grow(-8).has_point(Vector2(at.x,at.z)): return false
	if course.road_distance(at) < course.ROAD_HALF_WIDTH+radius+3: return false
	for site in course.destinations:
		if at.distance_to(site.position) < radius+24: return false
	for landmark in course.landmarks:
		if at.distance_to(landmark.position) < radius+landmark.radius+6: return false
	for i in range(3):
		var supply: Vector3 = course.center_at(float(route.length)*[0.14,0.30,0.46][i])+Vector3(0,0,20 if i%2 == 0 else -20)
		if at.distance_to(supply) < radius+9: return false
	return at.distance_to(Vector3.ZERO) > radius+16
