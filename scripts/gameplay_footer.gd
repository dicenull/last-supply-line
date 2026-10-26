extends RefCounted
## One set of buttons for mouse, keyboard, and touch. Only available space
## determines the layout; input hardware never selects a different design.
var rect = Rect2(16,848,1408,80)
var compact = false

func arrange(game):
	var scale = maxf(0.01,game.get_viewport().get_final_transform().get_scale().x)
	compact = scale < 0.65
	var editing: bool = not game.battle_mode and game.can_manage_layout()
	var row_height = maxf(52,44/scale)
	var tab_height = maxf(24,36/scale)
	var bottom = 928.0
	var action_y = bottom-row_height
	var tools_y = action_y-row_height-10
	var tabs_y = tools_y-tab_height-10
	rect = Rect2(16,(tabs_y if editing else action_y)-12,1408,bottom-(tabs_y if editing else action_y)+12) if compact else game.FOOTER_RECT
	var order = ["erase","rotate","stow","roof","cargo","battle","play","menu"]
	for entry in game.icon_buttons:
		var target: Rect2 = entry.original_rect
		if compact:
			if entry.has("tab_index"):
				target = Rect2(32+entry.tab_index*276,tabs_y,264,tab_height)
			elif entry.icon in order:
				var index = order.find(entry.icon)
				target = Rect2(32+index*173,action_y,161,row_height)
			else:
				var index = game.icon_buttons.find(entry)-3
				target = Rect2(32+index*276,tools_y,264,row_height)
		entry.rect = target
		entry.button.position = target.position
		entry.button.size = target.size
	game.battle_retry.position = Vector2(32,action_y) if compact else Vector2(614,862)
	game.battle_retry.size = Vector2(264,row_height) if compact else Vector2(212,52)
	var scene_size = Vector2(game.WORLD_RECT.size.x,rect.position.y-12-game.WORLD_RECT.position.y)
	if game.factory_container.size != scene_size: game.factory_container.size = scene_size
	if game.battle_container != null and game.battle_container.size != scene_size: game.battle_container.size = scene_size
