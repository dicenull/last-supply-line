extends Control
## Presentation only: the expedition owns deterministic offers and grants the selected item.
signal finished
signal cue(kind: String)
const Models = preload("res://scripts/item_model.gd")
const Gear = preload("res://scripts/equipment_catalog.gd")
const Style = preload("res://scripts/ui_style.gd")
const DURATION = 6.8
var active = false
var age = 0.0
var stage = 1
var finale = false
var font: Font
var viewport: SubViewport
var scene: Node3D
var plane: Node3D
var camera: Camera3D
var crates: Array = []
var props: Array = []
var particles: Array = []
var models = Models.new()
var skip_button: Button
var overlay: Control
var legendary = false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var container = SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1440,940)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_titles)
	add_child(overlay)
	skip_button = Button.new()
	skip_button.add_theme_font_override("font",font)
	skip_button.add_theme_stylebox_override("normal",Style.style(Color("17262d"),Color("d5aa62")))
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.pressed.connect(skip)
	add_child(skip_button)
	hide()

func start(items: Array, sector: int, is_final: bool = false):
	cancel()
	stage = sector
	finale = is_final
	legendary = items.any(func(item): return item.get("rarity","") == "legendary")
	active = true
	age = 0
	visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene = Node3D.new()
	viewport.add_child(scene)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17242d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("afc6cc")
	env.ambient_light_energy = 0.65
	environment.environment = env
	scene.add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_color = Color("ffdba3")
	sun.light_energy = 1.6
	scene.add_child(sun)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(21,19,30)
	camera.look_at(Vector3(0,5,0))
	camera.fov = 52
	models.box(scene,Vector3(0,-0.4,0),Vector3(180,0.6,180),"303b39")
	models.box(scene,Vector3(0,-0.06,0),Vector3(100,0.1,17),"252e2e")
	for x in range(-40,41,8):
		models.box(scene,Vector3(x,0.02,0),Vector3(4,0.03,0.22),"b5aa8b")
		for z in [-9,9]: models.box(scene,Vector3(x,0.12,z),Vector3(0.3,0.2,0.3),"brass")
	build_plane()
	for i in range(3): build_crate(i,items[i] if i < items.size() else {})
	cue.emit("airdrop")
	advance(0)

func build_plane():
	plane = Node3D.new()
	scene.add_child(plane)
	var fuselage = CapsuleMesh.new()
	fuselage.radius = 1.25
	fuselage.height = 15
	var body = models.part(plane,fuselage,Vector3.ZERO,"paint")
	body.rotation.z = PI/2
	models.box(plane,Vector3(5.5,0.8,0),Vector3(1.8,0.55,1.8),"dark")
	models.box(plane,Vector3(0,0.25,0),Vector3(4,0.35,21),"paint")
	models.box(plane,Vector3(5.6,1.1,0),Vector3(1.8,0.08,1.8),"paint")
	models.box(plane,Vector3(-5.5,0.6,0),Vector3(3,0.25,8),"paint")
	models.box(plane,Vector3(-5.8,2,0),Vector3(2.8,3.5,0.3),"paint")
	for z in [-7.2,-3.8,3.8,7.2]:
		models.box(plane,Vector3(1,0,z),Vector3(4,1,1),"dark")
		var prop = Node3D.new()
		plane.add_child(prop)
		prop.position = Vector3(3.1,0,z)
		models.box(prop,Vector3.ZERO,Vector3(0.12,3.5,0.16),"steel")
		models.box(prop,Vector3.ZERO,Vector3(0.12,0.16,3.5),"steel")
		props.append(prop)
	for z in [-9,9]: models.box(plane,Vector3(0,0.45,z),Vector3(2,0.05,0.5),"brass")

func build_crate(index: int, item: Dictionary):
	var root = Node3D.new()
	scene.add_child(root)
	var rarity: String = item.get("rarity","rare")
	var color: String = Gear.RARITIES[rarity].color
	models.box(root,Vector3(0,0.6,0),Vector3(3,1.2,2.5),"paint")
	for x in [-1.25,1.25]: models.box(root,Vector3(x,0.65,0),Vector3(0.16,1.35,2.7),"steel")
	models.box(root,Vector3(0,0.7,1.26),Vector3(1.2,0.22,0.04),color)
	var lid = Node3D.new()
	root.add_child(lid)
	lid.position = Vector3(0,1.3,-1.25)
	models.box(lid,Vector3(0,0,1.25),Vector3(3.1,0.2,2.6),"dark")
	var chute = Node3D.new()
	root.add_child(chute)
	var dome = SphereMesh.new()
	dome.radius = 3.4
	dome.height = 6.8
	var canopy = models.part(chute,dome,Vector3(0,6,0),"c3bca3")
	canopy.scale.y = 0.28
	for k in range(8):
		var theta = k*TAU/8
		models.beam(chute,Vector3(cos(theta),1,sin(theta)),Vector3(cos(theta)*3.2,5.9,sin(theta)*3.2),0.025,"steel")
	var cargo = models.build(item.get("kind","scrap"),rarity)
	root.add_child(cargo)
	cargo.scale = Vector3.ONE*1.35
	cargo.visible = false
	var light = OmniLight3D.new()
	root.add_child(light)
	light.position.y = 3
	light.light_color = Color(color)
	light.omni_range = 10
	light.light_energy = 0
	var glow = StandardMaterial3D.new()
	glow.albedo_color = Color(Color(color),0.22)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rays: Array = []
	for k in range(8 if rarity == "legendary" else 4):
		var theta = k*TAU/(8 if rarity == "legendary" else 4)
		var ray = models.cylinder(root,Vector3(cos(theta)*1.8,4.5,sin(theta)*1.8),0.13 if rarity == "legendary" else 0.06,9,color)
		ray.material_override = glow
		rays.append(ray)
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 1.85
	ring_mesh.outer_radius = 2.0
	var ring = models.part(root,ring_mesh,Vector3(0,0.08,0),color)
	ring.material_override = glow
	var smoke: Array = []
	for k in range(8):
		var sphere = SphereMesh.new()
		sphere.radius = 0.7
		sphere.height = 1.4
		sphere.radial_segments = 8
		sphere.rings = 4
		var puff = models.part(root,sphere,Vector3.ZERO,"807961")
		smoke.append(puff)
	# Particle pool is fixed per crate; gold support creates more sparks and taller flares.
	for k in range(42 if rarity == "legendary" else 16):
		var spark = models.box(scene,Vector3.ZERO,Vector3.ONE*(0.08 if k%3 else 0.22),color if k%3 else "b6b19d")
		var spark_material = StandardMaterial3D.new()
		spark_material.albedo_color = Color(color) if k%3 else Color("b6b19d")
		if k%3: spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spark.material_override = spark_material
		particles.append({"node":spark,"index":index,"n":k,"gold":rarity == "legendary"})
	crates.append({"node":root,"lid":lid,"chute":chute,"cargo":cargo,"light":light,"rarity":rarity,"item":item,"rays":rays,"ring":ring,"smoke":smoke})

func advance(delta: float):
	if not active: return
	var before = age
	age += maxf(0,delta)
	if before < 3.2 and age >= 3.2: cue.emit("impact")
	if before < 4.0 and age >= 4.0: cue.emit("reward")
	if age >= DURATION:
		cancel()
		finished.emit()
		return
	plane.position = Vector3(lerpf(-34,42,age/3.4),14,-8)
	plane.rotation.z = sin(age*1.4)*0.07
	for prop in props: prop.rotation.x = age*45
	var push = smoothstep(3.2,4.5,age)
	camera.fov = lerpf(52,32,push)
	camera.look_at(Vector3(0,lerpf(5,2.5,push),0))
	var kick = maxf(0,1-absf(age-3.35)*4)*0.12
	camera.h_offset = sin(age*85)*kick
	camera.v_offset = cos(age*70)*kick
	for i in range(crates.size()):
		var crate: Dictionary = crates[i]
		var descent = clampf((age-1.0-i*0.16)/2.15,0,1)
		crate.node.position = Vector3((i-1)*6.5,14*(1-descent),sin(age*2+i)*(1-descent))
		crate.node.visible = age >= 1.0+i*0.16
		crate.chute.visible = descent < 1
		crate.lid.rotation.x = -clampf((age-3.7-i*0.12)*2.8,0,1)*2.0
		var reveal = clampf((age-4-i*0.12)/0.75,0,1)
		for ray in crate.rays: ray.visible = reveal > 0
		crate.cargo.visible = reveal > 0
		crate.cargo.position.y = 1.0+reveal*2.0
		crate.cargo.rotation.y = age*0.35
		crate.light.light_energy = reveal*(4 if crate.rarity == "legendary" else 1.5)
		var dust_age = maxf(0,age-3.15-i*0.16)
		crate.ring.visible = dust_age > 0 and dust_age < 1.4
		crate.ring.scale = Vector3(1+dust_age*4,0.2,1+dust_age*4)
		for k in range(crate.smoke.size()):
			var puff = crate.smoke[k]
			var theta = k*TAU/8
			puff.visible = dust_age > 0 and dust_age < 1.8
			puff.position = Vector3(cos(theta)*(1.5+dust_age*2.4),0.3+dust_age*0.7,sin(theta)*(1.5+dust_age*2.4))
			puff.scale = Vector3.ONE*(0.6+dust_age)*maxf(0,1-dust_age/1.8)
	for entry in particles:
		var t = age-3.2-entry.index*0.16
		entry.node.visible = t >= 0 and t < 2.8
		var angle = entry.n*2.39996
		var speed = 1.2+fmod(entry.n*0.71,2.4)
		entry.node.position = Vector3((entry.index-1)*6.5+cos(angle)*t*speed,maxf(0.05,t*(5.5 if entry.gold else 3.5)-t*t*1.7),sin(angle)*t*speed)
		entry.node.scale = Vector3.ONE*clampf(1-t/3,0,1)
	var unit = maxf(1,0.85/Style.screen_scale(self))
	skip_button.size = Vector2(210,48)*unit
	skip_button.position = Vector2(size.x-skip_button.size.x-32,size.y-skip_button.size.y-24)
	skip_button.add_theme_font_size_override("font_size",roundi(20*unit))
	skip_button.text = ("リザルトへ" if finale else "物資を選ぶ") if age >= 4.2 else "開封へ"
	overlay.queue_redraw()

func skip():
	if not active: return
	advance(4.25-age if age < 4.2 else DURATION)

func cancel():
	active = false
	hide()
	crates.clear()
	props.clear()
	particles.clear()
	if is_instance_valid(scene):
		scene.free()
		scene = null
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func draw_titles():
	if not active: return
	var unit = maxf(1,0.85/Style.screen_scale(self))
	var title = "作戦完遂" if finale else "ステージ %d クリア" % stage
	overlay.draw_rect(Rect2(0,0,size.x,114*unit),Color(0.04,0.08,0.1,0.88))
	overlay.draw_string(font,Vector2(36,35)*unit,"航空支援 / SUPPLY INBOUND",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(19*unit),Color("d5aa62"))
	overlay.draw_string(font,Vector2(32,89)*unit,title,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(37*unit),Color("f0ead9"))
	var caption = "輸送機接近 ── 投下地点を確保" if age < 1.3 else "支援物資を投下！" if age < 3.3 else "補給箱着地 ── ロック解除" if age < 4.1 else "特別支援物資 到着" if legendary else "補給完了 ── 次の戦線へ"
	if finale and age >= 4.1: caption = "全戦線を突破 ── 作戦完遂"
	overlay.draw_string(font,Vector2(32,size.y-42*unit),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-skip_button.size.x-90,roundi(24*unit),Color("d5aa62") if legendary else Color("f0ead9"))
	var flash = maxf(0,1-absf(age-4.1)*5)*0.16
	if flash > 0: overlay.draw_rect(Rect2(Vector2.ZERO,size),Color(1,0.85,0.55,flash))
