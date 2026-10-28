extends Control
## Responsive, paginated campaign result; no scrolling on desktop or touch.
const Style = preload("res://scripts/ui_style.gd")
const Gear = preload("res://scripts/equipment_catalog.gd")
signal retry_requested
signal title_requested
var ui = Style.new()
var provider: Callable
var expedition
var factory
var tab = 0
var page = 0
var page_size = 6
var entries: Array = []
var buttons: Array = []
var stats_rect: Rect2
var list_rect: Rect2
var old_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

func configure(read_models: Callable): provider = read_models

func _ready():
	ui.font = Style.create_font()
	mouse_filter = MOUSE_FILTER_STOP
	texture_filter = TEXTURE_FILTER_LINEAR
	for title in ["設置物","装備品","←","→","もう一度","タイトルへ"]:
		var index = buttons.size()
		var button = Button.new()
		button.text = title
		if index in [2,3,5]:
			button.icon = ui.pixel_icons.texture("forward" if index == 3 else "back")
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width",24)
			if index in [2,3]: button.text = ""
		button.focus_mode = FOCUS_NONE
		button.add_theme_font_override("font",ui.font)
		button.add_theme_font_size_override("font_size",16)
		button.add_theme_stylebox_override("normal",ui.style(ui.SURFACE,ui.EDGE))
		button.pressed.connect(func(): activate(index))
		add_child(button)
		buttons.append(button)
	hide()
	get_viewport().size_changed.connect(arrange)

func refresh():
	var state: Dictionary = provider.call()
	expedition = state.expedition
	factory = state.factory
	var should_show = expedition.phase == "won" and not state.get("cinematic",false)
	if should_show != visible:
		if should_show:
			old_aspect = get_window().content_scale_aspect
			get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			tab = 0
			page = 0
		else: get_window().content_scale_aspect = old_aspect
	visible = should_show
	if visible:
		collect_entries()
		arrange()

func collect_entries():
	entries.clear()
	if tab == 0:
		var counts = {}
		for at in factory.cells:
			if factory.ports.has(at) or factory.cells[at].kind in factory.auxiliary_ids: continue
			var kind = factory.cells[at].kind
			counts[kind] = counts.get(kind,0)+1
		for kind in counts:
			var title: String = factory.Content.BASIC_BLOCKS.get(kind,{}).get("name",kind)
			entries.append("%s  ×%d" % [title,counts[kind]])
		for item in expedition.gear_items:
			if item.position != Vector2i(-1,-1) and Gear.part_slot(item.kind).is_empty(): entries.append(Gear.Data.ITEMS[item.kind].name)
	else:
		for slot in Gear.PART_SLOTS:
			var found = false
			for item in expedition.gear_items:
				if item.position != Vector2i(-1,-1) and Gear.part_slot(item.kind) == slot:
					entries.append(Gear.Data.ITEMS[item.kind].name)
					found = true
			if not found: entries.append({"gear":"変速機","engine":"エンジン","tracks":"履帯","cannon":"主砲"}[slot]+("：装備なし" if slot in expedition.empty_part_slots else "：標準装備"))

func activate(index: int):
	if index < 2:
		tab = index
		page = 0
		collect_entries()
	elif index < 4: page += -1 if index == 2 else 1
	elif index == 4: retry_requested.emit()
	else: title_requested.emit()
	if visible: arrange()

func arrange():
	if not visible or buttons.is_empty(): return
	var screen_scale = Style.screen_scale(self)
	var physical = Style.screen_size(self)
	var factor = minf(1.0,minf(physical.x/320.0,physical.y/420.0))
	scale = Vector2.ONE*factor/screen_scale
	size = physical/factor
	position = Vector2.ZERO
	var wide = size.x >= 720
	var top = 98.0
	var bottom = size.y-64
	stats_rect = Rect2(20,top,(size.x-60)*0.45 if wide else size.x-40,180 if not wide else bottom-top)
	list_rect = Rect2(stats_rect.end.x+20 if wide else 20,top if wide else 214,size.x-stats_rect.end.x-40 if wide else size.x-40,bottom-(top if wide else 214))
	# Compact phones retain four summary metrics and use a short equipment page.
	if size.y < 480 and not wide:
		stats_rect.position.y = 86
		stats_rect.size.y = 90
		list_rect.position.y = 176
		list_rect.size.y = bottom-176
	page_size = maxi(1,int((list_rect.size.y-72)/28))
	page = clampi(page,0,maxi(0,ceili(entries.size()/float(page_size))-1))
	for i in range(2):
		buttons[i].position = list_rect.position+Vector2(i*104,0)
		buttons[i].size = Vector2(100,32)
	for i in range(2,4):
		buttons[i].position = Vector2(list_rect.position.x+(i-2)*52,list_rect.end.y-32)
		buttons[i].size = Vector2(46,32)
	buttons[2].disabled = page == 0
	buttons[3].disabled = (page+1)*page_size >= entries.size()
	for i in range(4,6):
		buttons[i].position = Vector2(size.x/2+(i-5)*144+4,size.y-50)
		buttons[i].size = Vector2(136,38)
	queue_redraw()

func text_at(value: String, at: Vector2, font_size: int = 18, color: Color = Style.INK, width: float = -1):
	draw_string(ui.font,at,value,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,color)

func _draw():
	if not visible or expedition == null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("171e21"))
	draw_rect(Rect2(20,20,4,44),ui.GOLD)
	text_at("補給線をつなぎ切った",Vector2(36,40),16,ui.MUTED)
	text_at("GAME CLEAR",Vector2(34,74),32,ui.GOLD)
	var stats = expedition.results
	var compact = size.y < 480 and size.x < 720
	var lines = ["SCORE  %d" % stats.points(expedition.cleared),"撃破 %d 両　最大コンボ %d" % [stats.kills,stats.best_combo],"作戦時間 %d:%02d　製造砲弾 %d" % [int(stats.elapsed)/60,int(stats.elapsed)%60,stats.shells],"突破 %d / 5 面" % expedition.cleared]
	for i in range(lines.size()): text_at(lines[i],stats_rect.position+Vector2(0,20+i*(21 if compact else 26)),16 if compact else 18,ui.GOLD if i == 0 else ui.INK)
	if size.x >= 720:
		text_at("スコア = 突破 ×1,000",stats_rect.position+Vector2(0,150),14,ui.MUTED)
		text_at("+ 撃破 ×100 + 最大コンボ ×50",stats_rect.position+Vector2(0,172),14,ui.MUTED)
	if stats.legacy: text_at("旧セーブ：集計は更新後の面から",Vector2(20,94),12,ui.MUTED)
	for i in range(page_size):
		var index = page*page_size+i
		if index >= entries.size(): break
		var value: String = entries[index]
		var max_width = list_rect.size.x
		while ui.font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x > max_width: value = value.left(-2)+"…"
		text_at(value,list_rect.position+Vector2(0,54+i*28),15)
	if entries.is_empty(): text_at("設置なし",list_rect.position+Vector2(0,54),15,ui.MUTED)
	text_at("%d / %d" % [page+1,maxi(1,ceili(entries.size()/float(page_size)))],Vector2(list_rect.position.x+112,list_rect.end.y-10),14,ui.MUTED)

func _exit_tree():
	if visible and is_instance_valid(get_window()): get_window().content_scale_aspect = old_aspect
