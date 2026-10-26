extends Control
## Standalone menu: reads presentation snapshots and emits user intent.
const UIStyle = preload("res://scripts/ui_style.gd")
const MenuState = preload("res://scripts/run_menu_state.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
const Content = preload("res://scripts/content.gd")
signal action_selected(index: int)
signal blueprint_selected(id: String)
signal layout_selected(kind: String)
signal utility_selected(kind: String)
signal difficulty_selected(id: String)
signal volume_changed(value: float)
var ui = UIStyle.new()
var state = MenuState.new()
var state_provider: Callable

var actions: Array = []
var blueprint_buttons: Array = []
var layout_buttons: Dictionary = {}
var utility_buttons: Dictionary = {}
const ROW_X = 520
const ROW_WIDTH = 400
const ROW_HEIGHT = 44
const PADDING = 10
var page = "start"
var navigation: Dictionary = {}
var back_button: Button
var volume_slider: HSlider
var mute_button: Button
var previous_volume = 0.35
var difficulty_select: Button
var difficulty_popup: Control
var difficulty_buttons: Array = []
var standalone_title = false
var framed = false
var title_shade: GradientTexture2D

func configure(visuals, read_state: Callable):
	ui = visuals
	state_provider = read_state

func read_state():
	if state_provider.is_valid(): state = state_provider.call()

func _ready():
	read_state()
	position = Vector2.ZERO
	size = Vector2(1440,940)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if standalone_title:
		title_shade = GradientTexture2D.new()
		title_shade.width = 1440
		title_shade.height = 1
		title_shade.gradient = Gradient.new()
		title_shade.gradient.offsets = PackedFloat32Array([0,0.26,0.62,1])
		title_shade.gradient.colors = PackedColorArray([Color("111713"),Color(0.067,0.09,0.075,0.94),Color(0.067,0.09,0.075,0.15),Color(0.067,0.09,0.075,0)])
	for i in range(5):
		var index = i
		actions.append(small_button(row_rect(104+i*ROW_HEIGHT),func(): action_selected.emit(index)))
	for i in range(Blueprints.IDS.size()):
		var id = Blueprints.IDS[i]
		blueprint_buttons.append(small_button(row_rect(550+i*ROW_HEIGHT),func(): blueprint_selected.emit(id)))
	for i in range(4):
		var kind: String = ["save","load","erase","undo"][i]
		layout_buttons[kind] = small_button(row_rect(286+i*ROW_HEIGHT),func(): layout_action(kind))
	for i in range(3):
		var kind: String = ["camera","roof","retreat"][i]
		utility_buttons[kind] = small_button(row_rect(414+i*ROW_HEIGHT),func(): utility_action(kind))
	for target in ["settings","workshop","history"]:
		navigation[target] = small_button(row_rect(0),func(): show_page(target))
	back_button = small_button(Rect2(808,140,112,40),func(): show_home())
	back_button.text = "← 戻る"
	back_button.add_theme_font_override("font",ui.font)
	back_button.add_theme_font_size_override("font_size",18)
	volume_slider = HSlider.new()
	volume_slider.position = Vector2(612,344)
	volume_slider.size = Vector2(218,32)
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.focus_mode = Control.FOCUS_NONE
	var rail = StyleBoxFlat.new()
	rail.bg_color = ui.BG
	rail.border_color = ui.MUTED
	rail.set_border_width_all(1)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	volume_slider.add_theme_stylebox_override("slider",rail)
	var fill = rail.duplicate()
	fill.bg_color = ui.GOLD
	volume_slider.add_theme_stylebox_override("grabber_area",fill)
	volume_slider.add_theme_stylebox_override("grabber_area_highlight",fill)
	volume_slider.add_theme_icon_override("grabber",ui.pixel_icons.texture("volume_knob"))
	volume_slider.add_theme_icon_override("grabber_highlight",ui.pixel_icons.texture("volume_knob"))
	volume_slider.value = state.volume*100
	volume_slider.value_changed.connect(func(value):
		volume_changed.emit(value/100.0)
		refresh())
	add_child(volume_slider)
	mute_button = small_button(row_rect(686),func():
		if state.volume > 0:
			previous_volume = state.volume
			volume_changed.emit(0.0)
		else: volume_changed.emit(previous_volume)
		refresh())
	difficulty_select = Button.new()
	difficulty_select.position = Vector2(ROW_X,480)
	difficulty_select.size = Vector2(ROW_WIDTH,44)
	difficulty_select.focus_mode = Control.FOCUS_NONE
	difficulty_select.add_theme_font_override("font",ui.font)
	difficulty_select.add_theme_font_size_override("font_size",18)
	difficulty_select.pressed.connect(func(): difficulty_popup.show())
	add_child(difficulty_select)
	difficulty_popup = Control.new()
	difficulty_popup.size = size
	difficulty_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(difficulty_popup)
	var shade = Panel.new()
	shade.size = size
	shade.add_theme_stylebox_override("panel",ui.style(Color(0.045,0.055,0.04,0.88)))
	difficulty_popup.add_child(shade)
	var panel = Panel.new()
	panel.position = Vector2(528,316)
	panel.size = Vector2(384,248)
	panel.add_theme_stylebox_override("panel",ui.style(ui.PANEL,ui.GOLD))
	difficulty_popup.add_child(panel)
	var title = Label.new()
	title.text = "難易度を選択"
	title.position = Vector2(548,334)
	title.add_theme_font_override("font",ui.font)
	title.add_theme_font_size_override("font_size",24)
	difficulty_popup.add_child(title)
	for i in range(3):
		var id: String = Content.DIFFICULTIES.keys()[i]
		var button = Button.new()
		button.text = Content.DIFFICULTIES[id].name
		button.icon = ui.pixel_icons.texture("shield" if i == 0 else "battle" if i == 1 else "battery")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",24)
		button.add_theme_font_override("font",ui.font)
		button.add_theme_font_size_override("font_size",20)
		button.position = Vector2(548,380+i*54)
		button.size = Vector2(344,44)
		button.pressed.connect(func():
			difficulty_selected.emit(id)
			difficulty_popup.hide()
			refresh())
		difficulty_popup.add_child(button)
		difficulty_buttons.append(button)
	difficulty_popup.hide()
	show_home()
	visible = false

func show_home():
	read_state()
	show_page("start" if state.title else "pause")

func show_page(target: String):
	if target not in ["start","pause","settings","workshop","history"]: return
	page = target
	difficulty_popup.hide()
	refresh()

func go_back() -> bool:
	if difficulty_popup.visible:
		difficulty_popup.hide()
		return true
	if page in ["start","pause"]: return false
	show_home()
	return true

func arrange():
	for button in actions+blueprint_buttons+layout_buttons.values()+utility_buttons.values()+navigation.values():
		button.hide()
		button.size = Vector2(ROW_WIDTH,ROW_HEIGHT)
	volume_slider.visible = page == "settings"
	mute_button.visible = page == "settings"
	difficulty_select.visible = page == "settings"
	back_button.visible = page not in ["start","pause"]
	match page:
		"start":
			place_rows([actions[0],actions[1],navigation.settings,navigation.history,actions[4]],360,56)
			if standalone_title:
				size = get_viewport_rect().size
				var screen_scale = maxf(0.01,get_viewport().get_final_transform().get_scale().x)
				var row_height = maxf(58,44/screen_scale)
				var gap = row_height+12
				var y = size.y*0.55 if size.x < size.y else minf(402,maxf(340,size.y-((4 if OS.has_feature("web") else 5)*gap)-100))
				var entries = [actions[0],actions[1],navigation.settings,navigation.history,actions[4]]
				for i in range(entries.size()):
					entries[i].position = Vector2(60,y+i*gap)
					entries[i].size = Vector2(maxf(320,200/screen_scale),row_height)
					entries[i].focus_mode = Control.FOCUS_ALL
					entries[i].add_theme_stylebox_override("focus",StyleBoxEmpty.new())
			if OS.has_feature("web"): actions[4].hide()
		"pause":
			place_rows([actions[0],actions[2],actions[1],navigation.workshop,navigation.settings,navigation.history,actions[3],utility_buttons.retreat,actions[4]],230,56)
		"workshop":
			place_rows(layout_buttons.values(),244,44)
			place_rows(blueprint_buttons,464,44)
			place_rows([utility_buttons.camera,utility_buttons.roof],646,44)
		"settings": mute_button.position = Vector2(ROW_X,274)

func frame_bounds() -> Rect2:
	if standalone_title and page == "start": return Rect2(Vector2.ZERO,get_viewport_rect().size)
	return Rect2(480,176,480,588) if page == "start" else Rect2(480,96,480,748)

func _notification(what: int):
	if what == NOTIFICATION_RESIZED and is_node_ready(): queue_redraw()

func _process(_delta):
	if standalone_title and page == "start" and visible and size != get_viewport_rect().size:
		arrange()
		queue_redraw()

func place_rows(buttons: Array, y: float, gap: float):
	for i in range(buttons.size()):
		buttons[i].position = Vector2(ROW_X,y+i*gap)
		buttons[i].show()

func row_rect(y: float) -> Rect2:
	return Rect2(ROW_X,y,ROW_WIDTH,ROW_HEIGHT)

func small_button(rect: Rect2, action: Callable) -> Button:
	var button = Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for button_state in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(button_state,ui.style(Color(1,1,1,0.08) if button_state in ["hover","pressed"] else Color.TRANSPARENT))
	button.pressed.connect(action)
	if standalone_title:
		button.mouse_entered.connect(queue_redraw)
		button.mouse_exited.connect(queue_redraw)
		button.focus_entered.connect(queue_redraw)
		button.focus_exited.connect(queue_redraw)
	add_child(button)
	return button

func layout_action(kind: String):
	layout_selected.emit(kind)

func utility_action(kind: String):
	utility_selected.emit(kind)

func refresh():
	read_state()
	arrange()
	difficulty_select.text = "難易度："+Content.DIFFICULTIES[state.difficulty].name
	difficulty_select.disabled = state.difficulty_locked
	actions[1].disabled = not state.can_continue
	actions[2].disabled = state.title
	if OS.has_feature("web"): actions[4].disabled = state.title
	volume_slider.set_value_no_signal(state.volume*100)
	for i in range(actions.size()): actions[i].tooltip_text = action_labels()[i]
	for kind in layout_buttons: layout_buttons[kind].tooltip_text = layout_label(kind)
	for kind in utility_buttons: utility_buttons[kind].tooltip_text = utility_label(kind).replace("\n","")
	mute_button.tooltip_text = "音を戻す" if state.volume == 0 else "消音"
	for kind in layout_buttons:
		layout_buttons[kind].disabled = not state.can_manage_layout or (kind == "undo" and not state.can_undo) or (kind == "load" and not state.can_load_layout)
	utility_buttons.retreat.disabled = not state.can_retreat
	for i in range(blueprint_buttons.size()):
		blueprint_buttons[i].disabled = not state.can_apply_blueprint or Blueprints.IDS[i] not in state.unlocked_blueprints
	queue_redraw()

func plate(rect: Rect2, fill: Color, border: Color = Color.TRANSPARENT):
	draw_style_box(ui.style(fill,border),rect)

func action_labels() -> Array:
	return ["はじめる" if state.title else "ゲームに戻る","続きから" if state.title else "保存したランを読込","ランを保存","新しいラン","保存してタイトルへ" if OS.has_feature("web") else "終了"]

func layout_label(kind: String) -> String:
	return {"save":"配置保存","load":"配置読込","erase":"全撤去","undo":"取り消し"}[kind]

func utility_label(kind: String) -> String:
	return {"camera":"視点初期化","roof":"装甲を開く" if state.roof_closed else "装甲を閉じる","retreat":"撤退"}[kind]

func line_text(value: String, rect: Rect2, font_size: int, color: Color, alignment: int = HORIZONTAL_ALIGNMENT_LEFT):
	var baseline = rect.position.y+(rect.size.y-ui.font.get_height(font_size))/2.0+ui.font.get_ascent(font_size)
	draw_string(ui.font,Vector2(rect.position.x,baseline),value,alignment,rect.size.x,font_size,color)

func draw_row(button: Button, icon: String, label: String, accent: bool = false, destructive: bool = false, detail: String = ""):
	if not button.visible: return
	var rect = button.get_rect()
	if accent: plate(rect,Color("51563b"),ui.GOLD)
	var tint = Color(1,1,1,0.3) if button.disabled else Color.WHITE
	var color = ui.MUTED.darkened(0.25) if button.disabled else ui.DANGER if destructive else ui.INK
	draw_texture_rect(ui.pixel_icons.texture(icon),Rect2(rect.position+Vector2(PADDING,PADDING),Vector2(24,24)),false,tint)
	line_text(label,Rect2(rect.position+Vector2(44,PADDING),Vector2(ROW_WIDTH-52,24)),18,color)
	if detail != "": line_text(detail,Rect2(rect.position+Vector2(204,PADDING),Vector2(184,24)),14,ui.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)

func section(label: String, y: float):
	line_text(label,Rect2(ROW_X+PADDING,y,ROW_WIDTH-8,22),14,ui.MUTED)
	var start = ROW_X+12+ui.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
	draw_line(Vector2(start,y+11),Vector2(ROW_X+ROW_WIDTH-PADDING,y+11),ui.EDGE,1)

func _draw():
	if standalone_title and page == "start":
		draw_title()
		return
	if not framed: draw_rect(Rect2(0,0,1440,940),Color(0.045,0.055,0.04,0.88))
	var panel = frame_bounds()
	plate(panel,ui.PANEL,ui.EDGE)
	draw_rect(Rect2(panel.position,Vector2(panel.size.x,3)),ui.GOLD)
	if page == "start":
		line_text("M.F.V. 03",Rect2(520,222,400,56),42,ui.INK,HORIZONTAL_ALIGNMENT_CENTER)
		line_text("自走工廠 · 1918",Rect2(520,282,400,32),20,ui.GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var heading = {"pause":"一時停止","settings":"設定","workshop":"配置・車両","history":"出撃履歴"}[page]
		line_text(heading,Rect2(520,140,280,40),28,ui.INK)
		if page == "pause": line_text("Esc で戻る",Rect2(800,146,120,30),15,ui.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	var kinds = ["play","load","save","reset","exit"]
	for i in range(actions.size()): draw_row(actions[i],kinds[i],action_labels()[i],i == 0,false)
	for target in navigation:
		var icon = {"settings":"settings","workshop":"belt","history":"clock"}[target]
		var label = {"settings":"設定","workshop":"配置・車両","history":"出撃履歴"}[target]
		draw_row(navigation[target],icon,label)
	for kind in utility_buttons:
		draw_row(utility_buttons[kind],"roof_open" if kind == "roof" and not state.roof_closed else kind,utility_label(kind),false,kind == "retreat")
	if page == "workshop": draw_workshop()
	elif page == "settings": draw_settings()
	elif page == "history": draw_history()
	var status = "完了" if state.status == "victory" else "操作失敗" if state.status != "" else ""
	if state.audio_error: status += " 音量保存失敗"
	if state.history_error: status += " 履歴保存失敗"
	line_text(status,Rect2(520,panel.end.y-44,400,24),14,ui.GOLD if state.status == "victory" else ui.DANGER)

func draw_title():
	var screen_scale = maxf(0.01,get_viewport().get_final_transform().get_scale().x)
	var portrait = size.x < size.y
	draw_texture_rect(title_shade,Rect2(Vector2.ZERO,size),false)
	draw_line(Vector2(64,76),Vector2(104,76),ui.GOLD,3)
	line_text("MOBILE FOUNDRY VEHICLE / 1918",Rect2(120,60,size.x-180,32),maxi(16,roundi(11/screen_scale)),ui.GOLD)
	line_text("M.F.V. 03",Rect2(58,106,1000,134),112,ui.INK)
	line_text("自走工廠",Rect2(66,244,1000,100 if portrait else 58),maxi(38,roundi(18/screen_scale)),ui.INK)
	if not portrait: line_text("生産をつなげ。戦場を走り抜けろ。",Rect2(68,312,1000,36),18,ui.MUTED)
	var entries = [actions[0],actions[1],navigation.settings,navigation.history,actions[4]]
	var labels = ["はじめる","続きから","設定","出撃履歴","終了"]
	for i in range(entries.size()):
		var button: Button = entries[i]
		if not button.visible: continue
		var active = button.is_hovered() or button.has_focus()
		var color = ui.MUTED.darkened(0.48) if button.disabled else ui.GOLD if active or i == 0 else ui.INK
		var rect = button.get_rect()
		line_text(labels[i],Rect2(rect.position+Vector2(34,0),rect.size-Vector2(34,0)),maxi(28,roundi(18/screen_scale)),color)
		if active and not button.disabled:
			draw_line(rect.position+Vector2(4,29),rect.position+Vector2(18,29),ui.GOLD,2)
			draw_line(rect.position+Vector2(12,23),rect.position+Vector2(18,29),ui.GOLD,2)
			draw_line(rect.position+Vector2(12,35),rect.position+Vector2(18,29),ui.GOLD,2)
	if state.status != "": line_text(state.status,Rect2(68,size.y-118,1000,50),maxi(17,roundi(14/screen_scale)),ui.DANGER)
	line_text("BUILD.  SUPPLY.  SURVIVE.",Rect2(68,size.y-78,size.x-120,32),maxi(16,roundi(11/screen_scale)),ui.GOLD)

func draw_workshop():
	section("ライン配置",210)
	for kind in layout_buttons: draw_row(layout_buttons[kind],kind,layout_label(kind),false,kind == "erase")
	section("配置テンプレート · 設備設計図 %d/10" % state.researched_count,432)
	for i in range(blueprint_buttons.size()):
		var id = Blueprints.IDS[i]
		var unlocked = id in state.unlocked_blueprints
		var selected = id in state.selected_blueprints
		var detail = "選択中" if selected else ""
		if not unlocked: detail = "%d戦クリアで開放" % Blueprints.REQUIREMENTS[id]
		draw_row(blueprint_buttons[i],"example" if unlocked else "lock",{"standard":"標準配置","parallel":"弾薬並列","buffered":"弾薬備蓄"}[id],selected,false,detail)
	section("車両表示",614)

func draw_settings():
	section("音声",236)
	draw_row(mute_button,"mute" if state.volume == 0 else "sound","音を戻す" if state.volume == 0 else "消音")
	line_text("音量",Rect2(530,348,72,24),18,ui.INK)
	line_text(str(roundi(state.volume*100))+"%",Rect2(850,348,60,24),18,ui.INK,HORIZONTAL_ALIGNMENT_RIGHT)
	section("ゲーム",438)
	line_text("難易度は第1戦の出撃前に変更できます。" if state.difficulty_locked else "次の出撃に向けて難易度を選べます。",Rect2(530,540,380,28),15,ui.MUTED)

func draw_history():
	section("直近の出撃",226)
	if state.entries.is_empty(): line_text("まだ出撃履歴がありません。",row_rect(280),18,ui.MUTED)
	for i in range(mini(2,state.entries.size())):
		var entry = state.entries[i]
		var at = Vector2(530,280+i*100)
		var icon = "victory" if entry.phase == "won" else "retreat" if entry.phase == "retreated" else "defeat"
		draw_texture_rect(ui.pixel_icons.texture(icon),Rect2(at,Vector2(32,32)),false)
		line_text("#"+entry.seed,Rect2(at+Vector2(48,0),Vector2(330,28)),16,ui.MUTED)
		line_text("%d/5戦 · %d発製造" % [entry.cleared,int(entry.shells)],Rect2(at+Vector2(48,36),Vector2(330,28)),20,ui.INK)
