extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
const Services = preload("res://scripts/field_services.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS services: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var model = Run.new(42)
	var standard = model.make_route("scrapyard")
	var rich = model.make_route("scrapyard",false,"rich")
	var hostile = model.make_route("scrapyard",false,"hostile")
	check(rich.scrap == standard.scrap*2 and rich.coal == standard.coal*2,"rich destination doubles real supply quantities")
	check(Run.enemy_count(hostile) == Run.enemy_count(standard)+6 and hostile.scrap > standard.scrap,"hostile destination adds six actual defenders and extra salvage")
	var seen = {}
	for seed_value in range(24):
		var course = Run.FieldCourse.new(Run.new(seed_value).current)
		for site in course.destinations:
			seen[site.encounter] = true
			check(Services.icon(site) == Services.ICONS[site.encounter],"encounter has a shared world/map icon")
	check(seen.size() == 3,"all three encounter types appear")
	var schema = preload("res://scripts/run_snapshot_schema.gd").new()
	for difficulty in ["easy","normal","hard"]:
		model.difficulty = difficulty
		model.sector = 5
		for encounter in ["rich","hostile","shop"]:
			check(schema.valid_route(model.make_route("coalfield",false,encounter)),"final encounter remains saveable: "+difficulty+"/"+encounter)
	var armor = Factory.new()
	armor.combat_editing = true
	armor.reserves = {"scrap":100,"coal":100}
	var plate = Vector2i(13,7)
	armor.edit(plate,"armor_block",0)
	armor.cells[plate].armor_hp = 1
	var stock = armor.reserves.scrap
	armor.rotate(plate)
	check(armor.cells[plate].armor_hp == 1 and armor.reserves.scrap == stock,"rotation preserves damaged armor without charging materials")
	var armor_rows = armor.layout()
	for row in armor_rows:
		if row[2] == "armor_block": row[3] = 2
	check(armor.restore(armor_rows) and armor.cells[plate].armor_hp == 1,"live layout restore cannot reset damaged armor")
	armor.edit(plate,"erase",0)
	check(armor.reserves.scrap == stock+1,"damaged armor salvages only its remaining durability")
	armor.undo()
	check(armor.cells[plate].armor_hp == 3 and armor.reserves.scrap == stock-4,"rebuilding armor pays the lost durability instead of free repair")
	armor.install_auxiliary("left_gun")
	armor.cells[armor.auxiliary_position("left_gun")].items = ["shell","shell"]
	armor.move_auxiliary("left_gun",Vector2i(13,6))
	armor.undo()
	check(armor.auxiliary_position("left_gun") == armor.AUXILIARY.left_gun and armor.auxiliary_ammo("left_gun") == 2,"undoing live auxiliary relocation preserves its loaded ammunition")
	var reserve = Factory.new()
	reserve.combat_editing = true
	reserve.reserves = {"scrap":1000,"coal":1000}
	reserve.clear_layout(false,false)
	for x in range(reserve.LIMITS.furnace): reserve.edit(Vector2i(x+1,1),"furnace",0)
	var broken = Vector2i(1,1)
	reserve.damage_at(Vector2(broken.x-6.5,broken.y-3.5))
	check(reserve.wrecks.has(broken) and not reserve.can_place(Vector2i(13,7),"furnace"),"wrecks reserve capacity so repair cannot exceed the block limit")
	reserve.edit(broken,"furnace",0)
	check(not reserve.wrecks.has(broken) and reserve.count_kind("furnace") == reserve.LIMITS.furnace,"rebuilding a wreck reuses its reserved capacity")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"field_services_test")
	game.show_start_menu = false
	root.size = Vector2i(1440,940)
	root.add_child(game)
	game.set_process(false)
	game.ensure_battle()
	# Force a known shop destination by selecting an actual generated yard.
	var shop_index = -1
	for seed_value in range(24):
		game.reset_battle(seed_value)
		for i in range(game.battlefield.field_course.destinations.size()):
			if game.battlefield.field_course.destinations[i].encounter == "shop": shop_index = i
		if shop_index >= 0: break
	game.toggle_running()
	check(game.can_manage_layout() and not game.factory.layout_locked and game.factory.combat_editing,"departure permits live editing")
	game.toggle_battle()
	var f = game.factory
	f.reserves = {"scrap":150,"coal":100}
	f.ammo = 5
	f.fuel = 6
	f.cells[Vector2i(2,2)].items = ["scrap"]
	f.cells[Vector2i(2,2)].work = 1
	game.selected = "belt"
	game.paint(Vector2i(13,7),false)
	check(f.cells.has(Vector2i(13,7)) and f.running and f.ammo == 5 and f.fuel == 6 and f.cells[Vector2i(2,2)].work == 1,"live placement preserves running state, loaded ammo, fuel and untouched processing")
	var rows = f.layout()
	check(f.restore(rows) and f.ammo == 5 and f.fuel == 6 and f.cells[Vector2i(2,2)].items == ["scrap"],"live layout restore preserves matching buffers and vehicle supplies")
	var target = Vector2i(4,2)
	f.damage_at(Vector2(target.x-6.5,target.y-3.5))
	game.battlefield.hull = 70
	game.field_actions.refresh()
	check(game.field_actions.visible and not game.field_actions.RECT.intersects(game.FOOTER_RECT) and not game.field_actions.RECT.intersects(game.HEADER_RECT),"damage exposes repair button outside the toolbar and header")
	var cost = Services.repair_cost(f,70)
	f.reserves.scrap = cost-1
	check(not game.repair_vehicle() and f.wrecks.has(target) and game.battlefield.hull == 70,"insufficient repair stock leaves all damage untouched")
	f.reserves.scrap = cost
	check(game.repair_vehicle() and f.reserves.scrap == 0 and f.wrecks.is_empty() and game.battlefield.hull == 100 and f.cells.has(target),"repair atomically charges scrap and restores hull and broken line")
	check(f.running and f.ammo == 5 and f.fuel == 6 and not game.field_actions.visible,"repair preserves combat and supplies, then hides its button")
	var mid = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,mid) and not game.factory.layout_locked and game.factory.combat_editing and not game.factory.running,"saved live edits restore unlocked and paused")
	game.toggle_running()
	game.battlefield.player.position = game.battlefield.goals[shop_index].position+Vector3(2,0,0)
	game._process(0)
	game.choose_run_option(0)
	check(game.expedition.phase == "shop" and game.shop_panel.visible and not game.factory.running,"physical shop arrival opens purchases after the clear reward")
	f = game.factory
	f.reserves.scrap = 0
	var coal_before = f.reserves.coal
	check(not game.buy_shop_item(0) and f.reserves.coal == coal_before and not game.expedition.current.shop_purchased[0],"unaffordable purchase is atomic")
	f.reserves.scrap = 100
	game.shop_panel.refresh()
	await click(game.shop_panel.buttons[0].get_rect().get_center())
	check(f.reserves.coal == coal_before+24 and f.reserves.scrap == 88,"real shop click exchanges actual scrap for supplies")
	check(not game.buy_shop_item(0) and f.reserves.scrap == 88,"shop stock cannot be bought twice")
	f.ammo = f.ammo_capacity
	check(not game.buy_shop_item(1),"full magazine cannot waste scrap on ammo")
	f.ammo = 0
	check(game.buy_shop_item(1) and f.ammo == 12 and f.reserves.scrap == 78,"ammo purchase fills the real main-gun magazine")
	var gear: String = game.expedition.current.shop_offers[2].trim_prefix("gear:")
	check(game.buy_shop_item(2) and gear in game.expedition.equipment and f.reserves.scrap == 46,"equipment purchase installs the offered upgrade")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved) and game.shop_panel.visible and not game.buy_shop_item(2),"shop offers and receipts survive checkpoint without rerolls or duplicate purchases")
	var bad = saved.duplicate(true)
	bad.run.current.shop_purchased[0] = 1
	check(not game.checkpoint.validate(bad),"malformed shop receipts are rejected")
	await capture(game,"res://build/services-audit/shop-1440.png")
	root.size = Vector2i(960,628)
	await process_frame
	await capture(game,"res://build/services-audit/shop-960.png")
	game.leave_shop()
	check(game.expedition.phase == "prepare" and not game.started and not game.shop_panel.visible and game.expedition.current.encounter == "shop","leaving shop resumes the selected next encounter")
	game.toggle_running()
	game.toggle_battle()
	game.factory.damage_at(Vector2(-2.5,-1.5))
	game.battlefield.hull = 80
	game.factory.reserves.scrap = 100
	game.field_actions.refresh()
	await capture(game,"res://build/services-audit/repair-960.png")
	# Actual button input at minimum window size.
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = root.get_final_transform()*game.field_actions.RECT.get_center()
	root.push_input(press,false)
	press = press.duplicate()
	press.pressed = false
	root.push_input(press,false)
	await process_frame
	check(game.battlefield.hull == 100 and game.factory.wrecks.is_empty(),"minimum-window repair button accepts real click input")
	var final_run = Run.new(0)
	final_run.sector = 5
	final_run.modifiers.routes = 3
	final_run.current = final_run.make_route("scrapyard")
	var final_course = Run.FieldCourse.new(final_run.current)
	var final_shop = -1
	for i in range(final_course.destinations.size()):
		if final_course.destinations[i].encounter == "shop": final_shop = i
	check(final_shop >= 0,"final-stage shop fixture is a physical destination")
	final_run.start_sector()
	final_run.finish_sector(true,100,{},true,final_shop)
	final_run.finish_crafting()
	final_run.choose_reward(0)
	check(final_run.phase == "shop" and final_run.finish_shopping() and final_run.phase == "won" and not final_run.finish_shopping(),"final-stage shop finishes the run exactly once")
	game.queue_free()
	await process_frame
	print("FIELD SERVICES RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func capture(game, path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func click(point: Vector2):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = root.get_final_transform()*point
	root.push_input(event,false)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,false)
	await process_frame
func _finalize(): Fixture.clean("field_services_test")
