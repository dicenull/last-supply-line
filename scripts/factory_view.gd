extends Node2D
const Factory = preload("res://scripts/factory.gd")
const BG = Color("171c18")
const PANEL = Color("2d342b")
const INK = Color("f2eddf")
const MUTED = Color("bdc0aa")
const GOLD = Color("e6bd73")
const MINT = Color("bfcca4")
const BLUE = Color("afc2ba")
const SURFACE = Color("20261f")
const EDGE = Color("68705a")
const DANGER = Color("f29c84")
const HEADER_RECT = Rect2(16,12,1408,60)
const WORLD_RECT = Rect2(16,84,1408,752)
const FOOTER_RECT = Rect2(16,848,1408,80)
const CHOICE_FOOTER_RECT = Rect2(16,800,1408,128)
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
var menu_title = true
var menu_status = ""
var menu_was_running = false
const RunState = preload("res://scripts/run_state.gd")
var expedition = RunState.new(int(Time.get_unix_time_from_system()*1000000))
var choice_buttons: Array = []
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
var factory = Factory.new()
var font: SystemFont
var selected = "belt"
var direction = 0
var hover = Vector2i(-1,-1)
var last_paint = Vector2i(-1,-1)
var start_button: Button
var tool_buttons: Dictionary = {}
var shot_glow = 0.0
var previous_shots = 0
var icon_buttons: Array = []
var notice_time = 0.0
var notice_bad = false
var last_message = ""

func _ready():
	get_window().min_size = Vector2i(960,628)
	history.load_file(history_path)
	get_tree().auto_accept_quit = false
	factory.finite_resources = true
	factory.auto_fire = false
	factory.example()
	factory.undo_stack.clear()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Helvetica Neue","Hiragino Sans","sans-serif"])
	font.font_weight = 600
	var container = SubViewportContainer.new()
	factory_container = container
	container.position = WORLD_RECT.position
	container.size = WORLD_RECT.size
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(WORLD_RECT.size)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	world = TankWorld.new()
	viewport.add_child(world)
	start_button = icon_button("play",Rect2(944,862,288,52),toggle_running,"Space")
	icon_button("battle",Rect2(740,862,180,52),toggle_battle,"B")
	icon_button("menu",Rect2(1274,862,134,52),func(): open_menu(false),"Esc")
	battle_retry = add_button("",Rect2(614,862,212,52),reset_battle)
	battle_retry.visible = false
	for i in range(3):
		var index = i
		choice_buttons.append(add_button("",choice_rect(i),func(): choose_run_option(index)))
		choice_buttons.back().visible = false
	var kinds = ["belt","furnace","press","splitter","depot","erase","refinery"]
	for i in kinds.size():
		var kind: String = kinds[i]
		tool_buttons[kind] = icon_button(kind,Rect2(32+i*82,862,72,52),func(): selected = kind,str(i+1))
	icon_button("rotate",Rect2(610,862,74,52),func(): direction = (direction+1)%4,"R")
	var logistics_layer = CanvasLayer.new()
	logistics_layer.layer = 2
	add_child(logistics_layer)
	logistics = preload("res://scripts/logistics_overlay.gd").new()
	logistics.game = self
	logistics_layer.add_child(logistics)
	sound = preload("res://scripts/game_audio.gd").new()
	sound.game = self
	sound.enabled = audio_enabled
	sound.settings_path = audio_settings_path
	add_child(sound)
	var menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu = RunMenu.new()
	menu.game = self
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
		world.playback_only = true
		battle_mode = true
	factory.running = not factory.running
	if not factory.running: sound.stop_all()
	refresh_view()

func toggle_battle():
	ensure_battle()
	battle_mode = not battle_mode
	refresh_view()

func ensure_battle():
	if battlefield == null:
		battle_container = SubViewportContainer.new()
		battle_container.position = WORLD_RECT.position
		battle_container.size = WORLD_RECT.size
		battle_container.stretch = true
		battle_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(battle_container)
		var battle_viewport = SubViewport.new()
		battle_viewport.size = Vector2i(WORLD_RECT.size)
		battle_viewport.own_world_3d = true
		battle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		battle_viewport.msaa_3d = Viewport.MSAA_2X
		battle_container.add_child(battle_viewport)
		battlefield = BattleWorld.new()
		battlefield.sector_config = expedition.current.duplicate(true)
		battlefield.hull = expedition.hull
		battlefield.fuel_multiplier = expedition.modifiers.fuel
		battlefield.reload_multiplier = expedition.modifiers.get("reload",1.0)
		battle_viewport.add_child(battlefield)

func footer_rect() -> Rect2:
	return CHOICE_FOOTER_RECT if expedition.phase in ["reward","route"] else FOOTER_RECT

func refresh_view():
	var scene_size = Vector2(WORLD_RECT.size.x,footer_rect().position.y-12-WORLD_RECT.position.y)
	factory_container.size = scene_size
	if battle_container != null:
		battle_container.size = scene_size
	factory_container.visible = not battle_mode
	if battle_container != null: battle_container.visible = battle_mode
	hover = Vector2i(-1,-1)
	for entry in icon_buttons:
		entry.button.visible = entry.icon == "menu" or ((expedition.phase in ["prepare","travel"]) and ((not battle_mode and (not started or live_control(entry.icon,entry.rect))) or entry.icon in ["battle","play"]))
	queue_redraw()

func reset_battle():
	if quitting: return
	sound.stop_all()
	if battlefield == null: return
	new_blueprints.clear()
	battle_container.queue_free()
	battlefield = null
	battle_mode = false
	started = false
	world.playback_only = false
	expedition = RunState.new(int(Time.get_unix_time_from_system()*1000000))
	factory.work_multiplier = 1.0
	factory.ammo_capacity = 12
	factory.reserve_capacity = 100
	factory.reserves = {"scrap":48,"coal":32}
	factory.collected = {"scrap":0,"coal":0}
	factory.reset_trial()
	ensure_battle()
	refresh_view()

func live_control(icon: String, _rect: Rect2) -> bool:
	return icon in ["belt","furnace","press","splitter","depot","refinery","erase","rotate","play","battle","menu"]

func can_manage_layout() -> bool:
	return not started and expedition.phase == "prepare"

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
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	if border.a > 0:
		s.set_border_width_all(2)
		s.border_color = border
	return s

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
	file.store_string(JSON.stringify({"version":1,"cells":factory.layout()}))
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
	if not data is Dictionary or data.get("version") != 1 or not data.get("cells") is Array:
		factory.message = "保存データの形式が正しくありません。"
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
	for kind in tool_buttons:
		tool_buttons[kind].add_theme_color_override("font_color",GOLD if selected == kind else MUTED)
	if started: battlefield.tick_battle(factory,minf(delta,0.1))
	if started and battlefield.result != 0 and expedition.phase == "travel":
		expedition.finish_sector(battlefield.result == 1,battlefield.hull)
		record_result()
		battle_mode = true
		refresh_view()
	if not battle_mode:
		world.sync(factory,hover,selected,direction,delta)
		if started:
			world.turret.rotation.y = battlefield.turret.rotation.y
			world.barrel.position.x = battlefield.barrel.position.x
			world.muzzle.visible = battlefield.muzzle.visible
	sound.sync()
	logistics.sync(delta)
	battle_retry.visible = battle_mode and expedition.phase in ["won","lost","retreated"]
	for i in range(choice_buttons.size()):
		choice_buttons[i].position = choice_rect(i).position
		choice_buttons[i].size = choice_rect(i).size
		choice_buttons[i].visible = expedition.phase == "reward" or (expedition.phase == "route" and i < 2)
	queue_redraw()

func cell_at(pos: Vector2) -> Vector2i:
	if battle_mode: return Vector2i(-1,-1)
	var canvas_pos = get_canvas_transform().affine_inverse()*pos
	if not WORLD_RECT.has_point(canvas_pos) or world == null: return Vector2i(-1,-1)
	return world.screen_cell(canvas_pos-WORLD_RECT.position)

func paint(p: Vector2i, erase: bool):
	if expedition.phase not in ["prepare","travel"]: return
	if p == last_paint: return
	last_paint = p
	var was_running = factory.running
	factory.edit(p,"erase" if erase else selected,direction)
	if started: factory.running = was_running

func _input(event):
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		hover = cell_at(event.position)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
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
				world.yaw -= 0.12
				world.update_camera()
			KEY_RIGHT:
				world.yaw += 0.12
				world.update_camera()
			KEY_UP:
				world.pitch = clampf(world.pitch+0.08,0.65,1.35)
				world.update_camera()
			KEY_DOWN:
				world.pitch = clampf(world.pitch-0.08,0.65,1.35)
				world.update_camera()
			KEY_R: direction = (direction+1)%4
			KEY_Q:
				var was_running = factory.running
				factory.rotate(hover)
				if started: factory.running = was_running
			KEY_Z:
				if not started: factory.undo()
			KEY_1: selected = "belt"
			KEY_2: selected = "furnace"
			KEY_3: selected = "press"
			KEY_4: selected = "splitter"
			KEY_5: selected = "depot"
			KEY_6: selected = "erase"
			KEY_7: selected = "refinery"
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			world.yaw -= event.relative.x*0.007
			world.pitch = clampf(world.pitch+event.relative.y*0.005,0.65,1.35)
			world.update_camera()
		hover = cell_at(event.position)
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT: paint(hover,false)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT: paint(hover,true)
	if event is InputEventMouseButton:
		if event.pressed and WORLD_RECT.has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			world.zoom = clampf(world.zoom+(-0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8),11,24)
			world.update_camera()
		hover = cell_at(event.position)
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			last_paint = Vector2i(-1,-1)
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
	var primary = entry.icon == "play"
	panel(rect,Color("51563b") if picked else SURFACE,GOLD if picked or primary else EDGE)
	if picked: panel(Rect2(rect.position+Vector2(12,rect.size.y-5),Vector2(rect.size.x-24,3)),GOLD)
	var icon = entry.icon
	if icon == "play": icon = "pause" if factory.running else "play"
	if icon == "battle": icon = "example" if battle_mode else "battle"
	if icon == "roof": icon = "roof" if world.roof_closed else "roof_open"
	var center = rect.get_center()
	if entry.key != "": center.x += 10
	symbol(icon,center,minf(1.05 if entry.icon in tool_buttons else 0.82,(rect.size.y-4)/44.0))
	if entry.key != "": keycap(entry.key,rect.position+Vector2(5,5))

func _draw():
	draw_rect(Rect2(0,0,1440,940),BG)
	draw_header()
	metal_panel(footer_rect())
	for entry in icon_buttons:
		if entry.button.visible: draw_control(entry)
	if battle_retry.visible:
		symbol("reset",battle_retry.get_rect().get_center()+Vector2(12,0),1.0)
		keycap("R",battle_retry.position+Vector2(12,12))
	draw_expedition()

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
	return "%d/%d" % [amount,capacity]

func draw_header():
	metal_panel(HEADER_RECT)
	if not battle_mode and factory.cells.has(hover):
		draw_inspector()
	else:
		if not new_blueprints.is_empty() and expedition.phase in ["reward","route","won"]:
			symbol("example",Vector2(48,42),0.7)
			text_at("+"+str(new_blueprints.size()),Vector2(73,49),20,GOLD)
		elif expedition.phase in ["won","lost","retreated"]:
			symbol("victory" if expedition.phase == "won" else "retreat" if expedition.phase == "retreated" else "defeat",Vector2(48,42),0.75)
		else: text_at("M.F.V. 03",Vector2(32,49),19,INK)
		text_at("%d/5" % expedition.sector,Vector2(157,49),19,MUTED)
		symbol(expedition.current.get("terrain","road"),Vector2(218,42),0.55)
		symbol(expedition.current.get("formation","patrol"),Vector2(250,42),0.55)
	var hull = battlefield.hull if battlefield != null else expedition.hull
	header_stat(Rect2(274,22,100,40),"shield",str(hull),DANGER if hull <= 25 else GOLD,hull/100.0)
	header_stat(Rect2(384,22,128,40),"shell",stock_text("shell",factory.ammo,factory.ammo_capacity),DANGER if factory.ammo == 0 else INK,float(factory.ammo)/factory.ammo_capacity)
	header_stat(Rect2(522,22,138,40),"fuel","%.1f/12" % factory.fuel,DANGER if factory.fuel < 0.01 else INK,factory.fuel/12.0)
	for i in range(2):
		var raw = "scrap" if i == 0 else "coal"
		header_stat(Rect2(670+i*142,22,132,40),raw,stock_text(raw,factory.reserves[raw],factory.reserve_capacity),DANGER if factory.reserves[raw] == 0 else GOLD if factory.reserves[raw] == factory.reserve_capacity else INK)
	header_stat(Rect2(954,22,64,40),"steel",str(material_counts().steel))
	var distance = battlefield.distance if battlefield != null else 0.0
	var length = float(expedition.current.length)
	header_stat(Rect2(1028,22,158,40),"move","%.0f/%.0f" % [minf(distance,length),length],INK,distance/length)
	header_stat(Rect2(1196,22,92,40),"battle","%d/6" % (battlefield.kills if battlefield != null else 0))
	inset(Rect2(1298,22,110,40))
	text_at("%.1f m/s" % (battlefield.speed if battlefield != null else 0.0),Vector2(1308,48),18,MUTED)

func draw_inspector():
	var c: Dictionary = factory.cells[hover]
	var kind: String = c.kind
	symbol(kind,Vector2(47,42),0.65)
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
	return expedition.phase == "prepare" and expedition.sector == 1 and not started

func apply_blueprint(id: String) -> bool:
	if not can_apply_blueprint() or id not in history.unlocked or id not in Blueprints.IDS: return false
	factory.remember()
	if not factory.restore(Blueprints.layout(id)): return false
	menu.refresh()
	return true

func record_result() -> bool:
	var previous = history.unlocked.duplicate()
	if not history.unlock_for_clear(history_path,expedition.cleared): return false
	for id in history.unlocked:
		if id not in previous and id not in new_blueprints: new_blueprints.append(id)
	if expedition.phase not in ["won","lost","retreated"]: return true
	return history.record(history_path,expedition.run_seed,expedition.phase,expedition.cleared,int(factory.manufactured))

func retreat_run():
	if quitting: return
	sound.stop_all()
	if not expedition.retreat(): return
	record_result()
	factory.running = false
	ensure_battle()
	battle_mode = true
	refresh_view()

func choice_rect(index: int) -> Rect2:
	return Rect2(32+index*(620 if expedition.phase == "route" else 412),812,608 if expedition.phase == "route" else 400,104)

func choose_run_option(index: int):
	if expedition.phase == "reward":
		if expedition.choose_reward(index):
			factory.work_multiplier = expedition.modifiers.work
			factory.ammo_capacity = expedition.modifiers.magazine
			factory.reserve_capacity = expedition.modifiers.get("cargo",100)
			if battlefield != null: battlefield.reload_multiplier = expedition.modifiers.get("reload",1.0)
	elif expedition.phase == "route":
		if expedition.choose_route(index):
			new_blueprints.clear()
			battle_container.queue_free()
			battlefield = null
			started = false
			factory.running = false
			ensure_battle()
			battle_mode = false
	refresh_view()

func draw_expedition():
	if expedition.phase not in ["reward","route"]: return
	var count = 3 if expedition.phase == "reward" else 2
	for i in range(count):
		var rect = choice_rect(i)
		var at = rect.position
		panel(rect,SURFACE,EDGE)
		panel(Rect2(at+Vector2(0,12),Vector2(4,88)),GOLD)
		if expedition.phase == "reward":
			var reward = expedition.reward_options[i]
			symbol({"production":"press","economy":"fuel","magazine":"depot","autoload":"autoload","cargo":"cargo"}[reward],at+Vector2(65,54),1.4)
			text_at({"production":"×0.85","economy":"×0.80","magazine":"+4","autoload":"×0.80","cargo":"+25"}[reward],at+Vector2(130,65),29,GOLD)
		else:
			for divider in [93,218,385]:
				draw_line(at+Vector2(divider,18),at+Vector2(divider,94),EDGE,1)
			var route: Dictionary = expedition.route_options[i]
			symbol({"scrapyard":"scrap","coalfield":"coal","arsenal":"gun"}[route.kind],at+Vector2(45,44),1.2)
			if route.shells > 0: text_at("+"+str(route.shells),at+Vector2(28,92),19,GOLD)
			item_at("scrap",at+Vector2(125,35),0.7)
			text_at(str(route.scrap),at+Vector2(150,43),22,INK)
			item_at("coal",at+Vector2(125,78),0.7)
			text_at(str(route.coal),at+Vector2(150,86),22,INK)
			symbol(route.get("formation","patrol"),at+Vector2(260,35),0.9)
			text_at(str(RunState.total_health(route)),at+Vector2(290,43),22,INK)
			symbol("move",at+Vector2(260,78),0.65)
			text_at(str(int(route.length)),at+Vector2(290,86),22,INK)
			var surface = RunState.condition(route)
			symbol(route.get("terrain","road"),at+Vector2(420,35),0.9)
			text_at("%.1f m/s" % surface.speed,at+Vector2(455,43),22,INK)
			symbol("fuel",at+Vector2(420,78),0.7)
			text_at("×%.2f" % surface.fuel,at+Vector2(455,86),22,INK)

func open_menu(title: bool = false):
	if quitting: return
	sound.stop_all()
	menu_title = title
	menu_was_running = factory.running
	factory.running = false
	menu_status = ""
	menu.visible = true
	menu.refresh()

func close_menu():
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
	menu.hide()
	sound.queue_free()
	# Release playback nodes while the audio thread still runs, before engine shutdown.
	await get_tree().create_timer(0.08).timeout
	get_tree().quit()
