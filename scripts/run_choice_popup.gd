extends Control
## Modal expedition choices, above the scene and below the Esc menu.
const PANEL_RECT = Rect2(368,230,704,480)
var game
var buttons: Array = []
var continue_button: Button
var craft_page = 0
var page_buttons: Array = []

func craft_id(index: int) -> String:
	var offset = craft_page*3+index
	return game.RunState.ENEMY_RECIPES[offset] if offset < game.RunState.ENEMY_RECIPES.size() else ""

func route_threats(route: Dictionary, all_types: bool = false) -> String:
	if not route.has("enemies"):
		return {"patrol":"混成","raiders":"襲撃隊","battery":"重砲隊"}[route.get("formation","patrol")]
	var tier = 0
	var names: Array[String] = []
	for role in route.enemies:
		var enemy = game.RunState.Content.ENEMIES[role]
		if not all_types and enemy.tier > tier:
			tier = enemy.tier
			names.clear()
		if (all_types or enemy.tier == tier) and enemy.name not in names: names.append(enemy.name)
	return "・".join(names if all_types else names.slice(0,2))

func _ready():
	size = Vector2(1440,940)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in range(3):
		var index = i
		var button = Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal","hover","pressed","disabled"]:
			button.add_theme_stylebox_override(state,game.style(Color(1,1,1,0.08) if state in ["hover","pressed"] else Color.TRANSPARENT))
		button.pressed.connect(func(): game.choose_run_option(index))
		add_child(button)
		buttons.append(button)
	continue_button = Button.new()
	continue_button.position = Vector2(864,658)
	continue_button.size = Vector2(184,36)
	continue_button.text = "次へ"
	continue_button.add_theme_font_override("font",game.font)
	continue_button.add_theme_font_size_override("font_size",20)
	continue_button.add_theme_stylebox_override("normal",game.style(game.SURFACE,game.GOLD))
	continue_button.pressed.connect(func(): game.finish_crafting())
	add_child(continue_button)
	for change in [-1,1]:
		var step = change
		var button = Button.new()
		button.text = "←" if step < 0 else "→"
		button.position = Vector2(660 if step < 0 else 750,658)
		button.size = Vector2(74,36)
		button.pressed.connect(func():
			craft_page = clampi(craft_page+step,0,ceili(game.RunState.ENEMY_RECIPES.size()/3.0)-1)
			refresh())
		add_child(button)
		page_buttons.append(button)
	refresh()

func option_rect(index: int) -> Rect2:
	if game.expedition.phase == "craft": return Rect2(392,330+index*104,656,96)
	if game.expedition.phase == "route" and game.expedition.route_options.size() == 3: return Rect2(392,330+index*104,656,96)
	return Rect2(392,330+index*146,656,132) if game.expedition.phase == "route" else Rect2(392,330+index*112,656,96)

func refresh():
	visible = game.expedition.phase in ["craft","reward","route"]
	var crafting = game.expedition.phase == "craft"
	continue_button.visible = crafting
	for i in range(page_buttons.size()):
		page_buttons[i].visible = crafting
		page_buttons[i].disabled = craft_page == (0 if i == 0 else ceili(game.RunState.ENEMY_RECIPES.size()/3.0)-1)
	continue_button.text = "遠征を完了" if game.expedition.sector == game.RunState.SECTORS else "次へ"
	for i in range(buttons.size()):
		buttons[i].position = option_rect(i).position
		buttons[i].size = option_rect(i).size
		buttons[i].visible = visible and (game.expedition.phase != "route" or i < game.expedition.route_options.size()) and (not crafting or craft_id(i) != "") and (game.expedition.phase != "reward" or i < game.expedition.reward_options.size())
		buttons[i].disabled = crafting and not game.expedition.can_craft(craft_id(i),game.factory.reserves)
		if game.expedition.phase == "reward" and i < game.expedition.reward_options.size(): buttons[i].disabled = not game.can_claim_reward(game.expedition.reward_options[i])
		buttons[i].tooltip_text = ""
		if game.expedition.phase == "route" and i < game.expedition.route_options.size():
			var route = game.expedition.route_options[i]
			var surface = game.RunState.condition(route)
			buttons[i].tooltip_text = "%s\n%d両 / %dm / %.1fm/s / 燃料 ×%.2f" % [route_threats(route,true),game.RunState.enemy_count(route),route.length,surface.speed,surface.fuel]
		if crafting and game.Factory.AUXILIARY.has(craft_id(i)) and not game.factory.inside(game.factory.install_position(craft_id(i))): buttons[i].disabled = true
	queue_redraw()

func label(value: String, at: Vector2, font_size: int = 20, color: Color = Color.WHITE):
	draw_string(game.font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func icon(kind: String, at: Vector2, side: float = 28):
	draw_texture_rect(game.pixel_icons.texture(kind),Rect2(at,Vector2.ONE*side),false)

func stat(kind: String, value: String, at: Vector2):
	icon(kind,at,24)
	label(value,at+Vector2(32,20),18,game.INK)

func _draw():
	if not visible: return
	draw_rect(Rect2(0,0,1440,940),Color(0.045,0.055,0.04,0.78))
	draw_style_box(game.style(game.PANEL,game.EDGE),PANEL_RECT)
	draw_rect(Rect2(PANEL_RECT.position,Vector2(PANEL_RECT.size.x,4)),game.GOLD)
	var reward_phase = game.expedition.phase == "reward"
	var crafting = game.expedition.phase == "craft"
	label("装備を製作" if crafting else "報酬を選択" if reward_phase else "次の経路を選択",Vector2(396,284 if crafting else 292),28,game.INK)
	if crafting:
		label("%d / %d" % [craft_page+1,ceili(game.RunState.ENEMY_RECIPES.size()/3.0)],Vector2(660,288),18,game.MUTED)
		stat("scrap",str(game.factory.reserves.scrap),Vector2(800,267))
		stat("coal",str(game.factory.reserves.coal),Vector2(936,267))
	for i in range(game.expedition.route_options.size() if game.expedition.phase == "route" else game.expedition.reward_options.size() if reward_phase else 3):
		if crafting and craft_id(i) == "": continue
		var rect = option_rect(i)
		var at = rect.position
		draw_style_box(game.style(game.SURFACE,game.EDGE),rect)
		draw_rect(Rect2(at+Vector2(0,12),Vector2(3,rect.size.y-24)),game.GOLD)
		if crafting:
			var id: String = craft_id(i)
			var recipe: Dictionary = game.RunState.EQUIPMENT[id]
			var cost = game.expedition.craft_cost(id)
			var known = id in game.expedition.recipes
			var installed = id in game.expedition.equipment
			icon(recipe.icon,at+Vector2(16,24),40)
			label(recipe.name,at+Vector2(72,29),22,game.INK if known else game.MUTED)
			label(recipe.effect,at+Vector2(72,55),16,game.MUTED)
			label("廃材 %d / 石炭 %d" % [cost.scrap,cost.coal],at+Vector2(72,80),17,game.GOLD if known else game.MUTED)
			var no_space = game.Factory.AUXILIARY.has(id) and not game.factory.inside(game.factory.install_position(id))
			var status = "装着済み" if installed else "レシピ未獲得" if not known else "空き区画なし" if no_space else "資源不足" if buttons[i].disabled else "製作・装着"
			label(status,at+Vector2(480,56),18,game.MUTED if buttons[i].disabled else game.GOLD)
			if id in game.expedition.stage_recipes and not installed: label("NEW",at+Vector2(360,29),15,game.GOLD)
		elif reward_phase:
			var reward = game.expedition.reward_options[i]
			var info = game.RunState.Content.reward_info(reward)
			icon(info.icon,at+Vector2(20,24),48)
			var title: String = info.name
			if reward.begins_with("block:"):
				var kind = reward.trim_prefix("block:")
				var count = mini(game.RunState.Content.block_bundle(kind),game.Factory.LIMITS[kind]-game.factory.inventory[kind])
				title += " ×%d" % count
				label("所持 %d" % game.factory.inventory[kind],at+Vector2(510,37),17,game.MUTED)
			elif reward.begins_with("gear:"):
				label("装備",at+Vector2(550,37),17,game.MUTED)
			label(title,at+Vector2(88,37),22,game.INK)
			label(info.effect,at+Vector2(88,68),17,game.GOLD)
		else:
			var route: Dictionary = game.expedition.route_options[i]
			var surface = game.RunState.condition(route)
			label({"scrapyard":"車両墓場","coalfield":"炭鉱","arsenal":"兵器庫"}[route.kind],at+Vector2(20,30),22,game.INK)
			var terrain_name = {"road":"道路","mud":"泥濘","rubble":"瓦礫"}[route.get("terrain","road")]
			label(terrain_name+" / "+route_threats(route),at+Vector2(202,30),17,game.MUTED)
			stat("scrap",str(route.scrap),at+Vector2(20,48))
			stat("coal",str(route.coal),at+Vector2(180,48))
			stat("shell",str(route.shells),at+Vector2(340,48))
			stat(route.get("formation","patrol"),str(game.RunState.total_health(route)),at+Vector2(500,48))
			if rect.size.y < 120: continue
			stat("move","%dm" % int(route.length),at+Vector2(20,90))
			stat(route.get("terrain","road"),"%.1fm/s" % surface.speed,at+Vector2(180,90))
			stat("fuel","×%.2f" % surface.fuel,at+Vector2(340,90))
	label("Esc  メニュー",Vector2(396,688),15,game.MUTED)
