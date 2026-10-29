extends Control
const Style = preload("res://scripts/ui_style.gd")
## Overlay panes fit the existing gameplay viewport without changing its scale.
var warehouse: Control
var loadout: Control
var bounds_provider: Callable
var narrow = false
var arranging = false

func configure(right: Control):
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	warehouse = right
	warehouse.close_requested.connect(close_all)
	add_child(warehouse)
	loadout = warehouse.loadout_panel
	add_child(loadout)
	warehouse.visibility_changed.connect(func(): sync_visibility(warehouse))
	loadout.visibility_changed.connect(func(): sync_visibility(loadout))
	sync_visibility()

func open_left():
	loadout.show()
	sync_visibility(loadout)
func open_right():
	warehouse.show()
	sync_visibility(warehouse)
func toggle_left():
	loadout.visible = not loadout.visible
	sync_visibility(loadout)
func toggle_right():
	if warehouse.visible: close_all()
	else: open_right()
func close_all():
	warehouse.hide()
	loadout.hide()
func sync_visibility(preferred: Control = null):
	if arranging: return
	arranging = true
	visible = warehouse.visible or loadout.visible
	if visible: arrange(preferred)
	arranging = false
func _process(_delta):
	if warehouse != null and visible: arrange()
func arrange(preferred: Control = null):
	var canvas_to_screen = get_viewport().get_final_transform()
	var screen_scale = maxf(0.01,canvas_to_screen.get_scale().x)
	var bounds: Rect2 = bounds_provider.call() if bounds_provider.is_valid() else get_viewport_rect()
	var screen_bounds = (canvas_to_screen*bounds).intersection(Rect2(Vector2.ZERO,Vector2(get_window().size)))
	var density = Style.pixel_density()
	var margin = minf(16*density,screen_bounds.size.y*0.04)
	var available = screen_bounds.grow(-margin)
	var preferred_scale = maxf(screen_scale,0.9*density)
	narrow = available.size.x/preferred_scale < 800
	var width = 392.0 if narrow else 800.0
	var factor = minf(preferred_scale,minf(available.size.x/width,available.size.y/300.0))
	factor = maxf(factor,0.01)
	var height = minf(716,available.size.y/factor)
	# Include the viewport's letterbox translation, not only its scale.
	position = canvas_to_screen.affine_inverse()*available.position
	scale = Vector2.ONE*factor/screen_scale
	size = Vector2(available.size.x/factor,height)
	warehouse.position = Vector2(size.x-392,0)
	warehouse.size = Vector2(392,height)
	warehouse.stacked = narrow
	loadout.position = Vector2.ZERO
	loadout.size = Vector2(392,height)
	if narrow and warehouse.visible and loadout.visible:
		if preferred == loadout: warehouse.hide()
		else: loadout.hide()
	warehouse.arrange_rows()
	loadout.update_state(warehouse.state)

func has_point_on_pane(screen_position: Vector2) -> bool:
	for pane in [warehouse,loadout]:
		if pane.is_visible_in_tree() and Rect2(Vector2.ZERO,pane.size).has_point((get_viewport().get_final_transform()*pane.get_global_transform()).affine_inverse()*screen_position): return true
	return false
