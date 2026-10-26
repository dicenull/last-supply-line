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
	var rect = Rect2(Vector2(anchor.x-0.5,anchor.z-0.5),Vector2(size)).grow(-0.139)
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
		if not Gear.part_slot(id).is_empty(): continue # Dedicated vehicle slots have their own regression suite.
		f = F.new(2)
		check(f.place_equipment(id,Vector2i(0,0)),"mount family: "+id)
		world.configure_equipment([id],f.auxiliary_positions(),f.equipment_mounts)
		battle.configure_equipment([id],f.auxiliary_positions(),f.equipment_mounts)
		var size: Vector2i = Gear.DEFINITIONS[id].size
		if id in F.Content.ALL_GUNS:
			var gun: Dictionary = world.auxiliary_guns[0]
			var fits = true
			for recoil in [0.0,0.2]:
				gun.barrel.position.x = 0.6-recoil
				gun.muzzle.show()
				for i in range(49):
					gun.pivot.rotation.y = lerpf(-gun.half_arc,gun.half_arc,i/48.0)
					fits = fits and footprint_contains(corners(gun.pivot,world.upgrade_mount),world,Vector2i(0,0),size)
			check(fits,"rotation, recoil and muzzle flash retain a 14 cm footprint margin: "+id)
			gun.barrel.position.x = world.EquipmentModels.BARREL_REST
			var old_scale = world.EquipmentModels.mount_scale(gun.pivot,size,true)
			check(gun.mount_scale > old_scale*1.1,"limited traverse enlarges the whole weapon beyond its old full-circle fit: "+id)
			world.toggle_roof()
			var points = corners(gun.pivot,world.upgrade_mount)
			var main_bottom = INF
			for point in corners(world.barrel,world.upgrade_mount): main_bottom = minf(main_bottom,point.y)
			check(points.all(func(p): return p.y >= 4.10 and p.y < main_bottom-0.1),"enlarged exterior weapon clears the roof and main barrel vertically: "+id)
			var highest = 0.0
			for point in points: highest = maxf(highest,point.y)
			check(highest >= 5.32 and footprint_contains(points,world,Vector2i(0,0),size),"exterior weapon is visibly taller while retaining its horizontal reservation: "+id)
			world.toggle_roof()
		else:
			var model = world.mounted_models[id]
			check(footprint_contains(corners(model,world.upgrade_mount),world,Vector2i(0,0),size),"internal model stays inside reserved footprint: "+id)
			check(corners(model,world.upgrade_mount).all(func(p): return p.y <= world.DECK_Y+1.051),"module stays below roof and turret base: "+id)
			world.toggle_roof()
			check(not model.visible,"closed armor hides its internal module: "+id)
			world.toggle_roof()
		if id in F.Content.ALL_GUNS:
			check(is_equal_approx(battle.auxiliary_guns[0].pivot.position.y,4.18),"battle exposes mounted weapon on the roof: "+id)
		else:
			check(battle.mounted_models[id].position == world.mounted_models[id].position,"battle uses the same installed module location: "+id)
		var moved = f.place_equipment(id,Vector2i(2,0))
		world.configure_equipment([id],f.auxiliary_positions(),f.equipment_mounts)
		var moved_model = world.auxiliary_guns[0].pivot if id in F.Content.ALL_GUNS else world.mounted_models[id]
		check(moved and footprint_contains(corners(moved_model,world.upgrade_mount),world,Vector2i(2,0),size),"moving an installed item preserves its center and margin: "+id)
		await process_frame
	# Adjacent reservations and the feed socket exercise the assembled scene.
	f = F.new(2)
	var mounts = {"long_gun_focus_l05":Vector2i(0,0),"scatter_gun":Vector2i(2,0),"servo":Vector2i(0,2),"blast_fuse":Vector2i(1,2),"armor":Vector2i(2,2)}
	for id in mounts: check(f.place_equipment(id,mounts[id]),"adjacent placement: "+id)
	world.configure_equipment(mounts.keys(),f.auxiliary_positions(),f.equipment_mounts)
	world.sync(f,Vector2i(-1,-1),"belt",0,0)
	for gun in world.auxiliary_guns:
		var feed_points = corners(world.machines[mounts[gun.id]].root,world)
		var model_points = corners(gun.pivot,world.upgrade_mount)
		var highest_feed = -INF
		var lowest_gun = INF
		for p in feed_points: highest_feed = maxf(highest_feed,p.y)
		for p in model_points: lowest_gun = minf(lowest_gun,p.y)
		check(highest_feed <= lowest_gun+0.001,"feed socket stays below the rotating weapon: "+gun.id)
		world.preview_equipment(f,{"kind":gun.id},mounts[gun.id])
		check(world.equipment_preview.position == world.cell_position(mounts[gun.id]),"placement preview stays at the reservation origin")
	interior_view.queue_free()
	exterior_view.queue_free()
	await process_frame
	print("EQUIPMENT GEOMETRY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
