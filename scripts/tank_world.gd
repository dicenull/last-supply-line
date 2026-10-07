extends Node3D
## Native low-poly 3D diorama. Grid coordinates are on the exposed tank deck.
const F = preload("res://scripts/factory.gd")
const DECK_Y = 2.72
const TURRET_CENTER = Vector3(2.6,4.08,0)
const BARREL_REST = 2.4
var camera: Camera3D
var equipment: Node3D
var roof: Node3D
var goods: Node3D
var marker: MeshInstance3D
var muzzle: MeshInstance3D
var mats: Dictionary = {}
var material_meshes: Dictionary = {}
var rendered_layout = ""
var goods_pool: Array = []
var machines: Dictionary = {}
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
var shot_time = 0.0

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

func mesh_node(parent: Node3D, mesh: Mesh, pos: Vector3, mat: String) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mats[mat]
	node.position = pos
	if mat.begins_with("turret_"): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: String, sides: int = 10, top: float = -1) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = mini(sides,8)
	return mesh_node(parent,mesh,pos,mat)

func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: String):
	var node = cylinder(parent,(a+b)/2,radius,a.distance_to(b),mat,8)
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
	material("brass","bb9750",0.55)
	material("wood","655038")
	material("floor","4b5045",0.2)
	material("floor2","515648",0.2)
	material("rust","955f3e",0.25)
	material("coal","322d25")
	material("fire","ee9f47",0.1,1.8)
	material("shell","d3ac5b",0.6)
	material("tip","d8c9a0",0.6)
	material("mud","44483c")
	material("stone","696553")
	material("mark","dfd3a6")
	material("green","acb977",0,0.3)
	material("red","c26a48",0,0.3)
	material("inlet","70d4cc",0,0.25)
	material("outlet","ffcf65",0,0.25)
	material("kiln","ae4f32")
	material("fuel","5b9b99")
	for spec in [["turret_armor","8f916c",0.12],["turret_edge","c6bd91",0.18],["turret_dark","505644",0.22]]:
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

func update_camera():
	var target = Vector3(0,1.7,0)
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*34
	camera.look_at(target,Vector3.UP)
	camera.size = zoom

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
	for key in ["turret_armor","turret_edge","turret_dark"]:
		var mat: StandardMaterial3D = mats[key]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if roof_closed else BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 1.0 if roof_closed else float(mat.get_meta("interior_alpha"))
	marker.visible = false

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

	# A rear engine compartment, exhaust stacks and front driver's armored cabin.
	box(self,Vector3(-7.85,3.0,0),Vector3(1.55,1.0,6.0),"armor")
	for z in [-1.8,1.8]:
		cylinder(self,Vector3(-7.85,3.8,z),0.17,1.4,"dark",8)


	# Low rectangular driver's deck; the old wedge-shaped upper cabin is removed.
	box(self,Vector3(7.6,3.13,0),Vector3(1.85,0.82,3.7),"armor")
	box(self,Vector3(8.54,3.2,0),Vector3(0.03,0.12,1.0),"dark")
	# A translucent, enlarged turret above the forward half of the factory deck.
	build_turret()
	roof = Node3D.new()
	add_child(roof)
	box(roof,Vector3(0,3.9,0),Vector3(14.1,0.24,8.15),"armor")
	box(roof,Vector3(-3,4.08,0),Vector3(1.7,0.13,1.4),"edge")
	roof.visible = false

func track(side: int):
	var profile = PackedVector2Array([Vector2(-9,1),Vector2(-7.3,3.4),Vector2(6.9,3.4),Vector2(9,1.45),Vector2(7,0.25),Vector2(-7.7,0.25)])
	var plate = prism(self,profile,side*5.7-0.13,side*5.7+0.13,"armor")
	plate.rotation.x = PI/2
	plate.scale.z = -1
	# Six broad faces replace the dozens of individual tread links.
	for i in profile.size():
		var a = profile[i]
		var b = profile[(i+1)%profile.size()]
		var midpoint = (a+b)/2
		var tread = box(self,Vector3(midpoint.x,midpoint.y,side*5.05),Vector3(a.distance_to(b),0.18,1.2),"track")
		tread.rotation.z = atan2(b.y-a.y,b.x-a.x)
	for i in range(5):
		var wheel = cylinder(self,Vector3(-5.8+i*2.9,1.32,side*5.83),0.68,0.16,"dark",6)
		wheel.rotation.x = PI/2
	box(self,Vector3(-4.0,1.7,side*5.86),Vector3(0.4,1.8,0.05),"mark")

func build_turret():
	cylinder(self,TURRET_CENTER-Vector3(0,0.08,0),3.55,0.24,"turret_dark",8)
	turret = Node3D.new()
	turret.position = TURRET_CENTER
	add_child(turret)
	cylinder(turret,Vector3(0,0.9,0),3.4,1.8,"turret_armor",8,3.4)
	box(turret,Vector3(-0.4,1.88,0),Vector3(1.45,0.16,1.45),"turret_edge")
	barrel = Node3D.new()
	barrel.position = Vector3(BARREL_REST,1.0,0)
	turret.add_child(barrel)
	beam(barrel,Vector3.ZERO,Vector3(4.0,0,0),0.25,"turret_dark")
	var sleeve = cylinder(barrel,Vector3(0.35,0,0),0.44,1.2,"turret_edge",6)
	sleeve.rotation.z = -PI/2
	muzzle = cylinder(barrel,Vector3(4.25,0,0),0.42,0.7,"fire",4,0.05)
	muzzle.rotation.z = -PI/2
	muzzle.visible = false

func fire_visual():
	var direction = Vector3(cos(turret.rotation.y),0,-sin(turret.rotation.y))
	var origin = muzzle.global_position
	var shot = Node3D.new()
	add_child(shot)
	shot.global_position = origin
	beam(shot,Vector3.ZERO,-direction*1.8,0.085,"fire")
	projectiles.append({"node":shot,"origin":origin,"dir":direction,"age":0.0})
	recoil = 0.25
	shot_time = 0.14
	fired_directions.append(visual_shots%4)
	if fired_directions.size() > 32: fired_directions.pop_front()
	visual_shots += 1
	target_angle = fposmod(visual_shots*PI/2,TAU)

func update_gun(factory, delta: float):
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

func direction_arrow(parent: Node3D, height: float):
	box(parent,Vector3(0,height,0),Vector3(0.44,0.018,0.06),"brass")
	prism(parent,PackedVector2Array([Vector2(0.3,0),Vector2(0.1,-0.13),Vector2(0.1,0.13)]),height,height+0.025,"brass")

func flow_ports(kind: String, parent: Node3D, inputs: Array):
	# All four sides accept input in the simulation; output is directional.
	for side in range(4):
		var port = Node3D.new()
		parent.add_child(port)
		port.rotation.y = -side*PI/2
		if kind not in ["source","coal_source"] and side in inputs:
			# Recessed receiving tray; geometry communicates flow without small arrows.
			box(port,Vector3(0.43,0.16,-0.19),Vector3(0.14,0.05,0.25),"dark")
			for z in [-0.32,-0.06]: box(port,Vector3(0.43,0.20,z),Vector3(0.14,0.035,0.035),"inlet")
		if kind not in ["gun","engine"] and (side == 0 or (kind == "splitter" and side == 1)):
			box(port,Vector3(0.35,0.17,0.18),Vector3(0.26,0.055,0.27),"outlet")

func machine(kind: String, parent: Node3D, inputs: Array = [2]) -> Dictionary:
	var parts: Dictionary = {}
	match kind:
		"belt", "splitter":
			box(parent,Vector3(0,0.08,0),Vector3(0.93,0.12,0.7),"dark")
			direction_arrow(parent,0.24)
			if kind == "splitter":
				box(parent,Vector3(0,0.12,0.27),Vector3(0.65,0.16,0.53),"dark")
				var arm = Node3D.new()
				parent.add_child(arm)
				arm.rotation.y = -PI/2
				direction_arrow(arm,0.26)
		"furnace":
			box(parent,Vector3(0,0.33,0),Vector3(0.60,0.56,0.56),"kiln")
			# Open glowing hearth on both visible faces, with a tall chimney.
			for z in [-0.29,0.29]:
				box(parent,Vector3(0,0.34,z),Vector3(0.37,0.30,0.025),"dark")
				box(parent,Vector3(0,0.30,z*1.04),Vector3(0.25,0.16,0.025),"fire")
			cylinder(parent,Vector3(-0.18,0.86,-0.15),0.10,0.66,"dark",6)
			cylinder(parent,Vector3(-0.18,1.20,-0.15),0.14,0.08,"rust",6)
			box(parent,Vector3(0,0.63,0),Vector3(0.64,0.06,0.60),"rust")
			parts.fire = box(parent,Vector3(0.20,0.67,0.12),Vector3(0.18,0.04,0.20),"fire")
		"press":
			box(parent,Vector3(0,0.10,0),Vector3(0.62,0.16,0.64),"steel")
			for z in [-0.24,0.24]: box(parent,Vector3(0,0.57,z),Vector3(0.15,0.92,0.12),"steel")
			box(parent,Vector3(0,1.03,0),Vector3(0.38,0.17,0.65),"steel")
			cylinder(parent,Vector3(0,0.87,0),0.09,0.22,"brass",6)
			parts.piston = box(parent,Vector3(0,0.74,0),Vector3(0.40,0.16,0.37),"steel")
			box(parent,Vector3(0,0.29,0),Vector3(0.38,0.13,0.38),"dark")
		"depot":
			box(parent,Vector3(0,0.12,0),Vector3(0.62,0.20,0.62),"wood")
			for z in [-0.28,0.28]: box(parent,Vector3(0,0.32,z),Vector3(0.62,0.35,0.05),"wood")
			# Large embossed shell silhouettes identify the rack even when empty.
			for x in [-0.19,0,0.19]:
				cylinder(parent,Vector3(x,0.33,-0.30),0.055,0.22,"shell",6)
				cylinder(parent,Vector3(x,0.48,-0.30),0.055,0.09,"tip",6,0)
		"source", "coal_source":
			cylinder(parent,Vector3(0,0.32,0),0.22,0.46,"rust",4,0.44)
			box(parent,Vector3(0,0.56,0),Vector3(0.56,0.025,0.56),"dark")
			for offset in [Vector3(-0.15,0.57,0),Vector3(0.12,0.59,0.13),Vector3(0.03,0.57,-0.17)]:
				var scrap = make_good("coal" if kind == "coal_source" else "scrap")
				parent.add_child(scrap)
				scrap.position = offset
		"refinery":
			box(parent,Vector3(0,0.10,0),Vector3(0.65,0.14,0.65),"dark")
			cylinder(parent,Vector3(-0.14,0.58,0),0.19,0.92,"fuel",6)
			cylinder(parent,Vector3(0.19,0.39,0),0.14,0.52,"brass",6)
			beam(parent,Vector3(-0.14,0.98,0),Vector3(0.19,0.65,0),0.045,"steel")
			box(parent,Vector3(-0.14,0.18,0.19),Vector3(0.18,0.15,0.025),"fire")
		"engine":
			box(parent,Vector3(0,0.26,0),Vector3(0.68,0.44,0.60),"fuel")
			for x in [-0.22,0,0.22]: box(parent,Vector3(x,0.53,0),Vector3(0.09,0.16,0.5),"dark")
			cylinder(parent,Vector3(0.19,0.77,-0.17),0.07,0.35,"dark",6)
		"gun":
			box(parent,Vector3(0,0.22,0),Vector3(0.62,0.40,0.62),"dark")
			for z in [-0.18,0,0.18]:
				var round_node = make_good("shell")
				parent.add_child(round_node)
				round_node.position = Vector3(0,0.44,z)
			beam(parent,Vector3(0.23,0.3,0),Vector3(0.23,0.95,0),0.14,"brass")
	if kind not in ["belt","splitter"]: flow_ports(kind,parent,inputs)
	return parts

func make_good(kind: String) -> Node3D:
	var n = Node3D.new()
	match kind:
		"scrap":
			var a = box(n,Vector3(0,0.06,0),Vector3(0.3,0.12,0.21),"rust")
			a.rotation_degrees = Vector3(15,20,10)
		"coal":
			var chunk = cylinder(n,Vector3(0,0.12,0),0.19,0.23,"coal",5,0.11)
			chunk.rotation.z = 0.2
		"fuel":
			cylinder(n,Vector3(0,0.16,0),0.13,0.3,"fuel",6)
			for y in [0.06,0.25]: cylinder(n,Vector3(0,y,0),0.14,0.035,"brass",6)
		"steel":
			box(n,Vector3(0,0.08,0),Vector3(0.42,0.16,0.28),"steel")
		"shell":
			var casing = cylinder(n,Vector3(-0.05,0.09,0),0.085,0.28,"shell",8)
			casing.rotation.z = -PI/2
			var nose = cylinder(n,Vector3(0.15,0.09,0),0.085,0.14,"tip",8,0.0)
			nose.rotation.z = -PI/2
	n.set_meta("kind",kind)
	return n

func good_height(kind: String) -> float:
	return {"furnace":0.83,"press":0.38,"source":0.4,"depot":0.35,"gun":0.4,"refinery":1.08,"engine":0.65,"coal_source":0.6}.get(kind,0.25)

func item_frames(factory) -> Array:
	var frames: Array = []
	var arrivals: Dictionary = {}
	for move in factory.moves: arrivals[move.to] = true
	for p in factory.cells:
		var c: Dictionary = factory.cells[p]
		var count = c.items.size()-(1 if arrivals.has(p) else 0)
		for i in range(count):
			var offset = Vector3(0,good_height(c.kind),0)
			if c.kind == "depot": offset += Vector3(-0.21+int(i/4)*0.42,0,-0.29+(i%4)*0.19)
			frames.append({"kind":c.items[i],"pos":cell_position(p)+offset,"dir":c.dir})
	for move in factory.moves:
		if not factory.cells.has(move.from) or not factory.cells.has(move.to): continue
		var a = cell_position(move.from)+Vector3(0,good_height(factory.cells[move.from].kind),0)
		var b = cell_position(move.to)+Vector3(0,good_height(factory.cells[move.to].kind),0)
		frames.append({"kind":move.item,"pos":a.lerp(b,clampf(factory.clock/F.TICK,0,1)),"dir":factory.cells[move.from].dir})
	return frames

func sync(factory, hovered: Vector2i, selected: String, direction: int, delta: float):
	var signature = str(factory.layout())
	if signature != rendered_layout:
		rendered_layout = signature
		for child in equipment.get_children():
			equipment.remove_child(child)
			child.queue_free()
		machines.clear()
		for p in factory.cells:
			var c: Dictionary = factory.cells[p]
			var n = Node3D.new()
			equipment.add_child(n)
			n.position = cell_position(p)
			n.rotation.y = -c.dir*PI/2
			var inputs: Array = []
			for side in range(4):
				var neighbor: Vector2i = p+F.DIRS[side]
				if not factory.cells.has(neighbor): continue
				var upstream: Dictionary = factory.cells[neighbor]
				if upstream.kind in ["gun","engine"]: continue
				var toward = (side+2)%4
				if upstream.dir == toward or (upstream.kind == "splitter" and (upstream.dir+1)%4 == toward):
					inputs.append((side-c.dir+4)%4)
			if inputs.is_empty(): inputs = [2]
			machines[p] = machine(c.kind,n,inputs)
	for p in machines:
		var c: Dictionary = factory.cells[p]
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
		goods_pool[i].position = frame.pos
		goods_pool[i].rotation.y = -frame.dir*PI/2
	marker.visible = not roof_closed and factory.inside(hovered)
	if marker.visible:
		marker.position = cell_position(hovered)+Vector3(0,0.015,0)
		marker.material_override = mats.red if hovered in F.BLOCKS or F.PORTS.has(hovered) else mats.green
	update_gun(factory,delta)
