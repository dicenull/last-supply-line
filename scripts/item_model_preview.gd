extends TextureRect
## Six reusable, render-on-change previews, with the same geometry as field drops.
const Models = preload("res://scripts/item_model.gd")
var viewport: SubViewport
var model: Node3D
var signature = ""

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewport = SubViewport.new()
	viewport.size = Vector2i(144,128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
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
	var camera = Camera3D.new()
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
	signature = key
	if model != null:
		viewport.remove_child(model)
		model.queue_free()
	model = Models.new().build(item.kind,item.rarity)
	viewport.add_child(model)
	model.rotation.y = -int(item.get("direction",0))*PI/2
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
