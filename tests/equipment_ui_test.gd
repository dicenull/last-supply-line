extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize():
	# Input is injected below. Ignore desktop pointer events so this suite can
	# run while the player is using a separate game window.
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment UI: ",label)
	else:
		failures += 1
		push_error(label)
func mouse(pos: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT):
	var e = InputEventMouseButton.new()
	e.position = root.get_final_transform()*pos
	e.button_index = button
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
	var parent = b.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(b)
			await process_frame
		parent = parent.get_parent()
	await process_frame
	var p = root.get_final_transform()*b.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = p
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
		if pressed:
			for i in range(6): game._process(0.016)
	game._process(0)
	await process_frame

func screen(p: Vector2i) -> Vector2:
	return game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(p)+Vector3(0,0.03,0))
func gun_screen() -> Vector2:
	var gun = game.world.auxiliary_guns[0]
	return game.WORLD_RECT.position+game.world.camera.unproject_position(gun.pivot.to_global(Vector3(-0.12,0.7,0)))
func capture(label):
	game._process(0)
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
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
	root.size = Vector2i(1440,940)
	DirAccess.make_dir_recursive_absolute("res://build/equipment-audit")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_ui_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": RenderingServer.force_draw()
	game.ensure_battle()
	game.reset_battle(42)
	game.toggle_inventory()
	for slot in game.Inventory.Catalog.PART_SLOTS:
		game.inventory_panel.select_tab(slot)
		check(game.inventory_panel.rows.size() == 1 and game.inventory_panel.rows[0].get("stock",false) and game.inventory_panel.rows[0].position != game.Inventory.STOWED and game.inventory_panel.equip_buttons[0].visible == (slot == "cannon") and not game.inventory_panel.action_buttons[0].disabled,"stock part is listed as equipped before removal: "+slot)
	game.inventory_panel.select_tab("")
	await click(game.inventory_panel.row_buttons[1])
	var selected_uid = game.expedition.gear_items[1].uid
	game.equipment_workspace.close_all()
	await motion(screen(Vector2i(0,0)),false)
	check(game.selected_item_uid == selected_uid and game.dragging_item == -1 and game.world.equipment_preview.visible,"click selection shows a placement preview without dragging")
	game.rotate_selection()
	await motion(screen(Vector2i(6,3)),false)
	check(game.world.equipment_preview.visible and game.world.equipment_preview_key.contains("false"),"occupied cells show the invalid preview")
	await mouse(screen(Vector2i(6,3)),true)
	await mouse(screen(Vector2i(6,3)),false)
	check(game.selected_item_uid == selected_uid and game.expedition.gear_items[1].position == game.Inventory.STOWED and game.item_direction == 1,"invalid click retains pending selection and rotation")
	await motion(screen(Vector2i(0,0)),false)
	await capture("click-placement-preview")
	await mouse(screen(Vector2i(0,0)),true)
	await mouse(screen(Vector2i(0,0)),false)
	game._process(0)
	check(game.factory.equipment_mounts.get("armor") == Vector2i.ZERO and game.factory.equipment_rotations.armor == 1 and game.selected_item_uid == selected_uid and not game.world.equipment_preview.visible and game.equipment_placement_uid() < 0,"valid click commits the preview once and switches to installed selection")
	var installed = game.factory.layout()
	await motion(screen(Vector2i(3,0)),true)
	check(game.factory.layout() == installed,"selected equipment cannot accidentally paint conveyor cells")
	game.stow_item(selected_uid)
	game.select_equipment(selected_uid)
	await motion(screen(Vector2i(0,0)),false)
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape,false)
	game._process(0)
	check(game.selected_item_uid == -1 and not game.world.equipment_preview.visible and not game.menu.visible,"Escape cancels pending placement and preview without opening a menu")
	root.min_size = Vector2i(320,320)
	var placement_geometry = {}
	for dimensions in [Vector2i(1440,940),Vector2i(844,390)]:
		root.size = dimensions
		await process_frame
		game._process(0)
		await process_frame
		var point = root.get_final_transform()*screen(Vector2i.ZERO)
		placement_geometry[str(dimensions.x)] = [point.x,point.y]
		check(game.cell_at(screen(Vector2i.ZERO)) == Vector2i.ZERO,"browser placement target projects back to its cell: "+str(dimensions.x))
	var geometry_file = FileAccess.open("res://build/equipment-audit/placement-geometry.json",FileAccess.WRITE)
	geometry_file.store_string(JSON.stringify(placement_geometry))
	geometry_file.close()
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
		var mount_offset: Vector2 = game.world.auxiliary_guns[0].mount_offset
		check(game.world.auxiliary_guns.size() == 1 and game.world.auxiliary_guns[0].pivot.position.is_equal_approx(game.world.cell_position(Vector2i(0,0))+Vector3(0.5+mount_offset.x*2,game.world.MOUNTED_GUN_Y,0.5+mount_offset.y*2)),"limited-traverse gun follows its computed pivot within the 2×2 reservation")
		await capture("installed-"+str(dimensions.x))
		game.factory.cells[Vector2i.ZERO].items = ["shell","shell","shell"]
		game.factory.edit(Vector2i(3,6),"belt",0)
		# Uncover the raised model before sending an actual world click.
		game.equipment_workspace.close_all()
		await mouse(gun_screen(),true,MOUSE_BUTTON_RIGHT)
		var right_drag = InputEventMouseMotion.new()
		right_drag.position = root.get_final_transform()*screen(Vector2i(3,6))
		right_drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
		root.push_input(right_drag,false)
		await process_frame
		check(game.factory.equipment_mounts.is_empty() and game.expedition.gear_items[0].position == Vector2i(-1,-1) and game.expedition.gear_items[0].ammo == 3,"right-clicking the actual raised model stores it with loaded ammunition")
		check(game.factory.cells.has(Vector2i(3,6)),"dragging after stowing cannot erase a neighboring production line")
		await mouse(screen(Vector2i(3,6)),false,MOUSE_BUTTON_RIGHT)
		# Taller world bounds also enlarge the comparison pane; uncover the line before clicking it.
		game.equipment_workspace.close_all()
		await mouse(screen(Vector2i(3,6)),true,MOUSE_BUTTON_RIGHT)
		await mouse(screen(Vector2i(3,6)),false,MOUSE_BUTTON_RIGHT)
		check(not game.factory.cells.has(Vector2i(3,6)),"a new right-click still removes ordinary line equipment")
		check(game.place_item(uid,Vector2i.ZERO) and game.factory.auxiliary_ammo("left_gun") == 3,"stowed equipment can be placed again without losing its rounds")
		game._process(0)
		game.world.toggle_roof()
		await motion(Vector2(700,850),false)
		await capture("exterior-installed-"+str(dimensions.x))
		game.world.toggle_roof()
		await click(game.inventory_button)
		await drag(game.inventory_panel.row_buttons[1],Vector2i(1,1))
		check(game.expedition.gear_items[1].position == Vector2i(-1,-1),"overlapping drop leaves inventory untouched")
		await click(game.inventory_button)
		var stock = game.factory.reserves.duplicate()
		await click(game.inventory_panel.action_buttons[2])
		check(game.expedition.gear_items.size() == 6 and game.factory.reserves.scrap > stock.scrap and game.factory.reserves.coal > stock.coal,"real salvage button grants materials")
		check(game.logistics.notices.get("scrap",{}).get("accepted",-1) == game.factory.reserves.scrap-stock.scrap and game.logistics.notices.get("coal",{}).get("accepted",-1) == game.factory.reserves.coal-stock.coal,"dismantling reports both material gains to the receipt system")
		var row_center = game.inventory_panel.row_buttons[0].get_global_rect().get_center()
		await mouse(row_center,true,MOUSE_BUTTON_RIGHT)
		await mouse(row_center,false,MOUSE_BUTTON_RIGHT)
		check(game.factory.equipment_mounts.is_empty(),"right-clicking an installed inventory row also returns it to storage")
		game.place_item(uid,Vector2i.ZERO)
		game.inventory_panel.refresh()
		await click(game.inventory_panel.action_buttons[0])
		check(game.factory.equipment_mounts.is_empty() and game.expedition.equipment.is_empty(),"real stow button removes mounted effects")
		await drag(game.inventory_panel.row_buttons[0],Vector2i(0,0))
		game.toggle_running()
		game.toggle_running()
		game.toggle_battle()
		await click(game.inventory_button)
		check(game.inventory_panel.visible and game.inventory_panel.equip_buttons[0].disabled and game.inventory_panel.action_buttons[0].disabled,"departed loadout shows disabled removal and dismantling")
		var locked_layout = game.factory.layout()
		await drag(game.inventory_panel.row_buttons[0],Vector2i(2,0))
		check(game.factory.equipment_mounts.get("left_gun") == Vector2i(0,0) and game.dragging_item < 0,"drag cannot bypass departure lock while paused")
		check(game.factory.layout() == locked_layout,"rejected equipment drag cannot accidentally paint a conveyor")
		# Uncover the raised model before sending an actual world click.
		game.equipment_workspace.close_all()
		await mouse(gun_screen(),true,MOUSE_BUTTON_RIGHT)
		await mouse(gun_screen(),false,MOUSE_BUTTON_RIGHT)
		check(game.factory.equipment_mounts.get("left_gun") == Vector2i.ZERO and game.factory.layout() == locked_layout,"right-click cannot bypass the deployed equipment lock")
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
		check(not game.equipment_workspace.visible,"Escape closes the remaining comparison pane")
		root.push_input(e)
		await process_frame
		check(game.menu.visible,"keyboard menu remains usable after closing the remaining comparison pane")
		game.close_menu()
		for id in game.Inventory.Catalog.DEFINITIONS:
			for rarity in game.Inventory.Catalog.RARITIES: game.expedition.add_item({"kind":id,"rarity":rarity})
		await click(game.inventory_button)
		await click(game.inventory_panel.tabs[1])
		check(game.inventory_panel.rows.all(func(item): return game.Inventory.Catalog.part_slot(item.kind) == "gear"),"genre tab filters all rarity variants")
		var first_page = game.inventory_panel.rows.duplicate()
		await click(game.inventory_panel.next)
		check(game.inventory_panel.page == 1 and game.inventory_panel.rows != first_page,"large inventory advances to distinct pages")
		await click(game.inventory_panel.tabs[2])
		check(game.inventory_panel.page == 0 and game.inventory_panel.rows.all(func(item): return game.Inventory.Catalog.part_slot(item.kind) == "engine"),"changing genre resets pagination")
		await capture("rarities-"+str(dimensions.x))
		await click(game.inventory_panel.sort_button)
		var descending = true
		for i in range(1,game.inventory_panel.rows.size()):
			descending = descending and game.Inventory.Catalog.RARITIES[game.inventory_panel.rows[i-1].rarity].power >= game.Inventory.Catalog.RARITIES[game.inventory_panel.rows[i].rarity].power
		check(game.inventory_panel.quality_order and descending,"quality sorting brings stronger equipment to the first page")
		var before_bulk = game.expedition.gear_items.duplicate(true)
		var bulk_stock = game.factory.reserves.duplicate()
		var expected_bulk = {"count":0,"scrap":0,"coal":0}
		for item in before_bulk:
			if game.Inventory.Catalog.part_slot(item.kind) != "engine" or item.rarity != "normal" or item.position != game.Inventory.STOWED: continue
			expected_bulk.count += 1
			var materials = game.Inventory.Catalog.salvage(item)
			expected_bulk.scrap += materials.scrap
			expected_bulk.coal += materials.coal
		await click(game.inventory_panel.bulk_button)
		check(game.inventory_panel.bulk_quote == expected_bulk,"bulk preview quotes every stowed normal engine part, including historical designs")
		check(game.inventory_panel.rows.size() == mini(expected_bulk.count,game.inventory_panel.page_size) and game.inventory_panel.rows.all(func(item): return item.uid in game.inventory_panel.bulk_uids) and game.inventory_panel.action_buttons.all(func(button): return button.disabled or not button.visible),"bulk preview shows only reviewed items and disables individual destructive actions")
		await capture("bulk-preview-"+str(dimensions.x))
		await click(game.inventory_panel.cancel_button)
		check(game.expedition.gear_items == before_bulk and game.factory.reserves == bulk_stock and game.inventory_panel.bulk_quote.is_empty(),"bulk preview cancellation changes no items or materials")
		await click(game.inventory_panel.bulk_button)
		var reviewed = game.inventory_panel.bulk_uids.duplicate()
		game.receive_item({"kind":"armor","rarity":"normal"})
		var arrived = game.expedition.gear_items.back().uid
		game._process(0)
		check(game.inventory_panel.bulk_uids == reviewed and game.inventory_panel.bulk_quote.count == expected_bulk.count,"new loot does not enter an already reviewed bulk selection")
		await click(game.inventory_panel.confirm_button)
		check(reviewed.all(func(id): return game.Inventory.find_item(game.expedition,id).is_empty()) and not game.Inventory.find_item(game.expedition,arrived).is_empty() and game.factory.reserves.scrap == bulk_stock.scrap+expected_bulk.scrap and game.factory.reserves.coal == bulk_stock.coal+expected_bulk.coal,"confirmed bulk action grants the previewed materials and keeps later arrivals")
		await click(game.inventory_panel.tabs[0])
		await click(game.inventory_panel.bulk_button)
		var preview_first = game.inventory_panel.rows.duplicate()
		var preview_ids = game.inventory_panel.bulk_uids.duplicate()
		await click(game.inventory_panel.next)
		check(game.inventory_panel.page == 1 and game.inventory_panel.rows != preview_first and game.inventory_panel.rows.all(func(item): return item.uid in preview_ids),"large bulk preview pages through the reviewed selection")
		await click(game.inventory_panel.cancel_button)
		check(game.inventory_panel.bulk_uids.is_empty() and game.inventory_panel.next.position == Vector2(296,game.inventory_panel.size.y-44) and game.inventory_panel.next.size == Vector2(80,40),"cancelling preview restores ordinary inventory navigation")
		game.inventory_panel.hide()
		game.reset_battle(42)
		game.toggle_running()
		game.factory.running = false
		await click(game.inventory_button)
		await click(game.inventory_panel.sort_button)
		var pressed_at = game.inventory_panel.action_buttons[2].get_global_rect().get_center()
		await motion(pressed_at,false)
		await mouse(pressed_at,true)
		game.receive_item({"kind":"mortar_gun","rarity":"legendary"})
		game._process(0)
		await mouse(pressed_at,false)
		check(game.Inventory.find_item(game.expedition,2).is_empty() and not game.Inventory.find_item(game.expedition,1).is_empty() and game.expedition.gear_items.back().rarity == "legendary","loot reordering between press and release cannot dismantle the wrong item")
		game.battlefield.hull = 70
		game.factory.cells[Vector2i(1,0)] = game.factory.make_cell("belt",0)
		game.factory.wrecks[Vector2i(1,0)] = "belt"
		game.factory.wreck_directions[Vector2i(1,0)] = 0
		game.factory.cells.erase(Vector2i(1,0))
		game.factory.reserves.scrap = 100
		game.field_actions.refresh()
		var repair_rect = game.field_actions.button.get_global_rect()
		check(game.field_actions.visible and not repair_rect.intersects(game.inventory_panel.get_global_rect()) and not repair_rect.intersects(game.footer_rect()) and not repair_rect.intersects(game.HEADER_RECT),"repair stays outside the inventory, header and footer when the vehicle is damaged")
		await capture("inventory-repair-"+str(dimensions.x))
		var repair_cost = game.repair_state().cost
		var repair_layout_size = game.factory.layout().size()
		var repair_items = game.expedition.gear_items.duplicate(true)
		await click(game.field_actions.button)
		check(game.battlefield.hull == 70 and game.factory.reserves.scrap == 100-repair_cost and game.inventory_panel.visible and game.expedition.gear_items == repair_items and game.factory.layout().size() == repair_layout_size+1 and game.factory.cells[Vector2i(1,0)].kind == "belt","repair click beside inventory charges once without closing the list or painting the line")
		game.inventory_panel.hide()
		game.battlefield.hull = 70
		game._process(0)
		game.field_actions.refresh()
		check(is_equal_approx(game.field_actions.button.get_global_rect().end.x,game.start_button.get_global_rect().end.x) and game.field_actions.button.get_rect().end.y < game.start_button.position.y,"closing inventory returns repair above the floating sortie action")
	game.reset_battle(42)
	game.toggle_running()
	game.factory.running = false
	game.expedition.phase = "shop"
	game.expedition.current.shop_offers = ["gear:armor","gear:economizer","gear:left_gun"]
	game.expedition.current.shop_purchased = [false,false,false]
	game.refresh_view()
	await click(game.shop_panel.inventory_button)
	check(game.inventory_panel.visible and game.inventory_panel.get_canvas_layer_node().layer > game.shop_panel.get_canvas_layer_node().layer,"shop opens a usable inventory above the modal")
	var before_shop = game.factory.reserves.scrap
	await click(game.inventory_panel.action_buttons[2])
	check(game.factory.reserves.scrap > before_shop,"shop inventory can dismantle equipment for purchase funds")
	await capture("shop-inventory-960")
	game.toggle_inventory()
	var purchase_funds = game.factory.reserves.scrap
	await click(game.shop_panel.buttons[0])
	check(game.expedition.current.shop_purchased[0] and game.factory.reserves.scrap == purchase_funds-game.RunState.Services.GEAR_PRICE and game.expedition.gear_items.back().rarity == "uncommon" and game.expedition.equipment.is_empty(),"shop purchase enters inventory without changing departed loadout")
	await click(game.shop_panel.buttons[0])
	check(game.factory.reserves.scrap == purchase_funds-game.RunState.Services.GEAR_PRICE,"purchased offer cannot be charged twice")
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		game.reset_battle(42)
		game.expedition.gear_items.clear()
		var kinds = ["mortar_gun_focus_l10","armor_mobile_l09","supercharger_economy_l08","servo_efficient_l10"]
		var positions = [Vector2i(0,0),Vector2i(2,0),Vector2i(0,2),Vector2i(2,2)]
		for kind in kinds: game.expedition.add_item({"kind":kind,"rarity":"legendary"})
		await click(game.inventory_button)
		await capture("advanced-inventory-"+str(dimensions.x))
		for index in range(kinds.size()):
			if not game.inventory_panel.visible: await click(game.inventory_button)
			game.inventory_panel.page = index/game.inventory_panel.page_size
			game.inventory_panel.refresh()
			var row = index%game.inventory_panel.page_size
			check(game.inventory_panel.row_buttons[row].tooltip_text.contains(game.RunState.EQUIPMENT[kinds[index]].name),"advanced model tooltip preserves full name and performance")
			await drag(game.inventory_panel.row_buttons[row],positions[index])
			check(game.factory.equipment_mounts.get(kinds[index]) == positions[index],"advanced equipment drag places genre "+str(index)+" at "+str(dimensions.x))
		await capture("advanced-mounted-"+str(dimensions.x))
		game.expedition.add_item({"kind":"armor","rarity":"legendary"})
		await click(game.inventory_button)
		await click(game.inventory_panel.sort_button)
		var ordered = game.inventory_panel.rows.map(func(item): return game.Inventory.Catalog.level(item.kind))
		check(ordered == [10,10,9,8,1].slice(0,game.inventory_panel.page_size),"equal-quality items sort by equipment level before acquisition order")
		game.inventory_panel.hide()
		game.expedition.phase = "reward"
		game.expedition.reward_options = ["gear:mortar_gun_focus_l10","gear:rangefinder_focus_l10","gear:drum_loader_efficient_l10"]
		game.refresh_view()
		check(game.choice_popup.buttons.all(func(button): return not button.tooltip_text.is_empty()),"advanced reward cards retain complete effects in tooltips")
		await capture("advanced-rewards-"+str(dimensions.x))
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_ui_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
