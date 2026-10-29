extends TextureRect
## Six reusable, render-on-change previews, with the same geometry as field drops.
const Models = preload("res://scripts/item_model.gd")
var viewport: SubViewport
var model: Node3D
var camera: Camera3D
var signature = ""

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewport = SubViewport.new()
	viewport.size = Vector2i(144,128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	texture = viewport.get_texture()
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-35,0)
	light.light_energy = 1.6
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	viewport.add_child(camera)
	camera.position = Vector3(3.2,2.6,3.5)
	camera.look_at(Vector3(0.15,0.5,0))
	camera.current = true
	visibility_changed.connect(func():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)

func show_item(item: Dictionary):
	var key: String = item.kind+":"+item.rarity+":"+str(item.get("direction",0))
	if key == signature: return
	show_model(Models.new().build(item.kind,item.rarity),key,int(item.get("direction",0)))

func show_model(node: Node3D, key: String, direction: int = 0):
	if key == signature:
		node.free()
		return
	signature = key
	if model != null:
		viewport.remove_child(model)
		model.queue_free()
	model = node
	viewport.add_child(model)
	model.rotation.y = -direction*PI/2
	update_resolution()
	frame_model()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func frame_model():
	# Fit the actual silhouette, including the barrel, in both viewport axes.
	var low = Vector3(INF,INF,INF)
	var high = Vector3(-INF,-INF,-INF)
	var inverse = camera.basis.inverse()
	for point in Models.vertices(model,model.transform):
		var projected = inverse*point
		low = low.min(projected)
		high = high.max(projected)
	var center = camera.basis*((low+high)*0.5)
	camera.position = center+camera.basis.z*10.0
	var span = high-low
	camera.size = maxf(span.y,span.x*viewport.size.y/float(viewport.size.x))*1.14

func _process(_delta):
	if model != null and is_visible_in_tree(): update_resolution()

func update_resolution():
	if viewport == null or camera == null or model == null: return
	var display_scale = (get_viewport().get_final_transform()*get_global_transform_with_canvas()).get_scale().abs()
	# Use actual screen pixels, including HiDPI, with bounded supersampling.
	var pixels = size*display_scale*1.25
	var factor = minf(1.0,1024.0/maxf(1.0,maxf(pixels.x,pixels.y)))
	var target = Vector2i(maxi(32,ceili(pixels.x*factor)),maxi(32,ceili(pixels.y*factor)))
	if viewport.size == target: return
	viewport.size = target
	frame_model()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
