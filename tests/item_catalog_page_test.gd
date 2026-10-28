extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS catalog page: ",label)
	else:
		failures += 1
		push_error(label)
func click(button):
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
	await process_frame
func run():
	DirAccess.make_dir_recursive_absolute("res://build/catalog-ui")
	var title = load("res://scenes/start_screen.tscn").instantiate()
	title.audio_enabled = false
	title.checkpoint_path = "user://catalog_page_fixture.mfv"
	title.history_path = Fixture.path_for("catalog_page_test")
	title.audio_settings_path = "user://catalog_page_test_audio_fixture.json"
	root.add_child(title)
	root.min_size = Vector2i(320,320)
	var positions = {}
	for dimensions in [Vector2i(1440,940),Vector2i(844,390),Vector2i(390,844),Vector2i(320,320)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var coords = {}
		for key in ["start","continue","catalog"]:
			var button = title.menu.navigation.catalog if key == "catalog" else title.menu.actions[0 if key == "start" else 1]
			var point = root.get_final_transform()*button.get_global_rect().get_center()
			coords[key] = [point.x,point.y]
		positions[str(dimensions.x)] = coords
		await click(title.menu.navigation.catalog)
		var catalog = title.catalog
		check(catalog.visible and not title.menu.visible,"title opens catalog without launching gameplay")
		catalog.category = ""
		catalog.page = 0
		catalog.refresh()
		check(catalog.ids.size() == 28,"all equipment appears independently of ownership")
		var visited = []
		while true:
			for id in catalog.visible_ids:
				if id not in visited: visited.append(id)
			var clear = true
			for i in range(catalog.visible_ids.size()): clear = clear and Rect2(Vector2.ZERO,catalog.size).grow(0.1).encloses(catalog.tiles[i].get_rect())
			check(clear,"tiles remain in the available page")
			if catalog.next.disabled: break
			await click(catalog.next)
		check(visited.size() == 28,"every item reachable through pages")
		await click(catalog.filters.vehicle)
		await click(catalog.tiles[0])
		check(catalog.large.model.get_meta("kind") == catalog.visible_ids[0] and catalog.heading.text == catalog.Catalog.Data.ITEMS[catalog.visible_ids[0]].name,"tile selection changes large model and item name")
		check(catalog.large.size.x > catalog.previews[0].size.x,"selected model has a larger display than the tile")
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://build/catalog-ui/catalog-%d.png" % dimensions.x)
		catalog.detail_page = 0
		catalog.refresh_detail()
		await click(catalog.detail_button)
		check(catalog.show_history,"history and game-specific explanation are accessible")
		for id in ["mortar_gun_focus_l10","salvage_arm","vehicle_engine_power"]:
			catalog.choose(id)
			for section in range(6):
				await process_frame
				check(Rect2(Vector2.ZERO,catalog.size).grow(0.1).encloses(catalog.detail.get_rect()),"long item descriptions fit without scrolling")
				await click(catalog.detail_button)
		await click(catalog.back)
		check(title.menu.visible and not catalog.visible,"back returns to title")
	var file = FileAccess.open("res://build/catalog-ui/title-geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(positions))
	title.free()
	Fixture.clean("catalog_page_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
