extends Control
## Keep one canonical menu design. Fit its width, preserve readable text, and
## scroll vertically when the available height is smaller than the content.
var content: Control
var bounds_provider: Callable
var scroll: ScrollContainer
var extent: Control
var expand_viewport = false
var align_right = false
var shade = false
var expanded = false
var old_aspect: int
var signature = ""
var reference_position = Vector2(-1,-1)

func mount(view: Control, read_bounds: Callable):
	content = view
	bounds_provider = read_bounds
	mouse_filter = Control.MOUSE_FILTER_STOP if shade else Control.MOUSE_FILTER_IGNORE
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.scroll_deadzone = 12
	add_child(scroll)
	extent = Control.new()
	extent.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(extent)
	extent.add_child(content)
	content.visibility_changed.connect(reflow)
	get_viewport().size_changed.connect(reflow)
	reflow()

func _process(_delta):
	if content != null: reflow()

func reflow():
	if not is_inside_tree() or content == null or not content.is_inside_tree() or not content.is_node_ready(): return
	if expand_viewport and content.visible != expanded:
		expanded = content.visible
		if expanded:
			old_aspect = get_window().content_scale_aspect
			get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		else: get_window().content_scale_aspect = old_aspect
	visible = content.visible
	if not visible: return
	size = get_viewport_rect().size
	var bounds: Rect2 = bounds_provider.call()
	var fullscreen = bounds.position == Vector2.ZERO and bounds.size == size
	var screen_scale = maxf(0.01,get_viewport().get_final_transform().get_scale().x)
	var margin = 0.0 if fullscreen else 16.0/screen_scale
	var available = size-Vector2.ONE*margin*2
	var factor = 1.0 if fullscreen else minf(maxf(1.0,0.9/screen_scale),available.x/bounds.size.x)
	var next_signature = str([size,bounds,fullscreen,factor,content.get("page")])
	if next_signature == signature: return
	signature = next_signature
	var content_size = bounds.size*factor
	scroll.position = (size-Vector2(content_size.x,minf(content_size.y,available.y)))*0.5
	if align_right: scroll.position.x = size.x-margin-content_size.x
	if reference_position.x >= 0 and is_equal_approx(factor,1.0) and size.is_equal_approx(Vector2(1440,940)):
		scroll.position = reference_position
	extent.custom_minimum_size = content_size
	scroll.size = Vector2(content_size.x,minf(content_size.y,available.y))
	content.scale = Vector2.ONE*factor
	content.position = -bounds.position*factor
	scroll.scroll_vertical = 0
	queue_redraw()

func _draw():
	if shade and visible and not (content.get("standalone_title") == true and content.get("page") == "start"):
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.045,0.055,0.04,0.88))

func _exit_tree():
	if get_viewport().size_changed.is_connected(reflow): get_viewport().size_changed.disconnect(reflow)
	if expanded and is_instance_valid(get_window()): get_window().content_scale_aspect = old_aspect
