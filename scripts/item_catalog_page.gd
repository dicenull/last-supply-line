extends Control
## Read-only, paginated encyclopedia with a large selected model on the left.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Preview = preload("res://scripts/item_model_preview.gd")
const Style = preload("res://scripts/ui_style.gd")
signal closed
var font: Font
var selected = "vehicle_engine_power"
var category = ""
var page = 0
var page_size = 12
var ids: Array = []
var visible_ids: Array = []
var tiles: Array = []
var previews: Array = []
var names: Array = []
var filters: Dictionary = {}
var large: TextureRect
var heading: Label
var detail: Label
var page_label: Label
var previous: Button
var next: Button
var back: Button
var detail_button: Button
var show_history = false
var detail_page = 0
var old_aspect: int
var layout_signature = ""
var left_width = 360.0

func button(text_value: String, action: Callable) -> Button:
	var node = Button.new()
	node.text = text_value
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",14)
	node.add_theme_stylebox_override("normal",Style.style(Style.PANEL,Style.EDGE))
	node.pressed.connect(action)
	add_child(node)
	return node
func label(font_size: int) -> Label:
	var node = Label.new()
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",font_size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(node)
	return node
func _ready():
	font = Style.create_font()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_STOP
	back = button("タイトル",close)
	back.icon = preload("res://scripts/pixel_icons.gd").new().texture("back")
	back.expand_icon = true
	back.add_theme_constant_override("icon_max_width",24)
	previous = button("← 前",func(): page -= 1; refresh())
	next = button("次 →",func(): page += 1; refresh())
	page_label = label(14)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for key in ["","vehicle","secondary","protection","engine","support"]:
		var title: String = "全て" if key == "" else "車体" if key == "vehicle" else Catalog.GENRES[key]
		filters[key] = button(title,func(): category = key; page = 0; refresh())
	large = Preview.new()
	add_child(large)
	large.viewport.size = Vector2i(600,500)
	heading = label(18)
	detail = label(13)
	detail_button = button("性能 / 由来",func(): detail_page += 1; refresh_detail())
	for i in range(24):
		var index = i
		var tile = button("",func(): if index < visible_ids.size(): choose(visible_ids[index]))
		tiles.append(tile)
		var preview = Preview.new()
		add_child(preview)
		previews.append(preview)
		names.append(label(12))
	hide()
func open():
	old_aspect = get_window().content_scale_aspect
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	show()
	arrange()
	refresh()
func close():
	hide()
	get_window().content_scale_aspect = old_aspect
	closed.emit()
func choose(id: String):
	selected = id
	detail_page = 0
	refresh_detail()
	refresh_tiles()
func _process(_delta):
	if visible: arrange()
func arrange():
	var s = Style.screen_scale(self)
	var screen = Style.screen_size(self)
	var factor = minf(maxf(s,0.9),(screen.y-32)/350.0)
	position = Vector2.ONE*16/s
	scale = Vector2.ONE*factor/s
	size = (screen-Vector2.ONE*32)/factor
	var signature = str(size)
	if signature == layout_signature: return
	layout_signature = signature
	left_width = minf(360,size.x*0.42)
	var grid_x = left_width+16
	var grid_width = size.x-grid_x
	var columns = clampi(int(grid_width/156),1,6)
	var rows = clampi(int((size.y-104)/142),1,4)
	var old_size = page_size
	page_size = mini(24,columns*rows)
	page = page*old_size/page_size
	back.position = Vector2(0,0)
	back.size = Vector2(left_width,36)
	var filter_width = grid_width/3
	for i in range(filters.size()):
		filters.values()[i].position = Vector2(grid_x+(i%3)*filter_width,(i/3)*32)
		filters.values()[i].size = Vector2(filter_width-3,29)
	heading.position = Vector2(12,48)
	heading.size = Vector2(left_width-24,48)
	heading.add_theme_font_size_override("font_size",14 if left_width < 230 else 18)
	var model_height = clampf(size.y-268,84,340)
	large.position = Vector2(8,100)
	large.size = Vector2(left_width-16,model_height)
	detail_button.position = Vector2(12,108+model_height)
	detail_button.size = Vector2(left_width-24,30)
	detail.position = Vector2(12,146+model_height)
	detail.size = Vector2(left_width-24,size.y-154-model_height)
	var tile_width = grid_width/columns
	var tile_height = (size.y-108)/rows
	for i in range(tiles.size()):
		var at = Vector2(grid_x+(i%columns)*tile_width,70+(i/columns)*tile_height)
		tiles[i].position = at
		tiles[i].size = Vector2(tile_width-6,tile_height-6)
		previews[i].size = Vector2(minf(tile_width-16,left_width*0.60),minf(tile_height-52,left_width*0.50))
		previews[i].position = at+Vector2((tile_width-previews[i].size.x)/2,4)
		names[i].position = at+Vector2(8,tile_height-46)
		names[i].size = Vector2(tile_width-22,38)
	previous.position = Vector2(grid_x,size.y-32)
	previous.size = Vector2(grid_width*0.28,32)
	next.position = Vector2(size.x-grid_width*0.28,size.y-32)
	next.size = previous.size
	page_label.position = Vector2(grid_x+grid_width*0.28,size.y-27)
	page_label.size = Vector2(grid_width*0.44,26)
	refresh()
func refresh():
	ids = Catalog.Data.ACTIVE_IDS.filter(func(id): return category == "" or Catalog.Data.ITEMS[id].genre == category)
	page = clampi(page,0,maxi(0,ceili(ids.size()/float(page_size))-1))
	visible_ids = ids.slice(page*page_size,(page+1)*page_size)
	previous.disabled = page == 0
	next.disabled = (page+1)*page_size >= ids.size()
	page_label.text = "%d / %d · %d種" % [page+1,ceili(ids.size()/float(page_size)),ids.size()]
	for key in filters: filters[key].modulate = Style.GOLD if category == key else Color.WHITE
	refresh_tiles()
	refresh_detail()
	queue_redraw()
func refresh_tiles():
	for i in range(tiles.size()):
		for node in [tiles[i],previews[i],names[i]]: node.visible = i < visible_ids.size()
		if i >= visible_ids.size(): continue
		var id: String = visible_ids[i]
		previews[i].show_item({"kind":id,"rarity":"normal"})
		names[i].text = Catalog.Data.ITEMS[id].name
		tiles[i].tooltip_text = names[i].text
		tiles[i].add_theme_stylebox_override("normal",Style.style(Style.SURFACE,Style.GOLD if id == selected else Style.EDGE))
func refresh_detail():
	var spec: Dictionary = Catalog.Data.ITEMS[selected]
	heading.text = spec.name
	large.show_item({"kind":selected,"rarity":"normal"})
	var pages = []
	for history in [false,true]:
		var text: String = spec.get("inspiration","歴史上の機械構造を参考にしたゲーム用装備。")+"\n型式・性能はゲーム独自。" if history else Catalog.description({"kind":selected,"rarity":"normal"}).replace(" / ","\n")
		var lines: Array[String] = [""]
		for letter in text:
			if letter == "\n":
				lines.append("")
				continue
			if font.get_string_size(lines.back()+letter,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x > detail.size.x-2: lines.append("")
			lines[-1] += letter
		var count = maxi(1,int(detail.size.y/(font.get_height(13)+4)))
		for offset in range(0,lines.size(),count): pages.append({"history":history,"text":"\n".join(lines.slice(offset,offset+count))})
	detail_page = posmod(detail_page,pages.size())
	show_history = pages[detail_page].history
	detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail.text = pages[detail_page].text
	detail_button.text = ("由来" if show_history else "性能")+"  %d/%d →" % [detail_page+1,pages.size()]
	queue_redraw()
func _draw():
	draw_style_box(Style.style(Style.BG,Style.EDGE),Rect2(Vector2.ZERO,size))
	draw_style_box(Style.style(Style.PANEL),Rect2(0,42,left_width,size.y-42))
