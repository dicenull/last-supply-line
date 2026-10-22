extends Node3D
## Static cosmetic meshes, batched by shape and 64 m region for coarse culling.
const Plan = preload("res://scripts/field_surface.gd")
const CHUNK_SIZE = 64.0
var instance_total = 0

func build(course, route: Dictionary):
	name = "SurfaceDetails"
	var groups: Dictionary = {}
	for entry in Plan.generate(course,route):
		var tile = Vector2i(floori(entry.position.x/CHUNK_SIZE),floori(entry.position.z/CHUNK_SIZE))
		var key = entry.kind+":"+str(tile.x)+":"+str(tile.y)
		if not groups.has(key): groups[key] = []
		groups[key].append(entry)
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1
	var meshes: Dictionary = {}
	for key in groups:
		var entries: Array = groups[key]
		var kind: String = entries[0].kind
		if not meshes.has(kind): meshes[kind] = shape(kind)
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = meshes[kind]
		multimesh.instance_count = entries.size()
		var bounds: AABB
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			var transform = Transform3D(Basis(Vector3.UP,entry.yaw)*Basis.from_scale(entry.scale),entry.position)
			multimesh.set_instance_transform(i,transform)
			multimesh.set_instance_color(i,entry.color)
			var instance_bounds: AABB = transform*multimesh.mesh.get_aabb()
			bounds = instance_bounds if i == 0 else bounds.merge(instance_bounds)
		multimesh.custom_aabb = bounds.grow(0.05)
		var batch = MultiMeshInstance3D.new()
		batch.name = key.replace(":","_")
		batch.multimesh = multimesh
		batch.material_override = material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		instance_total += entries.size()

func shape(kind: String) -> Mesh:
	if kind in ["rut","scuff"]:
		var outline = PackedVector2Array([Vector2(-0.5,-0.12),Vector2(-0.36,-0.46),Vector2(0.1,-0.34),Vector2(0.4,-0.5),Vector2(0.5,0.05),Vector2(0.31,0.35),Vector2(-0.1,0.42),Vector2(-0.43,0.5)])
		var triangles = Geometry2D.triangulate_polygon(outline)
		var surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in triangles:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(outline[index].x,0,outline[index].y))
		return surface.commit()
	if kind == "timber":
		var plank = BoxMesh.new()
		plank.size = Vector3.ONE
		return plank
	var mound = CylinderMesh.new()
	mound.height = 1
	mound.bottom_radius = 0.5
	mound.top_radius = 0 if kind == "grass" else 0.28
	mound.radial_segments = 3 if kind == "grass" else 5
	mound.rings = 1
	return mound
