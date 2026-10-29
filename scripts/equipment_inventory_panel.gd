extends Control
## Inventory presentation; all mutations go through the owner's commands.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const ModelPreview = preload("res://scripts/item_model_preview.gd")
const Style = preload("res://scripts/ui_style.gd")
const PANEL = Rect2(1016,100,392,716)
const GENRE_ICONS = {"":"cargo","secondary":"gun","protection":"shield","engine":"fuel","support":"camera","vehicle":"engine"}
const TAB_LABELS = {"":"設置物","gear":"ギア","engine":"エンジン","tracks":"履帯","cannon":"主砲"}
const TAB_ICONS = {"":"cargo","gear":"rotate","engine":"engine","tracks":"move","cannon":"gun"}
signal drag_requested(uid: int)
signal item_selected(uid: int)
signal close_requested
var close_button: Button
var touch_mode = false
var page_size = 6
var row_pitch = 82.0
signal stow_requested(uid: int)
signal equip_part_requested(uid: int)
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
var model_previews: Array = []
var equip_buttons: Array = []
var action_buttons: Array = []
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
var display_items: Array = []
var list_signature = -1
var loadout_panel: Control
var stacked = false
var frame_width = 704.0

func select_tab(id: String):
	show()
	genre = id
	page = 0
	cancel_bulk()
	refresh()

func frame_bounds() -> Rect2:
	return Rect2(Vector2.ZERO,size)

func occupied_rect() -> Rect2:
	return get_global_transform()*frame_bounds()

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
	# Freeze action as well as identity: a held "stow" must never turn into scrap.
	b.button_down.connect(func():
		var item: Dictionary = rows[index] if index < rows.size() else {}
		b.set_meta("pressed_uid",item.get("uid",-1))
		b.set_meta("pressed_action",("stow_requested" if item.get("position",Inventory.STOWED) != Inventory.STOWED else "dismantle_requested") if action == "item_action" else action))
	b.pressed.connect(func():
		var uid = int(b.get_meta("pressed_uid",-1))
		var chosen: String = b.get_meta("pressed_action","")
		b.remove_meta("pressed_uid")
		b.remove_meta("pressed_action")
		if uid >= 0 and not chosen.is_empty(): emit_signal(chosen,uid))
	return b

func _ready():
	position = PANEL.position
	size = PANEL.size
	mouse_filter = Control.MOUSE_FILTER_STOP
	loadout_panel = preload("res://scripts/equipment_loadout_panel.gd").new()
	loadout_panel.font = font
	loadout_panel.hide()
	for i in range(TAB_LABELS.size()):
		var id: String = TAB_LABELS.keys()[i]
		tabs.append(button(Rect2(16+i*72,54,68,44),TAB_LABELS[id],func(): select_tab(id)))
	close_button = button(Rect2(336,10,40,36),"一覧とパラメータを閉じる（E）",func():
		hide()
		close_requested.emit())
	sort_button = button(Rect2(236,10,40,36),"品質の高い順に並べる",func(): quality_order = not quality_order; page = 0; cancel_bulk(); refresh())
	for i in range(6):
		var index = i
		var row = button(Rect2(16,108+i*82,230,72),"",func(): pass)
		row.gui_input.connect(func(event):
			if bulk_quote.is_empty() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and index < rows.size():
				if state.editable and rows[index].position != Inventory.STOWED: stow_requested.emit(rows[index].uid)
				accept_event()
				return
			if bulk_quote.is_empty() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and index < rows.size():
				pending_uid = rows[index].uid
				drag_origin = row.get_global_transform()*event.position)
		row.pressed.connect(func():
			if bulk_quote.is_empty() and index < rows.size(): item_selected.emit(rows[index].uid))
		row_buttons.append(row)
		var preview = ModelPreview.new()
		preview.position = row.position+Vector2(8,4)
		preview.size = Vector2(64,64)
		add_child(preview)
		model_previews.append(preview)
		equip_buttons.append(item_button(Rect2(254,108+i*82,54,72),"車体パーツを換装","equip_part_requested",index))
		action_buttons.append(item_button(Rect2(316,108+i*82,60,72),"","item_action",index))
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
	bulk_uids = Inventory.normal_candidates(filtered_items)
	page = 0
	refresh()

func cancel_bulk():
	bulk_uids.clear()
	bulk_quote.clear()

func _input(event):
	if not visible:
		pending_uid = -1
		return
	if not touch_mode and event is InputEventMouseMotion and pending_uid >= 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT and (get_canvas_transform().affine_inverse()*event.position).distance_to(drag_origin) > 8:
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
	loadout_panel.update_state(state)
	if not visible: return
	arrange_rows()
	var signature = [state.items.hash(),genre,quality_order].hash()
	if signature != list_signature:
		list_signature = signature
		filtered_items = state.items.filter(func(item):
			var slot = Catalog.part_slot(item.kind)
			if genre == "": return slot.is_empty()
			if genre in Catalog.PART_SLOTS: return slot == genre
			return Catalog.DEFINITIONS[item.kind].genre == genre)
		if quality_order:
			filtered_items.sort_custom(func(a,b):
				var a_power: float = Catalog.RARITIES[a.rarity].power
				var b_power: float = Catalog.RARITIES[b.rarity].power
				if a_power != b_power: return a_power > b_power
				var a_level = Catalog.level(a.kind)
				var b_level = Catalog.level(b.kind)
				return a_level > b_level if a_level != b_level else a.uid < b.uid)
	bulk_quote = Inventory.quote_normals(state.items,bulk_uids)
	if bulk_quote.is_empty() or state.phase in ["lost","won","retreated"]: cancel_bulk()
	var previewing = not bulk_quote.is_empty()
	display_items = filtered_items.filter(func(item): return item.uid in bulk_uids) if previewing else filtered_items
	page = clampi(page,0,maxi(0,ceili(float(display_items.size())/page_size)-1))
	rows = display_items.slice(page*page_size,page*page_size+page_size)
	previous.disabled = page == 0
	next.disabled = (page+1)*page_size >= display_items.size()
	previous.position = Vector2(148,10) if previewing else Vector2(16,size.y-44)
	next.position = Vector2(192,10) if previewing else Vector2(296,size.y-44)
	previous.size = Vector2(40,36) if previewing else Vector2(80,40)
	next.size = previous.size
	sort_button.tooltip_text = "入手順に戻す" if quality_order else "品質の高い順に並べる"
	bulk_button.visible = not previewing
	for b in [cancel_button,confirm_button]: b.visible = previewing
	var candidates = Inventory.normal_candidates(filtered_items)
	bulk_button.disabled = candidates.is_empty() or state.phase in ["lost","won","retreated"]
	bulk_button.tooltip_text = "このジャンルのノーマル %d個をまとめて解体\n未設置・弾なしのみ。次に対象数と素材量を確認します。" % candidates.size()
	if previewing: confirm_button.tooltip_text = "%d個を解体：スクラップ +%d / 石炭 +%d（元に戻せません）" % [bulk_quote.count,bulk_quote.scrap,bulk_quote.coal]
	for i in range(6):
		for b in [row_buttons[i],equip_buttons[i],action_buttons[i],model_previews[i]]: b.visible = i < rows.size()
		if i >= rows.size(): continue
		var item: Dictionary = rows[i]
		model_previews[i].show_item(item)
		var definition = Catalog.DEFINITIONS[item.kind]
		var rarity = Catalog.RARITIES[item.rarity]
		var mounted = item.position != Inventory.STOWED
		var slot = Catalog.part_slot(item.kind)
		var materials = Catalog.salvage(item)
		row_buttons[i].tooltip_text = "%s · %s\n%s / %d×%d\n%s\n%s" % [rarity.name,Catalog.Content.EQUIPMENT[item.kind].name,Catalog.GENRES[definition.genre],definition.size.x,definition.size.y,Catalog.description(item),"選択後に空き枠をクリックして設置 / D&Dで移動（同じ系統は1基まで）" if state.editable else "出撃中：装備変更不可"]
		if item.kind in Catalog.Content.ALL_GUNS:
			row_buttons[i].tooltip_text += "\n大型副砲 / 干渉時は二段配置 / 2×2枠の外周から給弾"
			if item.get("ammo",0) > 0: row_buttons[i].tooltip_text += "\n保管弾 %d発" % item.ammo
		# Set the final state once. Disabling then re-enabling a held swap
		# button cancels its press before the mouse/touch release arrives.
		equip_buttons[i].visible = not slot.is_empty() and (not mounted or slot == "cannon")
		equip_buttons[i].disabled = previewing or not state.editable or (mounted and slot != "cannon")
		equip_buttons[i].tooltip_text = "装備を外して一覧に戻す（出撃準備のみ）"
		if not slot.is_empty():
			var current: Dictionary = state.get("vehicle_parts",{}).get(slot,{})
			var current_name: String = Catalog.Data.ITEMS[current.kind].name if not current.is_empty() else ("装備なし" if slot in state.get("empty_slots",[]) else "標準装備")
			row_buttons[i].tooltip_text = "%s · %s\n%s\n現在の%s：%s\n出撃準備中に換装ボタンで交換" % [rarity.name,Catalog.Data.ITEMS[item.kind].name,Catalog.description(item),Catalog.PART_SLOTS[slot],current_name]
			equip_buttons[i].tooltip_text = "主砲を移動：給弾口ごと移動先を選択" if mounted and slot == "cannon" else "装備中" if mounted else Catalog.PART_SLOTS[slot]+"を換装："+current_name+" → "+Catalog.Data.ITEMS[item.kind].name
		action_buttons[i].disabled = previewing or (not state.editable if mounted else state.phase in ["lost","won","retreated"])
		action_buttons[i].tooltip_text = "解体：スクラップ +%d / 石炭 +%d（元に戻せません）" % [materials.scrap,materials.coal]
		if item.get("ammo",0) > 0: action_buttons[i].tooltip_text += "\n保管弾 %d発も失います" % item.ammo
		if mounted: action_buttons[i].tooltip_text = "しまう：装備を外して倉庫へ戻す（出撃準備のみ）"
		if mounted: row_buttons[i].tooltip_text += "\n右クリックで倉庫へ戻す（出撃準備のみ）"
		row_buttons[i].tooltip_text += "\n"+("設置済み" if mounted else "未設置・倉庫")+(" / 選択中" if item.uid == state.get("selected_uid",-1) else "")
		if slot.is_empty(): row_buttons[i].tooltip_text += " / 選択してR・回転ボタンで90°回転"
		var activation: Dictionary = state.get("activation",{}).get(item.uid,{})
		if not activation.get("requirement","").is_empty(): row_buttons[i].tooltip_text += "\n発動条件："+activation.requirement+" / "+activation.reason
		row_buttons[i].tooltip_text += "\n着想："+Catalog.Data.ITEMS[item.kind].get("inspiration","史実の機械構造を参考にしたゲーム用装備")
	queue_redraw()

func icon(id: String, rect: Rect2, tint: Color = Color.WHITE):
	draw_texture_rect(icons.texture(id),rect,false,tint)

func _draw():
	draw_style_box(Style.style(Style.OVERLAY_PANEL,Style.EDGE),Rect2(Vector2.ZERO,size))
	icon("cargo",Rect2(16,10,30,30))
	draw_string(font,Vector2(56,33),str(state.items.size()),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	icon("play" if state.editable else "lock",Rect2(288,12,26,26))
	icon("close",Rect2(344,16,24,24))
	icon("sort",Rect2(244,16,24,24),Style.GOLD if quality_order else Style.MUTED)
	for i in range(tabs.size()):
		var id: String = TAB_LABELS.keys()[i]
		icon(TAB_ICONS[id],Rect2(tabs[i].position+Vector2(24,3),Vector2(20,20)),Style.GOLD if genre == id else Style.MUTED)
		draw_string(font,tabs[i].position+Vector2(2,38),TAB_LABELS[id],HORIZONTAL_ALIGNMENT_CENTER,64,12,Style.GOLD if genre == id else Style.MUTED)
	for i in range(rows.size()):
		var item: Dictionary = rows[i]
		var at: Vector2 = row_buttons[i].position
		if item.uid == state.get("selected_uid",-1): draw_style_box(Style.style(Color(0.9,0.7,0.35,0.12),Style.GOLD),Rect2(at,row_buttons[i].size))
		var rarity = Catalog.RARITIES[item.rarity]
		var rank = Catalog.RARITIES.keys().find(item.rarity)+1
		draw_rect(Rect2(at+Vector2(1,1),Vector2(5,70)),Color(rarity.color))
		var slot = Catalog.part_slot(item.kind)
		var name_lines = [""]
		for letter in Catalog.Data.ITEMS[item.kind].name:
			if font.get_string_size(name_lines.back()+letter,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x > 144: name_lines.append("")
			name_lines[-1] += letter
		for line in range(name_lines.size()): draw_string(font,at+Vector2(80,18+line*15),name_lines[line],HORIZONTAL_ALIGNMENT_LEFT,144,12,Style.INK)
		icon(Catalog.profile_icon(item.kind),Rect2(at+Vector2(80,40),Vector2(18,18)))
		for j in range(rank): draw_rect(Rect2(at+Vector2(102+j*10,46),Vector2(7,7)),Color(rarity.color))
		var footprint: Vector2i = Catalog.footprint(item.kind,item.get("direction",0))
		draw_string(font,at+Vector2(148,55),"" if item.kind in Catalog.Data.ACTIVE_IDS else "Lv.%d" % Catalog.level(item.kind),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Style.INK)
		draw_string(font,at+Vector2(192,55),Catalog.PART_SLOTS[slot] if not slot.is_empty() else "%d×%d" % [footprint.x,footprint.y],HORIZONTAL_ALIGNMENT_LEFT,44,10,Style.MUTED)
		if item.position != Inventory.STOWED: icon("victory",Rect2(at+Vector2(206,5),Vector2(18,18)))
		var status = ("設置済み" if slot.is_empty() else "装備中") if item.position != Inventory.STOWED else ("未設置" if slot.is_empty() else "未装備")
		if item.uid == state.get("selected_uid",-1): status = "選択中 / "+status
		if item.position != Inventory.STOWED and not state.get("activation",{}).get(item.uid,{}).get("active",true): status = "設置済み・効果なし"
		if slot.is_empty(): status += " "+["→","↓","←","↑"][int(item.get("direction",0))]
		draw_string(font,at+Vector2(80,68),status,HORIZONTAL_ALIGNMENT_LEFT,145,12,Style.GOLD if item.uid == state.get("selected_uid",-1) else Style.MINT if item.position != Inventory.STOWED else Style.MUTED)
		if equip_buttons[i].visible:
			icon("ready",Rect2(equip_buttons[i].position+Vector2(13,12),Vector2(28,28)),Style.MUTED if equip_buttons[i].disabled else Style.INK)
			draw_string(font,equip_buttons[i].position+Vector2(4,60),"移動" if slot == "cannon" and item.position != Inventory.STOWED else "換装",HORIZONTAL_ALIGNMENT_CENTER,46,14,Style.MUTED if equip_buttons[i].disabled else Style.INK)
		var mounted = item.position != Inventory.STOWED
		var tint = Style.MUTED if action_buttons[i].disabled else Style.INK if mounted else Style.GOLD
		icon("cargo" if mounted else "scrap",Rect2(action_buttons[i].position+Vector2(16,10),Vector2(28,28)),tint)
		draw_string(font,action_buttons[i].position+Vector2(1,60),"しまう" if mounted else "+%d" % Catalog.salvage(item).scrap,HORIZONTAL_ALIGNMENT_CENTER,58,16,tint)
	icon("scrap",Rect2(16,size.y-76,24,24))
	draw_string(font,Vector2(48,size.y-55),"+"+str(bulk_quote.scrap) if not bulk_quote.is_empty() else str(state.reserves.scrap),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Style.INK)
	icon("coal",Rect2(162,size.y-76,24,24))
	draw_string(font,Vector2(194,size.y-55),"+"+str(bulk_quote.coal) if not bulk_quote.is_empty() else str(state.reserves.coal),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Style.INK)
	draw_string(font,Vector2(310,size.y-55),"%d/%d" % [page+1,maxi(1,ceili(float(display_items.size())/page_size))],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Style.MUTED)
	if not bulk_quote.is_empty():
		icon("back",Rect2(previous.position+Vector2(8,6),Vector2(24,24)),Style.MUTED if previous.disabled else Style.INK)
		icon("forward",Rect2(next.position+Vector2(8,6),Vector2(24,24)),Style.MUTED if next.disabled else Style.INK)
	icon("close" if not bulk_quote.is_empty() else "back",Rect2(44,size.y-36,24,24))
	icon("ready" if not bulk_quote.is_empty() else "forward",Rect2(324,size.y-36,24,24))
	icon("scrap",Rect2(126,size.y-36,24,24),Style.MUTED if bulk_button.disabled else Style.GOLD)
	var count = bulk_quote.count if not bulk_quote.is_empty() else Inventory.normal_candidates(filtered_items).size()
	draw_string(font,Vector2(166,size.y-16),"×"+str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Style.INK)
	draw_rect(Rect2(254,size.y-28,10,8),Color(Catalog.RARITIES.normal.color))

func cancel_pending_drag():
	pending_uid = -1

func reset_view():
	loadout_panel.hide()
	cancel_pending_drag()
	genre = ""
	page = 0
	quality_order = false
	list_signature = -1
	filtered_items.clear()
	display_items.clear()
	cancel_bulk()
	rows.clear()
	hide()

func arrange_rows():
	if not is_node_ready(): return
	row_pitch = 72.0 if size.y >= 398 and size.y < 410 else 76.0 if size.y >= 410 and size.y < 440 else 82.0
	var next_page_size = clampi(int((size.y-182)/row_pitch),1,6)
	for i in range(row_buttons.size()):
		for b in [row_buttons[i],equip_buttons[i],action_buttons[i]]: b.position.y = 108+i*row_pitch
		model_previews[i].position.y = 112+i*row_pitch
	if next_page_size != page_size:
		page = page*page_size/next_page_size
		page_size = next_page_size
	for button in [bulk_button,cancel_button,confirm_button]: button.position.y = size.y-44
	if bulk_quote.is_empty():
		previous.position.y = size.y-44
		next.position.y = size.y-44
	queue_redraw()
