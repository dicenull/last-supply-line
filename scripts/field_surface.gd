extends RefCounted
## Cosmetic road wear and low roadside details. Never changes course collision.
const MAX_INSTANCES = 720
const PALETTES = preload("res://scripts/field_landscape.gd").PALETTES

static func generate(course, route: Dictionary) -> Array:
	if course.landscape == "": return []
	var rng = RandomNumberGenerator.new()
	rng.seed = int(route.seed)+197813
	var rows: Array = []
	var palette: Dictionary = PALETTES[course.landscape]
	for segment_index in range(course.segments.size()):
		var segment: Array = course.segments[segment_index]
		var forward: Vector3 = (segment[1]-segment[0]).normalized()
		var side = Vector3(-forward.z,0,forward.x)
		var yaw = atan2(-forward.z,forward.x)
		var distance: float = segment[0].distance_to(segment[1])
		var steps = maxi(1,int(distance/5))
		for i in range(steps):
			var center: Vector3 = segment[0].lerp(segment[1],(i+0.5)/steps)
			for sign_value in [-1,1]:
				if rng.randf() < 0.14: continue
				var at = center+side*sign_value*rng.randf_range(4.2,4.9)+forward*rng.randf_range(-1,1)
				at.y = -0.037+segment_index*0.00005
				rows.append(row("rut",at,Vector3(rng.randf_range(5.2,8.5),1,rng.randf_range(0.45,0.85)),yaw+rng.randf_range(-0.025,0.025),Color(palette.road).darkened(rng.randf_range(0.10,0.16))))
			if i%2 == 0:
				var at = center+side*rng.randf_range(-9,9)
				at.y = -0.032+segment_index*0.00005
				rows.append(row("scuff",at,Vector3(rng.randf_range(1.5,3.5),1,rng.randf_range(0.6,1.8)),yaw+rng.randf_range(-0.3,0.3),Color(palette.road).lightened(rng.randf_range(0.03,0.06))))
		var clusters = maxi(1,int(distance/11))
		for i in range(clusters):
			var center: Vector3 = segment[0].lerp(segment[1],(i+0.5)/clusters)
			for sign_value in [-1,1]:
				var at = center+side*sign_value*rng.randf_range(15,20)+forward*rng.randf_range(-2,2)
				if not roadside_clear(course,at,2,float(route.length)): continue
				var kind = "grass" if course.landscape == "wetland" else "stone" if course.landscape in ["quarry","ruins"] else "timber"
				if rng.randf() < 0.25: kind = "grass"
				var count = 4 if kind == "grass" else 2
				for j in range(count):
					var pos = at+Vector3(rng.randf_range(-0.7,0.7),0,rng.randf_range(-0.7,0.7))
					var scale_value: Vector3
					var color: Color
					match kind:
						"grass":
							scale_value = Vector3(rng.randf_range(0.4,0.8),rng.randf_range(0.5,1.2),rng.randf_range(0.4,0.8))
							color = Color(palette.ground).darkened(rng.randf_range(0,0.12))
						"stone":
							scale_value = Vector3(rng.randf_range(0.6,1.5),rng.randf_range(0.25,0.7),rng.randf_range(0.5,1.2))
							color = Color(palette.detail).darkened(rng.randf_range(0.05,0.18))
						_:
							scale_value = Vector3(rng.randf_range(1.2,2.4),0.14,0.25)
							color = Color("635241").lightened(rng.randf_range(0,0.12))
					pos.y = scale_value.y/2-0.07
					rows.append(row(kind,pos,scale_value,yaw+rng.randf_range(-0.8,0.8),color))
	return rows.slice(0,MAX_INSTANCES)

static func row(kind: String, at: Vector3, scale_value: Vector3, yaw: float, color: Color) -> Dictionary:
	return {"kind":kind,"position":at,"scale":scale_value,"yaw":yaw,"color":color}

static func roadside_clear(course, at: Vector3, radius: float, length: float) -> bool:
	if not course.bounds.has_point(Vector2(at.x,at.z)): return false
	if course.road_distance(at) < course.ROAD_HALF_WIDTH+radius+1: return false
	for site in course.destinations:
		if at.distance_to(site.position) < radius+22: return false
	for landmark in course.landmarks:
		if at.distance_to(landmark.position) < radius+landmark.radius+2: return false
	# Supply loading pads sit beside the trunk at these three progress fractions.
	for i in range(3):
		var supply: Vector3 = course.center_at(length*[0.14,0.30,0.46][i])+Vector3(0,0,20 if i%2 == 0 else -20)
		if at.distance_to(supply) < radius+10: return false
	return true
