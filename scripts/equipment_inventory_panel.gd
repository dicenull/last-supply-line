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
signal normal_dismantle_requested(uids: Array)
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
var sort_button: Button
var bulk_button: Button
var confirm_button: Button
var cancel_button: Button
var quality_order = false
var bulk_uids: Array = []
var bulk_quote: Dictionary = {}
var filtered_items: Array = []
var list_signature = -1

func button(rect: Rect2, hint: String, callback: Callable) -> Button:
	var b = Button.new()
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = hint
	b.add_theme_stylebox_override("normal",Style.style(Color.TRANSPARENT,Style.EDGE))
	b.add_theme_stylebox_override("hover",Style.style(Color(1,1,1,0.08),Style.GOLD))
	if callback.is_valid(): b.pressed.connect(callback)
	add_child(b)
	return b

func item_button(rect: Rect2, hint: String, action: StringName, index: int) -> Button:
	var b = button(rect,hint,Callable())
	# Loot can reorder rows between press and release. Keep the item the player
	# actually pressed, even when a higher-quality drop arrives in the meantime.
	b.button_down.connect(func(): b.set_meta("pressed_uid",rows[index].uid if index < rows.size() else -1))
	b.pressed.connect(func():
		var uid = int(b.get_meta("pressed_uid",-1))
		if b.has_meta("pressed_uid"): b.remove_meta("pressed_uid")
		if uid >= 0: emit_signal(action,uid))
	return b

func _ready():
	position = PANEL.position
	size = PANEL.size
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(GENRE_ICONS.size()):
		var id: String = GENRE_ICONS.keys()[i]
		tabs.append(button(Rect2(16+i*60,54,54,38),Catalog.GENRES.get(id,"すべて"),func(): genre = id; page = 0; cancel_bulk(); refresh()))
	button(Rect2(336,10,40,36),"閉じる",hide)
	sort_button = button(Rect2(236,10,40,36),"品質の高い順に並べる",func(): quality_order = not quality_order; page = 0; cancel_bulk(); refresh())
	for i in range(6):
		var index = i
		var row = button(Rect2(16,108+i*82,230,72),"",func(): pass)
		row.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and index < rows.size():
				pending_uid = rows[index].uid
				drag_origin = row.get_global_transform()*event.position)
		row_buttons.append(row)
		stow_buttons.append(item_button(Rect2(254,108+i*82,54,72),"装備を外して一覧に戻す（出撃準備のみ）","stow_requested",index))
		salvage_buttons.append(item_button(Rect2(316,108+i*82,60,72),"","dismantle_requested",index))
	previous = button(Rect2(16,660,80,40),"前のページ",func(): page = maxi(0,page-1); refresh())
	next = button(Rect2(296,660,80,40),"次のページ",func(): page += 1; refresh())
	bulk_button = button(Rect2(110,660,172,40),"",begin_bulk)
	cancel_button = button(Rect2(16,660,80,40),"まとめて解体をキャンセル",func(): cancel_bulk(); refresh())
	confirm_button = button(Rect2(296,660,80,40),"",func():
		normal_dismantle_requested.emit(bulk_uids.duplicate())
		cancel_bulk()
		refresh())
	visibility_changed.connect(func():
		if not visible: cancel_bulk())
	hide()

func begin_bulk():
	bulk_uids = Inventory.normal_candidates(state.items,genre)
	refresh()

func cancel_bulk():
	bulk_uids.clear()
	bulk_quote.clear()

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
	var signature = [state.items.hash(),genre,quality_order].hash()
	if signature != list_signature:
		list_signature = signature
		filtered_items = state.items.filter(func(item): return genre == "" or Catalog.DEFINITIONS[item.kind].genre == genre)
		if quality_order:
			filtered_items.sort_custom(func(a,b):
				var a_power: float = Catalog.RARITIES[a.rarity].power
				var b_power: float = Catalog.RARITIES[b.rarity].power
				return a_power > b_power if a_power != b_power else a.uid < b.uid)
	page = clampi(page,0,maxi(0,ceili(filtered_items.size()/6.0)-1))
	rows = filtered_items.slice(page*6,page*6+6)
	previous.disabled = page == 0
	next.disabled = (page+1)*6 >= filtered_items.size()
	sort_button.tooltip_text = "入手順に戻す" if quality_order else "品質の高い順に並べる"
	bulk_quote = Inventory.quote_normals(state.items,bulk_uids)
	if bulk_quote.is_empty() or state.phase in ["lost","won","retreated"]: cancel_bulk()
	var previewing = not bulk_quote.is_empty()
	for b in [previous,next,bulk_button]: b.visible = not previewing
	for b in [cancel_button,confirm_button]: b.visible = previewing
	var candidates = Inventory.normal_candidates(state.items,genre)
	bulk_button.disabled = candidates.is_empty() or state.phase in ["lost","won","retreated"]
	bulk_button.tooltip_text = "このジャンルのノーマル %d個をまとめて解体\n未設置・弾なしのみ。次に対象数と素材量を確認します。" % candidates.size()
	if previewing: confirm_button.tooltip_text = "%d個を解体：スクラップ +%d / 石炭 +%d（元に戻せません）" % [bulk_quote.count,bulk_quote.scrap,bulk_quote.coal]
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
	icon("sort",Rect2(244,16,24,24),Style.GOLD if quality_order else Style.MUTED)
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
	draw_string(font,Vector2(48,633),"+"+str(bulk_quote.scrap) if not bulk_quote.is_empty() else str(state.reserves.scrap),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	icon("coal",Rect2(162,612,24,24))
	draw_string(font,Vector2(194,633),"+"+str(bulk_quote.coal) if not bulk_quote.is_empty() else str(state.reserves.coal),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	draw_string(font,Vector2(310,633),"%d/%d" % [page+1,maxi(1,ceili(filtered_items.size()/6.0))],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Style.MUTED)
	icon("close" if not bulk_quote.is_empty() else "rotate",Rect2(44,668,24,24))
	icon("victory" if not bulk_quote.is_empty() else "play",Rect2(324,668,24,24))
	icon("scrap",Rect2(126,668,24,24),Style.MUTED if bulk_button.disabled else Style.GOLD)
	var count = bulk_quote.count if not bulk_quote.is_empty() else Inventory.normal_candidates(state.items,genre).size()
	draw_string(font,Vector2(166,688),"×"+str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	draw_rect(Rect2(254,676,10,8),Color(Catalog.RARITIES.normal.color))

func cancel_pending_drag():
	pending_uid = -1

func reset_view():
	cancel_pending_drag()
	genre = ""
	page = 0
	quality_order = false
	list_signature = -1
	filtered_items.clear()
	cancel_bulk()
	rows.clear()
	hide()
