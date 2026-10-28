extends RefCounted
const UIStyle = preload("res://scripts/ui_style.gd")
## Ten equal horizontal units: eight building slots and two units for controls.
const ACTIONS = ["loadout","warehouse","cargo","roof","battle","rotate","stow","erase","menu"]
const ACTION_LABELS = {"loadout":"性能","warehouse":"倉庫","cargo":"一覧","roof":"外装","battle":"視点","rotate":"回転","stow":"収納","erase":"削除","menu":"中断"}
var rect = Rect2(16,848,1408,80)
var compact = false
var controls_rect = Rect2()
var building_rect = Rect2()

func arrange(game):
	var scale = UIStyle.screen_scale(game)
	compact = scale < 0.65
	var editing: bool = not game.battle_mode and game.can_manage_layout()
	var tool_height = maxf(52,44/scale)
	var tab_height = maxf(32,36/scale)
	var gap = 6.0
	var bottom = 928.0
	var height = tool_height*2+tab_height+20 if editing else tool_height
	var row_height = (height-gap*3)/4 if editing else (height-gap)/2
	var top = bottom-height
	var unit = 1384.0/10
	building_rect = Rect2(32,top,unit*8-gap,height)
	controls_rect = Rect2(32+unit*8,top,unit*2,height)
	rect = Rect2(16,top-12,1408,height+12)
	for entry in game.icon_buttons:
		var target: Rect2 = entry.original_rect
		if entry.has("tab_index"):
			var step = unit*8/5
			target = Rect2(32+entry.tab_index*step,top,step-gap,tab_height)
		elif entry.has("tool_index"):
			target = Rect2(32+entry.tool_index*unit,top+tab_height+gap,unit-gap,height-tab_height-gap)
		elif entry.icon == "play" and editing:
			target = Rect2(controls_rect.position+Vector2(0,3*(row_height+gap)),Vector2(controls_rect.size.x,row_height))
		elif entry.icon in ACTIONS or entry.icon == "play":
			var order = ACTIONS if editing else ["loadout","warehouse","cargo","battle","play","menu"]
			var index = maxi(0,order.find(entry.icon))
			var width = (controls_rect.size.x-gap*2)/3
			target = Rect2(controls_rect.position+Vector2((index%3)*(width+gap),(index/3)*(row_height+gap)),Vector2(width,row_height))
		entry.rect = target
		entry.button.position = target.position
		entry.button.size = target.size
	game.battle_retry.position = building_rect.position+Vector2(0,12)
	game.battle_retry.size = Vector2(264,row_height)
	var scene_size = Vector2(game.WORLD_RECT.size.x,rect.position.y-12-game.WORLD_RECT.position.y)
	if game.factory_container.size != scene_size: game.factory_container.size = scene_size
	if game.battle_container != null and game.battle_container.size != scene_size: game.battle_container.size = scene_size
