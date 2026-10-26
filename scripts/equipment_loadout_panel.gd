extends Control
## Equipped chassis and live values, alongside the warehouse.
const Style = preload("res://scripts/ui_style.gd")
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Preview = preload("res://scripts/item_model_preview.gd")
signal slot_selected(slot: String)
signal remove_requested(slot: String)
var font: Font
var state: Dictionary = {}
var slots: Dictionary = {}
var remove_buttons: Dictionary = {}
var previews: Dictionary = {}

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(4):
		var slot: String = Catalog.PART_SLOTS.keys()[i]
		var button = Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal",Style.style(Color.TRANSPARENT,Style.EDGE))
		button.pressed.connect(func(): slot_selected.emit(slot))
		add_child(button)
		slots[slot] = button
		var remove = Button.new()
		remove.text = "外す"
		remove.focus_mode = Control.FOCUS_NONE
		remove.add_theme_font_override("font",font)
		remove.add_theme_font_size_override("font_size",14)
		remove.pressed.connect(func():
			var part: Dictionary = state.get("vehicle_parts",{}).get(slot,{})
			remove_requested.emit(slot))
		add_child(remove)
		remove_buttons[slot] = remove
		var preview = Preview.new()
		add_child(preview)
		previews[slot] = preview
	update_state({})

func update_state(value: Dictionary):
	state = value
	if not is_node_ready(): return
	for i in range(4):
		var slot: String = Catalog.PART_SLOTS.keys()[i]
		var part: Dictionary = state.get("vehicle_parts",{}).get(slot,{})
		slots[slot].position = Vector2(12,52+i*78)
		slots[slot].size = Vector2(size.x-24,70)
		slots[slot].tooltip_text = Catalog.description(part) if not part.is_empty() else Catalog.PART_SLOTS[slot]+("：装備なし" if slot in state.get("empty_slots",[]) else "：標準装備")
		remove_buttons[slot].position = Vector2(size.x-62,76+i*78)
		remove_buttons[slot].size = Vector2(44,30)
		remove_buttons[slot].disabled = slot in state.get("empty_slots",[]) or not state.get("editable",false)
		previews[slot].position = Vector2(18,56+i*78)
		previews[slot].size = Vector2(56,56)
		previews[slot].show_item(part if not part.is_empty() else {"kind":("empty_" if slot in state.get("empty_slots",[]) else "vehicle_")+slot,"rarity":"normal"})
	queue_redraw()

func _draw():
	draw_style_box(Style.style(Style.PANEL,Style.EDGE),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(16,32),"装備中",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Style.GOLD)
	for i in range(4):
		var slot: String = Catalog.PART_SLOTS.keys()[i]
		var part: Dictionary = state.get("vehicle_parts",{}).get(slot,{})
		var color = Color(Catalog.RARITIES[part.rarity].color) if not part.is_empty() else Style.MUTED
		draw_string(font,Vector2(82,75+i*78),Catalog.PART_SLOTS[slot],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Style.MUTED)
		var name: String = Catalog.Data.ITEMS[part.kind].name if not part.is_empty() else ("装備なし" if slot in state.get("empty_slots",[]) else "標準装備")
		draw_string(font,Vector2(82,101+i*78),name,HORIZONTAL_ALIGNMENT_LEFT,size.x-150,15,color)
	draw_string(font,Vector2(16,394),"車両パラメータ",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Style.GOLD)
	var parameters: Dictionary = state.get("parameters",{})
	var labels = {"speed":"走行速度","turn":"車体旋回","fuel":"燃料消費 / m","reload":"主砲 射撃間隔","range":"主砲 射程","splash":"主砲 爆発範囲","damage":"被ダメージ倍率","offroad":"悪路速度倍率"}
	for i in range(labels.size()):
		var key: String = labels.keys()[i]
		var y = 426+i*29
		draw_string(font,Vector2(16,y),labels[key],HORIZONTAL_ALIGNMENT_LEFT,-1,15,Style.MUTED)
		var text: String = parameters.get(key,"—")
		draw_string(font,Vector2(size.x-122,y),text,HORIZONTAL_ALIGNMENT_RIGHT,106,16,Style.INK)
	draw_string(font,Vector2(16,686),"換装は出撃準備中のみ" if not state.get("editable",false) else "換装すると性能と車体に即反映",HORIZONTAL_ALIGNMENT_LEFT,size.x-32,13,Style.MUTED)
