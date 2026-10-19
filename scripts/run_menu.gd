extends Control
## Icon-and-text menu over both 3D viewports; gameplay HUD remains icon-led.
var game
var actions: Array = []
var blueprint_buttons: Array = []
var layout_buttons: Dictionary = {}
var utility_buttons: Dictionary = {}
const ROW_X = 540
const ROW_WIDTH = 360
const ROW_HEIGHT = 32
const PADDING = 4
var volume_slider: HSlider
var mute_button: Button
var previous_volume = 0.35
func _ready():
	position = Vector2.ZERO
	size = Vector2(1440,940)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in range(5):
		var index = i
		actions.append(small_button(row_rect(104+i*ROW_HEIGHT),func(): game.menu_action(index)))
	for i in range(game.Blueprints.IDS.size()):
		var id = game.Blueprints.IDS[i]
		blueprint_buttons.append(small_button(row_rect(550+i*ROW_HEIGHT),func(): game.apply_blueprint(id)))
	for i in range(4):
		var kind: String = ["save","load","erase","undo"][i]
		layout_buttons[kind] = small_button(row_rect(286+i*ROW_HEIGHT),func(): layout_action(kind))
	for i in range(3):
		var kind: String = ["camera","roof","retreat"][i]
		utility_buttons[kind] = small_button(row_rect(414+i*ROW_HEIGHT),func(): utility_action(kind))
	volume_slider = HSlider.new()
	volume_slider.position = Vector2(612,718)
	volume_slider.size = Vector2(218,32)
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.focus_mode = Control.FOCUS_NONE
	var rail = StyleBoxFlat.new()
	rail.bg_color = game.BG
	rail.border_color = game.MUTED
	rail.set_border_width_all(1)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	volume_slider.add_theme_stylebox_override("slider",rail)
	var fill = rail.duplicate()
	fill.bg_color = game.GOLD
	volume_slider.add_theme_stylebox_override("grabber_area",fill)
	volume_slider.add_theme_stylebox_override("grabber_area_highlight",fill)
	volume_slider.add_theme_icon_override("grabber",game.pixel_icons.texture("volume_knob"))
	volume_slider.add_theme_icon_override("grabber_highlight",game.pixel_icons.texture("volume_knob"))
	volume_slider.value = game.sound.volume*100
	volume_slider.value_changed.connect(func(value):
		game.sound.set_volume(value/100.0)
		queue_redraw())
	add_child(volume_slider)
	mute_button = small_button(row_rect(686),func():
		if game.sound.volume > 0:
			previous_volume = game.sound.volume
			game.sound.set_volume(0)
		else: game.sound.set_volume(previous_volume)
		volume_slider.set_value_no_signal(game.sound.volume*100)
		queue_redraw())
	visible = false

func row_rect(y: float) -> Rect2:
	return Rect2(ROW_X,y,ROW_WIDTH,ROW_HEIGHT)

func small_button(rect: Rect2, action: Callable) -> Button:
	var button = Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(state,game.style(Color(1,1,1,0.08) if state in ["hover","pressed"] else Color.TRANSPARENT))
	button.pressed.connect(action)
	add_child(button)
	return button

func layout_action(kind: String):
	# Pausing an active run must not grant permission to replace its cargo/layout.
	if not game.can_manage_layout(): return
	var success = true
	match kind:
		"save": success = game.save_layout()
		"load": success = game.load_layout()
		"erase": game.factory.clear_layout()
		"undo":
			if game.factory.undo_stack.is_empty(): return
			game.factory.undo()
	game.menu_status = "victory" if success else "defeat"
	refresh()
	game.queue_redraw()

func utility_action(kind: String):
	match kind:
		"camera": game.reset_camera()
		"roof": game.world.toggle_roof()
		"retreat":
			if game.expedition.phase not in ["prepare","travel"]: return
			game.menu_was_running = false
			game.retreat_run()
			game.close_menu()
	refresh()
	game.queue_redraw()

func refresh():
	actions[1].disabled = not FileAccess.file_exists(game.checkpoint_path) and not FileAccess.file_exists(game.checkpoint_path+".bak")
	actions[2].disabled = game.menu_title
	volume_slider.set_value_no_signal(game.sound.volume*100)
	for i in range(actions.size()): actions[i].tooltip_text = action_labels()[i]
	for kind in layout_buttons: layout_buttons[kind].tooltip_text = layout_label(kind)
	for kind in utility_buttons: utility_buttons[kind].tooltip_text = utility_label(kind).replace("\n","")
	mute_button.tooltip_text = "音を戻す" if game.sound.volume == 0 else "消音"
	for kind in layout_buttons:
		layout_buttons[kind].disabled = not game.can_manage_layout() or (kind == "undo" and game.factory.undo_stack.is_empty()) or (kind == "load" and not FileAccess.file_exists(game.layout_path))
	utility_buttons.retreat.disabled = game.expedition.phase not in ["prepare","travel"]
	for i in range(blueprint_buttons.size()):
		blueprint_buttons[i].disabled = not game.can_apply_blueprint() or game.Blueprints.IDS[i] not in game.history.unlocked
	queue_redraw()

func plate(rect: Rect2, fill: Color, border: Color = Color.TRANSPARENT):
	draw_style_box(game.style(fill,border),rect)

func action_labels() -> Array:
	return ["準備へ" if game.menu_title else "ゲームに戻る","続きから","ランを保存","新しいラン","終了"]

func layout_label(kind: String) -> String:
	return {"save":"配置保存","load":"配置読込","erase":"全撤去","undo":"取り消し"}[kind]

func utility_label(kind: String) -> String:
	return {"camera":"視点初期化","roof":"装甲を開く" if game.world.roof_closed else "装甲を閉じる","retreat":"撤退"}[kind]

func line_text(value: String, rect: Rect2, font_size: int, color: Color, alignment: int = HORIZONTAL_ALIGNMENT_LEFT):
	var baseline = rect.position.y+(rect.size.y-game.font.get_height(font_size))/2.0+game.font.get_ascent(font_size)
	draw_string(game.font,Vector2(rect.position.x,baseline),value,alignment,rect.size.x,font_size,color)

func draw_row(button: Button, icon: String, label: String, accent: bool = false, destructive: bool = false, detail: String = ""):
	var rect = button.get_rect()
	if accent: plate(rect,Color("51563b"),game.GOLD)
	var tint = Color(1,1,1,0.3) if button.disabled else Color.WHITE
	var color = game.MUTED.darkened(0.25) if button.disabled else game.DANGER if destructive else game.INK
	draw_texture_rect(game.pixel_icons.texture(icon),Rect2(rect.position+Vector2(PADDING,PADDING),Vector2(24,24)),false,tint)
	line_text(label,Rect2(rect.position+Vector2(32,PADDING),Vector2(ROW_WIDTH-36,24)),18,color)
	if detail != "": line_text(detail,Rect2(rect.position+Vector2(176,PADDING),Vector2(180,24)),14,game.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)

func section(label: String, y: float):
	line_text(label,Rect2(ROW_X+PADDING,y,ROW_WIDTH-8,22),14,game.MUTED)
	var start = ROW_X+12+game.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
	draw_line(Vector2(start,y+11),Vector2(ROW_X+ROW_WIDTH-PADDING,y+11),game.EDGE,1)

func _draw():
	draw_rect(Rect2(0,0,1440,940),Color(0.045,0.055,0.04,0.88))
	plate(Rect2(528,48,384,864),game.PANEL,game.EDGE)
	draw_rect(Rect2(528,48,384,3),game.GOLD)
	line_text("M.F.V. 03",Rect2(544,64,240,32),26,game.INK)
	line_text("1918 · Esc",Rect2(784,64,112,32),15,game.GOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	var kinds = ["play","load","save","reset","exit"]
	for i in range(actions.size()): draw_row(actions[i],kinds[i],action_labels()[i],i == 0)
	section("配置・車両",264)
	for kind in layout_buttons: draw_row(layout_buttons[kind],kind,layout_label(kind),false,kind == "erase")
	for kind in utility_buttons:
		draw_row(utility_buttons[kind],"roof_open" if kind == "roof" and not game.world.roof_closed else kind,utility_label(kind),false,kind == "retreat")
	section("設計図",526)
	for i in range(blueprint_buttons.size()):
		var id = game.Blueprints.IDS[i]
		var unlocked = id in game.history.unlocked
		var selected = game.Blueprints.matches(game.factory.layout(),id)
		var detail = "選択中" if selected else ""
		if not unlocked: detail = "%d戦クリアで開放" % game.Blueprints.REQUIREMENTS[id]
		draw_row(blueprint_buttons[i],"example" if unlocked else "lock",{"standard":"標準配置","parallel":"弾薬並列","buffered":"弾薬備蓄"}[id],selected,false,detail)
	section("音声",662)
	draw_row(mute_button,"mute" if game.sound.volume == 0 else "sound","音を戻す" if game.sound.volume == 0 else "消音")
	line_text("音量",Rect2(544,722,64,24),18,game.INK)
	line_text(str(roundi(game.sound.volume*100))+"%",Rect2(842,722,54,24),18,game.INK,HORIZONTAL_ALIGNMENT_RIGHT)
	section("直近の出撃",758)
	if game.history.entries.is_empty(): line_text("履歴なし",row_rect(782).grow(-PADDING),14,game.MUTED)
	for i in range(mini(3,game.history.entries.size())):
		var entry = game.history.entries[i]
		var at = Vector2(544,786+i*30)
		var icon = "victory" if entry.phase == "won" else "retreat" if entry.phase == "retreated" else "defeat"
		draw_texture_rect(game.pixel_icons.texture(icon),Rect2(at,Vector2(24,24)),false)
		line_text("#"+entry.seed,Rect2(at+Vector2(28,0),Vector2(184,24)),12,game.MUTED)
		line_text("%d/5戦 · %d発" % [entry.cleared,int(entry.shells)],Rect2(at+Vector2(212,0),Vector2(140,24)),14,game.INK,HORIZONTAL_ALIGNMENT_RIGHT)
	var status = "完了" if game.menu_status == "victory" else "操作失敗" if game.menu_status != "" else ""
	if game.sound.settings_error: status += " 音量保存失敗"
	if game.history.error: status += " 履歴保存失敗"
	line_text(status,Rect2(544,882,352,22),14,game.GOLD if game.menu_status == "victory" else game.DANGER)
