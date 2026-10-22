extends Control
## Inventory presentation; all mutations go through the owner's commands.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Style = preload("res://scripts/ui_style.gd")
const PANEL = Rect2(1016,100,392,716)
const GENRE_ICONS = {"":"cargo","secondary":"gun","protection":"shield","engine":"fuel","support":"camera"}
signal drag_requested(uid: int)
signal stow_requested(uid: int)
signal dismantle_requested(uid: int)
var state_provider: Callable
var state: Dictionary = {}
var icons
var font: Font
var genre = ""
var page = 0
var rows: Array = []
var row_buttons: Array = []
var stow_buttons: Array = []
var salvage_buttons: Array = []
var tabs: Array = []
var pending_uid = -1
var drag_origin = Vector2.ZERO
var previous: Button
var next: Button

func button(rect: Rect2, hint: String, callback: Callable) -> Button:
	var b = Button.new()
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = hint
	b.add_theme_stylebox_override("normal",Style.style(Color.TRANSPARENT,Style.EDGE))
	b.add_theme_stylebox_override("hover",Style.style(Color(1,1,1,0.08),Style.GOLD))
	b.pressed.connect(callback)
	add_child(b)
	return b

func _ready():
	position = PANEL.position
	size = PANEL.size
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(GENRE_ICONS.size()):
		var id: String = GENRE_ICONS.keys()[i]
		tabs.append(button(Rect2(16+i*60,54,54,38),Catalog.GENRES.get(id,"すべて"),func(): genre = id; page = 0; refresh()))
	button(Rect2(336,10,40,36),"閉じる",hide)
	for i in range(6):
		var index = i
		var row = button(Rect2(16,108+i*82,230,72),"",func(): pass)
		row.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and index < rows.size():
				pending_uid = rows[index].uid
				drag_origin = row.get_global_transform()*event.position)
		row_buttons.append(row)
		stow_buttons.append(button(Rect2(254,108+i*82,54,72),"装備を外して一覧に戻す（出撃準備のみ）",func():
			if index < rows.size(): stow_requested.emit(rows[index].uid)))
		salvage_buttons.append(button(Rect2(316,108+i*82,60,72),"",func():
			if index < rows.size(): dismantle_requested.emit(rows[index].uid)))
	previous = button(Rect2(16,660,80,40),"前のページ",func(): page = maxi(0,page-1); refresh())
	next = button(Rect2(296,660,80,40),"次のページ",func(): page += 1; refresh())
	hide()

func _input(event):
	if not visible:
		pending_uid = -1
		return
	if event is InputEventMouseMotion and pending_uid >= 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT and (get_canvas_transform().affine_inverse()*event.position).distance_to(drag_origin) > 8:
		var uid = pending_uid
		pending_uid = -1
		drag_requested.emit(uid)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed: pending_uid = -1

func refresh():
	if not is_node_ready(): return
	state = state_provider.call() if state_provider.is_valid() else {"enabled":false}
	if not state.get("enabled",false) or state.get("menu_visible",false):
		hide()
	if not visible: return
	var items = state.items.filter(func(item): return genre == "" or Catalog.DEFINITIONS[item.kind].genre == genre)
	page = clampi(page,0,maxi(0,ceili(items.size()/6.0)-1))
	rows = items.slice(page*6,page*6+6)
	previous.disabled = page == 0
	next.disabled = (page+1)*6 >= items.size()
	for i in range(6):
		for b in [row_buttons[i],stow_buttons[i],salvage_buttons[i]]: b.visible = i < rows.size()
		if i >= rows.size(): continue
		var item: Dictionary = rows[i]
		var definition = Catalog.DEFINITIONS[item.kind]
		var rarity = Catalog.RARITIES[item.rarity]
		var mounted = item.position != Inventory.STOWED
		var materials = Catalog.salvage(item)
		row_buttons[i].tooltip_text = "%s · %s\n%s / %d×%d\n%s\n%s" % [rarity.name,Catalog.Content.EQUIPMENT[item.kind].name,Catalog.GENRES[definition.genre],definition.size.x,definition.size.y,Catalog.description(item),"D&Dで配置（同型は1基まで）" if state.editable else "出撃中：装備変更不可"]
		if item.kind in Catalog.Content.GUNS:
			row_buttons[i].tooltip_text += "\n主砲の旋回範囲外に設置 / 2×2枠の外周から給弾"
			if item.get("ammo",0) > 0: row_buttons[i].tooltip_text += "\n保管弾 %d発" % item.ammo
		stow_buttons[i].disabled = not mounted or not state.editable
		salvage_buttons[i].disabled = mounted or state.phase in ["lost","won","retreated"]
		salvage_buttons[i].tooltip_text = "解体：スクラップ +%d / 石炭 +%d（元に戻せません）" % [materials.scrap,materials.coal]
		if item.get("ammo",0) > 0: salvage_buttons[i].tooltip_text += "\n保管弾 %d発も失います" % item.ammo
	queue_redraw()

func icon(id: String, rect: Rect2, tint: Color = Color.WHITE):
	draw_texture_rect(icons.texture(id),rect,false,tint)

func _draw():
	draw_style_box(Style.style(Style.PANEL,Style.EDGE),Rect2(Vector2.ZERO,size))
	icon("cargo",Rect2(16,10,30,30))
	draw_string(font,Vector2(56,33),str(state.items.size()),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	icon("play" if state.editable else "lock",Rect2(288,12,26,26))
	icon("close",Rect2(344,16,24,24))
	for i in range(tabs.size()):
		var id: String = GENRE_ICONS.keys()[i]
		icon(GENRE_ICONS[id],Rect2(tabs[i].position+Vector2(14,6),Vector2(26,26)),Style.GOLD if genre == id else Style.MUTED)
	for i in range(rows.size()):
		var item: Dictionary = rows[i]
		var at: Vector2 = row_buttons[i].position
		var rarity = Catalog.RARITIES[item.rarity]
		var rank = Catalog.RARITIES.keys().find(item.rarity)+1
		draw_rect(Rect2(at+Vector2(1,1),Vector2(5,70)),Color(rarity.color))
		icon(Catalog.Content.EQUIPMENT[item.kind].icon,Rect2(at+Vector2(14,10),Vector2(44,44)))
		icon(GENRE_ICONS[Catalog.DEFINITIONS[item.kind].genre],Rect2(at+Vector2(80,12),Vector2(24,24)),Color(rarity.color))
		for j in range(rank): draw_rect(Rect2(at+Vector2(80+j*14,46),Vector2(10,8)),Color(rarity.color))
		var footprint: Vector2i = Catalog.DEFINITIONS[item.kind].size
		draw_string(font,at+Vector2(156,44),"%d×%d" % [footprint.x,footprint.y],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
		if item.position != Inventory.STOWED: icon("victory",Rect2(at+Vector2(206,5),Vector2(18,18)))
		icon("cargo",Rect2(stow_buttons[i].position+Vector2(13,23),Vector2(28,28)),Style.MUTED if stow_buttons[i].disabled else Style.INK)
		icon("scrap",Rect2(salvage_buttons[i].position+Vector2(16,12),Vector2(28,28)),Style.MUTED if salvage_buttons[i].disabled else Style.GOLD)
		draw_string(font,salvage_buttons[i].position+Vector2(15,60),str(Catalog.salvage(item).scrap),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Style.MUTED if salvage_buttons[i].disabled else Style.INK)
	icon("scrap",Rect2(16,612,24,24))
	draw_string(font,Vector2(48,633),str(state.reserves.scrap),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	icon("coal",Rect2(162,612,24,24))
	draw_string(font,Vector2(194,633),str(state.reserves.coal),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	draw_string(font,Vector2(162,688),str(page+1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	icon("rotate",Rect2(44,668,24,24))
	icon("play",Rect2(324,668,24,24))

func cancel_pending_drag():
	pending_uid = -1

func reset_view():
	cancel_pending_drag()
	genre = ""
	page = 0
	rows.clear()
	hide()
