extends Control
## Icon-only modal over both 3D viewports. No explanatory UI text.
var game
var actions: Array = []
var blueprint_buttons: Array = []
var previews: Array = []
func _ready():
	position = Vector2.ZERO
	size = Vector2(1440,940)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in range(5):
		var index = i
		var button = Button.new()
		button.position = Vector2(405+i*130,434)
		button.size = Vector2(110,88)
		button.focus_mode = Control.FOCUS_NONE
		for state in ["normal","hover","pressed","disabled"]:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(1,1,1,0.08) if state == "hover" else Color.TRANSPARENT
			button.add_theme_stylebox_override(state,style)
		button.pressed.connect(func(): game.menu_action(index))
		add_child(button)
		actions.append(button)
	for i in range(game.Blueprints.IDS.size()):
		var id = game.Blueprints.IDS[i]
		var button = Button.new()
		button.position = Vector2(348+i*252,104)
		button.size = Vector2(240,156)
		button.focus_mode = Control.FOCUS_NONE
		for state in ["normal","hover","pressed","disabled"]:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(1,1,1,0.08) if state == "hover" else Color.TRANSPARENT
			button.add_theme_stylebox_override(state,style)
		button.pressed.connect(func(): game.apply_blueprint(id))
		add_child(button)
		blueprint_buttons.append(button)
		previews.append(game.Blueprints.layout(id))
	visible = false

func refresh():
	actions[1].disabled = not FileAccess.file_exists(game.checkpoint_path) and not FileAccess.file_exists(game.checkpoint_path+".bak")
	actions[2].disabled = game.menu_title
	for i in range(blueprint_buttons.size()):
		blueprint_buttons[i].disabled = not game.can_apply_blueprint() or game.Blueprints.IDS[i] not in game.history.unlocked
	queue_redraw()

func _draw():
	draw_rect(Rect2(0,0,1440,940),Color(0.04,0.06,0.04,0.86))
	draw_rect(Rect2(348,284,744,334),Color("414437"))
	draw_rect(Rect2(348,284,744,334),Color("cfad66"),false,2)
	draw_string(game.font,Vector2(553,370),"M.F.V. 03",HORIZONTAL_ALIGNMENT_LEFT,-1,46,Color("e4d7b2"))
	var kinds = ["play","load","save","reset","exit"]
	for i in range(kinds.size()):
		var at = Vector2(405+i*130,434)
		draw_rect(Rect2(at,Vector2(110,88)),Color("a7a084"),false,1)
		var tint = Color(1,1,1,0.25) if actions[i].disabled else Color.WHITE
		draw_texture_rect(game.pixel_icons.texture(kinds[i]),Rect2(at+Vector2(23,12),Vector2(64,64)),false,tint)
	if game.menu_status != "":
		draw_texture_rect(game.pixel_icons.texture(game.menu_status),Rect2(699,551,42,42),false)
	draw_string(game.font,Vector2(372,598),"Esc",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("a7a084"))

	for i in range(mini(3,game.history.entries.size())):
		var row = game.history.entries[i]
		var y = 666+i*64
		draw_rect(Rect2(348,y-28,744,54),Color("414437"))
		var kind = "victory" if row.phase == "won" else "retreat" if row.phase == "retreated" else "defeat"
		draw_texture_rect(game.pixel_icons.texture(kind),Rect2(368,y-20,40,40),false)
		draw_string(game.font,Vector2(430,y+8),"#"+row.seed,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("e4d7b2"))
		draw_string(game.font,Vector2(760,y+8),"%d / 5" % row.cleared,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("cfad66"))
		draw_texture_rect(game.pixel_icons.texture("press"),Rect2(890,y-20,40,40),false)
		draw_string(game.font,Vector2(954,y+8),str(int(row.shells)),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("e4d7b2"))
	if game.history.error:
		draw_texture_rect(game.pixel_icons.texture("defeat"),Rect2(1050,560,28,28),false)

	for i in range(blueprint_buttons.size()):
		var id = game.Blueprints.IDS[i]
		var unlocked = id in game.history.unlocked
		var at = Vector2(348+i*252,104)
		var selected = game.Blueprints.matches(game.factory.layout(),id)
		draw_rect(Rect2(at,Vector2(240,156)),Color("414437"))
		draw_rect(Rect2(at,Vector2(240,156)),Color("cfad66") if selected else Color("778365"),false,2)
		var tint = Color.WHITE if not blueprint_buttons[i].disabled else Color(1,1,1,0.35)
		draw_texture_rect(game.pixel_icons.texture("example" if unlocked else "lock"),Rect2(at+Vector2(12,10),Vector2(32,32)),false)
		if unlocked:
			draw_texture_rect(game.pixel_icons.texture("depot" if id == "buffered" else "press"),Rect2(at+Vector2(155,12),Vector2(24,24)),false)
			draw_string(game.font,at+Vector2(185,32),"×"+str(1 if id == "standard" else 2),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("cfad66"))
		if not unlocked:
			draw_texture_rect(game.pixel_icons.texture("victory"),Rect2(at+Vector2(165,12),Vector2(24,24)),false)
			draw_string(game.font,at+Vector2(199,32),str(game.Blueprints.REQUIREMENTS[id]),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("cfad66"))
		var origin = at+Vector2(34,48)
		for y in range(8):
			for x in range(14): draw_rect(Rect2(origin+Vector2(x,y)*12,Vector2(11,11)),Color("252820"))
		for row in previews[i]:
			draw_set_transform(origin+Vector2(row[0],row[1])*12+Vector2(6,6),row[3]*PI/2)
			draw_texture_rect(game.pixel_icons.texture(row[2]),Rect2(-6,-6,12,12),false,tint)
			draw_set_transform(Vector2.ZERO)
		for pos in game.Factory.PORTS:
			draw_texture_rect(game.pixel_icons.texture(game.Factory.PORTS[pos]),Rect2(origin+Vector2(pos)*12,Vector2(12,12)),false,tint)
