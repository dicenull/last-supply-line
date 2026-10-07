extends Node2D
const Factory = preload("res://scripts/factory.gd")
const BG = Color("252820")
const PANEL = Color("414437")
const INK = Color("e4d7b2")
const MUTED = Color("a7a084")
const GOLD = Color("cfad66")
const MINT = Color("c1c19a")
const BLUE = Color("a7b6aa")
const WORLD_RECT = Rect2(0,88,1120,678)
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
var show_start_menu = true
var menu
var menu_title = true
var menu_status = ""
var menu_was_running = false
const RunState = preload("res://scripts/run_state.gd")
var expedition = RunState.new(int(Time.get_unix_time_from_system()*1000000))
var choice_buttons: Array = []
var retreat_button: Button
var battle_retry: Button
const PixelIcons = preload("res://scripts/pixel_icons.gd")
var pixel_icons = PixelIcons.new()
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
	history.load_file(history_path)
	get_tree().auto_accept_quit = false
	factory.finite_resources = true
	factory.auto_fire = false
	factory.example()
	factory.undo_stack.clear()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next Condensed","Helvetica Neue","Hiragino Sans","sans-serif"])
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
	start_button = icon_button("play",Rect2(1230,25,166,42),toggle_running,"Space")
	icon_button("roof",Rect2(1070,25,130,42),func(): world.toggle_roof(),"Tab")
	icon_button("battle",Rect2(935,25,110,42),toggle_battle,"B")
	battle_retry = add_button("",Rect2(730,807,80,78),reset_battle)
	battle_retry.visible = false
	retreat_button = add_button("",Rect2(865,25,52,42),retreat_run)
	for i in range(3):
		var index = i
		choice_buttons.append(add_button("",Rect2(55+i*460,796,420,112),func(): choose_run_option(index)))
		choice_buttons.back().visible = false
	var kinds = ["belt","furnace","press","splitter","depot","erase"]
	for i in kinds.size():
		var kind: String = kinds[i]
		tool_buttons[kind] = icon_button(kind,Rect2(40+i*100,793,88,62),func(): selected = kind,str(i+1))
	icon_button("rotate",Rect2(665,878,88,38),func(): direction = (direction+1)%4,"R")
	tool_buttons["refinery"] = icon_button("refinery",Rect2(665,793,88,62),func(): selected = "refinery","7")
	icon_button("reset",Rect2(777,793,88,62),func(): factory.reset_trial())
	icon_button("example",Rect2(40,878,108,38),func(): factory.example())
	icon_button("save",Rect2(164,878,108,38),save_layout)
	icon_button("load",Rect2(288,878,108,38),load_layout)
	icon_button("erase",Rect2(412,878,108,38),func(): factory.clear_layout())
	icon_button("undo",Rect2(536,878,108,38),func(): factory.undo(),"Z")
	icon_button("camera",Rect2(777,878,88,38),reset_camera)
	for i in range(3):
		var target = [30,60,90][i]
		icon_button("rate",Rect2(1147+i*84,691,76,38),func(): factory.rate = target,str(target))
	var menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu = RunMenu.new()
	menu.game = self
	menu_layer.add_child(menu)
	if show_start_menu: open_menu(true)

func toggle_running():
	if expedition.phase not in ["prepare","travel"]: return
	ensure_battle()
	if battlefield.result != 0: return
	if not started:
		expedition.start_sector()
		started = true
		world.playback_only = true
		battle_mode = true
	factory.running = not factory.running
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
		battle_viewport.add_child(battlefield)

func refresh_view():
	factory_container.visible = not battle_mode
	if battle_container != null: battle_container.visible = battle_mode
	hover = Vector2i(-1,-1)
	for entry in icon_buttons:
		entry.button.visible = (expedition.phase in ["prepare","travel"]) and ((not battle_mode and (not started or live_control(entry.icon,entry.rect))) or entry.icon in ["battle","play"])
	queue_redraw()

func reset_battle():
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
	factory.reserves = {"scrap":48,"coal":32}
	factory.collected = {"scrap":0,"coal":0}
	factory.reset_trial()
	ensure_battle()
	refresh_view()

func live_control(icon: String, rect: Rect2) -> bool:
	# Whole-layout actions reset simulation; local construction does not.
	if icon == "erase" and rect.position.y > 850: return false
	return icon in ["belt","furnace","press","splitter","depot","refinery","erase","rotate","rate","play","battle","roof","camera","save"]

func reset_camera():
	world.yaw = 0.65
	world.pitch = 0.92
	world.zoom = 17.8
	world.update_camera()

func icon_button(icon: String, rect: Rect2, action: Callable, keycap: String = "") -> Button:
	var b = add_button("",rect,func():
		if started and not live_control(icon,rect): return
		action.call())
	b.add_theme_stylebox_override("normal",style(Color.TRANSPARENT,MUTED.darkened(0.4)))
	b.add_theme_stylebox_override("hover",style(Color(1,1,1,0.06),GOLD))
	b.add_theme_stylebox_override("pressed",style(Color(1,0.8,0.4,0.12),GOLD))
	icon_buttons.append({"icon":icon,"rect":rect,"key":keycap,"button":b})
	return b

func style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(2)
	if border.a > 0:
		s.set_border_width_all(1)
		s.border_color = border
	return s

func add_button(title: String, rect: Rect2, action: Callable, color: Color = MUTED) -> Button:
	var b = Button.new()
	b.text = title
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",15)
	b.add_theme_color_override("font_color",INK)
	b.add_theme_stylebox_override("normal",style(Color.TRANSPARENT,color.darkened(0.35)))
	b.add_theme_stylebox_override("hover",style(Color(1,1,1,0.06),color))
	b.pressed.connect(action)
	add_child(b)
	return b

func save_layout():
	var file = FileAccess.open("user://ammo_layout.json",FileAccess.WRITE)
	if file == null:
		factory.message = "配置を保存できませんでした。"
		return
	file.store_string(JSON.stringify({"version":1,"cells":factory.layout()}))
	factory.message = "配置を保存しました。物資や計測値は保存しません。"

func load_layout():
	if started: return
	if not FileAccess.file_exists("user://ammo_layout.json"):
		factory.message = "保存済みの配置がありません。"
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://ammo_layout.json"))
	if not data is Dictionary or data.get("version") != 1 or not data.get("cells") is Array:
		factory.message = "保存データの形式が正しくありません。"
		return
	var before = factory.layout()
	if factory.restore(data.cells):
		factory.undo_stack.append(before)
		factory.message = "配置を読み込みました。試運転で流れを確認してください。"
	else: factory.message = "保存データに配置できない設備があります。現在の配置を維持します。"

func _process(delta):
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
	battle_retry.visible = battle_mode and expedition.phase in ["won","lost","retreated"]
	retreat_button.visible = expedition.phase in ["prepare","travel"]
	for i in range(choice_buttons.size()):
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
	draw_rect(Rect2(rect.position+Vector2(3,4),rect.size),Color("111610"))
	panel(rect,PANEL,Color("77765a"))
	draw_line(rect.position+Vector2(2,2),rect.position+Vector2(rect.size.x-2,2),Color("969073"),1)
	for offset in [Vector2(8,8),Vector2(rect.size.x-8,8),Vector2(8,rect.size.y-8),rect.size-Vector2(8,8)]:
		var at = rect.position+offset
		draw_circle(at+Vector2(1,1),3.5,Color("20251d"))
		draw_circle(at,3,Color("9d9575"))
		draw_line(at-Vector2(1.5,1.5),at+Vector2(1.5,1.5),Color("444737"),1)

func _draw():
	draw_rect(Rect2(0,0,1440,940),BG)
	metal_panel(Rect2(24,14,1392,66))
	text_at("M.F.V.  03",Vector2(55,57),29,GOLD)
	text_at("1918",Vector2(258,56),18,MUTED)
	var counts = material_counts()
	for i in range(5):
		var item: String = ["scrap","steel","shell","coal","fuel"][i]
		item_at(item,Vector2(360+i*113,47),1.1)
		text_at(str(counts[item]),Vector2(387+i*113,57),26,INK)
	if battle_mode:
		draw_battle()
		draw_expedition()
		return
	metal_panel(Rect2(1130,99,286,658))
	instrument_panel()
	metal_panel(Rect2(24,776,1392,154))
	for entry in icon_buttons:
		if not entry.button.visible: continue
		var rect: Rect2 = entry.rect
		var picked = selected == entry.icon or (entry.icon == "rate" and str(factory.rate) == entry.key) or (entry.icon == "roof" and world.roof_closed)
		panel(rect,Color("69664b") if picked else Color("33392d"),GOLD if picked else Color("77765a"))
		if entry.icon == "rate":
			text_at(entry.key,rect.position+Vector2(24,26),20,GOLD if picked else INK)
		else:
			symbol(("pause" if factory.running else "play") if entry.icon == "play" else entry.icon,rect.get_center(),1.30 if entry.icon in tool_buttons else 0.83,GOLD if picked else MINT)
			if entry.key != "": text_at(entry.key,rect.position+Vector2(7,15),11,MUTED)
	# Engraved recipe pictograms on the lower instrument panel.
	var points = [Vector2(939,820),Vector2(1040,820),Vector2(1141,820),Vector2(1242,820),Vector2(1343,820)]
	item_at("scrap",points[0],1.05)
	symbol("furnace",points[1],0.85)
	item_at("steel",points[2],1.05)
	symbol("press",points[3],0.85)
	item_at("shell",points[4],1.05)
	for i in range(4): arrow(points[i]+Vector2(30,0),points[i+1]-Vector2(30,0),MUTED)
	item_at("coal",Vector2(939,896),1.05)
	symbol("refinery",Vector2(1141,896),0.85)
	item_at("fuel",Vector2(1343,896),1.05)
	arrow(Vector2(975,896),Vector2(1100,896),MUTED)
	arrow(Vector2(1180,896),Vector2(1305,896),MUTED)
	if notice_time > 0:
		var color = Color("cc7a56") if notice_bad else MINT
		draw_circle(Vector2(1380,900),10,color,false,2)
		if notice_bad:
			draw_line(Vector2(1375,895),Vector2(1385,905),color,2)
			draw_line(Vector2(1385,895),Vector2(1375,905),color,2)
		else: draw_polyline(PackedVector2Array([Vector2(1374,900),Vector2(1378,904),Vector2(1387,893)]),color,2)

	draw_expedition()

func instrument_panel():
	var center = Vector2(1273,233)
	draw_circle(center+Vector2(2,3),101,Color("252b20"))
	draw_circle(center,99,Color("9c8755"))
	draw_circle(center,92,Color("dbd0a5"))
	draw_circle(center,86,Color("242e23"),false,2)
	for i in range(19):
		var angle = PI*0.75+i/18.0*PI*1.5
		var d = Vector2(cos(angle),sin(angle))
		draw_line(center+d*(70 if i%3 == 0 else 77),center+d*83,Color("4c4b37"),2 if i%3 == 0 else 1)
	var angle = PI*0.75+clampf(factory.recent_rate()/90.0,0,1)*PI*1.5
	var d = Vector2(cos(angle),sin(angle))
	draw_line(center-d*14,center+d*66,Color("904b32"),3)
	draw_circle(center,7,Color("6e694a"))
	text_at("%.0f" % factory.recent_rate(),Vector2(1249,291),26,Color("393f2f"))
	item_at("shell",Vector2(1273,176),0.55)
	text_at("min⁻¹",Vector2(1255,314),11,Color("615d43"))
	symbol("gun",Vector2(1171,364),0.55)
	text_at(str(factory.availability())+"%",Vector2(1205,372),22,MINT)
	symbol("clock",Vector2(1302,364),0.48)
	text_at("%.0f" % factory.elapsed,Vector2(1331,372),20,MUTED)
	symbol("press",Vector2(1171,418),0.55)
	text_at(str(factory.manufactured),Vector2(1205,426),22,GOLD)
	symbol("gun",Vector2(1302,418),0.55)
	text_at(str(factory.shots),Vector2(1331,426),20,MINT)
	for i in range(factory.ammo_capacity):
		var at = Vector2(1161+(i%8)*28,470+int(i/8)*18)
		draw_rect(Rect2(at-Vector2(12,7),Vector2(24,14)),Color("282f24"))
		if i < factory.ammo: item_at("shell",at,0.7)
	if factory.cells.has(hover):
		var c: Dictionary = factory.cells[hover]
		symbol(c.kind,Vector2(1175,554),0.7)
		if Factory.RECIPES.has(c.kind):
			var recipe = Factory.RECIPES[c.kind]
			item_at(recipe[0],Vector2(1240,554),0.8)
			arrow(Vector2(1268,554),Vector2(1312,554),MUTED)
			item_at(recipe[1],Vector2(1345,554),0.8)
			draw_rect(Rect2(1160,584,224,4),Color("242b20"))
			if c.work > 0: draw_rect(Rect2(1160,584,224*(1-float(c.work)/recipe[2]),4),GOLD)
		elif not c.items.is_empty():
			item_at(c.items[0],Vector2(1250,554),0.9)
			text_at("×%d" % c.items.size(),Vector2(1300,563),21,INK)
	else:
		symbol("source",Vector2(1175,554),0.65)
		arrow(Vector2(1210,554),Vector2(1260,554),MUTED)
		symbol("gun",Vector2(1320,554),0.65)
	for i in range(3):
		var kind: String = ["furnace","press","depot"][i]
		symbol(kind,Vector2(1172+i*85,634),0.52)
		text_at("%d/%d" % [factory.count_kind(kind),Factory.LIMITS[kind]],Vector2(1158+i*85,668),16,MUTED)

func draw_battle():
	metal_panel(Rect2(1130,99,286,658))
	metal_panel(Rect2(24,776,1392,154))
	for entry in icon_buttons:
		if not entry.button.visible: continue
		panel(entry.rect,PANEL,GOLD)
		symbol(("example" if battle_mode else "camera") if entry.icon == "battle" else ("roof_open" if not world.roof_closed else "roof") if entry.icon == "roof" else ("pause" if factory.running else "play"),entry.rect.get_center(),0.85)
		text_at(entry.key,entry.rect.position+Vector2(7,15),11,MUTED)
	symbol("shield",Vector2(1200,169),1.5)
	text_at(str(battlefield.hull),Vector2(1280,182),32,INK)
	panel(Rect2(1160,220,224,16),BG)
	panel(Rect2(1160,220,224*battlefield.hull/100.0,16),GOLD)
	symbol("battle",Vector2(1200,302),1.3)
	text_at("%d / %d" % [battlefield.kills,battlefield.total],Vector2(1260,314),26,INK)
	item_at("shell",Vector2(1200,415),1.5)
	text_at(str(factory.ammo),Vector2(1280,426),32,INK)
	for i in range(factory.ammo_capacity):
		var pos = Vector2(1175+(i%8)*28,476+int(i/8)*18)
		panel(Rect2(pos-Vector2(12,7),Vector2(24,14)),BG)
		if i < factory.ammo: item_at("shell",pos,0.6)
	symbol("fuel",Vector2(1190,572),0.9)
	text_at("%.1f" % factory.fuel,Vector2(1270,584),26,INK)
	symbol("move",Vector2(1185,640),0.7)
	text_at("%.0f / %.0f" % [minf(battlefield.route_length,battlefield.distance),battlefield.route_length],Vector2(1220,647),20,INK)
	panel(Rect2(1160,674,224,9),BG)
	panel(Rect2(1160,674,224*minf(1,battlefield.distance/battlefield.route_length),9),GOLD)
	text_at("%.1f m/s" % battlefield.speed,Vector2(1230,721),19,MUTED)
	if expedition.phase in ["won","lost","retreated"]:
		symbol("victory" if expedition.phase == "won" else "retreat" if expedition.phase == "retreated" else "defeat",Vector2(650,846),1.7)
		text_at("#%s" % expedition.run_seed,Vector2(70,829),20,MUTED)
		symbol("press",Vector2(90,875),0.8)
		text_at(str(factory.manufactured),Vector2(125,882),24,INK)
		symbol("reset",Vector2(770,842),1.0)
		text_at("R",Vector2(765,883),16,GOLD)
	else:
		for i in range(battlefield.total):
			var pos = Vector2(180+i*205,846)
			symbol("gun",pos,1.2)
			for pip in range(battlefield.enemies[i].max_hp):
				panel(Rect2(pos+Vector2(-29+pip*21,40),Vector2(16,8)),GOLD if pip < battlefield.enemies[i].hp else BG)

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
	if not expedition.retreat(): return
	record_result()
	factory.running = false
	ensure_battle()
	battle_mode = true
	refresh_view()

func choose_run_option(index: int):
	if expedition.phase == "reward":
		if expedition.choose_reward(index):
			factory.work_multiplier = expedition.modifiers.work
			factory.ammo_capacity = expedition.modifiers.magazine
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
	if not new_blueprints.is_empty() and expedition.phase in ["reward","route","won"]:
		panel(Rect2(945,20,150,54),PANEL,GOLD)
		symbol("example",Vector2(980,47),1.1)
		text_at("+"+str(new_blueprints.size()),Vector2(1015,57),26,GOLD)
	if retreat_button.visible: symbol("retreat",Vector2(891,47),0.8)
	# Sector lamps and bounded raw-material reserve counters.
	for i in range(RunState.SECTORS):
		draw_circle(Vector2(1160+i*20,119),5,GOLD if i < expedition.sector else BG)
	for i in range(2):
		var raw = "scrap" if i == 0 else "coal"
		item_at(raw,Vector2(1170+i*125,750),0.55)
		text_at(str(factory.reserves[raw]),Vector2(1187+i*125,756),15,MUTED)
	if expedition.phase not in ["reward","route"]: return
	metal_panel(Rect2(24,776,1392,154))
	var count = 3 if expedition.phase == "reward" else 2
	for i in range(count):
		var at = Vector2(55+i*460,796)
		panel(Rect2(at,Vector2(420,112)),PANEL,GOLD)
		if expedition.phase == "reward":
			symbol(["press","fuel","depot"][i],at+Vector2(65,54),1.4)
			text_at(["×0.85","×0.80","+4"][i],at+Vector2(130,65),29,GOLD)
		else:
			var route: Dictionary = expedition.route_options[i]
			symbol({"scrapyard":"scrap","coalfield":"coal","arsenal":"gun"}[route.kind],at+Vector2(45,44),1.2)
			if route.shells > 0: text_at("+"+str(route.shells),at+Vector2(28,92),19,GOLD)
			item_at("scrap",at+Vector2(125,35),0.7)
			text_at(str(route.scrap),at+Vector2(150,43),22,INK)
			item_at("coal",at+Vector2(125,78),0.7)
			text_at(str(route.coal),at+Vector2(150,86),22,INK)
			symbol("battle",at+Vector2(260,35),0.65)
			text_at(str(route.enemy_hp),at+Vector2(290,43),22,INK)
			symbol("move",at+Vector2(260,78),0.65)
			text_at(str(int(route.length)),at+Vector2(290,86),22,INK)

func open_menu(title: bool = false):
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
			if menu_title or save_checkpoint(): get_tree().quit()

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if menu_title or save_checkpoint():
			get_tree().quit()
		else:
			open_menu(false)
			menu_status = "defeat"
			menu.refresh()
