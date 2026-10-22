extends SceneTree
const F = preload("res://scripts/factory.gd")
const Gear = F.Gear
var world
var battle
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment geometry: ",label)
	else:
		failures += 1
		push_error(label)
func corners(node: Node3D, reference: Node3D) -> Array:
	var points: Array = []
	if node is MeshInstance3D:
		# Use actual mesh vertices: rotating a cylinder's local AABB invents
		# corners that the visible model never occupies.
		for vertex in node.mesh.get_faces(): points.append(reference.to_local(node.to_global(vertex)))
	for child in node.get_children():
		if child is Node3D: points.append_array(corners(child,reference))
	return points
func footprint_contains(points: Array, world, at: Vector2i, size: Vector2i) -> bool:
	var anchor: Vector3 = world.cell_position(at)
	var rect = Rect2(Vector2(anchor.x-0.5,anchor.z-0.5),Vector2(size)).grow(0.001)
	return points.all(func(p): return rect.has_point(Vector2(p.x,p.z)))
func run():
	var interior_view = SubViewport.new()
	interior_view.size = Vector2i(1408,752)
	root.add_child(interior_view)
	world = preload("res://scripts/tank_world.gd").new()
	world.layout_version = 2
	interior_view.add_child(world)
	var exterior_view = SubViewport.new()
	exterior_view.size = Vector2i(1408,752)
	root.add_child(exterior_view)
	battle = preload("res://scripts/battle_world.gd").new()
	battle.layout_version = 2
	battle.sector_config = preload("res://scripts/run_state.gd").new(42).current
	exterior_view.add_child(battle)
	await process_frame
	var f = F.new(2)
	check(not f.can_place_equipment("left_gun",Vector2i(11,0)),"apparently empty cells within the main turret sweep reject a secondary gun")
	check(f.can_place_equipment("armor",Vector2i(11,0)),"internal modules may use deck space beneath the main turret")
	for id in Gear.DEFINITIONS:
		f = F.new(2)
		check(f.place_equipment(id,Vector2i(0,0)),"mount family: "+id)
		world.configure_equipment([id],f.auxiliary_positions(),f.equipment_mounts)
		battle.configure_equipment([id],f.auxiliary_positions(),f.equipment_mounts)
		var size: Vector2i = Gear.DEFINITIONS[id].size
		if id in F.Content.GUNS:
			var gun: Dictionary = world.auxiliary_guns[0]
			var fits = true
			for i in range(24):
				gun.pivot.rotation.y = TAU*i/24
				fits = fits and footprint_contains(corners(gun.pivot,world.upgrade_mount),world,Vector2i(0,0),size)
			check(fits,"full rotating barrel remains inside reserved footprint: "+id)
			world.toggle_roof()
			var points = corners(gun.pivot,world.upgrade_mount)
			check(points.all(func(p): return p.y >= 4.10 and p.y < 4.79),"exterior weapon clears the roof and main barrel vertically: "+id)
			world.toggle_roof()
		else:
			var model = world.mounted_models[id]
			check(footprint_contains(corners(model,world.upgrade_mount),world,Vector2i(0,0),size),"internal model stays inside reserved footprint: "+id)
			world.toggle_roof()
			check(not model.visible,"closed armor hides its internal module: "+id)
			world.toggle_roof()
		if id in F.Content.GUNS:
			check(is_equal_approx(battle.auxiliary_guns[0].pivot.position.y,4.18),"battle exposes mounted weapon on the roof: "+id)
		else:
			check(battle.mounted_models[id].position == world.mounted_models[id].position,"battle uses the same installed module location: "+id)
	interior_view.queue_free()
	exterior_view.queue_free()
	await process_frame
	print("EQUIPMENT GEOMETRY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
