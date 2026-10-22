extends Control
## A floating repair action, outside the header and construction toolbar.
signal repair_requested
var state_provider: Callable
var icons
var font: Font
var button: Button
var state: Dictionary = {}
var face: Control
const RECT = Rect2(1312,748,88,80)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1440,940)
	button = Button.new()
	button.position = RECT.position
	button.size = RECT.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal",preload("res://scripts/ui_style.gd").style(Color("303c35"),Color("e6bd73")))
	button.add_theme_stylebox_override("hover",preload("res://scripts/ui_style.gd").style(Color("4a5847"),Color("ffe3a5")))
	button.pressed.connect(func(): repair_requested.emit())
	add_child(button)
	face = Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(draw_face)
	add_child(face)

func _process(_delta): refresh()

func refresh():
	state = state_provider.call()
	visible = state.get("visible",false)
	button.disabled = not state.get("allowed",false)
	button.tooltip_text = "一括修復 / 廃材 %d" % int(state.get("cost",0))
	face.queue_redraw()

func draw_face():
	face.draw_texture_rect(icons.texture("repair"),Rect2(RECT.position+Vector2(26,5),Vector2(36,36)),false)
	face.draw_texture_rect(icons.texture("scrap"),Rect2(RECT.position+Vector2(12,48),Vector2(22,22)),false)
	face.draw_string(font,RECT.position+Vector2(40,65),str(state.get("cost",0)),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f2eddf") if state.get("allowed",false) else Color("f29c84"))
