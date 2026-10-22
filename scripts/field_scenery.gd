extends Node3D
## Render a road graph without owning expedition state or input.
func build(world, course):
	name = "FieldScenery"
	var area: Rect2 = course.bounds.grow(35)
	world.box(self,Vector3(area.get_center().x,-0.3,area.get_center().y),Vector3(area.size.x,0.4,area.size.y),"mud")
	var ground = world.sector_config.get("terrain","road")
	world.material("route_ground","39342d" if ground == "mud" else "54544a" if ground == "rubble" else "4b4b40")
	for segment in course.segments:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var road = world.box(self,(a+b)/2+Vector3(0,-0.065,0),Vector3(a.distance_to(b),0.035,course.ROAD_HALF_WIDTH*2),"route_ground")
		road.rotation.y = atan2(-(b-a).z,(b-a).x)
		world.cylinder(self,a+Vector3(0,-0.065,0),course.ROAD_HALF_WIDTH,0.035,"route_ground",16)
		var steps = maxi(1,int(a.distance_to(b)/8))
		for i in range(steps):
			var mark = world.box(self,a.lerp(b,(i+0.5)/steps)+Vector3(0,-0.035,0),Vector3(2.8,0.025,0.22),"edge")
			mark.rotation.y = road.rotation.y
	var rng = RandomNumberGenerator.new()
	rng.seed = int(world.sector_config.seed)+19
	for i in range(100):
		var at = Vector3(rng.randf_range(area.position.x,area.end.x),0,rng.randf_range(area.position.y,area.end.y))
		if course.road_distance(at) < 21 or world.near_supply_point(at.x,at.z): continue
		var near_goal = false
		for site in course.destinations:
			if at.distance_to(site.position) < 29: near_goal = true
		if near_goal: continue
		if i%3 == 0: world.cylinder(self,at+Vector3(0,-0.04,0),rng.randf_range(1,3),0.04,"dark",8)
		else:
			var ruin = world.box(self,at+Vector3(0,0.8,0),Vector3(1.3,1.6,rng.randf_range(1,4)),"stone")
			ruin.rotation.y = rng.randf()*PI
