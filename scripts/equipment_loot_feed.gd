extends Control
## Bounded, transient equipment and material receipts; never changes inventory.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Style = preload("res://scripts/ui_style.gd")
const MAX_ENTRIES = 4
const DURATION = 4.0
var icons
var font: Font
var entries: Array = []

func _ready():
	position = Vector2(32,104)
	size = Vector2(MAX_ENTRIES*64,76)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hide()

func push_item(item: Dictionary):
	if not Catalog.valid(item): return
	if not entries.is_empty() and entries.back().kind == item.kind and entries.back().rarity == item.rarity:
		entries.back().count += 1
		entries.back().time = DURATION
	else:
		entries.append({"kind":item.kind,"rarity":item.rarity,"count":1,"time":DURATION})
		if entries.size() > MAX_ENTRIES: entries.pop_front()
	queue_redraw()

func push_material(kind: String, amount: int):
	if kind not in ["scrap","coal"] or amount <= 0: return
	for entry in entries:
		if entry.kind == kind and entry.rarity == "":
			entry.count += amount
			entry.time = DURATION
			queue_redraw()
			return
	entries.append({"kind":kind,"rarity":"","count":amount,"time":DURATION})
	if entries.size() > MAX_ENTRIES: entries.pop_front()
	queue_redraw()

func advance(delta: float, shown: bool):
	scale = Vector2.ONE*maxf(1.0,0.85/Style.screen_scale(self))
	for entry in entries: entry.time -= maxf(0,delta)
	entries = entries.filter(func(entry): return entry.time > 0)
	visible = shown and not entries.is_empty()
	queue_redraw()

func clear():
	entries.clear()
	hide()
	queue_redraw()

func receipt_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var available = maxf(58,(get_viewport_rect().size.x-position.x-16)/scale.x)
	var at = Vector2.ZERO
	for entry in entries:
		var width = maxf(58,ceilf(font.get_string_size("+"+str(entry.count),HORIZONTAL_ALIGNMENT_LEFT,-1,16).x)+16)
		if at.x > 0 and at.x+width > available: at = Vector2(0,at.y+82)
		result.append(Rect2(at,Vector2(width,76)))
		at.x += width+6
	return result

func _draw():
	var cards = receipt_rects()
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var card: Rect2 = cards[i]
		var at = card.position
		var material_receipt = entry.rarity.is_empty()
		var tint = Color("d5aa62") if material_receipt else Color(Catalog.RARITIES[entry.rarity].color)
		var alpha = minf(1,entry.time)
		draw_style_box(Style.style(Color(Style.PANEL,alpha),Color(tint,alpha)),card)
		draw_texture_rect(icons.texture(entry.kind if material_receipt else Catalog.Content.EQUIPMENT[entry.kind].icon),Rect2(at+Vector2((card.size.x-36)/2,5),Vector2(36,36)),false,Color(1,1,1,alpha))
		var rank = 0 if material_receipt else Catalog.RARITIES.keys().find(entry.rarity)+1
		for mark in range(rank): draw_rect(Rect2(at+Vector2((card.size.x-rank*7+2)/2+mark*7,67),Vector2(5,4)),Color(tint,alpha))
		draw_string(font,at+Vector2(8,59),"+"+str(entry.count),HORIZONTAL_ALIGNMENT_CENTER,card.size.x-16,16,Color(Style.INK,alpha))
