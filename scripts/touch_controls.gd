extends Control
## Touch driving is separate from mouse emulation used by the existing UI.
const Style = preload("res://scripts/ui_style.gd")
var stick_center = Vector2(170,650)
const STICK_RADIUS = 126.0
var game
var stick_index = -1
var stick = Vector2.ZERO
var buttons: Dictionary = {}
var mode = "build"
var selected_uid = -1
var last_landscape = true
var pressed_buttons: Dictionary = {}
var suppress_world_until_release = false

func _ready():
	size = Vector2(1440,940)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.inventory_panel.touch_mode = game.touch_enabled
	game.inventory_panel.item_selected.connect(func(uid):
		if game.selected_item_uid == uid and game.dragging_item < 0:
			game.set_hand_free()
		elif game.touch_enabled: select_item(uid)
		else: game.select_equipment(uid))
	get_window().size_changed.connect(resized)
	refresh()

func action(id: String):
	if game.menu.visible: return
	match id:
		"rotate": game.rotate_selection()
		"erase", "stow":
			var next_mode = "build" if mode == id else id
			game.clear_equipment_selection()
			mode = next_mode
		"roof": game.world.toggle_roof()
		"inventory":
			cancel_placement()
			game.toggle_inventory()
		"view":
			cancel_placement()
			game.toggle_battle()
		"play":
			cancel_placement()
			game.toggle_running()
		"menu":
			cancel_placement()
			game.open_menu()
	refresh()

func select_item(uid: int):
	if not game.inventory_state().editable: return
	var item: Dictionary = game.Inventory.find_item(game.expedition,uid)
	if item.is_empty(): return
	if not game.Inventory.Catalog.part_slot(item.kind).is_empty() and not (game.Inventory.Catalog.part_slot(item.kind) == "cannon" and item.position != game.Inventory.STOWED):
		game.select_equipment(uid)
		return
	if game.battle_mode: game.toggle_battle()
	if game.world.roof_closed: game.world.toggle_roof()
	if not game.select_equipment(uid): return
	selected_uid = uid
	mode = "place"
	game.inventory_panel.hide()
	game.equipment_workspace.open_left()
	game.factory.message = "装備の設置場所をタップ。倉庫ボタンでキャンセル。"
	queue_redraw()

func cancel_placement(keep_selection: bool = false):
	selected_uid = -1
	mode = "build"
	if not keep_selection: game.clear_equipment_selection()
	game.world.preview_equipment(game.factory,{},Vector2i(-1,-1))

func blocked() -> bool:
	return game.menu.visible or game.inventory_panel.visible or game.choice_popup.visible or game.shop_panel.visible or (game.result_page != null and game.result_page.visible)

func driving() -> bool:
	return game.touch_enabled and not blocked() and game.battle_mode and game.started and game.factory.running and game.expedition.phase == "travel"

func release_stick():
	stick_index = -1
	stick = Vector2.ZERO
	game.touch_movement = Vector2.ZERO
	game.update_movement()
	queue_redraw()

func move_stick(at: Vector2):
	stick = (at-stick_center).limit_length(STICK_RADIUS)/STICK_RADIUS
	game.touch_movement = Vector2(0 if absf(stick.x) < 0.16 else stick.x,0 if absf(stick.y) < 0.16 else stick.y)
	game.update_movement()
	queue_redraw()

func _input(event):
	if event is InputEventScreenTouch:
		var at = get_canvas_transform().affine_inverse()*event.position
		if not event.pressed and pressed_buttons.has(event.index):
			var button = pressed_buttons[event.index]
			pressed_buttons.erase(event.index)
			if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and not event.canceled and button.get_global_rect().has_point(at): button.pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			var candidates: Array = footer_buttons_at(at)
			for button in candidates:
				if button is Button and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(at):
					pressed_buttons[event.index] = button
					get_viewport().set_input_as_handled()
					return
		if not event.pressed and event.index == stick_index:
			release_stick()
			get_viewport().set_input_as_handled()
		elif event.pressed and driving() and stick_index < 0 and at.distance_to(stick_center) <= STICK_RADIUS+28:
			stick_index = event.index
			move_stick(at)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == stick_index:
		move_stick(get_canvas_transform().affine_inverse()*event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and pressed_buttons.has(event.index):
		get_viewport().set_input_as_handled()

func swallow_mouse(event) -> bool:
	if not event is InputEventMouseButton and not event is InputEventMouseMotion: return false
	var at = get_canvas_transform().affine_inverse()*event.position
	if event.device != InputEvent.DEVICE_ID_EMULATION: return false
	for button in footer_buttons_at(at):
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at): return true
	return driving() and at.distance_to(stick_center) < STICK_RADIUS+28

func handle_world_input(event) -> bool:
	if suppress_world_until_release and (event is InputEventMouseMotion or event is InputEventMouseButton):
		if event is InputEventMouseButton and not event.pressed: suppress_world_until_release = false
		get_viewport().set_input_as_handled()
		return true
	if blocked() or game.battle_mode or (not game.touch_enabled and mode == "build"): return false
	if mode != "build" and event is InputEventMouseMotion: return true
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return false
	var at = game.get_canvas_transform().affine_inverse()*event.position
	if not game.world_rect().has_point(at): return false
	if mode == "stow":
		game.stow_at_screen(event.position)
	elif mode == "erase":
		game.last_paint = Vector2i(-1,-1)
		game.paint(game.cell_at(event.position),true)
	elif mode == "place" and selected_uid >= 0:
		if game.place_item(selected_uid,game.cell_at(event.position)):
			cancel_placement(true)
		else: game.factory.message = "ここには配置できません。空いている枠をタップしてください。"
	else:
		var cell = game.cell_at(event.position)
		if game.factory.ports.get(cell,"") == "gun":
			var cannon: Dictionary = game.Inventory.vehicle_parts(game.expedition).get("cannon",{})
			if not cannon.is_empty(): select_item(cannon.uid)
			return true
		var kind: String = game.factory.mounted_at(cell)
		if kind.is_empty(): return false
		for item in game.expedition.gear_items:
			if item.kind == kind and item.position != game.Inventory.STOWED:
				select_item(item.uid)
				break
	suppress_world_until_release = true
	get_viewport().set_input_as_handled()
	return true

func resized():
	if not is_inside_tree() or get_window() == null: return
	release_stick()
	pressed_buttons.clear()
	suppress_world_until_release = false
	var landscape = get_window().size.x >= get_window().size.y
	var turned_portrait = not landscape and last_landscape
	last_landscape = landscape
	if not landscape and game.factory.running:
		game.factory.running = false
		game.clear_movement()
		game.sound.stop_all()
	if turned_portrait and not game.menu.visible and game.expedition.phase in ["prepare","travel"]: game.open_menu()

func _process(_delta): refresh()

func _notification(what: int):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and game != null:
		pressed_buttons.clear()
		release_stick()

func footer_buttons_at(at: Vector2) -> Array:
	if game.menu.visible or game.choice_popup.visible or game.shop_panel.visible or (game.result_page != null and game.result_page.visible): return []
	if game.inventory_panel.visible and game.inventory_panel.occupied_rect().has_point(at): return []
	var candidates: Array = []
	for entry in game.icon_buttons:
		if entry.button.is_visible_in_tree(): candidates.append(entry.button)
	if game.battle_retry.visible: candidates.append(game.battle_retry)
	return candidates

func refresh():
	buttons.clear()
	for entry in game.icon_buttons:
		var id: String = {"cargo":"inventory","battle":"view"}.get(entry.icon,entry.icon)
		if not entry.has("tab_index"): buttons[id] = entry.button
	stick_center.y = minf(650,game.footer_rect().position.y-STICK_RADIUS-24)
	if not driving() and stick_index >= 0: release_stick()
	if mode != "build" and (game.battle_mode or game.inventory_panel.visible or not game.can_manage_layout()): cancel_placement()
	if selected_uid >= 0 and (not game.inventory_state().editable or game.inventory_panel.visible): cancel_placement()
	queue_redraw()

func _draw():
	game.draw_equipment_selection(self)
	if driving():
		draw_circle(stick_center,STICK_RADIUS,Color(0.07,0.1,0.08,0.7))
		draw_arc(stick_center,STICK_RADIUS,0,TAU,64,Style.GOLD,3,true)
		draw_line(stick_center-Vector2(80,0),stick_center+Vector2(80,0),Style.EDGE,2)
		draw_line(stick_center-Vector2(0,80),stick_center+Vector2(0,80),Style.EDGE,2)
		draw_circle(stick_center+stick*STICK_RADIUS,42,Color(Style.GOLD,0.8))
	if not blocked() and mode in ["stow","erase"]:
		var hint = "設置場所をタップ" if mode == "place" else "収納する装備をタップ" if mode == "stow" else "撤去する設備をタップ"
		draw_style_box(Style.style(Style.PANEL,Style.GOLD),Rect2(400,game.footer_rect().position.y-80,640,64))
		draw_string(game.font,Vector2(420,game.footer_rect().position.y-37),hint,HORIZONTAL_ALIGNMENT_CENTER,600,27,Style.INK)
