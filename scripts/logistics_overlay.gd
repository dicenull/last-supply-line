extends Control
## Read-only feedback over the 3D view. Mouse input continues to reach construction.
var game
var notices: Dictionary = {}
var battle_id = 0
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,940)
func sync(delta: float):
	var current_id = game.battlefield.get_instance_id() if game.battlefield != null else 0
	if current_id != battle_id:
		notices.clear()
		battle_id = current_id
	if game.factory.running:
		for item in notices.keys():
			notices[item].time -= delta
			if notices[item].time <= 0: notices.erase(item)
	if game.battlefield != null:
		for event in game.battlefield.collection_events:
			if not notices.has(event.item): notices[event.item] = {"accepted":0,"lost":0,"time":4.0}
			notices[event.item].accepted += event.accepted
			notices[event.item].lost += event.lost
			notices[event.item].time = 4.0
		game.battlefield.collection_events.clear()
	queue_redraw()
func badges() -> Array:
	var result: Array = []
	if game.battle_mode or game.world.roof_closed or game.factory.elapsed <= 0: return result
	for pos in game.factory.wrecks: result.append({"pos":pos,"code":"defeat"})
	for pos in game.factory.cells:
		var c = game.factory.cells[pos]
		var state = game.factory.diagnostic(pos)
		var show = state.code in ["disconnected","incompatible"]
		show = show or (state.code == "empty" and (c.kind in ["source","coal_source","gun","engine","blast_furnace","auto_press"] or game.Factory.AUXILIARY.has(c.kind)))
		show = show or (state.code == "full" and (c.kind in ["gun","engine","depot","fuel_depot","overflow_gate"] or game.Factory.AUXILIARY.has(c.kind)))
		if show: result.append({"pos":pos,"code":state.code})
	return result
func _draw():
	var battle = game.battlefield
	if game.battle_mode and battle != null and battle.combo >= 2 and battle.combo_time > 0:
		var alpha = minf(1.0,battle.combo_time)
		var at = Vector2(1160,128)
		draw_string(game.font,at,"連続撃破 ×%d" % battle.combo,HORIZONTAL_ALIGNMENT_RIGHT,220,24,Color(game.GOLD,alpha))
	for entry in badges():
		var world_pos = game.world.cell_position(entry.pos)+Vector3(0,1.4,0)
		if game.world.camera.is_position_behind(world_pos): continue
		var at = game.WORLD_RECT.position+game.world.camera.unproject_position(world_pos)
		if not game.WORLD_RECT.grow(-18).has_point(at): continue
		draw_circle(at,16,Color(0.10,0.14,0.12,0.92))
		draw_texture_rect(game.pixel_icons.texture(entry.code),Rect2(at-Vector2(14,14),Vector2(28,28)),false)
