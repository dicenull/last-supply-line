extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS result UI: ",label)
	else:
		failures += 1
		push_error(label)
func click(button):
	var at = root.get_final_transform()*button.get_global_rect().get_center()
	for down in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,false)
	await process_frame
func capture(name):
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/result-ui/"+name+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/result-ui")
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"result_ui_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.place_item(game.expedition.gear_items[0].uid,Vector2i.ZERO)
	game.expedition.sector = 5
	game.expedition.cleared = 4
	game.expedition.current = game.expedition.make_route("arsenal")
	game.toggle_running()
	var b = game.battlefield
	b.player.position = b.goal.position-Vector3(70,0,0)
	b.zoom = 110
	b.update_camera()
	await capture("final-base")
	for enemy in b.enemies: b.kill_enemy(enemy,game.factory,enemy.node.position)
	b.player.position = b.goal.position+Vector3(12,0,0)
	game._process(0.016)
	check(game.airdrop.active and not game.result_page.visible,"final arrival plays support animation before results")
	game.airdrop.advance(7)
	check(game.expedition.phase == "won" and game.result_page.visible,"real final arrival presents the result screen")
	check(game.checkpoint.write_file("res://build/result-ui/web-fixture.mfv",game.checkpoint.snapshot(game)),"completed result fixture validates for browser")
	var page = game.result_page
	var geometry = {}
	for dimensions in [Vector2i(1440,940),Vector2i(844,390),Vector2i(390,844),Vector2i(320,320)]:
		root.min_size = Vector2i(320,320)
		root.size = dimensions
		await process_frame
		page.arrange()
		await process_frame
		var fit = true
		for button in page.buttons:
			var rect: Rect2 = root.get_final_transform()*button.get_global_rect()
			fit = fit and Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(rect)
		check(fit,"all result controls fit without scroll: "+str(dimensions))
		check(page.card_rect(mini(page.entries.size(),page.page_size)-1).end.y <= page.list_rect.end.y-32,"list text leaves room for pager: "+str(dimensions))
		await click(page.buttons[1])
		check(page.tab == 1 and page.entries.size() == 4,"equipment tab responds to pointer input")
		check(page.previews[0].visible and page.previews[0].model != null and page.labels[0].text == page.entries[0].label,"result equipment uses matching 3D model and label")
		await capture("equipment-"+str(dimensions.x))
		await click(page.buttons[0])
		check(page.tab == 0 and page.entries.any(func(line): return line.label.contains("×9")),"installation list includes initial defensive ring")
		await capture("clear-"+str(dimensions.x))
		geometry[str(dimensions.x)] = page.buttons.map(func(button):
			var at = root.get_final_transform()*button.get_global_rect().get_center()
			return [at.x,at.y])
	FileAccess.open("res://build/result-ui/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(geometry))
	await click(page.buttons[4])
	check(game.expedition.phase == "prepare" and not page.visible and game.expedition.results.kills == 0,"retry starts a clean run and clears results")
	game.toggle_running()
	game.battlefield.kill_enemy(game.battlefield.enemies[0],game.factory,game.battlefield.enemies[0].node.position)
	game.battlefield.progress.take_damage(1000)
	game._process(0)
	check(game.expedition.phase == "lost" and game.battlefield.defeat_active() and not page.visible and game.battlefield.impacts.size() > 0,"zero HP starts a vehicle explosion before defeat results")
	var death = game.battlefield.defeat_age
	game.open_menu()
	game._process(1)
	check(game.battlefield.defeat_age == death,"menu pauses destruction cinematic")
	game.close_menu()
	game._process(1)
	check(game.battlefield.feedback.emitted.get("kill",0) >= 3 and not page.visible,"staggered secondary explosions precede results")
	game._process(3)
	check(page.visible and game.expedition.results.kills == 1 and game.expedition.hull == 0,"defeat uses the common result page with actual kills and zero HP")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved) and page.visible and not game.battlefield.defeat_active(),"loading defeat goes straight to results without replay or duplicate tally")
	check(game.checkpoint.write_file("res://build/result-ui/defeat-fixture.mfv",saved),"defeat browser fixture validates")
	game.free()
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP,"leaving the clear scene restores the gameplay aspect ratio")
	Fixture.clean("result_ui_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
