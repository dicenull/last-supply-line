extends Node2D
const Factory = preload("res://scripts/factory.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const BG = UIStyle.BG
const PANEL = UIStyle.PANEL
const INK = UIStyle.INK
const MUTED = UIStyle.MUTED
const GOLD = UIStyle.GOLD
const MINT = UIStyle.MINT
const BLUE = UIStyle.BLUE
const SURFACE = UIStyle.SURFACE
const EDGE = UIStyle.EDGE
const DANGER = UIStyle.DANGER
const HEADER_RECT = Rect2(16,12,1408,60)
const WORLD_RECT = Rect2(16,84,1408,752)
const FOOTER_RECT = Rect2(16,848,1408,80)
const WorldViewport = preload("res://scenes/world_viewport.tscn")
const TankWorld = preload("res://scripts/tank_world.gd")
var world
const BattleWorld = preload("res://scripts/battle_world.gd")
var battlefield
var battle_container: SubViewportContainer
var factory_container: SubViewportContainer
var battle_mode = false
var started = false
const RunSave = preload("res://scripts/run_save.gd")
const RunMenu = preload("res://scripts/run_menu.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
const RunHistory = preload("res://scripts/run_history.gd")
var history = RunHistory.new()
var history_path = "user://run_history.json"
var new_blueprints: Array = []
var checkpoint = RunSave.new()
var checkpoint_path = "user://run_save.mfv"
var layout_path = "user://ammo_layout.json"
var show_start_menu = true
var menu
var menu_presenter
var menu_title = true
var menu_status = ""
var menu_was_running = false
const RunState = preload("res://scripts/run_state.gd")
var expedition = RunState.new(int(Time.get_unix_time_from_system()*1000000))
var choice_buttons: Array = []
var choice_popup
var battle_retry: Button
const PixelIcons = preload("res://scripts/pixel_icons.gd")
var pixel_icons = PixelIcons.new()
var logistics
var sound
var quitting = false
var audio_enabled = true
var audio_settings_path = "user://audio_settings.json"
var viewport: SubViewport
const NAMES = {"belt":"搬送", "furnace":"精錬炉", "press":"砲弾機", "splitter":"分配器", "depot":"弾薬庫", "erase":"撤去", "source":"廃材口", "gun":"試射口"}
const ITEMS = {"scrap":"廃材", "steel":"鋼材", "shell":"砲弾"}
var new_layout_version = 2
var factory = Factory.new(2)
var font: Font
var selected = "belt"
var direction = 0
var hover = Vector2i(-1,-1)
var last_paint = Vector2i(-1,-1)
var dragging_auxiliary = ""
const Inventory = preload("res://scripts/equipment_inventory.gd")
var inventory_panel
var dragging_item = -1
var suppress_item_paint = false
var inventory_button: Button
var loot_feed
var movement_keys: Dictionary = {}
var tool_page = 0
const TOOL_TABS = [
	{"name":"搬送・選別","icon":"belt","kinds":["belt","scrap_filter","shell_filter","fuel_filter"]},
	{"name":"分岐","icon":"splitter","kinds":["splitter","smart_splitter","priority_splitter","router"]},
	{"name":"加工","icon":"furnace","kinds":["furnace","press","refinery","blast_furnace","auto_press"]},
	{"name":"備蓄","icon":"depot","kinds":["depot","overflow_gate","fuel_depot"]},
	{"name":"防御","icon":"shield","kinds":["armor_block"]}
]
var tool_tabs: Array = []
var erase_button: Button
var start_button: Button
var tool_buttons: Dictionary = {}
var shot_glow = 0.0
var previous_shots = 0
var icon_buttons: Array = []
var field_map: Control
var field_actions: Control
var shop_panel: Control
var notice_time = 0.0
var notice_bad = false
var last_message = ""

func _ready():
	get_window().min_size = Vector2i(960,628)
	history.load_file(history_path)
	get_tree().auto_accept_quit = false
	if factory.layout_version == 2: expedition.enable_items()
	factory.finite_resources = true
	factory.auto_fire = false
	factory.unlocked_blocks = RunState.Content.STARTING_BLOCKS.keys()+history.researched_blocks
	factory.example(false)
	factory.undo_stack.clear()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if OS.has_feature("web"):
		var web_font = FontVariation.new()
		web_font.base_font = load("res://assets/fonts/NotoSansJP.ttf")
		web_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"):600}
		font = web_font
	else:
		var system_font = SystemFont.new()
		system_font.font_names = PackedStringArray(["Helvetica Neue","Hiragino Sans","sans-serif"])
		system_font.font_weight = 600
		font = system_font
	var ui = UIStyle.new()
	ui.font = font
	ui.pixel_icons = pixel_icons
	factory_container = create_world_viewport()
	viewport = factory_container.get_node("Viewport")
	world = TankWorld.new()
	world.layout_version = factory.layout_version
	viewport.add_child(world)
	start_button = icon_button("play",Rect2(944,862,288,52),toggle_running,"Space")
	icon_button("battle",Rect2(764,862,156,52),toggle_battle,"B")
	icon_button("menu",Rect2(1274,862,134,52),func(): open_menu(false),"Esc")
	battle_retry = add_button("",Rect2(614,862,212,52),reset_battle)
	battle_retry.visible = false
	for i in range(7):
		icon_button("",Rect2(110+i*68,880,62,44),func(): pass,str(i+1))
	icon_button("rotate",Rect2(610,880,74,44),func(): direction = (direction+1)%4,"R")
	erase_button = icon_button("erase",Rect2(32,862,64,52),func(): selected = "erase","0")
	erase_button.tooltip_text = "撤去（0）"
	for i in range(TOOL_TABS.size()):
		var index = i
		var button = icon_button(TOOL_TABS[i].icon,Rect2(110+i*96,852,90,24),func(): select_tool_tab(index))
		button.tooltip_text = TOOL_TABS[i].name
		icon_buttons.back().tab_index = i
		tool_tabs.append(button)
	inventory_button = icon_button("cargo",Rect2(690,862,60,52),toggle_inventory,"I")
	inventory_button.tooltip_text = "装備一覧 / 解体（I）"
	var logistics_layer = CanvasLayer.new()
	logistics_layer.layer = 2
	add_child(logistics_layer)
	logistics = preload("res://scripts/logistics_overlay.gd").new()
	logistics.game = self
	logistics_layer.add_child(logistics)
	loot_feed = preload("res://scripts/equipment_loot_feed.gd").new()
	loot_feed.icons = pixel_icons
	loot_feed.font = font
	logistics_layer.add_child(loot_feed)
	field_map = preload("res://scripts/field_map.gd").new()
	field_map.icons = pixel_icons
	field_map.state_provider = func(): return {"battle":battlefield,"visible":battle_mode and not menu.visible}
	logistics_layer.add_child(field_map)
	var actions_layer = CanvasLayer.new()
	actions_layer.layer = 4
	add_child(actions_layer)
	field_actions = preload("res://scripts/field_actions.gd").new()
	field_actions.icons = pixel_icons
	field_actions.font = font
	field_actions.state_provider = repair_state
	field_actions.repair_requested.connect(repair_vehicle)
	actions_layer.add_child(field_actions)
	sound = preload("res://scripts/game_audio.gd").new()
	sound.game = self
	sound.enabled = audio_enabled
	sound.settings_path = audio_settings_path
	add_child(sound)
	var choice_layer = CanvasLayer.new()
	choice_layer.layer = 6
	add_child(choice_layer)
	var inventory_layer = CanvasLayer.new()
	inventory_layer.layer = 8
	add_child(inventory_layer)
	inventory_panel = preload("res://scripts/equipment_inventory_panel.gd").new()
	inventory_panel.icons = pixel_icons
	inventory_panel.font = font
	inventory_panel.state_provider = inventory_state
	inventory_panel.drag_requested.connect(begin_item_drag)
	inventory_panel.stow_requested.connect(stow_item)
	inventory_panel.dismantle_requested.connect(dismantle_item)
	inventory_layer.add_child(inventory_panel)
	choice_popup = preload("res://scripts/run_choice_popup.gd").new()
	choice_popup.configure(ui,choice_models,can_claim_reward)
	choice_popup.option_selected.connect(choose_run_option)
	choice_popup.crafting_finished.connect(finish_crafting)
	choice_layer.add_child(choice_popup)
	choice_buttons = choice_popup.buttons
	shop_panel = preload("res://scripts/shop_panel.gd").new()
	shop_panel.icons = pixel_icons
	shop_panel.font = font
	shop_panel.state_provider = shop_state
	shop_panel.purchase_requested.connect(buy_shop_item)
	shop_panel.finished.connect(leave_shop)
	shop_panel.inventory_requested.connect(toggle_inventory)
	choice_layer.add_child(shop_panel)
	var menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu = RunMenu.new()
	menu_presenter = preload("res://scripts/run_menu_presenter.gd").new(self)
	menu_presenter.bind(menu,ui)
	menu_layer.add_child(menu)
	if show_start_menu: open_menu(true)

func toggle_running():
	if quitting: return
	if expedition.phase not in ["prepare","travel"]: return
	ensure_battle()
	if battlefield.result != 0: return
	if not started:
		expedition.start_sector()
		started = true
		factory.loadout_locked = true
		factory.layout_locked = false
		factory.combat_editing = true
		world.playback_only = true
		battle_mode = true
	factory.running = not factory.running
	clear_movement()
	if not factory.running: sound.stop_all()
	refresh_view()

func toggle_battle():
	ensure_battle()
	battle_mode = not battle_mode
	refresh_view()

func create_world_viewport() -> SubViewportContainer:
	var container = WorldViewport.instantiate()
	container.position = WORLD_RECT.position
	container.size = WORLD_RECT.size
	add_child(container)
	return container

func release_battle():
	if is_instance_valid(battle_container): battle_container.queue_free()
	battle_container = null
	battlefield = null

func ensure_battle():
	if battlefield == null:
		battle_container = create_world_viewport()
		var battle_viewport = battle_container.get_node("Viewport")
		battlefield = BattleWorld.new()
		battlefield.layout_version = factory.layout_version
		battlefield.item_mode = expedition.item_mode
		battlefield.item_dropped.connect(receive_item)
		battlefield.sector_config = expedition.current.duplicate(true)
		battlefield.hull = expedition.hull
		battlefield.fuel_multiplier = expedition.modifiers.fuel
		battlefield.reload_multiplier = expedition.modifiers.get("reload",1.0)
		battle_viewport.add_child(battlefield)
	sync_equipment()

func sync_equipment():
	var positions = factory.auxiliary_positions()
	world.configure_equipment(expedition.equipment,positions,factory.equipment_mounts)
	world.sync_damage(factory)
	if battlefield != null:
		battlefield.configure_equipment(expedition.equipment,positions,factory.equipment_mounts)
		battlefield.sync_damage(factory)
		battlefield.combat_modifiers = expedition.modifiers.duplicate()
		battlefield.combat_modifiers.equipment_power = Inventory.powers(expedition)

func recover_recipe(role: int):
	var id = expedition.recover_recipe(role)
	if id != "": factory.message = "レシピ獲得："+RunState.EQUIPMENT[id].name

func craft_equipment(id: String) -> bool:
	if Factory.AUXILIARY.has(id) and not factory.inside(factory.install_position(id)): return false
	if menu.visible or not expedition.craft(id,factory.reserves): return false
	if Factory.AUXILIARY.has(id): factory.install_auxiliary(id)
	sync_equipment()
	refresh_view()
	return true

func finish_crafting():
	if menu.visible or not expedition.finish_crafting(factory.reserves,factory.inventory,has_mount_space()): return
	record_result()
	refresh_view()

func footer_rect() -> Rect2:
	return FOOTER_RECT

func refresh_view():
	cancel_item_drag()
	dragging_auxiliary = ""
	var scene_size = Vector2(WORLD_RECT.size.x,footer_rect().position.y-12-WORLD_RECT.position.y)
	factory_container.size = scene_size
	if battle_container != null:
		battle_container.size = scene_size
	factory_container.visible = not battle_mode
	if battle_container != null: battle_container.visible = battle_mode
	hover = Vector2i(-1,-1)
	world.placement_preview.visible = false
	for entry in icon_buttons:
		entry.button.visible = entry.icon == "menu" or ((expedition.phase in ["prepare","travel"]) and ((not battle_mode and can_manage_layout()) or entry.icon in ["battle","play","cargo"]))
	sync_tools()
	start_button.tooltip_text = "出撃" if not started else "一時停止 / 再開"
	if choice_popup != null: choice_popup.refresh()
	if shop_panel != null: shop_panel.refresh()
	if inventory_panel != null: inventory_panel.refresh()
	queue_redraw()

func reset_battle(seed_value: int = -1):
	if quitting: return
	sound.stop_all()
	if world.feedback != null: world.feedback.clear()
	if battlefield == null: return
	new_blueprints.clear()
	choice_popup.craft_page = 0
	inventory_panel.reset_view()
	loot_feed.clear()
	release_battle()
	battle_mode = false
	started = false
	clear_movement()
	factory.layout_locked = false
	factory.combat_editing = false
	world.playback_only = false
	# An explicit seed makes restart/replay callers reproducible; UI calls use a fresh seed.
	var next_seed = int(Time.get_unix_time_from_system()*1000000) if seed_value == -1 else seed_value
	expedition = RunState.new(next_seed,expedition.difficulty)
	factory = Factory.new(new_layout_version)
	factory.finite_resources = true
	factory.auto_fire = false
	if new_layout_version == 2: expedition.enable_items()
	factory.work_multiplier = 1.0
	factory.ammo_capacity = 12
	factory.reserve_capacity = 100
	var settings = RunState.Content.DIFFICULTIES[expedition.difficulty]
	factory.reserves = {"scrap":settings.scrap,"coal":settings.coal}
	factory.collected = {"scrap":0,"coal":0}
	factory.remove_auxiliary()
	factory.unlocked_blocks = RunState.Content.STARTING_BLOCKS.keys()+history.researched_blocks
	factory.clear_layout(false,false)
	factory.example(false)
	factory.undo_stack.clear()
	factory.reset_trial()
	ensure_battle()
	refresh_view()

func live_control(icon: String, _rect: Rect2) -> bool:
	return icon in ["play","battle","menu","cargo"] or (can_manage_layout() and not battle_mode)

func available_tools() -> Array:
	var kinds: Array = []
	for tab in TOOL_TABS: kinds.append_array(tab.kinds.filter(func(kind): return kind in factory.unlocked_blocks))
	return kinds

func available_tool_tabs() -> Array:
	var tabs: Array = []
	for i in range(TOOL_TABS.size()):
		if TOOL_TABS[i].kinds.any(func(kind): return kind in factory.unlocked_blocks): tabs.append(i)
	return tabs

func tool_page_count() -> int:
	return available_tool_tabs().size()

func tool_kinds() -> Array:
	var tabs = available_tool_tabs()
	if tabs.is_empty(): return []
	if tool_page not in tabs: tool_page = tabs[0]
	return TOOL_TABS[tool_page].kinds.filter(func(kind): return kind in factory.unlocked_blocks)

func select_tool_tab(index: int):
	if index not in available_tool_tabs(): return
	tool_page = index
	if selected != "erase": selected = tool_kinds()[0]
	sync_tools()
	queue_redraw()

func cycle_tools():
	var tabs = available_tool_tabs()
	if not tabs.is_empty(): select_tool_tab(tabs[(tabs.find(tool_page)+1)%tabs.size()])

func sync_tools():
	if inventory_button != null: inventory_button.visible = expedition.item_mode and expedition.phase in ["prepare","travel","reward","shop"]
	var kinds = tool_kinds()
	if selected != "erase" and selected not in available_tools(): selected = kinds[0] if not kinds.is_empty() else "erase"
	var changed = tool_buttons.keys() != kinds
	if changed: tool_buttons.clear()
	var shown = expedition.phase in ["prepare","travel"] and not battle_mode and can_manage_layout()
	for i in range(7):
		var entry = icon_buttons[3+i]
		entry.button.visible = shown and i < kinds.size()
		if not changed: continue
		for connection in entry.button.pressed.get_connections(): entry.button.pressed.disconnect(connection.callable)
		if i >= kinds.size():
			entry.icon = ""
			continue
		entry.icon = kinds[i]
		var kind: String = kinds[i]
		entry.button.pressed.connect(func(): selected = kind)
		entry.button.disabled = false
		entry.button.tooltip_text = Factory.Content.BLOCKS[kind].name+"："+Factory.Content.BLOCKS[kind].effect if Factory.Content.BLOCKS.has(kind) else NAMES.get(kind,kind)
		tool_buttons[kind] = entry.button
	erase_button.visible = shown
	for i in range(tool_tabs.size()):
		tool_tabs[i].visible = shown and i in available_tool_tabs()

func set_difficulty(mode: String) -> bool:
	if started or mode not in RunState.Content.DIFFICULTIES or not can_manage_layout() or expedition.sector != 1: return false
	if mode == expedition.difficulty: return true
	inventory_panel.reset_view()
	loot_feed.clear()
	expedition = RunState.new(expedition.run_seed,mode)
	if factory.layout_version == 2: expedition.enable_items()
	factory.remove_auxiliary()
	factory.clear_layout(false,false)
	factory.example(false)
	factory.undo_stack.clear()
	factory.collected = {"scrap":0,"coal":0}
	var settings = RunState.Content.DIFFICULTIES[mode]
	factory.reserves = {"scrap":settings.scrap,"coal":settings.coal}
	if battlefield != null:
		release_battle()
		ensure_battle()
	return true

func can_manage_layout() -> bool:
	return expedition.phase in ["prepare","travel"]

func clear_movement():
	movement_keys.clear()
	if battlefield != null: battlefield.movement_direction = Vector3.ZERO

func update_movement():
	if battlefield == null: return
	var horizontal = int(movement_keys.has(KEY_D) or movement_keys.has(KEY_RIGHT))-int(movement_keys.has(KEY_A) or movement_keys.has(KEY_LEFT))
	var vertical = int(movement_keys.has(KEY_S) or movement_keys.has(KEY_DOWN))-int(movement_keys.has(KEY_W) or movement_keys.has(KEY_UP))
	# Independent throttle and steering; the battle applies the current hull heading.
	battlefield.movement_direction = Vector3(-vertical,0,horizontal)

func reset_camera():
	world.yaw = 0.65
	world.pitch = 0.92
	world.zoom = 17.8
	world.update_camera()

func icon_button(icon: String, rect: Rect2, action: Callable, keycap: String = "") -> Button:
	var b = add_button("",rect,func():
		if started and not live_control(icon,rect): return
		action.call())
	b.add_theme_stylebox_override("normal",style(Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover",style(Color(1,1,1,0.06),GOLD))
	b.add_theme_stylebox_override("pressed",style(Color(1,0.8,0.4,0.12),GOLD))
	icon_buttons.append({"icon":icon,"rect":rect,"key":keycap,"button":b})
	return b

func style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	return UIStyle.style(color,border)

func add_button(title: String, rect: Rect2, action: Callable, color: Color = MUTED) -> Button:
	var b = Button.new()
	b.text = title
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",15)
	b.add_theme_color_override("font_color",INK)
	b.add_theme_stylebox_override("normal",style(Color.TRANSPARENT,EDGE))
	b.add_theme_stylebox_override("hover",style(Color(1,1,1,0.06),color))
	b.pressed.connect(action)
	add_child(b)
	return b

func save_layout() -> bool:
	var file = FileAccess.open(layout_path,FileAccess.WRITE)
	if file == null:
		factory.message = "配置を保存できませんでした。"
		return false
	file.store_string(JSON.stringify({"version":2,"layout_version":factory.layout_version,"cells":factory.layout()}))
	file.flush()
	if file.get_error() != OK: return false
	factory.message = "配置を保存しました。物資や計測値は保存しません。"
	return true

func load_layout() -> bool:
	if not can_manage_layout(): return false
	if not FileAccess.file_exists(layout_path):
		factory.message = "保存済みの配置がありません。"
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2) or not data.get("cells") is Array:
		factory.message = "保存データの形式が正しくありません。"
		return false
	if data.get("layout_version",1) != factory.layout_version:
		factory.message = "車内の固定設備が異なる配置は読み込めません。"
		return false
	var before = factory.layout()
	if factory.restore(data.cells):
		factory.undo_stack.append(before)
		factory.message = "配置を読み込みました。試運転で流れを確認してください。"
		return true
	else: factory.message = "保存データに配置できない設備があります。現在の配置を維持します。"
	return false

func _process(delta):
	if quitting: return
	sync_equipment()
	factory.step(minf(delta,0.1))
	notice_time = maxf(0,notice_time-delta)
	if factory.message != last_message:
		notice_bad = "できません" in factory.message or "ありません" in factory.message or "正しく" in factory.message or "上限" in factory.message or "配置できない" in factory.message
		notice_time = 2.0 if last_message != "" else 0.0
		last_message = factory.message
	if factory.shots > previous_shots: shot_glow = 0.18
	previous_shots = factory.shots
	shot_glow = maxf(0,shot_glow-delta)
	start_button.text = ""
	sync_tools()
	for kind in tool_buttons:
		tool_buttons[kind].add_theme_color_override("font_color",GOLD if selected == kind else MUTED)
		if Factory.LIMITS.has(kind):
			tool_buttons[kind].disabled = kind not in factory.unlocked_blocks
			var cost = RunState.Content.BUILD_COSTS[kind]
			tool_buttons[kind].tooltip_text = "%s　スクラップ %d / 石炭 %d%s" % [RunState.Content.reward_info("block:"+kind).name,cost.scrap,cost.coal,"" if kind in factory.unlocked_blocks else "　未解放：死亡時に設計図を獲得"]
			if kind == "armor_block": tool_buttons[kind].tooltip_text += "\n"+RunState.Content.BASIC_BLOCKS[kind].effect
	if started: battlefield.tick_battle(factory,minf(delta,0.1))
	if started and battlefield.result != 0 and expedition.phase == "travel":
		factory.combat_editing = false
		factory.layout_locked = battlefield.result < 0
		# Restore occupied cells before drafting equipment so wrecks cannot
		# masquerade as spare mounting space.
		if battlefield.result == 1 and battlefield.hull > 0:
			factory.repair_line()
		expedition.finish_sector(battlefield.result == 1,battlefield.hull,factory.inventory,has_mount_space(),battlefield.arrived_destination if battlefield.arrived_destination >= 0 else 0)
		clear_movement()
		if battlefield.result == 1 and expedition.phase != "lost":
			factory.layout_locked = false
			battlefield.hull = expedition.hull
			world.sync_damage(factory)
			battlefield.sync_damage(factory)
			factory.message = "コースクリア。車体とラインを一括修復しました。"
			battlefield.feedback_effect("reward",battlefield.player.position+Vector3(0,5,0),2.0)
			sound.play_effect("reward")
		record_result()
		if expedition.phase == "prepare": prepare_next_sector()
		else: battle_mode = true
		refresh_view()
	if not battle_mode:
		world.sync(factory,hover,selected,direction,delta,can_manage_layout() and not menu.visible and not choice_popup.visible and dragging_auxiliary == "" and dragging_item < 0 and not suppress_item_paint)
		world.preview_equipment(factory,Inventory.find_item(expedition,dragging_item),hover,Inventory.can_place(expedition,factory,dragging_item,hover))
		if dragging_auxiliary != "" and world.marker.visible:
			world.marker.material_override = world.mats.green if factory.can_move_auxiliary(dragging_auxiliary,hover) else world.mats.red
		if started:
			world.turret.rotation.y = battlefield.turret.rotation.y
			world.barrel.position.x = battlefield.barrel.position.x
			world.muzzle.visible = battlefield.muzzle.visible
			for i in range(world.auxiliary_guns.size()):
				var gun = world.auxiliary_guns[i]
				var source = battlefield.auxiliary_guns[i]
				gun.pivot.rotation.y = source.pivot.rotation.y
				gun.barrel.position.x = source.barrel.position.x
				gun.muzzle.visible = source.muzzle.visible
	sound.sync()
	present_feedback(delta)
	logistics.sync(delta)
	battle_retry.visible = battle_mode and expedition.phase in ["won","lost","retreated"]
	choice_popup.refresh()
	shop_panel.refresh()
	inventory_panel.refresh()
	loot_feed.advance(delta if not menu.visible and (factory.running or expedition.phase == "prepare") else 0.0,not menu.visible and expedition.phase in ["prepare","travel"])
	queue_redraw()

func present_feedback(delta: float):
	var animate = not menu.visible and (factory.running or not factory.layout_locked)
	world.tick_feedback(delta if animate else 0.0)
	# Battle particles are driven here too so end-of-course fireworks can finish.
	if battlefield != null: battlefield.tick_feedback(delta if animate or (not menu.visible and expedition.phase in ["reward","route","won"]) else 0.0)
	if menu.visible: return
	var sounds: Dictionary = {}
	for event in factory.feedback_events:
		var target_world = battlefield if battle_mode and battlefield != null else world
		var at: Vector3 = target_world.cell_position(event.cell)+Vector3(0,0.55,0)
		if target_world == battlefield:
			if event.kind in ["place","connect","production"]: continue
			var turret_offset = Vector2(at.x-battlefield.TURRET_CENTER.x,at.z-battlefield.TURRET_CENTER.z)
			var surface_height = battlefield.TURRET_CENTER.y+2.7 if turret_offset.length() < 3.7 else 4.5
			at.y = maxf(at.y,surface_height)
			at = battlefield.player.to_global(at)
		target_world.feedback_effect(event.kind,at,1.4 if event.kind == "armor" else 1.0)
		if event.kind in ["place","connect","armor"]: sounds[event.kind] = true
	for kind in sounds: sound.play_effect(kind)
	factory.feedback_events.clear()

func cell_at(pos: Vector2) -> Vector2i:
	if battle_mode: return Vector2i(-1,-1)
	var canvas_pos = get_canvas_transform().affine_inverse()*pos
	if not WORLD_RECT.has_point(canvas_pos) or world == null: return Vector2i(-1,-1)
	return world.screen_cell(canvas_pos-WORLD_RECT.position)

func paint(p: Vector2i, erase: bool):
	if menu.visible or battle_mode or world.roof_closed or not can_manage_layout(): return
	if p == last_paint: return
	last_paint = p
	var was_running = factory.running
	factory.edit(p,"erase" if erase else selected,direction)
	if started: factory.running = was_running

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and dragging_item < 0: suppress_item_paint = false
		elif not event.pressed: suppress_item_paint = false
	if dragging_item >= 0 and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_item_drag()
		get_viewport().set_input_as_handled()
		return
	if dragging_item >= 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var uid = dragging_item
		var destination = cell_at(event.position)
		cancel_item_drag()
		if not place_item(uid,destination): factory.message = "ここには装備を配置できません。空いている設置枠へ移動してください。"
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:
			if not event.pressed: movement_keys.erase(key)
			elif expedition.phase == "travel" and factory.running and not menu.visible and not event.echo: movement_keys[key] = true
			update_movement()
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		hover = cell_at(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging_auxiliary != "":
		move_auxiliary(dragging_auxiliary,hover)
		dragging_auxiliary = ""
		last_paint = Vector2i(-1,-1)

func move_auxiliary(id: String, destination: Vector2i) -> bool:
	if menu.visible or battle_mode or world.roof_closed or not can_manage_layout(): return false
	if not factory.move_auxiliary(id,destination): return false
	sync_equipment()
	world.rendered_layout = ""
	return true

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I and not menu.visible:
		toggle_inventory()
		return
	if dragging_item >= 0: return
	if suppress_item_paint and (event is InputEventMouseMotion or event is InputEventMouseButton): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not menu.visible and inventory_panel.visible:
			inventory_panel.hide()
			return
		if menu.visible and menu.go_back(): return
		if menu.visible and menu_title: return
		if menu.visible: close_menu()
		else: open_menu(false)
		return
	if menu.visible: return
	if expedition.phase not in ["prepare","travel"]:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and expedition.phase in ["won","lost","retreated"]: reset_battle()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		toggle_battle()
		return
	if expedition.phase == "travel" and battle_mode:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE: toggle_running()
			if event.keycode == KEY_TAB and not battle_mode: world.toggle_roof()
		return
	if battle_mode:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE: toggle_running()
			if event.keycode == KEY_R and expedition.phase in ["won","lost","retreated"]: reset_battle()
			if event.keycode == KEY_TAB and not battle_mode: world.toggle_roof()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: toggle_running()
			KEY_TAB: world.toggle_roof()
			KEY_LEFT:
				if started: return
				world.yaw -= 0.12
				world.update_camera()
			KEY_RIGHT:
				if started: return
				world.yaw += 0.12
				world.update_camera()
			KEY_UP:
				if started: return
				world.pitch = clampf(world.pitch+0.08,0.65,1.35)
				world.update_camera()
			KEY_DOWN:
				if started: return
				world.pitch = clampf(world.pitch-0.08,0.65,1.35)
				world.update_camera()
			KEY_R: direction = (direction+1)%4
			KEY_Q:
				var was_running = factory.running
				factory.rotate(hover)
				if started: factory.running = was_running
			KEY_Z:
				factory.undo()
			KEY_0: selected = "erase"
			KEY_8: cycle_tools()
			KEY_9:
				if "armor_block" in factory.unlocked_blocks:
					select_tool_tab(4)
					selected = "armor_block"
		if event.keycode >= KEY_1 and event.keycode <= KEY_7:
			var index = event.keycode-KEY_1
			if index < tool_kinds().size(): selected = tool_kinds()[index]
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			world.yaw -= event.relative.x*0.007
			world.pitch = clampf(world.pitch+event.relative.y*0.005,0.65,1.35)
			world.update_camera()
		hover = cell_at(event.position)
		if dragging_auxiliary != "": return
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT: paint(hover,false)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT: paint(hover,true)
	if event is InputEventMouseButton:
		if event.pressed and WORLD_RECT.has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			world.zoom = clampf(world.zoom+(-0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8),11,24)
			world.update_camera()
		hover = cell_at(event.position)
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			last_paint = Vector2i(-1,-1)
			if expedition.item_mode and event.button_index == MOUSE_BUTTON_LEFT and factory.mounted_at(hover) != "":
				for item in expedition.gear_items:
					if item.kind == factory.mounted_at(hover) and item.position != Inventory.STOWED: begin_item_drag(item.uid)
				return
			if event.button_index == MOUSE_BUTTON_LEFT and factory.cells.has(hover) and Factory.AUXILIARY.has(factory.cells[hover].kind):
				dragging_auxiliary = factory.cells[hover].kind
				return
			paint(hover,event.button_index == MOUSE_BUTTON_RIGHT)
		elif not event.pressed: last_paint = Vector2i(-1,-1)

func text_at(value: String, pos: Vector2, size_value: int = 16, color: Color = INK):
	draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value,color)

func panel(rect: Rect2, color: Color = PANEL, border: Color = Color.TRANSPARENT):
	draw_style_box(style(color,border),rect)

func arrow(start: Vector2, end: Vector2, color: Color, width: float = 2):
	draw_line(start,end,color,width)
	var d = (end-start).normalized()
	var normal = Vector2(-d.y,d.x)
	draw_line(end,end-d*6+normal*4,color,width)
	draw_line(end,end-d*6-normal*4,color,width)

func item_at(item: String, pos: Vector2, scale_value: float = 1.0):
	var side = roundf(32*scale_value)
	draw_texture_rect(pixel_icons.texture(item),Rect2((pos-Vector2.ONE*side/2).round(),Vector2.ONE*side),false)

func material_counts() -> Dictionary:
	var counts = {"scrap":0,"steel":0,"shell":factory.ammo,"coal":0,"fuel":floori(factory.fuel)}
	for c in factory.cells.values():
		for item in c.items: counts[item] += 1
	return counts

func visible_items() -> Array:
	return world.item_frames(factory)

func symbol(kind: String, pos: Vector2, scale_value: float = 1.0, _tint: Color = MINT):
	var icon = "roof_open" if kind == "roof" and not world.roof_closed else kind
	var side = roundf(44*scale_value)
	draw_texture_rect(pixel_icons.texture(icon),Rect2((pos-Vector2.ONE*side/2).round(),Vector2.ONE*side),false)

func metal_panel(rect: Rect2):
	panel(Rect2(rect.position+Vector2(0,4),rect.size),Color(0,0,0,0.22))
	panel(rect,PANEL,EDGE)
	draw_line(rect.position+Vector2(7,3),rect.position+Vector2(rect.size.x-7,3),Color("8b8967"),1)
	for offset in [Vector2(7,7),Vector2(rect.size.x-7,7),Vector2(7,rect.size.y-7),rect.size-Vector2(7,7)]:
		var at = rect.position+offset
		draw_circle(at,2,Color("9a906b"))
		draw_line(at-Vector2(1,1),at+Vector2(1,1),BG,1)

func inset(rect: Rect2):
	panel(rect,SURFACE)

func keycap(value: String, at: Vector2):
	var width = maxf(22,font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+12)
	panel(Rect2(at,Vector2(width,22)),BG,EDGE)
	text_at(value,at+Vector2(6,16),13,INK)

func draw_control(entry: Dictionary):
	var rect: Rect2 = entry.rect
	var picked = selected == entry.icon or (entry.icon == "roof" and world.roof_closed)
	if entry.has("tab_index"): picked = tool_page == entry.tab_index
	var primary = entry.icon == "play"
	panel(rect,Color("51563b") if picked else SURFACE,GOLD if picked or primary else EDGE)
	if entry.icon == "cargo":
		symbol("cargo",rect.position+Vector2(16,18),0.5)
		keycap("I",rect.position+Vector2(33,5))
		var count = str(expedition.gear_items.size())
		text_at(count,rect.position+Vector2((rect.size.x-font.get_string_size(count,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x)/2,45),16,INK)
		return
	if picked: panel(Rect2(rect.position+Vector2(12,rect.size.y-5),Vector2(rect.size.x-24,3)),GOLD)
	var icon = entry.icon
	if icon == "play": icon = "pause" if factory.running else "play"
	if icon == "battle": icon = "example" if battle_mode else "battle"
	if icon == "roof": icon = "roof" if world.roof_closed else "roof_open"
	var center = rect.get_center()
	if primary: center.x = rect.position.x+104
	if entry.key != "": center.x += 10
	symbol(icon,center,minf(1.05 if entry.icon in tool_buttons else 0.82,(rect.size.y-4)/44.0))
	if primary: text_at("出撃" if not started else "停止" if factory.running else "再開",rect.position+Vector2(160,34),20,INK)
	if entry.key != "": keycap(entry.key,rect.position+Vector2(5,5))
	if Factory.LIMITS.has(entry.icon) and not entry.has("tab_index"):
		var remaining = factory.available(entry.icon)
		panel(Rect2(rect.position+Vector2(rect.size.x-27,rect.size.y-21),Vector2(25,19)),SURFACE)
		text_at(str(remaining) if entry.icon in factory.unlocked_blocks else "—",rect.position+Vector2(rect.size.x-24,rect.size.y-6),14,GOLD if remaining > 0 else MUTED)

func _draw():
	draw_rect(Rect2(0,0,1440,940),BG)
	draw_header()
	metal_panel(footer_rect())
	for entry in icon_buttons:
		if entry.button.visible: draw_control(entry)
	if expedition.phase == "travel" and battle_mode:
		text_at("W 前進   S 後退   A/D 旋回",Vector2(40,895),20,INK)
		symbol("belt",Vector2(445,888),0.65)
		text_at("B 車内で編集",Vector2(470,895),20,MUTED)
	if battle_retry.visible:
		symbol("reset",battle_retry.get_rect().get_center()+Vector2(12,0),1.0)
		keycap("R",battle_retry.position+Vector2(12,12))

func meter(rect: Rect2, fraction: float, color: Color):
	panel(rect,BG)
	if fraction > 0: panel(Rect2(rect.position,Vector2(rect.size.x*clampf(fraction,0,1),rect.size.y)),color)

func header_stat(rect: Rect2, icon: String, value: String, color: Color = INK, fraction: float = -1):
	inset(rect)
	symbol(icon,rect.position+Vector2(17,19),0.58)
	var font_size = 20
	while font_size > 14 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > rect.size.x-36:
		font_size -= 1
	text_at(value,rect.position+Vector2(33,26),font_size,color)
	if fraction >= 0: meter(Rect2(rect.position+Vector2(8,35),Vector2(rect.size.x-16,3)),fraction,color)

func stock_text(item: String, amount: int, capacity: int) -> String:
	# Receipts share their resource's single-line counter, keeping the current stock visible.
	if logistics != null and logistics.notices.has(item):
		var receipt = logistics.notices[item]
		return "%d +%d" % [amount,receipt.accepted]+(" −%d" % receipt.lost if receipt.lost > 0 else "")
	if item in ["scrap","coal"]: return str(amount)
	return "%d/%d" % [amount,capacity]

func destination_text() -> String:
	var remaining = battlefield.remaining_distance() if battlefield != null else float(expedition.current.length)
	return "あと%dm" % ceili(remaining)

func draw_header():
	metal_panel(HEADER_RECT)
	if not battle_mode and (not factory.receiving_cell(hover).is_empty() or factory.wrecks.has(hover)):
		draw_inspector()
	else:
		if not new_blueprints.is_empty() and expedition.phase == "lost":
			var id = new_blueprints.back()
			text_at(RunState.Content.reward_info("block:"+id).name+" 解放",Vector2(24,49),14,GOLD)
		elif not new_blueprints.is_empty() and expedition.phase in ["reward","route","won"]:
			symbol("example",Vector2(48,42),0.7)
			text_at("+"+str(new_blueprints.size()),Vector2(73,49),20,GOLD)
		elif expedition.phase in ["won","lost","retreated"]:
			symbol("victory" if expedition.phase == "won" else "retreat" if expedition.phase == "retreated" else "defeat",Vector2(48,42),0.75)
		else: text_at("ライン構築" if expedition.phase == "prepare" else "戦闘" if expedition.phase == "travel" else "M.F.V. 03",Vector2(32,49),19,INK)
		text_at("%d/5" % expedition.sector,Vector2(157,49),19,MUTED)
		symbol(expedition.current.get("terrain","road"),Vector2(218,42),0.55)
		symbol(expedition.current.get("formation","patrol"),Vector2(250,42),0.55)
	var hull = battlefield.hull if battlefield != null else expedition.hull
	header_stat(Rect2(274,22,100,40),"shield",str(hull),DANGER if hull <= 25 else GOLD,hull/100.0)
	header_stat(Rect2(384,22,128,40),"shell",stock_text("shell",factory.ammo,factory.ammo_capacity),DANGER if factory.ammo == 0 else INK,float(factory.ammo)/factory.ammo_capacity)
	header_stat(Rect2(522,22,138,40),"fuel","%.1f/12" % factory.fuel,DANGER if factory.fuel < 0.01 else INK,factory.fuel/12.0)
	for i in range(2):
		var raw = "scrap" if i == 0 else "coal"
		header_stat(Rect2(670+i*142,22,132,40),raw,stock_text(raw,factory.reserves[raw],factory.reserve_capacity),DANGER if factory.reserves[raw] == 0 else INK)
	header_stat(Rect2(954,22,64,40),"steel",str(material_counts().steel))
	var length = float(expedition.current.length)
	var remaining = battlefield.remaining_distance() if battlefield != null else length
	header_stat(Rect2(1028,22,270,40),"move",destination_text(),INK,clampf(1.0-remaining/length,0,1))
	header_stat(Rect2(1308,22,100,40),"battle","%d/%d" % [battlefield.kills if battlefield != null else 0,RunState.enemy_count(expedition.current)])

func draw_inspector():
	if factory.wrecks.has(hover):
		symbol("defeat",Vector2(47,42),0.65)
		text_at("部位破壊",Vector2(68,49),17,DANGER)
		return
	var c: Dictionary = factory.receiving_cell(hover)
	var kind: String = c.kind
	symbol(kind,Vector2(47,42),0.65)
	if Factory.AUXILIARY.has(kind):
		text_at(RunState.EQUIPMENT[kind].name,Vector2(68,49),16,INK)
		text_at("%d/%d" % [c.items.size(),factory.ammo_capacity],Vector2(166,49),17,GOLD)
		symbol(factory.diagnostic(hover).code,Vector2(240,42),0.6)
		return
	if Factory.LIMITS.has(kind):
		text_at("%d/%d" % [factory.count_kind(kind),Factory.LIMITS[kind]],Vector2(68,49),17,INK)
	if Factory.RECIPES.has(kind):
		var recipe = Factory.RECIPES[kind]
		item_at(recipe[0],Vector2(139,42),0.65)
		arrow(Vector2(156,42),Vector2(179,42),MUTED)
		item_at(recipe[1],Vector2(196,42),0.65)
		var duration = maxi(1,int(ceil(recipe[2]*factory.work_multiplier)))
		if c.get("work",0) > 0: meter(Rect2(128,59,80,3),1.0-float(c.work)/duration,GOLD)
	else:
		var item: String = factory.diagnostic(hover).item
		if item != "": item_at(item,Vector2(162,42),0.7)
	symbol(factory.diagnostic(hover).code,Vector2(240,42),0.6)

func can_apply_blueprint() -> bool:
	return can_manage_layout()

func apply_blueprint(id: String) -> bool:
	if not can_apply_blueprint() or id not in history.unlocked or id not in Blueprints.IDS: return false
	var before = factory.layout()
	if not factory.restore(Blueprints.layout(id,factory.layout_version)): return false
	factory.undo_stack.append(before)
	if factory.undo_stack.size() > 50: factory.undo_stack.pop_front()
	menu.refresh()
	return true

func record_result() -> bool:
	var previous = history.unlocked.duplicate()
	if not history.unlock_for_clear(history_path,expedition.cleared): return false
	for id in history.unlocked:
		if id not in previous and id not in new_blueprints: new_blueprints.append(id)
	if expedition.phase not in ["won","lost","retreated"]: return true
	var previous_research = history.researched_blocks.duplicate()
	if not history.record(history_path,expedition.run_seed,expedition.phase,expedition.cleared,int(factory.manufactured)): return false
	factory.unlocked_blocks = RunState.Content.STARTING_BLOCKS.keys()+history.researched_blocks
	for id in history.researched_blocks:
		if id not in previous_research: new_blueprints.append(id)
	return true

func retreat_run():
	if quitting: return
	sound.stop_all()
	if not expedition.retreat(): return
	factory.layout_locked = true
	factory.combat_editing = false
	record_result()
	factory.running = false
	ensure_battle()
	battle_mode = true
	refresh_view()

func choice_models() -> Dictionary:
	return {"expedition":expedition,"factory":factory}

func choice_rect(index: int) -> Rect2:
	return choice_popup.option_rect(index)

func has_mount_space() -> bool:
	for id in Factory.AUXILIARY:
		if id not in factory.auxiliary_ids: return factory.inside(factory.install_position(id))
	return false

func can_claim_reward(id: String) -> bool:
	if id.begins_with("gear:"):
		if expedition.item_mode: return id.trim_prefix("gear:") in RunState.EQUIPMENT
		var gear = id.trim_prefix("gear:")
		return gear not in expedition.equipment and (not Factory.AUXILIARY.has(gear) or factory.inside(factory.install_position(gear)))
	if id.begins_with("block:"):
		var kind = id.trim_prefix("block:")
		return factory.inventory.get(kind,0) < Factory.LIMITS.get(kind,0)
	return id in RunState.REWARDS

func choose_run_option(index: int):
	if menu.visible: return
	if expedition.phase == "craft":
		if index >= 0 and index < 3: craft_equipment(choice_popup.craft_id(index))
	elif expedition.phase == "reward":
		if index < 0 or index >= expedition.reward_options.size(): return
		var reward: String = expedition.reward_options[index]
		if not can_claim_reward(reward): return
		if expedition.choose_reward(index):
			world.feedback_effect("reward",Vector3(0,4,0),1.3)
			if battlefield != null: battlefield.feedback_effect("reward",battlefield.player.position+Vector3(0,5,0),1.3)
			sound.play_effect("reward")
			if reward.begins_with("block:"):
				var kind = reward.trim_prefix("block:")
				factory.grant_blocks(kind,RunState.Content.block_bundle(kind))
			elif reward.begins_with("gear:"):
				var gear = reward.trim_prefix("gear:")
				if expedition.item_mode: loot_feed.push_item(expedition.gear_items.back())
				if not expedition.item_mode and Factory.AUXILIARY.has(gear): factory.install_auxiliary(gear)
				sync_equipment()
			match reward:
				"scrap_cache": factory.collect("scrap",24)
				"coal_cache": factory.collect("coal",18)
				"shell_cache":
					factory.ammo = mini(factory.ammo_capacity,factory.ammo+8)
					for id in factory.auxiliary_ids:
						var cell = factory.cells[factory.auxiliary_position(id)]
						for i in range(mini(2,factory.ammo_capacity-cell.items.size())): cell.items.append("shell")
			if battlefield != null: battlefield.hull = expedition.hull
			factory.work_multiplier = expedition.modifiers.work
			factory.ammo_capacity = expedition.modifiers.magazine
			factory.reserve_capacity = expedition.modifiers.get("cargo",100)
			if battlefield != null: battlefield.reload_multiplier = expedition.modifiers.get("reload",1.0)
			record_result()
		if expedition.phase == "prepare": prepare_next_sector()
	elif expedition.phase == "route":
		if expedition.choose_route(index):
			prepare_next_sector()
	refresh_view()

func prepare_next_sector():
	factory.loadout_locked = false
	new_blueprints.clear()
	last_paint = Vector2i(-1,-1)
	release_battle()
	started = false
	factory.layout_locked = false
	# Carried cargo also survives layout changes between battles.
	factory.combat_editing = true
	world.playback_only = false
	clear_movement()
	factory.running = false
	ensure_battle()
	battle_mode = false

func open_menu(title: bool = false):
	cancel_item_drag()
	if inventory_panel != null: inventory_panel.hide()
	dragging_auxiliary = ""
	clear_movement()
	if quitting: return
	sound.stop_all()
	menu_title = title
	menu_was_running = factory.running
	factory.running = false
	menu_status = ""
	menu.visible = true
	menu.show_home()
	world.placement_preview.visible = false
	menu.refresh()

func close_menu():
	menu.difficulty_popup.hide()
	menu.visible = false
	if not menu_title and expedition.phase == "travel": factory.running = menu_was_running
	menu_title = false

func save_checkpoint() -> bool:
	var recorded = record_result()
	var success = checkpoint.write_file(checkpoint_path,checkpoint.snapshot(self))
	success = success and recorded
	menu_status = "victory" if success else "defeat"
	if menu != null: menu.refresh()
	return success

func load_checkpoint() -> bool:
	var data = checkpoint.read_file(checkpoint_path)
	if data.is_empty(): data = checkpoint.read_file(checkpoint_path+".bak")
	if data.is_empty() or not checkpoint.apply(self,data):
		menu_status = "defeat"
		menu.refresh()
		return false
	new_blueprints.clear()
	record_result()
	menu_was_running = false
	menu_title = false
	menu.visible = false
	return true

func menu_action(index: int):
	if quitting: return
	match index:
		0: close_menu()
		1: load_checkpoint()
		2: save_checkpoint()
		3:
			ensure_battle()
			reset_battle()
			menu_was_running = false
			menu_title = false
			menu.visible = false
		4:
			if menu_title or save_checkpoint(): finish_quit()

func _notification(what: int):
	if quitting: return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_movement()
		cancel_item_drag()
		if inventory_panel != null: inventory_panel.cancel_pending_drag()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if menu_title or save_checkpoint():
			finish_quit()
		else:
			open_menu(false)
			menu_status = "defeat"
			menu.refresh()

func finish_quit():
	if quitting: return
	quitting = true
	factory.running = false
	sound.stop_all()
	if OS.has_feature("web"):
		# A browser tab cannot be closed by the game. Keep the saved run and
		# return to a fresh title scene without shutting down the WebAssembly engine.
		get_tree().reload_current_scene()
		return
	menu.hide()
	sound.queue_free()
	# Release playback nodes while the audio thread still runs, before engine shutdown.
	await get_tree().create_timer(0.08).timeout
	get_tree().quit()

func repair_state() -> Dictionary:
	var hull = battlefield.hull if battlefield != null else expedition.hull
	var cost = RunState.Services.repair_cost(factory,hull)
	var active = can_manage_layout() and hull > 0
	return {"visible":active and cost > 0 and menu != null and not menu.visible,"allowed":active and cost > 0 and factory.reserves.scrap >= cost,"cost":cost}

func repair_vehicle() -> bool:
	if menu.visible or not repair_state().allowed: return false
	var cost = int(repair_state().cost)
	factory.reserves.scrap -= cost
	factory.repair_line()
	expedition.hull = 100
	if battlefield != null: battlefield.hull = 100
	sync_equipment()
	field_actions.refresh()
	return true

func can_buy_shop(index: int) -> bool:
	if expedition.phase != "shop": return false
	var offers: Array = expedition.current.shop_offers
	if index < 0 or index >= offers.size() or expedition.current.shop_purchased[index]: return false
	var id: String = offers[index]
	if factory.reserves.scrap < RunState.Services.price(id): return false
	if id == "shell": return factory.ammo < factory.ammo_capacity
	return id == "coal" or can_claim_reward(id)

func shop_state() -> Dictionary:
	if expedition.phase != "shop": return {"visible":false}
	var allowed = []
	for i in range(expedition.current.shop_offers.size()): allowed.append(can_buy_shop(i))
	return {"visible":true,"offers":expedition.current.shop_offers,"purchased":expedition.current.shop_purchased,"allowed":allowed,"scrap":factory.reserves.scrap,"item_mode":expedition.item_mode}

func buy_shop_item(index: int) -> bool:
	if menu.visible or not can_buy_shop(index): return false
	var id: String = expedition.current.shop_offers[index]
	if id.begins_with("gear:"):
		var gear = id.trim_prefix("gear:")
		if expedition.item_mode:
			expedition.add_item({"kind":gear,"rarity":"uncommon"})
			loot_feed.push_item(expedition.gear_items.back())
		else:
			if Factory.AUXILIARY.has(gear) and not factory.install_auxiliary(gear): return false
			if gear not in expedition.recipes: expedition.recipes.append(gear)
			expedition.equipment.append(gear)
	elif id == "coal": factory.collect("coal",RunState.Services.COAL_AMOUNT)
	elif id == "shell": factory.ammo = mini(factory.ammo_capacity,factory.ammo+RunState.Services.SHELL_AMOUNT)
	factory.reserves.scrap -= RunState.Services.price(id)
	expedition.current.shop_purchased[index] = true
	sync_equipment()
	shop_panel.refresh()
	return true

func leave_shop():
	if menu.visible or not expedition.finish_shopping(): return
	if expedition.phase == "prepare": prepare_next_sector()
	record_result()
	refresh_view()

func receive_item(item: Dictionary):
	expedition.add_item(item)
	loot_feed.push_item(item)
	factory.message = Inventory.Catalog.RARITIES[item.rarity].name+"："+RunState.EQUIPMENT[item.kind].name+"を回収（Iで一覧・解体）"

func toggle_inventory():
	if not expedition.item_mode or menu.visible: return
	cancel_item_drag()
	inventory_panel.visible = not inventory_panel.visible
	inventory_panel.refresh()

func begin_item_drag(uid: int):
	suppress_item_paint = true
	if menu.visible or not Inventory.editable(expedition,factory):
		factory.message = "出撃後の装備変更はできません。次の出撃準備で変更できます。"
		return
	var item = Inventory.find_item(expedition,uid)
	if item.is_empty(): return
	if item.position == Inventory.STOWED and item.kind in expedition.equipment:
		factory.message = "同型の装備は1基までです。先に取り外してください。"
		return
	battle_mode = false
	if world.roof_closed: world.toggle_roof()
	refresh_view()
	inventory_panel.hide()
	dragging_item = uid
	last_paint = Vector2i(-1,-1)

func cancel_item_drag():
	dragging_item = -1
	if is_instance_valid(world): world.preview_equipment(factory,{},Vector2i(-1,-1))

func place_item(uid: int, at: Vector2i) -> bool:
	if menu.visible or battle_mode or world.roof_closed or not Inventory.place(expedition,factory,uid,at): return false
	sync_equipment()
	world.rendered_layout = ""
	return true

func stow_item(uid: int) -> bool:
	if menu.visible or not Inventory.stow(expedition,factory,uid): return false
	sync_equipment()
	world.rendered_layout = ""
	inventory_panel.refresh()
	return true

func dismantle_item(uid: int) -> bool:
	var before = factory.reserves.duplicate()
	if menu.visible or not Inventory.dismantle(expedition,factory,uid): return false
	for raw in before: logistics.add_receipt(raw,factory.reserves[raw]-before[raw])
	factory.message = "装備を解体してスクラップと石炭を回収しました。"
	inventory_panel.refresh()
	return true

func inventory_state() -> Dictionary:
	return {"enabled":expedition.item_mode,"menu_visible":menu != null and menu.visible,"items":expedition.gear_items,
		"editable":Inventory.editable(expedition,factory),"phase":expedition.phase,"reserves":factory.reserves}
