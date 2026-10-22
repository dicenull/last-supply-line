extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment UI: ",label)
	else:
		failures += 1
		push_error(label)
func mouse(pos: Vector2, pressed: bool):
	var e = InputEventMouseButton.new()
	e.position = root.get_final_transform()*pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	root.push_input(e,false)
	await process_frame
func motion(pos: Vector2, held: bool):
	var e = InputEventMouseMotion.new()
	e.position = root.get_final_transform()*pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(e,false)
	game._process(0)
	await process_frame
func click(b):
	var p = b.get_global_rect().get_center()
	await motion(p,false)
	await mouse(p,true)
	await mouse(p,false)
	game._process(0)
func screen(p: Vector2i) -> Vector2:
	return game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(p)+Vector3(0,0.03,0))
func capture(label):
	game._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/equipment-audit/"+label+".png")
func drag(row, at: Vector2i):
	var start = row.get_global_rect().get_center()
	await motion(start,false)
	await mouse(start,true)
	await motion(start-Vector2(30,0),true)
	await motion(screen(at),true)
	await capture("drag-"+str(root.size.x))
	await mouse(screen(at),false)
	game._process(0)
func run():
	DirAccess.make_dir_recursive_absolute("res://build/equipment-audit")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_ui_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		await process_frame
		game.ensure_battle()
		game.reset_battle(42)
		game._process(0)
		await capture("starter-layout-"+str(dimensions.x))
		await click(game.inventory_button)
		check(game.inventory_panel.visible and game.inventory_panel.rows.size() == 3,"inventory opens via footer at "+str(dimensions.x))
		await capture("inventory-"+str(dimensions.x))
		var uid = game.expedition.gear_items[0].uid
		await drag(game.inventory_panel.row_buttons[0],Vector2i(0,0))
		check(game.factory.equipment_mounts.get("left_gun") == Vector2i(0,0),"real drag and release places gun on grid at "+str(dimensions.x))
		check(game.dragging_item == -1 and not game.inventory_panel.visible,"drop completes and leaves deck visible")
		check(game.world.auxiliary_guns.size() == 1 and game.world.auxiliary_guns[0].pivot.position == game.world.cell_position(Vector2i(0,0))+Vector3(0.5,0.28,0.5),"gun model is centered on its full 2×2 footprint")
		await capture("installed-"+str(dimensions.x))
		game.world.toggle_roof()
		await motion(Vector2(700,850),false)
		await capture("exterior-installed-"+str(dimensions.x))
		game.world.toggle_roof()
		await click(game.inventory_button)
		await drag(game.inventory_panel.row_buttons[1],Vector2i(1,1))
		check(game.expedition.gear_items[1].position == Vector2i(-1,-1),"overlapping drop leaves inventory untouched")
		await click(game.inventory_button)
		var stock = game.factory.reserves.duplicate()
		await click(game.inventory_panel.salvage_buttons[2])
		check(game.expedition.gear_items.size() == 2 and game.factory.reserves.scrap > stock.scrap and game.factory.reserves.coal > stock.coal,"real salvage button grants materials")
		check(game.logistics.notices.scrap.accepted == game.factory.reserves.scrap-stock.scrap and game.logistics.notices.coal.accepted == game.factory.reserves.coal-stock.coal,"dismantling reports both material gains in the header")
		await click(game.inventory_panel.stow_buttons[0])
		check(game.factory.equipment_mounts.is_empty() and game.expedition.equipment.is_empty(),"real stow button removes mounted effects")
		await drag(game.inventory_panel.row_buttons[0],Vector2i(0,0))
		game.toggle_running()
		game.toggle_running()
		game.toggle_battle()
		await click(game.inventory_button)
		check(game.inventory_panel.visible and game.inventory_panel.stow_buttons[0].disabled and game.inventory_panel.salvage_buttons[0].disabled,"departed loadout shows disabled removal and dismantling")
		var locked_layout = game.factory.layout()
		await drag(game.inventory_panel.row_buttons[0],Vector2i(2,0))
		check(game.factory.equipment_mounts.get("left_gun") == Vector2i(0,0) and game.dragging_item < 0,"drag cannot bypass departure lock while paused")
		check(game.factory.layout() == locked_layout,"rejected equipment drag cannot accidentally paint a conveyor")
		await capture("locked-"+str(dimensions.x))
		game.inventory_panel.hide()
		game.reset_battle(42)
		game.place_item(game.expedition.gear_items[0].uid,Vector2i(0,0))
		game.expedition.add_item({"kind":"left_gun","rarity":"rare"})
		await click(game.inventory_button)
		var duplicate_layout = game.factory.layout()
		await drag(game.inventory_panel.row_buttons[3],Vector2i(3,0))
		check(game.inventory_panel.visible and game.dragging_item < 0 and game.factory.layout() == duplicate_layout,"duplicate-family drag remains in inventory and paints nothing")
		game.inventory_panel.hide()
		game.begin_item_drag(game.expedition.gear_items[1].uid)
		var e = InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.pressed = true
		root.push_input(e)
		await motion(screen(Vector2i(3,0)),true)
		await mouse(screen(Vector2i(3,0)),false)
		check(game.dragging_item < 0 and not game.menu.visible and game.factory.layout() == duplicate_layout,"Escape cancels item drag without opening menu or painting")
		game.begin_item_drag(game.expedition.gear_items[1].uid)
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(game.dragging_item < 0 and not game.world.equipment_preview.visible,"focus loss clears the placement ghost and item capture")
		root.push_input(e)
		await process_frame
		check(game.menu.visible,"keyboard menu remains usable after focus loss cancels a held drag")
		game.close_menu()
		for id in game.Inventory.Catalog.DEFINITIONS:
			for rarity in game.Inventory.Catalog.RARITIES: game.expedition.add_item({"kind":id,"rarity":rarity})
		await click(game.inventory_button)
		await click(game.inventory_panel.tabs[1])
		check(game.inventory_panel.rows.all(func(item): return game.Inventory.Catalog.DEFINITIONS[item.kind].genre == "secondary"),"genre tab filters all rarity variants")
		var first_page = game.inventory_panel.rows.duplicate()
		await click(game.inventory_panel.next)
		check(game.inventory_panel.page == 1 and game.inventory_panel.rows != first_page,"large inventory advances to distinct pages")
		await click(game.inventory_panel.tabs[2])
		check(game.inventory_panel.page == 0 and game.inventory_panel.rows.all(func(item): return game.Inventory.Catalog.DEFINITIONS[item.kind].genre == "protection"),"changing genre resets pagination")
		await capture("rarities-"+str(dimensions.x))
		await click(game.inventory_panel.sort_button)
		var descending = true
		for i in range(1,game.inventory_panel.rows.size()):
			descending = descending and game.Inventory.Catalog.RARITIES[game.inventory_panel.rows[i-1].rarity].power >= game.Inventory.Catalog.RARITIES[game.inventory_panel.rows[i].rarity].power
		check(game.inventory_panel.quality_order and descending,"quality sorting brings stronger equipment to the first page")
		var before_bulk = game.expedition.gear_items.duplicate(true)
		var bulk_stock = game.factory.reserves.duplicate()
		await click(game.inventory_panel.bulk_button)
		check(game.inventory_panel.bulk_quote.count == 3 and game.inventory_panel.bulk_quote.scrap == 16 and game.inventory_panel.bulk_quote.coal == 9,"bulk preview quotes only the three stowed normal protection items")
		check(game.inventory_panel.rows.size() == 3 and game.inventory_panel.rows.all(func(item): return item.uid in game.inventory_panel.bulk_uids) and game.inventory_panel.salvage_buttons.all(func(button): return button.disabled or not button.visible),"bulk preview shows only reviewed items and disables individual destructive actions")
		await capture("bulk-preview-"+str(dimensions.x))
		await click(game.inventory_panel.cancel_button)
		check(game.expedition.gear_items == before_bulk and game.factory.reserves == bulk_stock and game.inventory_panel.bulk_quote.is_empty(),"bulk preview cancellation changes no items or materials")
		await click(game.inventory_panel.bulk_button)
		var reviewed = game.inventory_panel.bulk_uids.duplicate()
		game.receive_item({"kind":"armor","rarity":"normal"})
		var arrived = game.expedition.gear_items.back().uid
		game._process(0)
		check(game.inventory_panel.bulk_uids == reviewed and game.inventory_panel.bulk_quote.count == 3,"new loot does not enter an already reviewed bulk selection")
		await click(game.inventory_panel.confirm_button)
		check(reviewed.all(func(id): return game.Inventory.find_item(game.expedition,id).is_empty()) and not game.Inventory.find_item(game.expedition,arrived).is_empty() and game.factory.reserves.scrap == bulk_stock.scrap+16 and game.factory.reserves.coal == bulk_stock.coal+9,"confirmed bulk action grants the previewed materials and keeps later arrivals")
		await click(game.inventory_panel.tabs[0])
		await click(game.inventory_panel.bulk_button)
		var preview_first = game.inventory_panel.rows.duplicate()
		var preview_ids = game.inventory_panel.bulk_uids.duplicate()
		await click(game.inventory_panel.next)
		check(game.inventory_panel.page == 1 and game.inventory_panel.rows != preview_first and game.inventory_panel.rows.all(func(item): return item.uid in preview_ids),"large bulk preview pages through the reviewed selection")
		await click(game.inventory_panel.cancel_button)
		check(game.inventory_panel.bulk_uids.is_empty() and game.inventory_panel.next.position == Vector2(296,660) and game.inventory_panel.next.size == Vector2(80,40),"cancelling preview restores ordinary inventory navigation")
		game.inventory_panel.hide()
		game.reset_battle(42)
		game.toggle_running()
		game.factory.running = false
		await click(game.inventory_button)
		await click(game.inventory_panel.sort_button)
		var pressed_at = game.inventory_panel.salvage_buttons[2].get_global_rect().get_center()
		await motion(pressed_at,false)
		await mouse(pressed_at,true)
		game.receive_item({"kind":"mortar_gun","rarity":"legendary"})
		game._process(0)
		await mouse(pressed_at,false)
		check(game.Inventory.find_item(game.expedition,2).is_empty() and not game.Inventory.find_item(game.expedition,1).is_empty() and game.expedition.gear_items.back().rarity == "legendary","loot reordering between press and release cannot dismantle the wrong item")
		game.inventory_panel.hide()
	game.reset_battle(42)
	game.toggle_running()
	game.factory.running = false
	game.expedition.phase = "shop"
	game.expedition.current.shop_offers = ["gear:armor","gear:economizer","gear:left_gun"]
	game.expedition.current.shop_purchased = [false,false,false]
	game.refresh_view()
	await click(game.shop_panel.inventory_button)
	check(game.inventory_panel.visible and game.inventory_panel.get_parent().layer > game.shop_panel.get_parent().layer,"shop opens a usable inventory above the modal")
	var before_shop = game.factory.reserves.scrap
	await click(game.inventory_panel.salvage_buttons[2])
	check(game.factory.reserves.scrap > before_shop,"shop inventory can dismantle equipment for purchase funds")
	await capture("shop-inventory-960")
	game.toggle_inventory()
	var purchase_funds = game.factory.reserves.scrap
	await click(game.shop_panel.buttons[0])
	check(game.expedition.current.shop_purchased[0] and game.factory.reserves.scrap == purchase_funds-game.RunState.Services.GEAR_PRICE and game.expedition.gear_items.back().rarity == "uncommon" and game.expedition.equipment.is_empty(),"shop purchase enters inventory without changing departed loadout")
	await click(game.shop_panel.buttons[0])
	check(game.factory.reserves.scrap == purchase_funds-game.RunState.Services.GEAR_PRICE,"purchased offer cannot be charged twice")
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_ui_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
