extends Node3D
## Native low-poly 3D diorama. Grid coordinates are on the exposed tank deck.
const EquipmentModels = preload("res://scripts/item_model.gd")
const MountLayout = preload("res://scripts/weapon_mount_layout.gd")
var main_gun_anchor = Vector2i(9,3)
const MOUNTED_GUN_Y = 0.62
const EXTERIOR_GUN_HEIGHT = 1.15
const MAIN_BARREL_HEIGHT = 1.9
const MAIN_BARREL_SCALE = Vector3(1.3,1.5,1.5)
var equipment_models = EquipmentModels.new()
const F = preload("res://scripts/factory.gd")
const DECK_Y = 2.72
const TURRET_CENTER = Vector3(2.6,4.08,0)
const BARREL_REST = 2.4
var layout_version = 1
var turret_base: MeshInstance3D
var camera: Camera3D
var equipment: Node3D
var roof: Node3D
var goods: Node3D
var marker: MeshInstance3D
var placement_preview: Node3D
var preview_model: Node3D
var preview_arrows: Node3D
var preview_kind = ""
var preview_topology = ""
var preview_valid = false
var preview_materials: Dictionary = {}
var muzzle: MeshInstance3D
var mats: Dictionary = {}
var material_meshes: Dictionary = {}
var rendered_layout = ""
var damage_layer: Node3D
var rendered_damage = ""
var goods_pool: Array = []
var machines: Dictionary = {}
var camera_offset = Vector3.ZERO
var empty_part_slots: Array = []
var track_belts: Array[Node3D] = []
var engine_shell: Array[Node3D] = []
var yaw = 0.65
var pitch = 0.92
var zoom = 17.8
var roof_closed = false
var turret: Node3D
var barrel: Node3D
var target_angle = 0.0
var pending_shots = 0
var visual_shots = 0
var fired_directions: Array[int] = []
var projectiles: Array = []
var recoil = 0.0
var old_shots = 0
var playback_only = false
var shot_time = 0.0
var installed_equipment: Array = []
var configured_layout_version = -1
var upgrade_mount: Node3D
var mounted_positions: Dictionary = {}
var mounted_rotations: Dictionary = {}
var equipment_marks: Node3D
var equipment_marks_key = ""
var mounted_models: Dictionary = {}
var equipment_preview: Node3D
var equipment_preview_key = ""
var auxiliary_guns: Array = []
var feedback: Node3D
var vehicle_part_visuals: Node3D
var vehicle_part_signature = ""
var installed_rarities: Dictionary = {}
const EXTERIOR_MOUNT_SCALE = 1.3
var vehicle_parts: Dictionary = {}

func configure_vehicle_parts(parts: Dictionary, empty_slots: Array = []):
	var signature = str(parts)+str(empty_slots)
	if signature == vehicle_part_signature: return
	vehicle_part_signature = signature
	vehicle_parts = parts.duplicate(true)
	empty_part_slots = empty_slots.duplicate()
	barrel.visible = "cannon" not in empty_slots
	for belt in track_belts: belt.visible = "tracks" not in empty_slots
	for piece in engine_shell: piece.visible = "engine" not in empty_slots
	if vehicle_part_visuals != null:
		vehicle_part_visuals.get_parent().remove_child(vehicle_part_visuals)
		vehicle_part_visuals.queue_free()
	vehicle_part_visuals = Node3D.new()
	vehicle_part_visuals.name = "VehicleParts"
	turret.get_parent().add_child(vehicle_part_visuals)
	barrel.scale = MAIN_BARREL_SCALE
	if not mats.track.has_meta("part_base_color"): mats.track.set_meta("part_base_color",mats.track.albedo_color)
	mats.track.albedo_color = mats.track.get_meta("part_base_color")
	if parts.has("cannon"):
		var variant = int(F.Gear.Data.ITEMS[parts.cannon.kind].visual)
		barrel.scale = Vector3(1.65,1.35,1.35) if variant == 1 else Vector3(1.1,1.8,1.8) if variant == 2 else MAIN_BARREL_SCALE
		# A colored breech ring follows the actual recoiling main barrel.
		var collar = equipment_models.cylinder(vehicle_part_visuals,Vector3.ZERO,0.43,0.25,F.Gear.RARITIES[parts.cannon.rarity].color)
		collar.name = "MainGunCollar"
		collar.rotation.z = PI/2
		collar.set_meta("follow_barrel",true)
		var fittings = Node3D.new()
		fittings.name = "CannonFittings"
		fittings.set_meta("kind",parts.cannon.kind)
		vehicle_part_visuals.add_child(fittings)
		var rank = F.Gear.RARITIES.keys().find(parts.cannon.rarity)
		for i in range(rank):
			var radiator = equipment_models.cylinder(fittings,Vector3(0.75+i*0.25,0,0),0.48,0.12,"iron")
			radiator.rotation.z = PI/2
		for x in ([1.7,3.1] if variant == 1 else [1.5]):
			var band = equipment_models.cylinder(fittings,Vector3(x,0,0),0.34 if variant != 2 else 0.42,0.18,F.Gear.RARITIES[parts.cannon.rarity].color)
			band.rotation.z = PI/2
		if variant == 1:
			equipment_models.box(fittings,Vector3(3.8,0,0),Vector3(0.5,0.65,0.9),"iron")
			for side in [-1,1]: equipment_models.box(fittings,Vector3(3.8,0,side*0.46),Vector3(0.28,0.25,0.02),"dark")
		elif variant == 2:
			equipment_models.box(fittings,Vector3(0.9,0,0),Vector3(0.6,0.8,1.0),"paint")
	for slot in ["gear","engine"]:
		if not parts.has(slot): continue
		var model = equipment_models.build(parts[slot].kind,parts[slot].rarity)
		vehicle_part_visuals.add_child(model)
		# Rear chassis fittings sit beyond the deck's X=-7 edge, keeping every
		# accessory reservation clear even when its limited-traverse gun turns.
		model.position = Vector3(-8.0,2.1,0) if slot == "engine" else Vector3(-7.9,2.1,3.2)
		model.rotation.y = PI/2
		model.scale = Vector3.ONE*(1.4 if slot == "engine" else 1.25)
	if parts.has("tracks"):
		var item: Dictionary = parts.tracks
		# Tracks retain their base metal; only two small identification plates use quality color.
		var variant = int(F.Gear.Data.ITEMS[item.kind].visual)
		var rank = F.Gear.RARITIES.keys().find(item.rarity)
		for side in [-1,1]:
			for i in range(rank): equipment_models.box(vehicle_part_visuals,Vector3(-4+i*3,3.1,side*6.2),Vector3(1.4,0.22,0.55),"dark")
			for i in range(5):
				var at = Vector3(-5.8+i*2.9,2.4,side*5.95)
				var plate = equipment_models.box(vehicle_part_visuals,at,Vector3(2.2 if variant == 1 else 1.4,0.65 if variant == 1 else 0.35,0.14),F.Gear.RARITIES[item.rarity].color if i == 0 else "paint")
				plate.set_meta("part_kind",item.kind)
				if variant == 2: plate.rotation.z = 0.18
			for i in range(6):
				var tread = equipment_models.box(vehicle_part_visuals,Vector3(-6.2+i*2.4,3.05,side*5.65),Vector3(1.6,0.18,0.9 if variant == 1 else 0.45),"iron")
				tread.set_meta("part_kind",item.kind)
				if variant == 1: equipment_models.box(vehicle_part_visuals,Vector3(-6.2+i*2.4,3.05,side*6.2),Vector3(0.9,0.16,0.4),"iron")
				elif variant == 2: equipment_models.box(vehicle_part_visuals,Vector3(-6.2+i*2.4,3.16,side*5.65),Vector3(1.3,0.1,0.38),"coal")
	if parts.has("gear"):
		var gear: Dictionary = parts.gear
		for side in [-1,1]:
			var housing = equipment_models.cylinder(vehicle_part_visuals,Vector3(-6.5,1.7,side*5.95),0.72 if int(F.Gear.Data.ITEMS[gear.kind].visual) == 2 else 0.5,0.18,F.Gear.RARITIES[gear.rarity].color)
			housing.rotation.x = PI/2
			housing.set_meta("part_kind",gear.kind)
	for slot in empty_slots:
		if slot == "tracks": continue
		var empty = equipment_models.build_empty(slot)
		vehicle_part_visuals.add_child(empty)
		if slot != "cannon":
			empty.position = Vector3(-8.0,2.1,0) if slot == "engine" else Vector3(-7.9,2.1,3.2)
			empty.rotation.y = PI/2
			empty.scale = Vector3.ONE*(1.4 if slot == "engine" else 1.25)
	update_vehicle_part_visuals()

func update_vehicle_part_visuals():
	if vehicle_part_visuals == null: return
	var empty = vehicle_part_visuals.get_node_or_null("Empty_cannon")
	if empty != null: empty.global_transform = barrel.global_transform
	var collar = vehicle_part_visuals.get_node_or_null("MainGunCollar")
	if collar != null:
		collar.global_transform = barrel.global_transform*Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(0.55,0,0))
	var fittings = vehicle_part_visuals.get_node_or_null("CannonFittings")
	if fittings != null: fittings.global_transform = barrel.global_transform

func equipped_model_at(screen_position: Vector2) -> String:
	var candidates: Dictionary = mounted_models.duplicate()
	for gun in auxiliary_guns: candidates[gun.id] = gun.pivot
	if vehicle_part_visuals != null:
		for model in vehicle_part_visuals.get_children():
			var kind: String = model.get_meta("kind",model.get_meta("part_kind",""))
			if kind.is_empty(): continue
			if not candidates.has(kind): candidates[kind] = []
			candidates[kind].append(model)
	if roof_closed and vehicle_parts.has("cannon"): candidates[vehicle_parts.cannon.kind] = turret
	var origin = camera.project_ray_origin(screen_position)
	var direction = camera.project_ray_normal(screen_position)
	var nearest = INF
	var selected_kind = ""
	for kind in candidates:
		var nodes: Array = candidates[kind] if candidates[kind] is Array else [candidates[kind]]
		for node in nodes:
			var distance = model_ray_distance(node,origin,direction)
			if distance < nearest:
				nearest = distance
				selected_kind = kind
	return selected_kind

static func model_ray_distance(node: Node3D, origin: Vector3, direction: Vector3) -> float:
	if not node.is_visible_in_tree(): return INF
	var nearest = INF
	if node is MeshInstance3D:
		var local_origin = node.to_local(origin)
		var local_direction = (node.global_basis.inverse()*direction).normalized()
		var faces = node.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var hit = Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
			if hit != null: nearest = minf(nearest,origin.distance_squared_to(node.to_global(hit)))
	for child in node.get_children():
		if child is Node3D: nearest = minf(nearest,model_ray_distance(child,origin,direction))
	return nearest

func ensure_feedback():
	if feedback == null:
		feedback = preload("res://scripts/feedback_fx.gd").new()
		add_child(feedback)
		feedback.setup(self)

func feedback_effect(kind: String, at: Vector3, strength: float = 1.0):
	ensure_feedback()
	return feedback.burst(kind,at,strength)

func tick_feedback(delta: float):
	if feedback != null: feedback.tick(delta)

func configure_equipment(ids: Array, positions: Dictionary = {}, mounts: Dictionary = {}, rotations: Dictionary = {}, rarities: Dictionary = {}):
	mounted_positions = mounts.duplicate()
	mounted_rotations = rotations.duplicate()
	if installed_equipment == ids and installed_rarities == rarities and configured_layout_version == layout_version:
		position_auxiliary_guns(positions)
		position_mounted_models()
		return
	installed_rarities = rarities.duplicate()
	configured_layout_version = layout_version
	installed_equipment = ids.duplicate()
	if upgrade_mount != null:
		upgrade_mount.get_parent().remove_child(upgrade_mount)
		upgrade_mount.queue_free()
	auxiliary_guns.clear()
	mounted_models.clear()
	upgrade_mount = Node3D.new()
	turret.get_parent().add_child(upgrade_mount)
	for id in F.Content.ALL_GUNS:
		if id not in ids: continue
		if layout_version == 2:
			build_equipment_gun(id)
			continue
		var family = F.Gear.family(id)
		var side = -1 if family == "left_gun" else 1
		var pivot = Node3D.new()
		upgrade_mount.add_child(pivot)
		pivot.position = Vector3(4.4,3.2,side*4.0)
		cylinder(pivot,Vector3.ZERO,0.9,0.25,"turret_dark",24)
		cylinder(pivot,Vector3(0,0.55,0),0.85,0.9,"turret_armor",24,0.7)
		cylinder(pivot,Vector3(0,1.03,0),0.72,0.12,"turret_edge",24)
		var gun_barrel = Node3D.new()
		pivot.add_child(gun_barrel)
		gun_barrel.position = Vector3(0.6,0.65,0)
		beam(gun_barrel,Vector3.ZERO,Vector3(2.1,0,0),0.16,"turret_dark",24)
		beam(gun_barrel,Vector3.ZERO,Vector3(0.8,0,0),0.27,"turret_armor",24)
		beam(gun_barrel,Vector3(1.95,0,0),Vector3(2.1,0,0),0.22,"turret_edge",24)
		if family == "long_gun": beam(gun_barrel,Vector3(2,0,0),Vector3(3.4,0,0),0.13,"turret_dark",24)
		if family == "rapid_gun": beam(gun_barrel,Vector3(0,0,0.25),Vector3(2.1,0,0.25),0.1,"turret_dark",16)
		if family == "mortar_gun": beam(pivot,Vector3(0,0.6,0),Vector3(0.8,2.1,0),0.3,"turret_edge",24)
		if family == "rear_gun": cylinder(pivot,Vector3(0,1.15,0),0.4,0.12,"turret_dark",16)
		if family == "scatter_gun":
			for z in [-0.36,0.36]:
				beam(gun_barrel,Vector3(0,0,z),Vector3(1.8,0,z),0.22,"turret_dark",16)
				beam(gun_barrel,Vector3(1.65,0,z),Vector3(1.9,0,z),0.28,"turret_edge",16)
		if family == "arc_gun":
			for x in [0.55,1.0,1.45]:
				var coil = cylinder(gun_barrel,Vector3(x,0,0),0.34,0.16,"machine_fuel",16)
				coil.rotation.z = PI/2
			for z in [-0.48,0.48]: cylinder(pivot,Vector3(-0.35,1.0,z),0.18,0.7,"machine_bronze",12)
		var flash = box(gun_barrel,Vector3(3.65 if family == "long_gun" else 2.35,0,0),Vector3(0.7,0.35,0.35),"arc_light" if family == "arc_gun" else "fire")
		if family == "scatter_gun":
			for z in [-0.36,0.36]: box(flash,Vector3(-0.3,0,z),Vector3(0.55,0.27,0.27),"fire")
		flash.visible = false
		if layout_version == 2: equipment_markings(pivot,id,1.10,Vector2(1.05,0.5))
		if layout_version == 2: solid_mounted_materials(pivot)
		auxiliary_guns.append({"id":id,"pivot":pivot,"barrel":gun_barrel,"muzzle":flash,"cooldown":0.0,"flash":0.0,"recoil":0.0})
	if layout_version == 2:
		for id in ids:
			if id in F.Content.ALL_GUNS: continue
			var model = Node3D.new()
			model.name = "Mounted_"+id
			upgrade_mount.add_child(model)
			mounted_models[id] = model
			build_mounted_model(model,id)
			solid_mounted_materials(model)
		position_auxiliary_guns(positions)
		position_mounted_models()
		return
	if "armor" in ids:
		for side in [-1,1]:
			for x in [-4,-1,2]:
				armor_block(upgrade_mount,Vector3(x,2.2,side*4.7),Vector3(2.6,1.3,0.3),0.12,"turret_armor")
				for dx in [-0.9,0.9]: box(upgrade_mount,Vector3(x+dx,2.2,side*4.9),Vector3(0.12,0.12,0.08),"turret_edge")
	if "rangefinder" in ids:
		beam(upgrade_mount,Vector3(1,6.5,-1.4),Vector3(1,6.5,1.4),0.18,"turret_edge",16)
	if "servo" in ids: cylinder(upgrade_mount,Vector3(2.6,4.1,0),3.6,0.18,"turret_edge",32)
	if "supercharger" in ids:
		for z in [-1,1]: cylinder(upgrade_mount,Vector3(-5,3.3,z),0.45,0.8,"turret_dark",20)
	if "economizer" in ids:
		for x in [-5.8,-5.4,-5.0]: box(upgrade_mount,Vector3(x,3.3,2.8),Vector3(0.16,0.8,1.4),"turret_edge")
	if "salvage_arm" in ids:
		beam(upgrade_mount,Vector3(-4,3.0,-3),Vector3(-4,5.4,-3),0.16,"turret_edge",16)
		beam(upgrade_mount,Vector3(-4,5.4,-3),Vector3(-6,4.7,-4),0.16,"turret_armor",16)
	if "skirts" in ids:
		for z in [-5.1,5.1]: armor_block(upgrade_mount,Vector3(0,1.7,z),Vector3(11,0.7,0.18),0.06,"turret_dark")
	if "blast_fuse" in ids:
		for x in [-1.8,-1.3,-0.8]:
			cylinder(upgrade_mount,Vector3(x,3.5,-3.6),0.18,0.65,"machine_hot",12)
	if "drum_loader" in ids:
		for z in [-1.3,1.3]:
			var drum = cylinder(upgrade_mount,Vector3(0.1,4.6,z),0.5,0.75,"turret_dark",16)
			drum.rotation.x = PI/2
	position_auxiliary_guns(positions)

func position_auxiliary_guns(positions: Dictionary):
	var tiers = MountLayout.tiers(positions,main_gun_anchor)
	for gun in auxiliary_guns:
		if positions.has(gun.id):
			var at = cell_position(positions[gun.id])
			gun.pivot.position = Vector3(at.x,3.2,at.z)
			if layout_version == 2:
				var facing = -int(mounted_rotations.get(gun.id,0))*PI/2
				if not is_equal_approx(gun.get("rest_yaw",0.0),facing): gun.pivot.rotation.y = facing
				gun.rest_yaw = facing
				gun.tier = tiers.get(gun.id,0)
				var height = MountLayout.UPPER_Y if gun.tier == 1 else (4.18 if roof_closed else DECK_Y+MOUNTED_GUN_Y)
				gun.pivot.position = Vector3(at.x+0.5,height,at.z+0.5)
				gun.pivot.position += Vector3(gun.mount_offset.x,0,gun.mount_offset.y).rotated(Vector3.UP,facing)*MountLayout.GUN_SCALE
				var factor: float = gun.mount_scale*MountLayout.GUN_SCALE
				gun.pivot.scale = Vector3(factor,MountLayout.GUN_HEIGHT/gun.model_height,factor)
				gun.pivot.rotation.y = clamp_gun_angle(gun,gun.pivot.rotation.y)
				gun.riser.visible = gun.tier == 1
				gun.riser.position = Vector3(gun.pivot.position.x,(height+DECK_Y)*0.5,gun.pivot.position.z)
				gun.riser.scale.y = height-DECK_Y

static func clamp_gun_angle(gun: Dictionary, angle: float) -> float:
	if not gun.has("half_arc"): return angle
	var rest: float = gun.get("rest_yaw",0.0)
	return rest+clampf(angle_difference(rest,angle),-gun.half_arc,gun.half_arc)

func build_equipment_gun(id: String):
	var pivot = equipment_models.build(id,installed_rarities.get(id,"normal"))
	upgrade_mount.add_child(pivot)
	var gun_barrel: Node3D = pivot.get_node("Barrel")
	var tip: Vector3 = pivot.get_meta("muzzle")
	var flash = box(gun_barrel,tip-Vector3(EquipmentModels.BARREL_REST,0,0),Vector3(0.45,0.28,0.28),"arc_light" if F.Gear.family(id) == "arc_gun" else "fire")
	flash.visible = false
	var mount = equipment_models.weapon_mount(pivot,id)
	var height = 0.0
	for point in EquipmentModels.vertices(pivot): height = maxf(height,point.y)
	var riser = cylinder(upgrade_mount,Vector3.ZERO,0.26,1.0,"turret_dark",12)
	auxiliary_guns.append({"id":id,"pivot":pivot,"barrel":gun_barrel,"muzzle":flash,"riser":riser,"tier":0,"mount_scale":mount.scale,"mount_offset":mount.offset,"half_arc":mount.half_arc,"model_height":height,"cooldown":0.0,"flash":0.0,"recoil":0.0})

func material(name: String, color: String, metal: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 1.0
	m.metallic = 0.0
	if glow > 0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = glow
	mats[name] = m
	return m

func box(parent: Node3D, pos: Vector3, size_value: Vector3, mat: String) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size_value
	return mesh_node(parent,mesh,pos,mat)

func armor_block(parent: Node3D, pos: Vector3, size_value: Vector3, bevel: float, mat: String) -> MeshInstance3D:
	# Four octagonal rings bevel every edge while retaining the shared cutaway material.
	var half = size_value/2
	var cut = minf(bevel,minf(half.x,minf(half.y,half.z))*0.8)
	var rings: Array = []
	for level in range(4):
		var inset = cut if level in [0,3] else 0.0
		var x = half.x-inset
		var z = half.z-inset
		var c = cut*0.5 if level in [0,3] else cut
		var y = [-half.y,-half.y+cut,half.y-cut,half.y][level]
		var outline = [Vector2(-x,-z+c),Vector2(-x+c,-z),Vector2(x-c,-z),Vector2(x,-z+c),Vector2(x,z-c),Vector2(x-c,z),Vector2(-x+c,z),Vector2(-x,z-c)]
		var ring = PackedVector3Array()
		for p in outline: ring.append(Vector3(p.x,y,p.y))
		rings.append(ring)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for level in range(3):
		for i in range(8):
			var next = (i+1)%8
			for v in [rings[level][i],rings[level][next],rings[level+1][next],rings[level][i],rings[level+1][next],rings[level+1][i]]: surface.add_vertex(v)
	for level in [0,3]:
		for i in range(1,7):
			for index in ([0,i,i+1] if level == 0 else [0,i+1,i]): surface.add_vertex(rings[level][index])
	surface.generate_normals()
	return mesh_node(parent,surface.commit(),pos,mat)

func rivets(parent: Node3D, transforms: Array[Transform3D], mat: String, radius: float = 0.065):
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius*0.75
	mesh.bottom_radius = radius
	mesh.height = radius*0.8
	mesh.radial_segments = 8
	var instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = transforms.size()
	for i in transforms.size(): instances.set_instance_transform(i,transforms[i])
	var node = MultiMeshInstance3D.new()
	node.multimesh = instances
	node.material_override = mats[mat]
	if mat.begins_with("turret_"): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if roof_closed else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

func mesh_node(parent: Node3D, mesh: Mesh, pos: Vector3, mat: String) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mats[mat]
	node.position = pos
	if mat.begins_with("turret_"): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if roof_closed else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: String, sides: int = 10, top: float = -1) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = clampi(sides,3,32)
	return mesh_node(parent,mesh,pos,mat)

func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: String, sides: int = 8):
	var node = cylinder(parent,(a+b)/2,radius,a.distance_to(b),mat,sides)
	var direction = (b-a).normalized()
	node.quaternion = Quaternion(Vector3.UP,direction)
	return node

func prism(parent: Node3D, outline: PackedVector2Array, bottom: float, top: float, mat: String) -> MeshInstance3D:
	# Extruded polygon in X/Z with hard normals for a low-poly silhouette.
	var vertices = PackedVector3Array()
	var ids = Geometry2D.triangulate_polygon(outline)
	for i in range(0,ids.size(),3):
		for j in [0,2,1]:
			var p = outline[ids[i+j]]
			vertices.append(Vector3(p.x,top,p.y))
		for j in [0,1,2]:
			var p = outline[ids[i+j]]
			vertices.append(Vector3(p.x,bottom,p.y))
	for i in outline.size():
		var a = outline[i]
		var b = outline[(i+1)%outline.size()]
		var corners = [Vector3(a.x,bottom,a.y),Vector3(b.x,bottom,b.y),Vector3(b.x,top,b.y),Vector3(a.x,top,a.y)]
		for j in [0,1,2,0,2,3]: vertices.append(corners[j])
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in vertices: st.add_vertex(v)
	st.generate_normals()
	var node = mesh_node(parent,st.commit(),Vector3.ZERO,mat)
	# Explicit double-sided armor surfaces also avoid vanishing cutaway interiors.
	var double = mats[mat].duplicate()
	double.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = double
	return node

func _ready():
	material("armor","656449",0.28)
	material("edge","85816a",0.25)
	material("dark","292c26",0.4)
	material("track","3a3a32",0.45)
	material("steel","89978e",0.5)
	material("pipe","343c35",0.2)
	material("pipe_joint","596052",0.25)
	material("pipe_cover","4c5547",0.25)
	material("machine_iron","697365",0.3)
	material("machine_hot","675c48",0.25)
	material("machine_fuel","51695e",0.25)
	material("machine_bronze","837b56",0.35)
	material("brass","bb9750",0.55)
	material("wood","655038")
	material("floor","4b5045",0.2)
	material("floor2","515648",0.2)
	material("rust","955f3e",0.25)
	material("coal","322d25")
	material("fire","ee9f47",0.1,1.8)
	material("arc_light","91b9a4",0,0.55)
	material("shell","d3ac5b",0.6)
	material("tip","d8c9a0",0.6)
	material("mud","44483c")
	material("stone","696553")
	material("mark","dfd3a6")
	material("green","acb977",0,0.3)
	material("red","c26a48",0,0.3)
	material("inlet","70d4cc",0,0.25)
	material("outlet","ffcf65",0,0.25)
	material("fuel","5b9b99")
	for spec in [["turret_armor","6b7057",0.12],["turret_edge","8b8d6f",0.18],["turret_dark","41493c",0.22]]:
		var translucent = material(spec[0],spec[1])
		translucent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		translucent.albedo_color.a = spec[2]
		translucent.set_meta("interior_alpha",spec[2])

	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("3b3c32")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d2c9a8")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_color = Color("f0e7d5")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35,145,0)
	fill.light_color = Color("98aba9")
	fill.light_energy = 0.3
	add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 150
	add_child(camera)
	camera.current = true
	update_camera()
	terrain()
	tank()
	equipment = Node3D.new()
	add_child(equipment)
	goods = Node3D.new()
	add_child(goods)
	marker = box(self,Vector3(0,DECK_Y+0.02,0),Vector3(0.94,0.025,0.94),"green")
	marker.visible = false
	placement_preview = Node3D.new()
	add_child(placement_preview)
	placement_preview.visible = false
	for id in ["valid","invalid","arrow","blocked_arrow"]:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color("a8c58a") if id == "valid" else Color("bcc1a9") if id == "arrow" else Color("e87555")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 20 if "arrow" in id else 10
		if "arrow" not in id:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.28
		preview_materials[id] = mat

func update_camera():
	var target = Vector3(0,1.7,0)+camera_offset
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*34
	camera.look_at(target,Vector3.UP)
	camera.size = zoom

func pan_camera(axis: Vector2, delta: float):
	var right = Vector3(cos(yaw),0,-sin(yaw))
	var back = Vector3(sin(yaw),0,cos(yaw))
	camera_offset = (camera_offset+(right*axis.x+back*axis.y)*zoom*0.55*delta).clamp(Vector3(-20,0,-20),Vector3(20,0,20))
	update_camera()

func cell_position(p: Vector2i) -> Vector3:
	return Vector3(p.x-6.5,DECK_Y,p.y-3.5)

func screen_cell(local: Vector2) -> Vector2i:
	if roof_closed: return Vector2i(-1,-1)
	var plane = Plane(Vector3.UP,DECK_Y+0.03)
	var hit = plane.intersects_ray(camera.project_ray_origin(local),camera.project_ray_normal(local))
	if hit == null: return Vector2i(-1,-1)
	return Vector2i(int(floor(hit.x+7)),int(floor(hit.z+4)))

func toggle_roof():
	roof_closed = not roof_closed
	roof.visible = roof_closed
	# Give the exterior turret and secondary guns height without widening their
	# reserved footprints. The elevated main barrel sweeps safely above them.
	turret.scale.y = 1.25 if roof_closed else 1.0
	for key in ["turret_armor","turret_edge","turret_dark"]:
		var mat: StandardMaterial3D = mats[key]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if roof_closed else BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 1.0 if roof_closed else float(mat.get_meta("interior_alpha"))
		for geometry in find_children("*","GeometryInstance3D",true,false):
			if geometry.material_override == mat:
				geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if roof_closed else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	placement_preview.visible = false
	if layout_version == 2:
		position_auxiliary_guns(mounted_positions)
		position_mounted_models()
		if equipment != null: equipment.visible = not roof_closed
		if goods != null: goods.visible = not roof_closed

func terrain():
	box(self,Vector3(0,-0.27,0),Vector3(100,0.3,100),"mud")
	var rng = RandomNumberGenerator.new()
	rng.seed = 1918
	for i in range(12):
		var x = rng.randf_range(-24,24)
		var z = rng.randf_range(-17,17)
		if absf(x) < 10 and absf(z) < 7: continue
		var rock = cylinder(self,Vector3(x,-0.04,z),rng.randf_range(0.09,0.32),0.13,"stone",5,0.08)
		rock.rotation.y = rng.randf()*TAU
	for z in [-5.1,5.1]:
		for x in range(-16,-9): box(self,Vector3(x*0.85,-0.09,z),Vector3(0.13,0.035,1.05),"coal")
	for i in range(3):
		var board = box(self,Vector3(-11+i*0.65,0.0,8),Vector3(0.46,0.15,2.4),"wood")
		board.rotation.y = 0.05*sin(i)
	for i in range(1):
		var p = Vector3(-9+i*1.25,0.46,-8)
		box(self,p,Vector3(1,0.9,0.85),"wood")
		for dz in [-0.34,0.34]: box(self,p+Vector3(0,0,dz),Vector3(1.04,0.95,0.06),"dark")

func tank():
	var outline = PackedVector2Array([Vector2(-8.5,-3.1),Vector2(-7,-4.5),Vector2(6.7,-4.5),Vector2(8.6,-2.9),Vector2(8.6,2.9),Vector2(6.7,4.5),Vector2(-7,4.5),Vector2(-8.5,3.1)])
	prism(self,outline,0.7,DECK_Y-0.04,"armor")
	for side in [-1,1]: track(side)
	# Exposed steel deck: same 14x8 usable grid as the simulation.
	for y in F.H:
		for x in F.W:
			box(self,cell_position(Vector2i(x,y))+Vector3(0,-0.04,0),Vector3(0.97,0.08,0.97),"floor" if (x+y)%2 == 0 else "floor2")
	for z in [-4.2,4.2]:
		box(self,Vector3(0,DECK_Y+0.15,z),Vector3(14.4,0.3,0.25),"armor")
		box(self,Vector3(0,DECK_Y+0.32,z),Vector3(14.6,0.08,0.3),"edge")

	var before_engine = get_child_count()
	# A rear engine compartment, exhaust stacks and front driver's armored cabin.
	armor_block(self,Vector3(-7.85,3.0,0),Vector3(1.55,1.0,6.0),0.18,"armor")
	for z in [-1.8,1.8]:
		cylinder(self,Vector3(-7.85,3.8,z),0.18,1.4,"dark",20)
		cylinder(self,Vector3(-7.85,3.62,z),0.29,0.4,"rust",20)
		for y in [3.46,3.8,4.43]: cylinder(self,Vector3(-7.85,y,z),0.23,0.1,"steel",20)
		cylinder(self,Vector3(-7.85,4.49,z),0.13,0.03,"coal",20)
	for z in [-0.7,0.7]:
		armor_block(self,Vector3(-7.85,3.53,z),Vector3(1.05,0.15,0.9),0.05,"edge")
		for x in [-8.15,-7.9,-7.65]: box(self,Vector3(x,3.62,z),Vector3(0.09,0.04,0.65),"dark")
	for i in range(before_engine,get_child_count()): engine_shell.append(get_child(i))
	# Beveled driver's housing, individual vision ports and a bolted front plate.
	armor_block(self,Vector3(7.6,3.13,0),Vector3(1.85,0.82,3.7),0.16,"armor")
	for z in [-0.85,0.85]:
		armor_block(self,Vector3(8.53,3.22,z),Vector3(0.12,0.34,0.95),0.04,"edge")
		box(self,Vector3(8.6,3.22,z),Vector3(0.035,0.11,0.66),"dark")
	armor_block(self,Vector3(8.61,1.85,0),Vector3(0.18,1.12,4.5),0.06,"armor")
	var front_bolts: Array[Transform3D] = []
	for z in [-1.9,-0.95,0.0,0.95,1.9]:
		for y in [1.45,2.24]: front_bolts.append(Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(8.72,y,z)))
	rivets(self,front_bolts,"edge",0.09)
	for z in [-2.7,2.7]:
		armor_block(self,Vector3(8.45,1.3,z),Vector3(0.5,0.34,0.4),0.07,"edge")
		beam(self,Vector3(8.65,1.3,z-0.2),Vector3(8.65,1.3,z+0.2),0.12,"dark",16)
	# A translucent, enlarged turret above the forward half of the factory deck.
	build_turret()
	roof = Node3D.new()
	add_child(roof)
	armor_block(roof,Vector3(0,3.9,0),Vector3(14.1,0.24,8.15),0.08,"dark")
	var roof_bolts: Array[Transform3D] = []
	for x in [-5.6,-2.8,0.0,2.8,5.6]:
		armor_block(roof,Vector3(x,4.035,0),Vector3(2.72,0.13,7.98),0.035,"armor")
		for z in [-3.7,3.7]:
			for dx in [-1.1,0.0,1.1]: roof_bolts.append(Transform3D(Basis.IDENTITY,Vector3(x+dx,4.12,z)))
	rivets(roof,roof_bolts,"edge",0.075)
	armor_block(roof,Vector3(-3,4.18,0),Vector3(1.85,0.18,1.55),0.07,"edge")
	armor_block(roof,Vector3(-3,4.29,0),Vector3(1.56,0.09,1.28),0.03,"armor")
	for z in [-0.52,0.52]: beam(roof,Vector3(-3.86,4.3,z-0.13),Vector3(-3.86,4.3,z+0.13),0.09,"steel",12)
	beam(roof,Vector3(-2.65,4.38,-0.28),Vector3(-2.65,4.38,0.28),0.06,"dark",12)
	for z in [-2.3,2.3]:
		armor_block(roof,Vector3(-3.75,4.16,z),Vector3(2.6,0.16,1.65),0.05,"edge")
		box(roof,Vector3(-3.75,4.25,z),Vector3(2.35,0.035,1.4),"dark")
		for i in range(7):
			var louver = box(roof,Vector3(-4.8+i*0.35,4.32,z),Vector3(0.22,0.07,1.32),"armor")
			louver.rotation.z = -0.3
		for x in [-5.8,-1.5]:
			armor_block(roof,Vector3(x,4.28,z),Vector3(1.05,0.34,1.55),0.09,"armor")
			box(roof,Vector3(x,4.47,z),Vector3(0.1,0.06,1.4),"edge")
	roof.visible = false

func track_shoe_mesh() -> ArrayMesh:
	# Chamfered shoe plus a raised transverse grouser, shared by every player link.
	var outline = PackedVector2Array([Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.15),Vector2(0.35,0.5),Vector2(-0.35,0.5),Vector2(-0.5,0.15)])
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ids = Geometry2D.triangulate_polygon(outline)
	for z in [-0.5,0.5]:
		for i in range(0,ids.size(),3):
			for j in ([0,1,2] if z < 0 else [0,2,1]):
				var p = outline[ids[i+j]]
				surface.add_vertex(Vector3(p.x,p.y,z))
	for i in outline.size():
		var a = outline[i]
		var b = outline[(i+1)%outline.size()]
		var corners = [Vector3(a.x,a.y,-0.5),Vector3(a.x,a.y,0.5),Vector3(b.x,b.y,0.5),Vector3(b.x,b.y,-0.5)]
		for j in [0,1,2,0,2,3]: surface.add_vertex(corners[j])
	surface.generate_normals()
	var mesh = surface.commit()
	var rib = BoxMesh.new()
	rib.size = Vector3(0.3,0.6,1.04)
	var rib_surface = SurfaceTool.new()
	rib_surface.append_from(rib,0,Transform3D(Basis.IDENTITY,Vector3(0,0.7,0)))
	rib_surface.commit(mesh)
	return mesh

func track_links(parent: Node3D, profile: PackedVector2Array, z: float, width: float, spacing: float, detailed: bool = false):
	# One instanced mesh per track keeps the extra tread geometry inexpensive.
	var transforms: Array[Transform3D] = []
	for i in profile.size():
		var a = profile[i]
		var b = profile[(i+1)%profile.size()]
		var count = maxi(1,ceili(a.distance_to(b)/spacing))
		var step = a.distance_to(b)/count
		var direction = (b-a).normalized()
		var normal = Vector2(-direction.y,direction.x)
		var thickness = 0.16 if detailed else spacing*0.22
		var basis = Basis(Vector3.FORWARD,-atan2(direction.y,direction.x)).scaled_local(Vector3(step*0.9 if detailed else step*0.84,thickness,width))
		for j in range(count):
			var at = a.lerp(b,(j+0.5)/count)+normal*(0.11 if detailed else spacing*0.08)
			transforms.append(Transform3D(basis,Vector3(at.x,at.y,z)))
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	var instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = track_shoe_mesh() if detailed else mesh
	instances.instance_count = transforms.size()
	for i in transforms.size(): instances.set_instance_transform(i,transforms[i])
	var links = MultiMeshInstance3D.new()
	links.multimesh = instances
	links.material_override = mats.track
	parent.add_child(links)

func track(side: int):
	var corners = PackedVector2Array([Vector2(-9,1),Vector2(-7.3,3.4),Vector2(6.9,3.4),Vector2(9,1.45),Vector2(7,0.25),Vector2(-7.7,0.25)])
	var profile = PackedVector2Array()
	# Round each bend without losing the long, rhomboid WW1 silhouette.
	for i in corners.size():
		var corner = corners[i]
		var start = corner+(corners[(i+corners.size()-1)%corners.size()]-corner).normalized()*0.65
		var end = corner+(corners[(i+1)%corners.size()]-corner).normalized()*0.65
		for step in range(6):
			var t = step/5.0
			profile.append(start.lerp(corner,t).lerp(corner.lerp(end,t),t))
	# Recessed inner housing leaves real depth behind the armor and running gear.
	var plate = prism(self,profile,side*5.54-0.1,side*5.54+0.1,"dark")
	plate.rotation.x = PI/2
	plate.scale.z = -1
	track_housing(side,profile)
	var belts = Node3D.new()
	belts.name = "TrackBelt"+str(side)
	add_child(belts)
	track_belts.append(belts)
	# Continuous backing under the individually spaced tread links.
	for i in profile.size():
		var a = profile[i]
		var b = profile[(i+1)%profile.size()]
		var midpoint = (a+b)/2
		var tread = box(belts,Vector3(midpoint.x,midpoint.y,side*5.05),Vector3(a.distance_to(b),0.18,1.2),"track")
		tread.rotation.z = atan2(b.y-a.y,b.x-a.x)
	track_links(belts,profile,side*5.05,1.28,0.52,true)
	for i in range(5):
		var wheel = cylinder(self,Vector3(-5.8+i*2.9,1.32,side*5.83),0.72,0.18,"dark",24)
		wheel.rotation.x = PI/2
		var rim = cylinder(self,Vector3(-5.8+i*2.9,1.32,side*5.94),0.55,0.08,"track",24)
		rim.rotation.x = PI/2
		var hub = cylinder(self,Vector3(-5.8+i*2.9,1.32,side*6.02),0.25,0.14,"edge",16)
		hub.rotation.x = PI/2
		for bolt_index in range(6):
			var angle = bolt_index*TAU/6
			var bolt = cylinder(self,Vector3(-5.8+i*2.9+cos(angle)*0.4,1.32+sin(angle)*0.4,side*6.0),0.055,0.07,"steel",8)
			bolt.rotation.x = PI/2
	for x in [-7.65,7.65]:
		var sprocket = cylinder(self,Vector3(x,1.35,side*5.86),0.63,0.2,"dark",24)
		sprocket.rotation.x = PI/2
		var axle = cylinder(self,Vector3(x,1.35,side*6.0),0.3,0.12,"edge",16)
		axle.rotation.x = PI/2
		for tooth in range(12):
			var angle = tooth*TAU/12
			var lug = box(self,Vector3(x+cos(angle)*0.62,1.35+sin(angle)*0.62,side*5.87),Vector3(0.18,0.18,0.22),"track")
			lug.rotation.z = angle
	box(self,Vector3(-4.0,2.52,side*5.89),Vector3(0.3,0.62,0.04),"mark")

func track_housing(side: int, profile: PackedVector2Array):
	# Raised perimeter, separate service panels and suspension cast their own shadows.
	var center = Vector2(0,1.8)
	for i in profile.size():
		var a = center+(profile[i]-center)*Vector2(0.98,0.87)
		var b = center+(profile[(i+1)%profile.size()]-center)*Vector2(0.98,0.87)
		var midpoint = (a+b)/2
		var rim = box(self,Vector3(midpoint.x,midpoint.y,side*5.77),Vector3(a.distance_to(b)+0.025,0.12,0.19),"armor")
		rim.rotation.z = atan2(b.y-a.y,b.x-a.x)
	box(self,Vector3(0,2.02,side*5.78),Vector3(13.9,0.16,0.22),"armor")
	for i in range(5):
		var x = -5.8+i*2.9
		box(self,Vector3(x,2.57,side*5.74),Vector3(2.62,0.83,0.2),"armor")
		box(self,Vector3(x,2.94,side*5.87),Vector3(2.64,0.07,0.09),"edge")
		# Overlapping leaf springs sit between the longitudinal rail and axle arm.
		for leaf in range(4):
			box(self,Vector3(x,1.86-leaf*0.065,side*5.87),Vector3(1.65-leaf*0.22,0.045,0.2),"track")
		beam(self,Vector3(x-0.54,1.94,side*5.91),Vector3(x,1.32,side*5.91),0.12,"armor",8)
		box(self,Vector3(x-0.55,1.96,side*5.93),Vector3(0.28,0.3,0.18),"edge")
		for dx in [-1.12,1.12]:
			for y in [2.3,2.82]:
				var rivet = cylinder(self,Vector3(x+dx,y,side*5.87),0.065,0.07,"edge",8)
				rivet.rotation.x = PI/2
	for i in range(4):
		var x = -4.35+i*2.9
		var brace = box(self,Vector3(x,1.28,side*5.75),Vector3(0.17,1.35,0.16),"armor")
		brace.rotation.z = -0.22

func set_layout_version(version: int):
	layout_version = version
	if equipment != null: equipment.visible = version != 2 or not roof_closed
	if goods != null: goods.visible = version != 2 or not roof_closed
	var grid = cell_position(main_gun_anchor)
	var center = Vector3(grid.x+0.5,4.08,grid.z+0.5) if version == 2 else TURRET_CENTER
	if turret != null: turret.position = center
	if turret_base != null: turret_base.position = center-Vector3(0,0.04,0)

func configure_main_gun(at: Vector2i):
	if main_gun_anchor == at: return
	main_gun_anchor = at
	set_layout_version(layout_version)
	position_auxiliary_guns(mounted_positions)
	rendered_layout = ""

func build_turret():
	turret_base = cylinder(self,TURRET_CENTER-Vector3(0,0.04,0),3.55,0.32,"turret_dark",32)
	turret = Node3D.new()
	turret.position = TURRET_CENTER
	add_child(turret)
	set_layout_version(layout_version)
	cylinder(turret,Vector3(0,0.9,0),3.4,1.8,"turret_armor",24,3.15)
	cylinder(turret,Vector3(0,0.12,0),3.42,0.16,"turret_edge",24,3.38)
	cylinder(turret,Vector3(0,1.82,0),3.2,0.16,"turret_edge",24,3.1)
	cylinder(turret,Vector3(0,1.91,0),3.08,0.08,"turret_armor",24)
	var turret_bolts: Array[Transform3D] = []
	for i in range(24):
		var angle = (i+0.5)*TAU/24
		var radial = Vector3(cos(angle),0,sin(angle))
		for y in [0.3,1.55]:
			var radius = 3.4-y/1.8*0.25
			turret_bolts.append(Transform3D(Basis(Quaternion(Vector3.UP,radial)),radial*radius+Vector3(0,y,0)))
		if i%3 == 0:
			beam(turret,radial*3.36+Vector3(0,0.22,0),radial*3.17+Vector3(0,1.65,0),0.035,"turret_dark",8)
			turret_bolts.append(Transform3D(Basis.IDENTITY,radial*2.86+Vector3(0,1.97,0)))
	rivets(turret,turret_bolts,"turret_edge",0.075)
	# Cupola, observation slits, hatch hinges and a separate service hatch.
	cylinder(turret,Vector3(-0.85,2.17,0),0.86,0.44,"turret_armor",24)
	cylinder(turret,Vector3(-0.85,2.43,0),0.91,0.12,"turret_edge",24,0.84)
	cylinder(turret,Vector3(-0.85,2.51,0),0.74,0.06,"turret_armor",24)
	for i in range(8):
		var angle = i*TAU/8
		var slit = box(turret,Vector3(-0.85+cos(angle)*0.85,2.22,sin(angle)*0.85),Vector3(0.045,0.12,0.37),"turret_dark")
		slit.rotation.y = -angle
	for z in [-0.48,0.48]: beam(turret,Vector3(-1.55,2.53,z-0.12),Vector3(-1.55,2.53,z+0.12),0.08,"turret_edge",12)
	beam(turret,Vector3(-0.6,2.62,-0.23),Vector3(-0.6,2.62,0.23),0.055,"turret_dark",12)
	armor_block(turret,Vector3(0.7,2.01,-1.25),Vector3(1.2,0.14,0.95),0.05,"turret_edge")
	armor_block(turret,Vector3(0.7,2.1,-1.25),Vector3(1.02,0.07,0.77),0.025,"turret_armor")
	beam(turret,Vector3(0.7,2.19,-1.46),Vector3(0.7,2.19,-1.04),0.05,"turret_dark",12)
	for z in [-1.9,1.9]:
		beam(turret,Vector3(-1.65,2.02,z),Vector3(-1.65,2.24,z),0.055,"turret_edge",12)
		beam(turret,Vector3(-0.55,2.02,z),Vector3(-0.55,2.24,z),0.055,"turret_edge",12)
		beam(turret,Vector3(-1.65,2.24,z),Vector3(-0.55,2.24,z),0.055,"turret_edge",12)
	armor_block(turret,Vector3(3.12,MAIN_BARREL_HEIGHT,0),Vector3(0.8,1.35,1.7),0.16,"turret_armor")
	barrel = Node3D.new()
	barrel.position = Vector3(BARREL_REST,MAIN_BARREL_HEIGHT,0)
	barrel.scale = MAIN_BARREL_SCALE
	turret.add_child(barrel)
	beam(barrel,Vector3.ZERO,Vector3(4.0,0,0),0.25,"turret_dark",24)
	var sleeve = cylinder(barrel,Vector3(0.5,0,0),0.45,1.5,"turret_armor",24,0.34)
	sleeve.rotation.z = -PI/2
	for x in [1.2,2.3]:
		var band = cylinder(barrel,Vector3(x,0,0),0.29,0.14,"turret_edge",24)
		band.rotation.z = -PI/2
	beam(barrel,Vector3(0.4,0.47,0),Vector3(2.35,0.47,0),0.14,"turret_armor",16)
	beam(barrel,Vector3(2.35,0.47,0),Vector3(2.65,0.47,0),0.07,"turret_edge",16)
	for x in [1.25,2.25]: armor_block(barrel,Vector3(x,0.28,0),Vector3(0.14,0.45,0.38),0.035,"turret_edge")
	var muzzle_rim = cylinder(barrel,Vector3(3.95,0,0),0.3,0.18,"turret_edge",24)
	muzzle_rim.rotation.z = -PI/2
	var bore = cylinder(barrel,Vector3(4.045,0,0),0.215,0.012,"turret_dark",24)
	bore.rotation.z = -PI/2
	muzzle = cylinder(barrel,Vector3(4.25,0,0),0.42,0.7,"fire",4,0.05)
	muzzle.rotation.z = -PI/2
	muzzle.visible = false

func fire_visual():
	if "cannon" in empty_part_slots: return
	var direction = Vector3(cos(turret.rotation.y),0,-sin(turret.rotation.y))
	var origin = muzzle.global_position
	var shot = Node3D.new()
	add_child(shot)
	shot.global_position = origin
	beam(shot,Vector3.ZERO,-direction*3.06,0.204,"fire")
	projectiles.append({"node":shot,"origin":origin,"dir":direction,"age":0.0})
	recoil = 0.25
	shot_time = 0.14
	fired_directions.append(visual_shots%4)
	if fired_directions.size() > 32: fired_directions.pop_front()
	visual_shots += 1
	target_angle = fposmod(visual_shots*PI/2,TAU)

func update_gun(factory, delta: float):
	if playback_only: return
	if factory.shots < old_shots:
		pending_shots = 0
		visual_shots = 0
		fired_directions.clear()
		target_angle = 0
		turret.rotation.y = 0
		shot_time = 0
		recoil = 0
		for shot in projectiles: shot.node.queue_free()
		projectiles.clear()
	pending_shots += maxi(0,factory.shots-old_shots)
	old_shots = factory.shots
	var dt = delta if factory.running else 0.0
	turret.rotation.y = rotate_toward(turret.rotation.y,target_angle,dt*4.8)
	recoil = maxf(0,recoil-dt*0.95)
	barrel.position.x = BARREL_REST-recoil
	shot_time = maxf(0,shot_time-dt)
	if factory.running and pending_shots > 0 and absf(angle_difference(turret.rotation.y,target_angle)) < 0.025:
		pending_shots -= 1
		fire_visual()
	muzzle.visible = shot_time > 0
	for shot in projectiles.duplicate():
		shot.age += dt
		shot.node.global_position = shot.origin+shot.dir*shot.age*18.0+Vector3(0,-1.2*shot.age*shot.age,0)
		if shot.age > 0.85:
			shot.node.queue_free()
			projectiles.erase(shot)

func directional_cover(parent: Node3D, height: float, compact: bool = false):
	# Folded access plates: their overlapping seams converge toward the outlet.
	# Branches keep each cover on its own arm, clear of the central manifold.
	var half_width = 0.12 if compact else 0.27
	var fold = 0.09 if compact else 0.16
	var depth = 0.08 if compact else 0.14
	var centers = [0.18,0.32] if compact else [-0.10,0.14]
	for x in centers:
		var outline = PackedVector2Array([
			Vector2(x-depth,-half_width),Vector2(x,-half_width),
			Vector2(x+fold,0),Vector2(x,half_width),
			Vector2(x-depth,half_width),Vector2(x+fold-depth,0)])
		prism(parent,outline,height,height+0.035,"pipe_cover")
		for side in [-1,1]:
			cylinder(parent,Vector3(x-depth*0.5,height+0.04,side*(half_width-0.025)),0.018,0.012,"pipe_joint",6)

func flow_ports(kind: String, parent: Node3D, inputs: Array):
	var outlets: Array = [] if kind in ["gun","engine"] or F.AUXILIARY.has(kind) else [0]
	var ports: Array = inputs.duplicate() if kind not in ["source","coal_source"] else []
	for side in outlets:
		if side not in ports: ports.append(side)
	for side in ports:
		var port = Node3D.new()
		parent.add_child(port)
		port.rotation.y = -side*PI/2
		var sleeve = Node3D.new()
		port.add_child(sleeve)
		# Same bore and height as the conveyor, from machine body to cell edge.
		sleeve.position.x = 0.37
		square_pipe(sleeve,0.26,false)
		# Folded coupling guards point along actual flow, including into consumers.
		var guard = Node3D.new()
		port.add_child(guard)
		guard.position.x = 0.2 if side in outlets else 0.5
		guard.scale = Vector3(0.6,1,1.8)
		if side not in outlets: guard.rotation.y = PI
		directional_cover(guard,0.486,true)

func machine_cover(kind: String, parent: Node3D):
	# Each machine carries the same folded metalwork on a real casing or outlet.
	var cover = Node3D.new()
	parent.add_child(cover)
	match kind:
		"furnace":
			cover.position = Vector3(0.06,0.662,0)
			cover.scale = Vector3(0.8,1,0.92)
		"press":
			cover.position.y = 1.117
			cover.scale = Vector3(0.58,1,1.0)
		"depot":
			cover.position = Vector3(0.04,0.5,0)
			cover.scale = Vector3(0.8,1,1.8)
		"refinery":
			cover.position = Vector3(0.19,0.652,0)
			cover.scale = Vector3(0.36,1,0.4)
		_:
			cover.position = Vector3(-0.025,0.578,0)
			cover.scale = Vector3(0.7,1,1.6)
	directional_cover(cover,0.0,kind not in ["furnace","press","refinery"])

func square_pipe(parent: Node3D, length: float = 0.94, inlet_flange: bool = true):
	# Four metal walls leave a square bore visible at the ends.
	box(parent,Vector3(0,0.08,0),Vector3(length,0.08,0.64),"dark")
	box(parent,Vector3(0,0.44,0),Vector3(length,0.08,0.64),"pipe")
	for side in [-1,1]:
		box(parent,Vector3(0,0.26,side*0.28),Vector3(length,0.28,0.08),"dark")
	for end in [-1,1]:
		if end == -1 and not inlet_flange: continue
		var x = end*(length*0.5-0.045)
		for height in [0.08,0.44]: box(parent,Vector3(x,height,0),Vector3(0.09,0.09,0.72),"pipe_joint")
		for side in [-1,1]: box(parent,Vector3(x,0.26,side*0.32),Vector3(0.09,0.3,0.08),"pipe_joint")

func pipe_junction(parent: Node3D, ports: Array):
	box(parent,Vector3(0,0.08,0),Vector3(0.64,0.08,0.64),"dark")
	box(parent,Vector3(0,0.44,0),Vector3(0.64,0.08,0.64),"pipe")
	for side in range(4):
		var arm = Node3D.new()
		parent.add_child(arm)
		arm.rotation.y = -side*PI/2
		if side in ports:
			var segment = Node3D.new()
			arm.add_child(segment)
			segment.position.x = 0.41
			square_pipe(segment,0.18,false)
		else:
			box(arm,Vector3(0.28,0.26,0),Vector3(0.08,0.28,0.64),"dark")

func machine(kind: String, parent: Node3D, inputs: Array = [2]) -> Dictionary:
	var parts = machine_body(kind,parent,inputs)
	var base_kind = F.Content.BLOCKS[kind].base if F.Content.BLOCKS.has(kind) else kind
	if base_kind in ["belt","splitter"]: return parts
	# Fill the cell with the casing, while keeping the real pipe couplings at
	# the cell boundary. Scale X/Z only so animated pistons retain their travel.
	var extent = Vector2.ZERO
	for point in EquipmentModels.vertices(parent):
		extent.x = maxf(extent.x,absf(point.x))
		extent.y = maxf(extent.y,absf(point.z))
	var factor = Vector3(0.46/maxf(extent.x,0.01),1,0.46/maxf(extent.y,0.01))
	for child in parent.get_children():
		if child is Node3D: child.transform = child.transform.scaled(factor)
	if kind != "armor_block": flow_ports(kind,parent,inputs)
	return parts

func machine_body(kind: String, parent: Node3D, inputs: Array = [2]) -> Dictionary:
	var parts: Dictionary = {}
	if kind == "armor_block":
		box(parent,Vector3(0,0.08,0),Vector3(0.9,0.16,0.9),"pipe_joint")
		parts.armor_plates = []
		for i in range(F.ARMOR_HITS):
			var plate = box(parent,Vector3(0,0.25+i*0.18,0),Vector3(0.78,0.14,0.78),"machine_iron")
			parts.armor_plates.append(plate)
			for x in [-0.31,0.31]:
				for z in [-0.31,0.31]:
					cylinder(plate,Vector3(x,0.1,z),0.055,0.06,"pipe_joint",6)
		return parts
	var base_kind = F.Content.BLOCKS[kind].base if F.Content.BLOCKS.has(kind) else kind
	if base_kind in ["belt","splitter"]:
		var ports: Array = inputs.duplicate()
		var exits = [0]
		if base_kind == "splitter": exits.append(1)
		if kind == "router": exits.append(3)
		for side in exits:
			if side not in ports: ports.append(side)
		pipe_junction(parent,ports)
		for side in exits:
			var cover = Node3D.new()
			parent.add_child(cover)
			cover.rotation.y = -side*PI/2
			directional_cover(cover,0.482,exits.size() > 1)
		if F.Content.BLOCKS.has(kind):
			var mark = "machine_fuel" if kind == "fuel_filter" else "machine_hot" if kind == "scrap_filter" else "machine_bronze"
			box(parent,Vector3(-0.2,0.52,0),Vector3(0.06,0.04,0.5),mark)
		parts.ports = ports
		return parts
	if F.Content.BLOCKS.has(kind):
		parts = machine_body(base_kind,parent,inputs)
		var mark = "machine_fuel" if kind in ["fuel_depot","auto_press"] else "machine_hot" if kind == "blast_furnace" else "machine_bronze"
		box(parent,Vector3(-0.3,0.13,0),Vector3(0.08,0.08,0.7),mark)
		if kind == "blast_furnace": cylinder(parent,Vector3(0.2,1.0,-0.2),0.14,0.7,"machine_hot",12)
		if kind == "auto_press": cylinder(parent,Vector3(0.28,0.35,0),0.16,0.4,"machine_fuel",12)
		return parts
	match kind:
		"furnace":
			box(parent,Vector3(0,0.33,0),Vector3(0.60,0.56,0.56),"machine_hot")
			# Open glowing hearth on both visible faces, with a tall chimney.
			for z in [-0.29,0.29]:
				box(parent,Vector3(0,0.34,z),Vector3(0.37,0.30,0.025),"dark")
				box(parent,Vector3(0,0.30,z*1.04),Vector3(0.25,0.16,0.025),"fire")
			cylinder(parent,Vector3(-0.18,0.86,-0.15),0.10,0.66,"dark",6)
			cylinder(parent,Vector3(-0.18,1.20,-0.15),0.14,0.08,"pipe_joint",6)
			box(parent,Vector3(0,0.63,0),Vector3(0.64,0.06,0.60),"pipe_joint")
			parts.fire = box(parent,Vector3(0.20,0.67,0.12),Vector3(0.18,0.04,0.20),"fire")
		"press":
			box(parent,Vector3(0,0.10,0),Vector3(0.62,0.16,0.64),"machine_iron")
			for z in [-0.24,0.24]: box(parent,Vector3(0,0.57,z),Vector3(0.15,0.92,0.12),"machine_iron")
			box(parent,Vector3(0,1.03,0),Vector3(0.38,0.17,0.65),"machine_iron")
			cylinder(parent,Vector3(0,0.87,0),0.09,0.22,"machine_bronze",6)
			parts.piston = box(parent,Vector3(0,0.74,0),Vector3(0.40,0.16,0.37),"machine_iron")
			box(parent,Vector3(0,0.29,0),Vector3(0.38,0.13,0.38),"dark")
		"depot":
			box(parent,Vector3(0,0.12,0),Vector3(0.62,0.20,0.62),"wood")
			for z in [-0.28,0.28]: box(parent,Vector3(0,0.32,z),Vector3(0.62,0.35,0.05),"wood")
			# Large embossed shell silhouettes identify the rack even when empty.
			for x in [-0.19,0,0.19]:
				cylinder(parent,Vector3(x,0.33,-0.30),0.055,0.22,"shell",6)
				cylinder(parent,Vector3(x,0.48,-0.30),0.055,0.09,"tip",6,0)
		"source", "coal_source":
			# Closed supply crates: solid sides and a strapped lid, not loose piles.
			var panel = "machine_hot" if kind == "source" else "pipe_cover"
			var mark = "rust" if kind == "source" else "coal"
			box(parent,Vector3(0,0.08,0),Vector3(0.9,0.16,0.9),mark)
			box(parent,Vector3(0,0.44,0),Vector3(0.84,0.64,0.84),panel)
			box(parent,Vector3(0,0.80,0),Vector3(0.9,0.08,0.9),"machine_iron")
			for side in [-1,1]:
				box(parent,Vector3(side*0.425,0.85,0),Vector3(0.05,0.04,0.9),mark)
				box(parent,Vector3(0,0.85,side*0.425),Vector3(0.8,0.04,0.05),mark)
			for x in [-0.34,0.34]:
				box(parent,Vector3(x,0.85,0),Vector3(0.075,0.04,0.8),mark)
				for z in [-0.43,0.43]:
					box(parent,Vector3(x,0.44,z),Vector3(0.075,0.68,0.04),mark)
			for z in [-0.435,0.435]:
				box(parent,Vector3(0,0.44,z),Vector3(0.38,0.30,0.025),mark)
				box(parent,Vector3(0,0.64,z*1.02),Vector3(0.2,0.045,0.035),"dark")
			box(parent,Vector3(-0.1,0.847,0),Vector3(0.32,0.014,0.38),"dark")
			if kind == "source":
				for z in [-0.085,0.085]: box(parent,Vector3(-0.1,0.86,z),Vector3(0.25,0.015,0.09),"rust")
			else:
				var badge = box(parent,Vector3(-0.1,0.86,0),Vector3(0.2,0.015,0.2),"mark")
				badge.rotation.y = PI/4
				var inset = box(parent,Vector3(-0.1,0.87,0),Vector3(0.14,0.01,0.14),"coal")
				inset.rotation.y = PI/4
			var arrow = Node3D.new()
			parent.add_child(arrow)
			arrow.position = Vector3(0.19,0.86,0)
			arrow.scale = Vector3(0.4,0.4,0.8)
			directional_cover(arrow,0,true)
		"refinery":
			box(parent,Vector3(0,0.10,0),Vector3(0.65,0.14,0.65),"dark")
			cylinder(parent,Vector3(-0.14,0.58,0),0.19,0.92,"machine_fuel",6)
			cylinder(parent,Vector3(0.19,0.39,0),0.14,0.52,"machine_bronze",6)
			beam(parent,Vector3(-0.14,0.98,0),Vector3(0.19,0.65,0),0.045,"machine_iron")
			box(parent,Vector3(-0.14,0.18,0.19),Vector3(0.18,0.15,0.025),"fire")
		"engine":
			box(parent,Vector3(0,0.26,0),Vector3(0.68,0.44,0.60),"machine_fuel")
			for x in [-0.22,0,0.22]: box(parent,Vector3(x,0.53,0),Vector3(0.09,0.16,0.5),"dark")
			cylinder(parent,Vector3(0.19,0.77,-0.17),0.07,0.35,"dark",6)
		"gun", "left_gun", "right_gun", "rapid_gun", "long_gun", "mortar_gun", "rear_gun", "scatter_gun", "arc_gun":
			box(parent,Vector3(0,0.22,0),Vector3(0.62,0.40,0.62),"dark")
			for z in [-0.18,0,0.18]:
				var round_node = make_good("shell",true)
				parent.add_child(round_node)
				round_node.position = Vector3(0,0.44,z)
			beam(parent,Vector3(0.23,0.3,0),Vector3(0.23,0.95,0),0.14,"machine_bronze")
			if F.AUXILIARY.has(kind):
				# Different side stripes identify the two independent magazines.
				box(parent,Vector3(0,0.05,-0.43 if F.Gear.family(kind) == "left_gun" else 0.43),Vector3(0.85,0.05,0.08),"machine_fuel")
	if kind in ["furnace","press","depot","refinery"]:
		machine_cover(kind,parent)
	return parts

func make_good(kind: String, compact: bool = false) -> Node3D:
	var n = Node3D.new()
	match kind:
		"scrap":
			var a = box(n,Vector3(0,0.06,0),Vector3(0.3,0.12,0.21),"rust")
			a.rotation_degrees = Vector3(15,20,10)
			var offcut = box(n,Vector3(-0.025,0.17,0.025),Vector3(0.27,0.055,0.08),"steel")
			offcut.rotation.y = -0.6
		"coal":
			var chunk = cylinder(n,Vector3(0,0.12,0),0.19,0.23,"coal",5,0.11)
			chunk.rotation.z = 0.2
			cylinder(n,Vector3(0.11,0.13,0.07),0.09,0.15,"coal",5,0.035)
		"fuel":
			cylinder(n,Vector3(0,0.16,0),0.13,0.3,"fuel",6)
			for y in [0.06,0.25]: cylinder(n,Vector3(0,y,0),0.14,0.035,"brass",6)
			cylinder(n,Vector3(0.055,0.32,0),0.04,0.04,"dark",6)
		"steel":
			box(n,Vector3(0,0.07,0),Vector3(0.40,0.14,0.27),"steel")
			box(n,Vector3(0,0.17,0),Vector3(0.32,0.06,0.21),"tip")
		"shell":
			var casing = cylinder(n,Vector3(-0.05,0.09,0),0.085,0.28,"shell",8)
			casing.rotation.z = -PI/2
			var nose = cylinder(n,Vector3(0.15,0.09,0),0.085,0.14,"tip",8,0.0)
			nose.rotation.z = -PI/2
	n.scale = Vector3.ONE*(0.85 if compact else 1.4)
	n.set_meta("kind",kind)
	return n

func good_height(kind: String) -> float:
	if F.Content.BLOCKS.has(kind): return good_height(F.Content.BLOCKS[kind].base)
	if F.AUXILIARY.has(kind): return 0.4
	return {"belt":0.57,"splitter":0.57,"furnace":0.83,"press":0.38,"source":0.4,"depot":0.35,"gun":0.4,"refinery":1.08,"engine":0.65,"coal_source":0.4}.get(kind,0.25)

func item_frames(factory) -> Array:
	var frames: Array = []
	var arrivals: Dictionary = {}
	for move in factory.moves: arrivals[move.to] = true
	for p in factory.cells:
		var c: Dictionary = factory.cells[p]
		if F.AUXILIARY.has(c.kind): continue
		var count = c.items.size()-(1 if arrivals.has(p) else 0)
		for i in range(count):
			var offset = Vector3(0,good_height(c.kind),0)
			var stored = c.kind in ["depot","fuel_depot","overflow_gate"]
			if stored: offset += Vector3(-0.22+(i%2)*0.44,int(i/4)*0.32, -0.22+(int(i/2)%2)*0.44)
			frames.append({"kind":c.items[i],"pos":cell_position(p)+offset,"dir":c.dir,"scale":0.65 if stored else 1.0})
	for move in factory.moves:
		var receiver = factory.receiving_cell(move.to)
		if not factory.cells.has(move.from) or receiver.is_empty(): continue
		var a = cell_position(move.from)+Vector3(0,good_height(factory.cells[move.from].kind),0)
		var b = cell_position(move.to)+Vector3(0,good_height(receiver.kind),0)
		frames.append({"kind":move.item,"pos":a.lerp(b,clampf(factory.clock/F.TICK,0,1)),"dir":factory.cells[move.from].dir})
	return frames

func sync_damage(factory):
	var signature = str(factory.wrecks)+str(roof_closed)
	if signature == rendered_damage: return
	rendered_damage = signature
	if damage_layer == null:
		damage_layer = Node3D.new()
		turret.get_parent().add_child(damage_layer)
	for child in damage_layer.get_children():
		damage_layer.remove_child(child)
		child.queue_free()
	for p in factory.wrecks:
		var at = cell_position(p)
		if roof_closed: at.y = 4.2
		box(damage_layer,at+Vector3(0,0.03,0),Vector3(0.94,0.06,0.94),"dark")
		for side in [-1,1]:
			var shard = box(damage_layer,at+Vector3(side*0.2,0.15,0),Vector3(0.18,0.19,0.65),"rust")
			shard.rotation = Vector3(0.2,side*0.7,side*0.3)
		beam(damage_layer,at+Vector3(-0.32,0.28,-0.32),at+Vector3(0.32,0.28,0.32),0.05,"red",6)
		beam(damage_layer,at+Vector3(-0.32,0.28,0.32),at+Vector3(0.32,0.28,-0.32),0.05,"red",6)

func tint_preview(node: Node, mat: StandardMaterial3D):
	if node is MeshInstance3D:
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): tint_preview(child,mat)

func sync_placement_preview(factory, hovered: Vector2i, selected: String, direction: int, enabled: bool = true):
	placement_preview.visible = enabled and not factory.layout_locked and not roof_closed and factory.inside(hovered) and F.LIMITS.has(selected)
	if not placement_preview.visible: return
	var valid = factory.can_place(hovered,selected)
	var topology = factory.connection_sides(hovered,factory.make_cell(selected,direction))
	var topology_key = str(topology.display_inputs)
	var rebuild = preview_kind != selected or preview_topology != topology_key
	if rebuild:
		for child in placement_preview.get_children():
			placement_preview.remove_child(child)
			child.queue_free()
		preview_kind = selected
		preview_topology = topology_key
		preview_model = Node3D.new()
		placement_preview.add_child(preview_model)
		machine(selected,preview_model,topology.display_inputs)
		preview_arrows = Node3D.new()
		placement_preview.add_child(preview_arrows)
		var exits = [0]
		if selected == "armor_block": exits.clear()
		if selected in ["splitter","smart_splitter","priority_splitter","router"]: exits.append(1)
		if selected == "router": exits.append(3)
		var base_kind = F.Content.BLOCKS[selected].base if F.Content.BLOCKS.has(selected) else selected
		var is_pipe = base_kind in ["belt","splitter"]
		for side in exits:
			var arrow = Node3D.new()
			preview_arrows.add_child(arrow)
			arrow.rotation.y = -side*PI/2
			if is_pipe:
				directional_cover(arrow,0.484,exits.size() > 1)
			else:
				machine_cover(base_kind,arrow)
	if rebuild or preview_valid != valid:
		preview_valid = valid
		tint_preview(preview_model,preview_materials.valid if valid else preview_materials.invalid)
		tint_preview(preview_arrows,preview_materials.arrow if valid else preview_materials.blocked_arrow)
	placement_preview.position = cell_position(hovered)+Vector3(0,0.035,0)
	placement_preview.rotation.y = -posmod(direction,4)*PI/2

func fixed_fitting(kind: String, parent: Node3D, inputs: Array, cell: Vector2i) -> Dictionary:
	flow_ports(kind,parent,inputs)
	if kind == "engine":
		# This inlet joins the rear engine housing, without a second tiny engine.
		var conduit = Node3D.new()
		parent.add_child(conduit)
		conduit.position = Vector3(-0.25,0,0)
		square_pipe(conduit,0.95)
		box(parent,Vector3(-0.55,0.34,0),Vector3(0.18,0.55,0.65),"machine_fuel")
	elif cell == main_gun_anchor:
		var magazine = Node3D.new()
		parent.add_child(magazine)
		magazine.name = "MainMagazine2x2"
		magazine.position = Vector3(0.5,0,0.5)
		box(magazine,Vector3(0,0.2,0),Vector3(1.9,0.4,1.9),"dark")
		for z in [-0.88,0.88]: box(magazine,Vector3(0,0.54,z),Vector3(1.9,0.4,0.12),"machine_bronze")
		for x in [-0.6,0,0.6]:
			for z in [-0.45,0.45]:
				var round_node = make_good("shell")
				magazine.add_child(round_node)
				round_node.position = Vector3(x,0.48,z)
				round_node.scale = Vector3.ONE*1.5
		cylinder(magazine,Vector3(0,0.85,0),0.24,0.8,"machine_bronze",12)
	return {"root":parent}

func sync(factory, hovered: Vector2i, selected: String, direction: int, delta: float, preview_enabled: bool = true):
	main_gun_anchor = factory.main_gun_anchor
	set_layout_version(factory.layout_version)
	sync_damage(factory)
	var signature = str(factory.layout_version)+str(factory.equipment_mounts)+str(factory.equipment_rotations)+str(factory.layout())
	if signature != rendered_layout:
		rendered_layout = signature
		for child in equipment.get_children():
			equipment.remove_child(child)
			child.queue_free()
		machines.clear()
		for p in factory.blocks:
			var wall = Node3D.new()
			equipment.add_child(wall)
			wall.position = cell_position(p)
			wall.name = "MaterialWall_"+str(p.x)+"_"+str(p.y)
			box(wall,Vector3(0,0.45,0),Vector3(0.94,0.9,0.94),"armor")
			box(wall,Vector3(0,0.94,0),Vector3(0.98,0.08,0.98),"edge")
		for p in factory.cells:
			var c: Dictionary = factory.cells[p]
			var n = Node3D.new()
			equipment.add_child(n)
			n.position = cell_position(p)
			n.rotation.y = -c.dir*PI/2
			var topology = factory.connection_sides(p)
			if factory.layout_version == 2 and factory.equipment_mounts.has(c.kind) and F.AUXILIARY.has(c.kind):
				# The shared weapon above this socket is the only gun model. The
				# old tall magazine occupied the same space as its rotating body.
				flow_ports(c.kind,n,topology.display_inputs)
				cylinder(n,Vector3(0.5,0.42,0.5),0.22,0.4,"dark",12)
				machines[p] = {"root":n}
			elif factory.layout_version == 2 and c.kind in ["gun","engine"]:
				machines[p] = fixed_fitting(c.kind,n,topology.display_inputs,p)
			else: machines[p] = machine(c.kind,n,topology.display_inputs)
			if factory.equipment_mounts.has(c.kind) and F.AUXILIARY.has(c.kind):
				for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
					var socket = Node3D.new()
					n.add_child(socket)
					socket.position = Vector3(offset.x,0,offset.y)
					flow_ports(c.kind,socket,factory.connection_sides(p+offset).display_inputs)
			machines[p].connections = topology.connected
			machines[p].inputs = topology.inputs
	for p in machines:
		var c: Dictionary = factory.cells[p]
		if machines[p].has("armor_plates"):
			for i in range(F.ARMOR_HITS): machines[p].armor_plates[i].visible = i < c.armor_hp
		if machines[p].has("piston"):
			machines[p].piston.position.y = 0.78-(0.29*sin((1.0-c.work/8.0)*PI) if c.work > 0 else 0.0)
		if machines[p].has("fire"): machines[p].fire.visible = c.work > 0
	var frames = item_frames(factory)
	while goods_pool.size() < frames.size(): goods_pool.append(null)
	for i in goods_pool.size():
		if i >= frames.size():
			if goods_pool[i] != null: goods_pool[i].visible = false
			continue
		var frame: Dictionary = frames[i]
		if goods_pool[i] == null or goods_pool[i].get_meta("kind") != frame.kind:
			if goods_pool[i] != null:
				goods.remove_child(goods_pool[i])
				goods_pool[i].queue_free()
			goods_pool[i] = make_good(frame.kind)
			goods.add_child(goods_pool[i])
		goods_pool[i].visible = not roof_closed
		goods_pool[i].scale = Vector3.ONE*1.4*float(frame.get("scale",1.0))
		goods_pool[i].position = frame.pos
		goods_pool[i].rotation.y = -frame.dir*PI/2
	marker.visible = not factory.layout_locked and not roof_closed and factory.inside(hovered)
	if marker.visible:
		marker.position = cell_position(hovered)+Vector3(0,0.015,0)
		var unavailable = F.LIMITS.has(selected) and not factory.can_place(hovered,selected)
		marker.material_override = mats.red if hovered in factory.blocks or factory.ports.has(hovered) or unavailable else mats.green
	sync_placement_preview(factory,hovered,selected,direction,preview_enabled)
	update_gun(factory,delta)
	update_vehicle_part_visuals()

func position_mounted_models():
	for id in mounted_models:
		if not mounted_positions.has(id): continue
		var facing = int(mounted_rotations.get(id,0))
		var size: Vector2i = F.Gear.footprint(id,facing)
		mounted_models[id].position = cell_position(mounted_positions[id])+Vector3((size.x-1)*0.5,0,(size.y-1)*0.5)
		mounted_models[id].rotation.y = -facing*PI/2
		mounted_models[id].visible = not roof_closed

func build_mounted_model(parent: Node3D, id: String):
	parent.add_child(equipment_models.build_mounted(id,installed_rarities.get(id,"normal")))

func equipment_markings(parent: Node3D, id: String, height: float, area: Vector2):
	var spec: Dictionary = F.Content.EQUIPMENT[id]
	if spec.level == 1 and spec.profile == "balanced": return
	# Level studs and role plates fit inside the reservation; no added collider.
	var span = area.x*0.8
	for index in range(spec.level):
		var x = -span*0.5+span*(index+0.5)/10.0
		box(parent,Vector3(x,height,-area.y*0.35),Vector3(span/16.0,0.045,0.065),"machine_bronze")
	if spec.visual == 1:
		for side in [-1,1]: box(parent,Vector3(side*area.x*0.3,height+0.06,area.y*0.2),Vector3(0.06,0.13,0.12),"edge")
	elif spec.visual == 2:
		box(parent,Vector3(0,height+0.02,area.y*0.2),Vector3(area.x*0.55,0.05,0.12),"machine_fuel")

func preview_equipment(factory, item: Dictionary, at: Vector2i, allowed: bool = true, facing: int = -1):
	if item.is_empty() or roof_closed or not factory.inside(at):
		if equipment_preview != null: equipment_preview.hide()
		return
	if facing < 0: facing = item.get("direction",0)
	var is_main = F.Gear.part_slot(item.kind) == "cannon"
	var valid = allowed and (factory.can_move_main_gun(at) if is_main else factory.can_place_equipment(item.kind,at,facing))
	var proposed_mounts = factory.equipment_mounts.duplicate()
	proposed_mounts[item.kind] = at
	var tier = MountLayout.tiers(proposed_mounts,factory.main_gun_anchor).get(item.kind,0)
	var proposed = item.duplicate()
	proposed.position = at
	proposed.direction = facing
	var activation = preload("res://scripts/equipment_activation.gd")
	var active: bool = activation.status(factory,proposed,activation.ammo_network(factory)).active
	if not mats.has("inactive_amber"): material("inactive_amber","e0a456",0,0.4)
	var tile_color = "green" if active else "inactive_amber"
	var key = item.kind+item.get("rarity","normal")+str(valid)+str(facing)+str(active)+str(tier)
	if equipment_preview == null:
		equipment_preview = Node3D.new()
		add_child(equipment_preview)
	if equipment_preview_key != key:
		equipment_preview_key = key
		for child in equipment_preview.get_children():
			equipment_preview.remove_child(child)
			child.queue_free()
		var size: Vector2i = Vector2i(2,2) if is_main else F.Gear.footprint(item.kind,facing)
		for y in range(size.y):
			for x in range(size.x): box(equipment_preview,Vector3(x,0.06,y),Vector3(0.94,0.035,0.94),tile_color if valid else "red")
		var secondary = item.kind in F.Content.ALL_GUNS
		var ghost = equipment_models.build(item.kind,item.get("rarity","normal")) if secondary else equipment_models.build_mounted(item.kind,item.get("rarity","normal"))
		equipment_preview.add_child(ghost)
		ghost.position = Vector3((size.x-1)*0.5,0.15,(size.y-1)*0.5)
		ghost.rotation.y = -facing*PI/2
		if secondary:
			var mount = equipment_models.weapon_mount(ghost,item.kind)
			var height = 0.0
			for point in EquipmentModels.vertices(ghost): height = maxf(height,point.y)
			ghost.scale = Vector3(mount.scale*MountLayout.GUN_SCALE,MountLayout.GUN_HEIGHT/height,mount.scale*MountLayout.GUN_SCALE)
			ghost.position.y = MountLayout.UPPER_Y-DECK_Y if tier == 1 else MOUNTED_GUN_Y
			ghost.position += Vector3(mount.offset.x,0,mount.offset.y).rotated(Vector3.UP,-facing*PI/2)*MountLayout.GUN_SCALE
		fade_equipment_preview(ghost)
		if item.kind in F.Content.ALL_GUNS:
			var center = Vector3((size.x-1)*0.5,0.12,(size.y-1)*0.5)
			for relative in [-F.Gear.SECONDARY_HALF_ARC,0.0,F.Gear.SECONDARY_HALF_ARC]:
				var angle = -facing*PI/2+relative
				beam(equipment_preview,center,center+Vector3(cos(angle),0,-sin(angle))*0.7,0.035,tile_color if valid else "red",6)
	equipment_preview.position = cell_position(at)
	equipment_preview.show()

func fade_equipment_preview(node: Node):
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var ghost_material: StandardMaterial3D = node.material_override.duplicate()
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.albedo_color.a = 0.45
		node.material_override = ghost_material
	for child in node.get_children(): fade_equipment_preview(child)

func mark_equipment(factory, selected_kind: String, enabled: bool):
	if equipment_marks == null:
		equipment_marks = Node3D.new()
		equipment_marks.name = "EquipmentStateMarks"
		add_child(equipment_marks)
	equipment_marks.visible = enabled and not roof_closed
	if not equipment_marks.visible: return
	var activation = preload("res://scripts/equipment_activation.gd")
	var network = activation.ammo_network(factory)
	var enabled_mounts = {}
	for id in factory.equipment_mounts:
		enabled_mounts[id] = activation.status(factory,{"kind":id,"position":factory.equipment_mounts[id],"direction":factory.equipment_rotations.get(id,0)},network).active
	var key = str(factory.equipment_mounts)+str(factory.equipment_rotations)+selected_kind+str(enabled_mounts)
	if key == equipment_marks_key: return
	equipment_marks_key = key
	for child in equipment_marks.get_children():
		equipment_marks.remove_child(child)
		child.queue_free()
	if not mats.has("selection_gold"):
		material("selection_gold","f6d273",0,0.45)
		material("installed_green","87bc80",0,0.25)
	for id in factory.equipment_mounts:
		var facing = int(factory.equipment_rotations.get(id,0))
		var size: Vector2i = F.Gear.footprint(id,facing)
		var mark = Node3D.new()
		mark.name = id
		equipment_marks.add_child(mark)
		mark.position = cell_position(factory.equipment_mounts[id])+Vector3((size.x-1)*0.5,0.14,(size.y-1)*0.5)
		if not mats.has("inactive_amber"): material("inactive_amber","e0a456",0,0.4)
		var tint = "inactive_amber" if not enabled_mounts[id] else "selection_gold" if id == selected_kind else "installed_green"
		var width = 0.10 if id == selected_kind else 0.05
		for side in [-1,1]:
			box(mark,Vector3(0,0,side*size.y*0.48),Vector3(size.x*0.96,width,width),tint)
			box(mark,Vector3(side*size.x*0.48,0,0),Vector3(width,width,size.y*0.96),tint)
		var heading = Vector3.RIGHT.rotated(Vector3.UP,-facing*PI/2)
		var side = Vector3(-heading.z,0,heading.x)
		var tip = heading*(size.x*0.35 if facing%2 == 0 else size.y*0.35)+Vector3(0,0.02,0)
		beam(mark,tip-heading*0.35-side*0.18,tip,0.045,tint,6)
		beam(mark,tip-heading*0.35+side*0.18,tip,0.045,tint,6)

func solid_mounted_materials(node: Node):
	if node is MeshInstance3D:
		for pair in [["turret_armor","machine_iron"],["turret_edge","machine_bronze"],["turret_dark","dark"]]:
			if node.material_override == mats[pair[0]]: node.material_override = mats[pair[1]]
	for child in node.get_children(): solid_mounted_materials(child)
