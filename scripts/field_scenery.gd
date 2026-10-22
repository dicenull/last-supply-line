extends Node3D
## Render a road graph without owning expedition state or input.
func build(world, course):
	name = "FieldScenery"
	var area: Rect2 = course.bounds.grow(35)
	var detailed = course.landscape != ""
	if detailed:
		var palette = preload("res://scripts/field_landscape.gd").PALETTES[course.landscape]
		for key in ["ground","patch","detail"]: world.material("land_"+key,palette[key])
		world.material("route_ground",palette.road)
	world.box(self,Vector3(area.get_center().x,-0.3,area.get_center().y),Vector3(area.size.x,0.4,area.size.y),"land_ground" if detailed else "mud")
	var ground = world.sector_config.get("terrain","road")
	if not detailed: world.material("route_ground","39342d" if ground == "mud" else "54544a" if ground == "rubble" else "4b4b40")
	for patch in course.patches:
		# A single upward surface avoids almost-coplanar top/bottom faces.
		var outline = preload("res://scripts/field_landscape.gd").outline(patch)
		var triangles = Geometry2D.triangulate_polygon(outline)
		var mesh = SurfaceTool.new()
		mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0,triangles.size(),3):
			for j in [0,1,2]:
				var point = outline[triangles[i+j]]
				mesh.set_normal(Vector3.UP)
				mesh.add_vertex(Vector3(point.x,-0.08,point.y))
		var surface = world.mesh_node(self,mesh.commit(),Vector3.ZERO,"land_patch")
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if detailed:
		var landmarks = preload("res://scripts/field_landmarks.gd").new()
		add_child(landmarks)
		landmarks.build(world,course)
		var surface_details = preload("res://scripts/field_surface_view.gd").new()
		add_child(surface_details)
		surface_details.build(course,world.sector_config)
		return
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
