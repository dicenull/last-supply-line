extends RefCounted
const UIStyle = preload("res://scripts/ui_style.gd")
## Floating construction dock and management rail, shared by mouse and touch.
const ACTIONS = ["loadout","warehouse","cargo","roof","battle","menu"]
const ACTION_LABELS = {"loadout":"性能","warehouse":"倉庫","cargo":"一覧","roof":"外装","battle":"視点","menu":"中断"}
var rect = Rect2(16,848,1408,80)
var compact = false
var controls_rect = Rect2()
var building_rect = Rect2()
var primary_rect = Rect2()
var selection_label: Label

# Separate floating docks. The world continues behind them to the bottom edge.
func arrange(game):
	var scale = UIStyle.screen_scale(game)
	compact = scale < 0.65
	var editing: bool = not game.battle_mode and game.can_manage_layout()
	var side = maxf(52,44/scale)
	var gap = 8.0
	var step = side+gap
	var columns = maxi(game.TOOL_TABS.size(),game.tool_kinds().size())
	var width = side*columns+gap*(columns-1)
	var left = (1280-width)/2
	var top = 928-side*2-gap
	building_rect = Rect2(left,top,width,side*2+gap)
	rect = building_rect if editing else Rect2(left,928,width,0)
	var management = ACTIONS if editing else ["loadout","warehouse","cargo","battle","menu"]
	var rail_gap = 4.0 if compact else gap
	controls_rect = Rect2(1408-side,88,side,management.size()*side+(management.size()-1)*rail_gap)
	var diameter = maxf(96,72/scale)
	primary_rect = Rect2(1408-diameter,928-diameter,diameter,diameter)
	for entry in game.icon_buttons:
		var target: Rect2 = entry.original_rect
		if entry.has("tab_index"):
			target = Rect2((1280-(game.TOOL_TABS.size()*step-gap))/2+entry.tab_index*step,top+step,side,side)
		elif entry.has("tool_index"):
			var count: int = game.tool_kinds().size()
			target = Rect2((1280-(count*step-gap))/2+entry.tool_index*step,top,side,side)
		elif entry.icon == "play":
			target = primary_rect
		elif entry.icon in management:
			target = Rect2(controls_rect.position+Vector2(0,management.find(entry.icon)*(side+rail_gap)),Vector2.ONE*side)
		entry.rect = target
		entry.button.position = target.position
		entry.button.size = target.size
		if entry.icon != "play": style_icon(game,entry,scale)
	arrange_primary(game,diameter,scale)
	arrange_selection(game,scale,editing)
	game.battle_retry.size = Vector2(maxf(264,160/scale),maxf(64,44/scale))
	game.battle_retry.position = Vector2(720-game.battle_retry.size.x/2,928-game.battle_retry.size.y)
	game.battle_retry.add_theme_constant_override("icon_max_width",roundi(maxf(32,24/scale)))
	game.battle_retry.add_theme_font_size_override("font_size",maxi(18,ceili(16/scale)))
	var scene_size = Vector2(game.WORLD_RECT.size.x,928-game.WORLD_RECT.position.y)
	if game.factory_container.size != scene_size: game.factory_container.size = scene_size
	if game.battle_container != null and game.battle_container.size != scene_size: game.battle_container.size = scene_size

func workspace_rect(game) -> Rect2:
	return Rect2(game.WORLD_RECT.position,Vector2(minf(controls_rect.position.x,primary_rect.position.x)-32,rect.position.y-game.WORLD_RECT.position.y-12))

func arrange_selection(game, scale: float, editing: bool):
	if selection_label == null:
		selection_label = Label.new()
		selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		selection_label.add_theme_font_override("font",UIStyle.BOLD_FONT)
		selection_label.add_theme_color_override("font_color",UIStyle.INK)
		selection_label.add_theme_stylebox_override("normal",UIStyle.style(Color(0.10,0.13,0.11,0.88)))
		game.start_button.get_parent().add_child(selection_label)
	selection_label.visible = editing and game.expedition.phase in ["prepare","travel"] and not game.equipment_workspace.visible
	var spec: Dictionary = game.Factory.Content.BLOCKS.get(game.selected,game.Factory.Content.BASIC_BLOCKS.get(game.selected,{}))
	selection_label.text = game.TOOL_TABS[game.tool_page].name+" / "+spec.get("name","撤去" if game.selected == "erase" else game.selected)
	if game.selected.is_empty() and game.selected_item_uid < 0: selection_label.text = "ハンドフリー"
	if game.touch_controls != null and game.touch_controls.mode == "stow": selection_label.text = "収納する装備を選択"
	selection_label.add_theme_font_size_override("font_size",maxi(16,ceili(14/scale)))
	selection_label.size = selection_label.get_minimum_size()+Vector2(24,4)
	selection_label.position = Vector2(640-selection_label.size.x/2,building_rect.position.y-selection_label.size.y-8)

func style_icon(game, entry: Dictionary, scale: float):
	var button: Button = entry.button
	var picked: bool = game.selected == entry.icon
	if game.selected_item_uid >= 0 and entry.icon in game.tool_buttons: picked = false
	if entry.icon == "roof": picked = game.world.roof_closed
	if entry.icon == "stow": picked = game.touch_controls != null and game.touch_controls.mode == "stow"
	if entry.icon == "loadout": picked = game.equipment_workspace.loadout.visible
	if entry.icon == "warehouse": picked = game.inventory_panel.visible
	if entry.has("tab_index"): picked = game.tool_page == entry.tab_index
	var icon: String = {"warehouse":"depot","stow":"cargo","loadout":"settings","cargo":"sort"}.get(entry.icon,entry.icon)
	if entry.icon == "battle": icon = "example" if game.battle_mode else "battle"
	if entry.icon == "roof": icon = "roof" if game.world.roof_closed else "roof_open"
	button.icon = game.pixel_icons.texture(icon) if icon != "" else null
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width",roundi(maxf(32,28/scale)))
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var style_key = str(picked)
	if button.get_meta("dock_style","") != style_key:
		button.set_meta("dock_style",style_key)
		for state in ["normal","hover","pressed"]:
			var face = UIStyle.style(Color("55513a") if picked or state == "pressed" else Color("353d32") if state == "hover" else Color(0.10,0.13,0.11,0.94),UIStyle.GOLD if picked or state == "hover" else Color("68705a"))
			face.set_corner_radius_all(8)
			face.set_border_width_all(2 if picked else 1)
			face.shadow_color = Color(0,0,0,0.25)
			face.shadow_size = 3
			button.add_theme_stylebox_override(state,face)
	if entry.has("tab_index"):
		button.tooltip_text = game.TOOL_TABS[entry.tab_index].name
	elif entry.icon in ACTION_LABELS:
		button.tooltip_text = ACTION_LABELS[entry.icon]+(" ("+entry.key+")" if entry.key != "" else "")
	var badge: Label = button.get_node_or_null("Count")
	if badge == null:
		badge = Label.new()
		badge.name = "Count"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_override("font",UIStyle.BOLD_FONT)
		badge.add_theme_color_override("font_color",UIStyle.GOLD)
		badge.add_theme_color_override("font_shadow_color",Color.BLACK)
		badge.add_theme_constant_override("shadow_offset_x",1)
		badge.add_theme_constant_override("shadow_offset_y",1)
		button.add_child(badge)
	badge.text = ""
	if entry.icon == "cargo": badge.text = str(game.expedition.gear_items.size())
	if game.Factory.LIMITS.has(entry.icon) and entry.has("tool_index"):
		badge.text = str(game.factory.available(entry.icon))
	badge.add_theme_font_size_override("font_size",maxi(14,ceili(14/scale)))
	badge.position = Vector2(button.size.x-badge.get_minimum_size().x-4,button.size.y-badge.get_minimum_size().y)

func arrange_primary(game, diameter: float, screen_scale: float):
	var button: Button = game.start_button
	button.text = "出撃" if not game.started else "停止" if game.factory.running else "再開"
	button.add_theme_font_override("font",UIStyle.HEADING_FONT)
	button.add_theme_font_size_override("font_size",maxi(24,ceili(20/screen_scale)))
	button.add_theme_color_override("font_color",UIStyle.BG)
	button.add_theme_color_override("font_hover_color",UIStyle.BG)
	button.add_theme_color_override("font_pressed_color",UIStyle.BG)
	if button.get_meta("fab_diameter",0.0) == diameter: return
	button.set_meta("fab_diameter",diameter)
	for state in ["normal","hover","pressed"]:
		var face = UIStyle.style(Color("ffe3a5") if state == "hover" else Color("c89e59") if state == "pressed" else UIStyle.GOLD,UIStyle.INK)
		face.set_corner_radius_all(ceili(diameter/2))
		face.shadow_color = Color(0,0,0,0.4)
		face.shadow_size = 6
		face.shadow_offset = Vector2(0,4)
		button.add_theme_stylebox_override(state,face)
