extends RefCounted
## Shared, deterministic low-poly models for battlefield loot and inventory previews.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const MOUNT_MARGIN = 0.14
const MOUNT_HEIGHT = 1.05
const BARREL_REST = 0.6
const RECOIL_TRAVEL = 0.2
const COLORS = {"iron":"657679","dark":"29383c","brass":"d5aa62","paint":"829078","glass":"70d8dd","coal":"333b46"}
var materials: Dictionary = {}
var drop_materials: Dictionary = {}
var weapon_mounts: Dictionary = {}

func decorate_drop(root: Node3D, model: Node3D, rarity: String = ""):
	var color = Color(Catalog.RARITIES[rarity].color if not rarity.is_empty() else "d5aa62")
	var ring = TorusMesh.new()
	ring.inner_radius = 1.55
	ring.outer_radius = 1.95
	ring.rings = 24
	ring.ring_segments = 6
	var marker = part(root,ring,Vector3(0,0.12,0),color.to_html(false))
	marker.name = "RarityRing"
	marker.scale.y = 0.2
	if rarity.is_empty(): return
	# Field-only materials: do not recolor shared inventory or mounted models.
	tint_drop(model,rarity,color)
	var key = "marker_"+rarity
	if not drop_materials.has(key):
		var glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = color
		drop_materials[key] = glow
	marker.material_override = drop_materials[key]
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beacon = cylinder(root,Vector3(0,2.3,0),0.07,4.4,color.to_html(false))
	beacon.name = "RarityBeacon"
	beacon.material_override = drop_materials[key]
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func tint_drop(node: Node3D, rarity: String, color: Color):
	if node is MeshInstance3D:
		var source: StandardMaterial3D = node.material_override
		var key = rarity+"_"+str(source.get_instance_id())
		if not drop_materials.has(key):
			var tinted: StandardMaterial3D = source.duplicate()
			tinted.albedo_color = source.albedo_color.lerp(color,0.65)
			tinted.emission_enabled = true
			tinted.emission = color
			tinted.emission_energy_multiplier = 0.18
			drop_materials[key] = tinted
		node.material_override = drop_materials[key]
	for child in node.get_children():
		if child is Node3D: tint_drop(child,rarity,color)

func material(key: String) -> StandardMaterial3D:
	if not materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(COLORS.get(key,key))
		m.roughness = 0.72
		materials[key] = m
	return materials[key]

func part(parent: Node3D, mesh: Mesh, at: Vector3, color: String) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.position = at
	parent.add_child(node)
	return node

func box(parent: Node3D, at: Vector3, dimensions: Vector3, color: String = "iron") -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	return part(parent,mesh,at,color)

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: String = "iron") -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	return part(parent,mesh,at,color)

func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: String = "iron"):
	var node = cylinder(parent,(a+b)/2,radius,a.distance_to(b),color)
	node.quaternion = Quaternion(Vector3.UP,(b-a).normalized())

func build(kind: String, rarity: String = "normal") -> Node3D:
	if kind.begins_with("empty_"): return build_empty(kind.trim_prefix("empty_"))
	var root = Node3D.new()
	root.name = "Item_"+kind
	root.set_meta("kind",kind)
	root.set_meta("rarity",rarity)
	if kind in ["scrap","coal","shell"]:
		build_resource(root,kind)
		return root
	var spec: Dictionary = Catalog.Data.ITEMS[kind]
	var family = Catalog.family(kind)
	var trim: String = Catalog.RARITIES[rarity].color
	box(root,Vector3(0,0.1,0),Vector3(1.7,0.2,1.2),"dark")
	box(root,Vector3(0,0.23,0),Vector3(1.6,0.08,1.1),trim)
	if not Catalog.part_slot(kind).is_empty():
		build_vehicle_part(root,spec,trim)
		return root
	if spec.genre == "secondary":
		cylinder(root,Vector3(0,0.36,0),0.55,0.25,"brass")
		box(root,Vector3(-0.12,0.7,0),Vector3(1.15,0.65,1.15),"paint")
		var length = 1.6 if family == "long_gun" else 1.15
		length *= 1.16 if spec.profile == "focus" else 0.88 if spec.profile == "rapid" else 1.0
		var barrel = Node3D.new()
		barrel.name = "Barrel"
		root.add_child(barrel)
		var barrels = 3 if family == "scatter_gun" else 2 if family in ["rapid_gun","rear_gun"] else 1
		for i in range(barrels):
			var z = (i-(barrels-1)/2.0)*0.45
			var end = Vector3(length,1.3 if family == "mortar_gun" else 0.7,z)
			beam(barrel,Vector3(0.15,0.65,z),end,0.24 if family == "mortar_gun" else 0.14,"iron")
			beam(barrel,end-Vector3(0.17,0,0),end,0.28 if family == "mortar_gun" else 0.2,"dark")
		if family == "arc_gun":
			for x in [0.45,0.7,0.95]:
				var coil = cylinder(barrel,Vector3(x,0.7,0),0.22,0.1,"glass")
				coil.rotation.z = PI/2
		elif family in ["left_gun","right_gun"]:
			box(root,Vector3(-0.15,0.7,-0.56 if family == "left_gun" else 0.56),Vector3(0.65,0.35,0.18),"brass")
		elif family == "rear_gun": box(root,Vector3(-0.45,0.85,0),Vector3(0.2,0.4,1.15),"iron")
		# Keep the shared appearance while giving installed guns a recoil rig.
		for child in barrel.get_children(): child.position.x -= BARREL_REST
		barrel.position.x = BARREL_REST
		root.set_meta("muzzle",Vector3(length,1.3 if family == "mortar_gun" else 0.7,0))
	else:
		match family:
			"armor":
				for i in range(3):
					var plate = box(root,Vector3((i-1)*0.48,0.65,0),Vector3(0.44,0.65,0.85),"paint")
					plate.rotation.z = -0.18
			"skirts":
				beam(root,Vector3(-0.72,0.95,0),Vector3(0.72,0.95,0),0.08,"brass")
				for i in range(4): box(root,Vector3((i-1.5)*0.37,0.6,0),Vector3(0.32,0.7,0.18),"paint")
			"supercharger":
				for x in [-0.48,0,0.48]: cylinder(root,Vector3(x,0.55,0),0.21,0.6,"iron")
				beam(root,Vector3(-0.65,0.95,0),Vector3(0.65,0.95,0),0.12,"brass")
				beam(root,Vector3(0.65,0.95,0),Vector3(0.65,0.55,0.4),0.12,"brass")
			"economizer":
				for i in range(6): box(root,Vector3((i-2.5)*0.23,0.65,0),Vector3(0.09,0.75,0.8),"iron")
				for z in [-0.4,0.4]: beam(root,Vector3(-0.7,0.8,z),Vector3(0.7,0.8,z),0.09,"brass")
			"servo":
				cylinder(root,Vector3(0,0.48,0),0.48,0.4,"paint")
				for i in range(8):
					var a = i*TAU/8
					var tooth = box(root,Vector3(cos(a)*0.5,0.65,sin(a)*0.5),Vector3(0.22,0.18,0.22),"brass")
					tooth.rotation.y = -a
				cylinder(root,Vector3(0,0.85,0),0.15,0.45,"iron")
			"rangefinder":
				cylinder(root,Vector3(0,0.55,0),0.16,0.6,"brass")
				beam(root,Vector3(-0.75,0.9,0),Vector3(0.75,0.9,0),0.18,"paint")
				for x in [-0.65,0.65]:
					beam(root,Vector3(x,0.9,0),Vector3(x,0.9,0.35),0.18,"dark")
					beam(root,Vector3(x,0.9,0.34),Vector3(x,0.9,0.38),0.14,"glass")
			"drum_loader":
				cylinder(root,Vector3(0,0.6,0),0.53,0.65,"paint")
				for i in range(8):
					var a = i*TAU/8
					cylinder(root,Vector3(cos(a)*0.4,0.95,sin(a)*0.4),0.085,0.24,"brass")
			"blast_fuse":
				for x in [-0.4,0,0.4]:
					cylinder(root,Vector3(x,0.6,0),0.15,0.65,"brass")
					cylinder(root,Vector3(x,1.0,0),0.09,0.18,"iron")
			"salvage_arm":
				cylinder(root,Vector3(-0.45,0.4,0),0.3,0.3,"paint")
				beam(root,Vector3(-0.45,0.45,0),Vector3(-0.3,1.25,0),0.13,"brass")
				beam(root,Vector3(-0.3,1.25,0),Vector3(0.65,1.1,0),0.11,"brass")
				beam(root,Vector3(0.65,1.1,0),Vector3(0.65,0.7,0),0.05,"dark")
				for side in [-1,1]: beam(root,Vector3(0.65,0.7,0),Vector3(0.65,0.5,side*0.2),0.06,"iron")
	# Profile changes silhouette; level studs identify all 300 catalog models.
	if spec.profile in ["focus","heavy","power"]:
		box(root,Vector3(-0.55,0.6,-0.5),Vector3(0.18,0.6,0.18),trim)
	elif spec.profile in ["rapid","mobile","economy","efficient"]:
		for z in [-0.45,0.45]: box(root,Vector3(-0.55,0.4,z),Vector3(0.4,0.16,0.15),"brass")
	for i in range(int(spec.level)):
		box(root,Vector3(-0.7+i*0.15,0.3,0.53),Vector3(0.085,0.08,0.12),"brass")
	return root

func build_vehicle_part(root: Node3D, spec: Dictionary, trim: String):
	var variant = int(spec.visual)
	match spec.slot:
		"gear":
			for i in range(2+variant):
				var center = Vector3(-0.48+i*0.38,0.55,0)
				var radius = 0.28 if variant == 1 else 0.35
				var gear = cylinder(root,center,radius,0.16,"brass")
				gear.rotation.x = PI/2
				for j in range(10):
					var angle = j*TAU/10
					var tooth = box(root,center+Vector3(cos(angle)*radius,sin(angle)*radius,0),Vector3(0.14,0.12,0.22),trim)
					tooth.rotation.z = angle
			beam(root,Vector3(-0.7,0.5,0),Vector3(0.7,0.5,0),0.08,"iron")
		"engine":
			box(root,Vector3(0,0.5,0),Vector3(1.25,0.5,0.8),"paint")
			for i in range(3+variant):
				cylinder(root,Vector3(-0.5+i*0.25,0.84,0),0.14,0.3,"iron")
			for z in [-0.45,0.45]: cylinder(root,Vector3(-0.45,0.8,z),0.1,0.85 if variant == 1 else 0.55,trim)
			if variant == 1: cylinder(root,Vector3(0.4,0.8,0.45),0.25,0.3,"brass")
			if variant == 2:
				for i in range(4): box(root,Vector3(0.5,0.5+i*0.13,-0.45),Vector3(0.5,0.05,0.2),"glass")
		"tracks":
			for z in [-0.4,0.4]:
				box(root,Vector3(0,0.5,z),Vector3(1.5,0.55,0.32 if variant == 1 else 0.22),"dark")
				for i in range(4):
					var wheel = cylinder(root,Vector3(-0.5+i/3.0,0.5,z+signf(z)*0.15),0.19,0.08,"brass" if variant == 2 else "iron")
					wheel.rotation.x = PI/2
				for i in range(6): box(root,Vector3(-0.65+i*0.26,0.8,z),Vector3(0.2,0.08,0.38 if variant == 1 else 0.24),trim)
		"cannon":
			cylinder(root,Vector3(-0.3,0.48,0),0.5,0.48,"paint")
			var length = 1.25 if variant == 1 else 0.85 if variant == 2 else 1.0
			var radius = 0.18 if variant == 2 else 0.11
			beam(root,Vector3(-0.2,0.65,0),Vector3(length,0.65,0),radius,"iron")
			beam(root,Vector3(length-0.15,0.65,0),Vector3(length,0.65,0),radius*1.3,trim)
			for i in range(variant+1): cylinder(root,Vector3(-0.6+i*0.3,0.8,-0.25),0.08,0.2,"brass")

func build_empty(slot: String) -> Node3D:
	var root = Node3D.new()
	root.name = "Empty_"+slot
	root.set_meta("empty_slot",slot)
	if slot == "cannon":
		var rim = cylinder(root,Vector3.ZERO,0.43,0.16,"iron")
		rim.rotation.z = PI/2
		var cap = cylinder(root,Vector3(0.1,0,0),0.32,0.05,"dark")
		cap.rotation.z = PI/2
	else:
		for z in [-0.48,0.48]:
			box(root,Vector3(0,0.2,z),Vector3(1.65,0.16,0.14),"iron")
		for x in [-0.65,0.65]:
			box(root,Vector3(x,0.2,0),Vector3(0.14,0.16,1.1),"iron")
			for z in [-0.48,0.48]: cylinder(root,Vector3(x,0.32,z),0.07,0.1,"brass")
		if slot == "gear":
			var socket = cylinder(root,Vector3(0,0.45,0),0.24,0.3,"dark")
			socket.rotation.x = PI/2
		if slot == "tracks":
			for x in [-0.5,0.5]:
				var wheel = cylinder(root,Vector3(x,0.55,0),0.3,0.2,"dark")
				wheel.rotation.x = PI/2
	return root

func build_resource(root: Node3D, kind: String):
	match kind:
		"scrap":
			for i in range(4):
				var plate = box(root,Vector3((i%2-0.5)*0.55,0.15+i*0.13,0),Vector3(0.85,0.16,0.6),"iron" if i%2 == 0 else "brass")
				plate.rotation.y = i*0.7
		"coal":
			for i in range(5):
				var mesh = SphereMesh.new()
				mesh.radius = 0.3
				mesh.height = 0.5
				mesh.radial_segments = 5
				mesh.rings = 3
				part(root,mesh,Vector3(cos(i*2.4)*0.35,0.25+(0.25 if i == 4 else 0),sin(i*2.4)*0.35),"coal")
		"shell":
			for x in [-0.3,0.3]:
				cylinder(root,Vector3(x,0.4,0),0.18,0.7,"brass")
				var tip = CylinderMesh.new()
				tip.top_radius = 0
				tip.bottom_radius = 0.18
				tip.height = 0.3
				part(root,tip,Vector3(x,0.9,0),"iron")

static func vertices(node: Node3D, transform_value: Transform3D = Transform3D.IDENTITY) -> PackedVector3Array:
	var result = PackedVector3Array()
	if node is MeshInstance3D:
		for vertex in node.mesh.get_faces(): result.append(transform_value*vertex)
	for child in node.get_children():
		if child is Node3D: result.append_array(vertices(child,transform_value*child.transform))
	return result

static func mount_scale(model: Node3D, footprint: Vector2i, rotating: bool = false) -> float:
	# Measure the real geometry, not a family-specific guessed scale. A turning
	# weapon reserves its full circular sweep, including flash and recoil.
	var extent = Vector2.ZERO
	var radius = 0.0
	var height = 0.0
	for point in vertices(model):
		height = maxf(height,point.y)
		extent.x = maxf(extent.x,absf(point.x))
		extent.y = maxf(extent.y,absf(point.z))
		radius = maxf(radius,Vector2(point.x,point.z).length())
	var half = Vector2(footprint)*0.5-Vector2.ONE*MOUNT_MARGIN
	if rotating: return minf(1.0,minf(half.x,half.y)/(radius+RECOIL_TRAVEL))
	return minf(MOUNT_HEIGHT/maxf(height,0.001),minf(1.0,minf(half.x/maxf(extent.x,0.001),half.y/maxf(extent.y,0.001))))

func weapon_mount(model: Node3D, kind: String) -> Dictionary:
	if weapon_mounts.has(kind): return weapon_mounts[kind]
	# Exact extrema of every vertex over the limited yaw arc. Barrel recoil is
	# linear, so its two endpoints also bound every intermediate recoil pose.
	var low = Vector2(INF,INF)
	var high = Vector2(-INF,-INF)
	var gun_barrel: Node3D = model.get_node("Barrel")
	var rest = gun_barrel.position
	var arc = Catalog.SECONDARY_HALF_ARC
	for recoil in [0.0,RECOIL_TRAVEL]:
		gun_barrel.position.x = BARREL_REST-recoil
		for vertex in vertices(model):
			var angles = [-arc,arc]
			for extreme in [atan2(vertex.z,vertex.x),atan2(-vertex.x,vertex.z)]:
				for opposite in [0.0,PI]:
					var angle = wrapf(extreme+opposite,-PI,PI)
					if absf(angle) <= arc: angles.append(angle)
			for angle in angles:
				var point = Vector2(vertex.x*cos(angle)+vertex.z*sin(angle),-vertex.x*sin(angle)+vertex.z*cos(angle))
				low = low.min(point)
				high = high.max(point)
	gun_barrel.position = rest
	var available = Vector2(Catalog.DEFINITIONS[kind].size)-Vector2.ONE*MOUNT_MARGIN*2
	var span = high-low
	var factor = minf(available.x/span.x,available.y/span.y)
	var mount = {"scale":factor,"offset":-(low+high)*0.5*factor,"half_arc":arc}
	weapon_mounts[kind] = mount
	return mount

func build_mounted(kind: String) -> Node3D:
	var model = build(kind)
	model.scale = Vector3.ONE*mount_scale(model,Catalog.DEFINITIONS[kind].size)
	return model
