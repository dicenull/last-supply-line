extends Control
## Bounded, transient equipment receipts. Receives values, never mutates the run.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Style = preload("res://scripts/ui_style.gd")
const MAX_ENTRIES = 4
const DURATION = 4.0
var icons
var font: Font
var entries: Array = []

func _ready():
	position = Vector2(32,104)
	size = Vector2(MAX_ENTRIES*64,60)
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

func advance(delta: float, shown: bool):
	for entry in entries: entry.time -= maxf(0,delta)
	entries = entries.filter(func(entry): return entry.time > 0)
	visible = shown and not entries.is_empty()
	queue_redraw()

func clear():
	entries.clear()
	hide()
	queue_redraw()

func _draw():
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var at = Vector2(i*64,0)
		var tint = Color(Catalog.RARITIES[entry.rarity].color)
		var alpha = minf(1,entry.time)
		draw_style_box(Style.style(Color(Style.PANEL,alpha),Color(tint,alpha)),Rect2(at,Vector2(58,58)))
		draw_texture_rect(icons.texture(Catalog.Content.EQUIPMENT[entry.kind].icon),Rect2(at+Vector2(11,5),Vector2(36,36)),false,Color(1,1,1,alpha))
		var rank = Catalog.RARITIES.keys().find(entry.rarity)+1
		for mark in range(rank): draw_rect(Rect2(at+Vector2(5+mark*7,47),Vector2(5,5)),Color(tint,alpha))
		draw_string(font,at+Vector2(33,52),"+"+str(entry.count),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(Style.INK,alpha))
