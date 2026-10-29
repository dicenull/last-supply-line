extends RefCounted
## Shared, deterministic low-poly models for battlefield loot and inventory previews.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const MOUNT_MARGIN = 0.045
const MOUNT_HEIGHT = 1.05
const BARREL_REST = 0.6
const RECOIL_TRAVEL = 0.2
const COLORS = {"iron":"657679","dark":"29383c","brass":"d5aa62","paint":"829078","glass":"70d8dd","coal":"263341","rust":"ad704e","steel":"b1c3c8","fuel":"609b88"}
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
	# The model already has a small quality badge; only its ground marker glows.
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
	if kind in ["scrap","coal","shell","steel","fuel"]:
		build_resource(root,kind)
		return root
	var spec: Dictionary = Catalog.Data.ITEMS[kind]
	var family = Catalog.family(kind)
	var trim: String = "paint"
	box(root,Vector3(0,0.1,0),Vector3(1.7,0.2,1.2),"dark")
	box(root,Vector3(0,0.23,0),Vector3(1.6,0.08,1.1),trim)
	if not Catalog.part_slot(kind).is_empty():
		build_vehicle_part(root,spec,trim)
		quality_details(root,spec,rarity)
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
		elif family == "rear_gun":
			box(root,Vector3(-0.45,0.85,0),Vector3(0.2,0.4,1.15),"iron")
			if spec.get("interceptor",false):
				beam(root,Vector3(-0.4,0.9,0),Vector3(-0.4,1.35,0),0.07,"iron")
				box(root,Vector3(-0.4,1.3,0),Vector3(0.14,0.32,0.7),"brass")
				for z in [-0.22,0.22]: box(root,Vector3(-0.31,1.32,z),Vector3(0.04,0.16,0.15),"glass")
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
	quality_details(root,spec,rarity)
	historical_details(root,spec,trim)
	# Profiles and revisions change the mechanism, not just the name or color.
	if spec.profile in ["focus","heavy","power"]:
		box(root,Vector3(-0.55,0.6,-0.5),Vector3(0.18,0.6,0.18),trim)
	elif spec.profile in ["rapid","mobile","economy","efficient"]:
		for z in [-0.45,0.45]: box(root,Vector3(-0.55,0.4,z),Vector3(0.4,0.16,0.15),"brass")
	for i in range(int(spec.level)):
		box(root,Vector3(-0.7+i*0.15,0.3,0.53),Vector3(0.085,0.08,0.12),"brass")
	return root

func quality_details(root: Node3D, spec: Dictionary, rarity: String):
	var rank = Catalog.RARITIES.keys().find(rarity)
	var upgrade = Node3D.new()
	upgrade.name = "QualityUpgrade"
	root.add_child(upgrade)
	# Neutral metal mechanisms change silhouette; a single plate carries color.
	var badge = box(upgrade,Vector3(-0.46,0.4,0.615),Vector3(0.35,0.18,0.04),Catalog.RARITIES[rarity].color)
	badge.name = "RarityAccent"
	badge.set_meta("rarity_accent",true)
	if rank == 0: return
	for side in [-1,1]:
		box(upgrade,Vector3(-0.42,0.52,side*0.56),Vector3(0.58,0.38,0.1),"iron")
	if rank >= 2:
		for i in range(3): box(upgrade,Vector3(-0.55+i*0.2,0.86,-0.48),Vector3(0.1,0.5,0.25),"dark")
	if rank >= 3:
		if spec.genre == "secondary" or not str(spec.get("slot","")).is_empty():
			for side in [-1,1]: cylinder(upgrade,Vector3(-0.55,0.9,side*0.4),0.17,0.7,"iron")
		else:
			beam(upgrade,Vector3(-0.6,0.6,0),Vector3(-0.6,1.4,0),0.1,"brass")
			box(upgrade,Vector3(-0.6,1.42,0),Vector3(0.48,0.16,0.35),"dark")

func historical_details(root: Node3D, spec: Dictionary, trim: String):
	var level = int(spec.level)
	var family: String = spec.family
	var revision = float(level-1)/9.0
	if spec.genre == "secondary":
		var barrel: Node3D = root.get_node("Barrel")
		barrel.scale.x = 1.0+revision*0.18
		var muzzle: Vector3 = root.get_meta("muzzle")
		muzzle.x = BARREL_REST+(muzzle.x-BARREL_REST)*barrel.scale.x
		root.set_meta("muzzle",muzzle)
		for z in [-0.48,0.48]:
			var trunnion = cylinder(root,Vector3(0.1,0.64,z),0.15,0.14,"iron")
			trunnion.rotation.x = PI/2
		match family:
			"left_gun", "right_gun":
				for z in [-0.52,0.52]:
					var shield = box(root,Vector3(0.38,0.7,z),Vector3(0.1,0.88+revision*0.18,0.4),"paint")
					shield.rotation.y = -signf(z)*0.25
				box(root,Vector3(-0.38,0.78,0),Vector3(0.4,0.27,0.4),"iron")
			"rapid_gun":
				for z in [-0.225,0.225]: beam(barrel,Vector3(-0.35,0.7,z),Vector3(0.25,0.7,z),0.21,"paint")
				box(root,Vector3(-0.6,0.55,-0.45),Vector3(0.42,0.48,0.3),"iron")
				beam(root,Vector3(-0.5,0.75,-0.4),Vector3(0.05,0.75,-0.25),0.04,"brass")
			"long_gun":
				box(barrel,Vector3(muzzle.x/barrel.scale.x-BARREL_REST-0.13,0.7,0),Vector3(0.25,0.27,0.43),"iron")
				beam(barrel,Vector3(-0.4,0.47,0),Vector3(0.2,0.47,0),0.09,"brass")
			"mortar_gun":
				for z in [-0.5,0.5]: beam(root,Vector3(0.4,0.3,z),Vector3(0.65,0.98,0),0.055,"iron")
				cylinder(root,Vector3(-0.35,0.3,0),0.42,0.09,"iron")
			"rear_gun":
				for z in [-0.5,0.5]: box(root,Vector3(0.22,0.64,z),Vector3(0.16,0.85,0.35),"paint")
			"scatter_gun":
				box(barrel,Vector3(0.2,0.5,0),Vector3(0.15,0.12,1.3),"iron")
			"arc_gun":
				for z in [-0.4,0.4]:
					for y in [0.5,0.66,0.82]: cylinder(root,Vector3(-0.5,y,z),0.13,0.08,"glass")
		if spec.profile == "focus": beam(root,Vector3(-0.45,1.02,-0.35),Vector3(0.4,1.02,-0.35),0.07,"dark")
		elif spec.profile == "rapid": box(root,Vector3(-0.4,0.52,0.48),Vector3(0.55,0.38,0.28),trim)
		for i in range(2+level/3):
			var band = cylinder(barrel,Vector3(-0.2+i*0.13,0.7,0),0.19,0.035,"brass")
			band.rotation.z = PI/2
	else:
		# Larger heat exchangers, deeper shields and wider mechanisms identify revisions.
		for child in root.get_children():
			if child is Node3D and child.position.y > 0.3:
				child.scale.y *= 1.0+revision*0.25
				child.position.y += revision*0.12
		match family:
			"armor":
				for x in [-0.65,0,0.65]:
					for y in [0.45,0.9]:
						var rivet = cylinder(root,Vector3(x,y,-0.45),0.045,0.04,"brass")
						rivet.rotation.x = PI/2
			"skirts":
				for x in [-0.6,0,0.6]: beam(root,Vector3(x,0.85,0),Vector3(x,0.85,-0.4),0.045,"iron")
			"supercharger":
				for z in [-0.22,0.22]: beam(root,Vector3(-0.5,0.48,z),Vector3(0.5,0.48,z),0.19,"paint")
				var pulley = cylinder(root,Vector3(-0.62,0.5,0),0.27,0.12,"dark")
				pulley.rotation.z = PI/2
			"economizer":
				for i in range(3+level/2):
					beam(root,Vector3(-0.7,0.42+i*0.075,-0.3),Vector3(0.7,0.42+i*0.075,-0.3),0.045,"brass")
			"rangefinder":
				box(root,Vector3(0,0.93,-0.16),Vector3(0.32,0.22,0.32),"dark")
				for x in [-0.65,0.65]: box(root,Vector3(x,1.1,0.25),Vector3(0.35,0.07,0.3),"paint")
			"servo":
				beam(root,Vector3(-0.65,0.48,-0.42),Vector3(0.65,0.48,-0.42),0.11,"iron")
				for i in range(6): box(root,Vector3(-0.45+i*0.18,0.49,-0.42),Vector3(0.06,0.27,0.27),"brass")
			"salvage_arm":
				for z in [-0.35,0.35]: beam(root,Vector3(-0.6,0.3,z),Vector3(-0.3,1.2,0),0.065,"iron")
				var drum = cylinder(root,Vector3(-0.25,0.5,0),0.22,0.6,"dark")
				drum.rotation.x = PI/2
			"blast_fuse":
				for x in [-0.4,0,0.4]:
					var nose = cylinder(root,Vector3(x,1.12,0),0.06,0.16,"dark")
					nose.scale.x = 0.75
			"drum_loader":
				box(root,Vector3(0.5,0.6,0),Vector3(0.62,0.16,0.38),"iron")
				for i in range(3): cylinder(root,Vector3(0.4+i*0.15,0.78,0),0.06,0.25,"brass")
		if spec.profile in ["heavy","power","focus"]:
			for z in [-0.5,0.5]: box(root,Vector3(0,0.52,z),Vector3(1.25,0.32+revision*0.2,0.09),"paint")
		elif spec.profile in ["mobile","economy","efficient"]:
			for x in [-0.55,0,0.55]: box(root,Vector3(x,0.35,-0.5),Vector3(0.12,0.25,0.12),"iron")

func spur_gear(root: Node3D, center: Vector3, radius: float, trim: String):
	var gear = cylinder(root,center,radius,0.14,"iron")
	gear.rotation.x = PI/2
	for j in range(12):
		var angle = j*TAU/12
		var tooth = box(root,center+Vector3(cos(angle)*radius,sin(angle)*radius,0),Vector3(0.12,0.1,0.18),trim)
		tooth.rotation.z = angle
	var hub = cylinder(root,center+Vector3(0,0,0.1),radius*0.28,0.16,"brass")
	hub.rotation.x = PI/2

func build_vehicle_part(root: Node3D, spec: Dictionary, trim: String):
	if spec.has("historical_model"):
		preload("res://scripts/historical_part_model.gd").build(self,root,spec)
		return
	var variant = int(spec.visual)
	match spec.slot:
		"gear":
			box(root,Vector3(0,0.35,-0.23),Vector3(1.45,0.2,0.65),"paint")
			if variant == 0:
				# Constant-mesh: parallel shafts and alternating gear diameters.
				for y in [0.52,0.9]:
					beam(root,Vector3(-0.72,y,0),Vector3(0.72,y,0),0.055,"iron")
					for i in range(3): spur_gear(root,Vector3(-0.48+i*0.48,y,0.08),0.18 if i%2 == 0 else 0.23,trim)
			elif variant == 1:
				# Sun, planets and annular ring of a planetary transmission.
				var ring = TorusMesh.new()
				ring.inner_radius = 0.44
				ring.outer_radius = 0.52
				var node = part(root,ring,Vector3(0,0.85,0),"paint")
				node.rotation.x = PI/2
				spur_gear(root,Vector3(0,0.85,0.05),0.17,"brass")
				for angle in [PI/2,PI*7/6,PI*11/6]: spur_gear(root,Vector3(cos(angle)*0.31,0.85+sin(angle)*0.31,0.08),0.12,trim)
			else:
				# Paired differential housings joined by the cross-drive shaft.
				beam(root,Vector3(-0.75,0.72,0),Vector3(0.75,0.72,0),0.1,"brass")
				for x in [-0.42,0.42]:
					spur_gear(root,Vector3(x,0.72,0),0.3,trim)
					box(root,Vector3(x,0.73,-0.21),Vector3(0.5,0.55,0.35),"paint")
				spur_gear(root,Vector3(0,0.95,0.15),0.14,"brass")
		"engine":
			box(root,Vector3(0,0.45,0),Vector3(1.4,0.35,0.65),"paint")
			# Six cylinder heads per bank; the V12 and twin inline six have distinct layouts.
			for side in ([0] if variant == 0 else [-1,1]):
				for i in range(6):
					var head = cylinder(root,Vector3(-0.55+i*0.22,0.76,side*0.22),0.105,0.4,"iron")
					if variant == 1: head.rotation.x = side*0.5
				box(root,Vector3(0,1.0,side*0.28),Vector3(1.35,0.13,0.2),"paint")
				beam(root,Vector3(-0.6,0.65,side*0.43),Vector3(0.6,0.65,side*0.43),0.06,"brass")
			var fan = cylinder(root,Vector3(0.76,0.65,0),0.3,0.1,"dark")
			fan.rotation.z = PI/2
			for i in range(6):
				var blade = box(root,Vector3(0.83,0.65,0),Vector3(0.04,0.52,0.06),"iron")
				blade.rotation.x = i*PI/3
			if variant == 1:
				for x in [-0.37,0.37]: cylinder(root,Vector3(x,1.2,0),0.21,0.19,"dark")
			elif variant == 2:
				for side in [-1,1]: box(root,Vector3(-0.42,1.15,side*0.28),Vector3(0.43,0.2,0.22),trim)
			else: cylinder(root,Vector3(-0.4,1.17,0),0.16,0.22,"dark")
		"tracks":
			for z in [-0.4,0.4]:
				box(root,Vector3(0,0.5,z),Vector3(1.5,0.55,0.26),"dark")
				for i in range(4):
					var wheel = cylinder(root,Vector3(-0.5+i/3.0,0.5,z+signf(z)*0.15),0.19,0.08,"iron")
					wheel.rotation.x = PI/2
				for i in range(7):
					var x = -0.66+i*0.22
					for y in [0.24,0.8]:
						box(root,Vector3(x,y,z),Vector3(0.19,0.08,0.3),"iron")
						if variant == 1: box(root,Vector3(x,y,z+signf(z)*0.22),Vector3(0.12,0.07,0.2),trim)
						elif variant == 2: box(root,Vector3(x,y+0.045,z),Vector3(0.14,0.04,0.24),"coal")
		"cannon":
			cylinder(root,Vector3(-0.3,0.48,0),0.5,0.48,"paint")
			box(root,Vector3(-0.43,0.74,0),Vector3(0.6,0.4,0.5),"iron")
			var length = 1.4 if variant == 1 else 0.8 if variant == 2 else 1.05
			var radius = 0.19 if variant == 2 else 0.11
			beam(root,Vector3(-0.2,0.7,0),Vector3(length,0.7,0),radius,"iron")
			beam(root,Vector3(length-0.12,0.7,0),Vector3(length,0.7,0),radius*1.25,"dark")
			box(root,Vector3(0,0.7,0),Vector3(0.2,0.6,0.85 if variant == 2 else 0.65),"paint")
			for z in [-0.22,0.22]: beam(root,Vector3(-0.4,0.48,z),Vector3(0.5,0.48,z),0.07,"brass")
			if variant == 1:
				box(root,Vector3(1.3,0.7,0),Vector3(0.25,0.28,0.42),"iron")
				for z in [-0.215,0.215]: box(root,Vector3(1.3,0.7,z),Vector3(0.13,0.12,0.01),"dark")
			elif variant == 2: cylinder(root,Vector3(-0.5,1.02,0),0.17,0.15,trim)

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
				var plate = box(root,Vector3((i%2-0.5)*0.55,0.15+i*0.13,0),Vector3(0.85,0.16,0.6),"rust" if i%2 == 0 else "iron")
				plate.rotation.y = i*0.7
			box(root,Vector3(0.1,0.78,0),Vector3(0.9,0.12,0.14),"steel")
		"coal":
			for i in range(5):
				var mesh = SphereMesh.new()
				mesh.radius = 0.3
				mesh.height = 0.5
				mesh.radial_segments = 5
				mesh.rings = 3
				part(root,mesh,Vector3(cos(i*2.4)*0.35,0.25+(0.25 if i == 4 else 0),sin(i*2.4)*0.35),"coal")
		"steel":
			for i in range(3):
				box(root,Vector3(0,0.13+i*0.23,0),Vector3(1.15-i*0.1,0.2,0.7),"steel")
		"fuel":
			cylinder(root,Vector3(0,0.5,0),0.46,0.95,"fuel")
			for y in [0.1,0.8]: cylinder(root,Vector3(0,y,0),0.48,0.09,"iron")
			cylinder(root,Vector3(0.2,1.0,0),0.1,0.08,"brass")
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
	var cache_key = kind+":"+str(model.get_meta("rarity","normal"))
	if weapon_mounts.has(cache_key): return weapon_mounts[cache_key]
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
	weapon_mounts[cache_key] = mount
	return mount

func build_mounted(kind: String, rarity: String = "normal") -> Node3D:
	var root = Node3D.new()
	root.set_meta("kind",kind)
	root.set_meta("rarity",rarity)
	var model = build(kind,rarity)
	root.add_child(model)
	var low = Vector3(INF,INF,INF)
	var high = -low
	for point in vertices(model):
		low = low.min(point)
		high = high.max(point)
	var span = high-low
	var footprint = Vector2(Catalog.DEFINITIONS[kind].size)-Vector2.ONE*MOUNT_MARGIN*2
	model.scale = Vector3(footprint.x/span.x,minf(MOUNT_HEIGHT/span.y,1.0),footprint.y/span.z)
	model.position = Vector3(-(low.x+high.x)*0.5,-low.y,-(low.z+high.z)*0.5)*model.scale
	return root
