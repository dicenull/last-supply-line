extends Control
## Purchases are commands to the owner; all eligibility comes from current models.
signal purchase_requested(index: int)
signal finished
signal inventory_requested
var inventory_button: Button
var state_provider: Callable
var icons
var font: Font
var state: Dictionary = {}
var buttons: Array = []
var close_button: Button
const PANEL = Rect2(400,242,640,456)
const Services = preload("res://scripts/field_services.gd")
const Content = preload("res://scripts/content.gd")
const Style = preload("res://scripts/ui_style.gd")

func _ready():
	size = Vector2(1440,940)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(3):
		var button = Button.new()
		button.position = Vector2(430+i*190,348)
		button.size = Vector2(170,214)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal",Style.style(Color.TRANSPARENT,Color("68705a")))
		button.add_theme_stylebox_override("hover",Style.style(Color(1,1,1,0.08),Color("e6bd73")))
		button.pressed.connect(func(): purchase_requested.emit(i))
		add_child(button)
		buttons.append(button)
	close_button = Button.new()
	close_button.position = Vector2(650,604)
	close_button.size = Vector2(140,64)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "買い物を終える"
	close_button.add_theme_stylebox_override("normal",Style.style(Color.TRANSPARENT,Color("e6bd73")))
	close_button.pressed.connect(func(): finished.emit())
	add_child(close_button)
	inventory_button = Button.new()
	inventory_button.position = Vector2(880,604)
	inventory_button.size = Vector2(64,64)
	inventory_button.focus_mode = Control.FOCUS_NONE
	inventory_button.tooltip_text = "装備一覧 / 解体（I）"
	inventory_button.add_theme_stylebox_override("normal",Style.style(Color.TRANSPARENT,Style.EDGE))
	inventory_button.pressed.connect(func(): inventory_requested.emit())
	add_child(inventory_button)
	refresh()

func refresh():
	state = state_provider.call()
	visible = state.get("visible",false)
	inventory_button.visible = state.get("item_mode",false)
	var offers: Array = state.get("offers",[])
	for i in range(buttons.size()):
		buttons[i].visible = visible and i < offers.size()
		buttons[i].disabled = i >= offers.size() or not state.get("allowed",[])[i]
		if i < offers.size():
			var id: String = offers[i]
			var label = "石炭 +24" if id == "coal" else "主砲弾 +12（装填上限まで）" if id == "shell" else Content.reward_info(id).name
			buttons[i].tooltip_text = label+" / 廃材 "+str(Services.price(id))
			if state.get("item_mode",false) and id.begins_with("gear:"):
				buttons[i].tooltip_text = "アンコモン · "+buttons[i].tooltip_text+"\n"+preload("res://scripts/equipment_catalog.gd").description({"kind":id.trim_prefix("gear:"),"rarity":"uncommon"})
	queue_redraw()

func _draw():
	if not visible: return
	draw_rect(Rect2(0,0,1440,940),Color(0.045,0.055,0.04,0.8))
	draw_style_box(Style.style(Color("2d342b"),Color("68705a")),PANEL)
	draw_texture_rect(icons.texture("shop"),Rect2(688,266,64,64),false)
	draw_texture_rect(icons.texture("scrap"),Rect2(870,280,28,28),false)
	draw_string(font,Vector2(910,303),str(state.get("scrap",0)),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Style.INK)
	var offers: Array = state.get("offers",[])
	for i in range(offers.size()):
		var at = buttons[i].position
		var id: String = offers[i]
		var icon = Content.reward_info(id).icon if id.begins_with("gear:") else id
		draw_texture_rect(icons.texture(icon),Rect2(at+Vector2(53,26),Vector2(64,64)),false)
		if id in ["coal","shell"]: draw_string(font,at+Vector2(66,126),"+24" if id == "coal" else "+12",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Style.INK)
		elif state.get("item_mode",false):
			var gear = preload("res://scripts/equipment_catalog.gd")
			var kind = id.trim_prefix("gear:")
			draw_texture_rect(icons.texture(gear.profile_icon(kind)),Rect2(at+Vector2(28,105),Vector2(26,26)),false)
			draw_string(font,at+Vector2(68,126),"換装" if not gear.part_slot(kind).is_empty() else "設置",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
		draw_texture_rect(icons.texture("scrap"),Rect2(at+Vector2(42,162),Vector2(26,26)),false)
		draw_string(font,at+Vector2(80,184),str(Services.price(id)),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Style.INK if state.allowed[i] else Style.MUTED)
		if state.purchased[i]: draw_texture_rect(icons.texture("victory"),Rect2(at+Vector2(126,8),Vector2(30,30)),false)
	draw_texture_rect(icons.texture("play"),Rect2(698,614,44,44),false)
	if inventory_button.visible: draw_texture_rect(icons.texture("cargo"),Rect2(890,614,44,44),false)
