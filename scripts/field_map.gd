extends Control
## Icon-only minimap. Driving into a yard selects the destination.
var state_provider: Callable
var icons
var battle
var course
const PANEL = Rect2(1168,96,240,184)
const MAP = Rect2(1184,112,208,152)
var panel_style = preload("res://scripts/ui_style.gd").style(Color("242b24"),Color("837c5b"))

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta):
	var state: Dictionary = state_provider.call()
	battle = state.get("battle")
	visible = state.get("visible",false) and is_instance_valid(battle) and battle.field_course != null
	if visible:
		course = battle.field_course
		queue_redraw()

func project(at: Vector3) -> Vector2:
	# Keep road angles and heading faithful to the field, with room for badges.
	var area: Rect2 = course.bounds
	var scale_value = minf(MAP.size.x/area.size.x,MAP.size.y/area.size.y)
	return MAP.get_center()+(Vector2(at.x,at.z)-area.get_center())*scale_value

func _draw():
	if not visible or course == null: return
	draw_style_box(panel_style,PANEL)
	for segment in course.segments:
		draw_line(project(segment[0]),project(segment[1]),Color("455043"),7,true)
		draw_line(project(segment[0]),project(segment[1]),Color("a39a73"),3,true)
	for i in range(course.destinations.size()):
		var site: Dictionary = course.destinations[i]
		var at = project(site.position)
		var selected = i == battle.arrived_destination
		draw_circle(at,17,Color("e6bd73") if selected else Color("8d9d7b"))
		draw_circle(at,15,Color("778365"))
		draw_texture_rect(icons.texture(preload("res://scripts/field_services.gd").icon(site)),Rect2((at-Vector2.ONE*14).round(),Vector2.ONE*28),false)
	var player_at = project(battle.player.position)
	var forward = Vector2(battle.player.basis.x.x,battle.player.basis.x.z).normalized()
	var side = Vector2(-forward.y,forward.x)
	draw_circle(player_at,8,Color("242b24"))
	draw_colored_polygon(PackedVector2Array([player_at+forward*8,player_at-forward*5+side*5,player_at-forward*5-side*5]),Color("ffe3a5"))
