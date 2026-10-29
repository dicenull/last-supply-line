extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Run = preload("res://scripts/run_state.gd")
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	root.min_size = Vector2i(320,240)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS airdrop: ",label)
	else:
		failures += 1
		push_error(label)
func capture(label):
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/supply-airdrop/"+label+".png")
func run():
	DirAccess.make_dir_recursive_absolute("res://build/supply-airdrop")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"supply_airdrop_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var r = game.expedition
	var original_seed = r.run_seed
	var gold = 0
	for seed_value in range(500):
		r.run_seed = seed_value
		if r.reward_rarity(0) == "legendary": gold += 1
	check(gold > 20 and gold < 80,"legendary supplies are occasional, around ten percent per crate")
	r.run_seed = original_seed
	game.toggle_running()
	game.battlefield.player.position = game.battlefield.goals[0].position+Vector3(5,0,0)
	game.battlefield.progress.resolve(0)
	var hp = game.battlefield.progress.hull
	game._process(0)
	check(r.phase == "reward" and game.airdrop.active and not game.choice_popup.visible,"real stage completion starts the cinematic and covers reward choices")
	check(game.battlefield.progress.hull == hp,"support arrival does not heal hull HP")
	var offers = []
	for i in range(r.reward_options.size()): offers.append(r.reward_item(i))
	var stock = r.gear_items.size()
	game.open_menu()
	var age = game.airdrop.age
	game._process(1)
	check(game.airdrop.age == age and not game.airdrop.visible,"menu hides and freezes the cinematic")
	game.close_menu()
	game._process(0)
	check(game.airdrop.visible,"resume restores support flyover")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"stage reward can be saved during flight")
	r = game.expedition
	check(game.airdrop.active and game.airdrop.selecting and not game.choice_popup.visible and r.reward_item(0) == offers[0],"load returns to unchanged offers without replay or reroll")
	var airdrop = game.airdrop
	airdrop.model_buttons[0].pressed.emit()
	check(airdrop.selected_index == 0 and not airdrop.acquire_button.disabled and r.gear_items.size() == stock,"clicking a model reveals details without granting the item")
	check(game.checkpoint.write_file("res://build/supply-airdrop/web-fixture.mfv",game.checkpoint.snapshot(game)),"pending support fixture preserves the three offers for browser testing")
	airdrop.acquire_button.pressed.emit()
	check(r.gear_items.size() == stock+1 and r.gear_items.back().kind == offers[0].kind and r.gear_items.back().rarity == offers[0].rarity,"selected support crate grants exactly its displayed kind and rarity")
	game.choose_run_option(0)
	check(r.gear_items.size() == stock+1,"repeated selection cannot duplicate a reward")
	var geometry = {}
	var a = game.airdrop
	for dimensions in [Vector2i(1440,940),Vector2i(844,390)]:
		root.min_size = Vector2i(320,240)
		root.size = dimensions
		await process_frame
		var items = [{"kind":"long_gun","rarity":"rare"},{"kind":"armor","rarity":"legendary"},{"kind":"vehicle_engine_power","rarity":"rare"}]
		# Use actual catalog identities, independent of a generated run's draft.
		items[2] = {"kind":"mortar_gun","rarity":"rare"}
		a.start(items,2)
		a.advance(1.8)
		await capture("flight-%d" % dimensions.x)
		check(a.crates.size() == 3 and a.crates[0].chute.visible,"three supply crates descend by parachute")
		a.advance(2.7)
		await capture("reveal-%d" % dimensions.x)
		check(a.crates[1].light.light_energy > a.crates[0].light.light_energy and a.crates[1].rays.size() > a.crates[0].rays.size(),"legendary opening has stronger illumination and more flares")
		check(a.get_rect().encloses(a.skip_button.get_rect()),"skip action remains on screen")
		var before = r.gear_items.size()
		a.skip()
		check(a.active and a.selecting and r.gear_items.size() == before,"skip enters direct model selection without granting inventory")
		check(a.get_rect().encloses(a.detail_panel.get_rect()) and a.model_buttons.all(func(button): return a.get_rect().encloses(button.get_rect()) and not button.get_rect().intersects(a.detail_panel.get_rect())),"models and details fit and remain separate")
		a.advance(20)
		check(a.active and a.selected_index == -1 and a.acquire_button.disabled,"selection waits indefinitely without an automatic grant")
		a.select_model(1)
		check(a.detail_title.text.contains("レジェンダリー") and not a.detail.text.is_empty(),"selected model details include actual rarity and effects")
		geometry[str(dimensions.x)] = {"models":a.model_buttons.map(func(button):
			var center = root.get_final_transform()*button.get_global_rect().get_center()
			return [center.x,center.y]),"acquire":[(root.get_final_transform()*a.acquire_button.get_global_rect().get_center()).x,(root.get_final_transform()*a.acquire_button.get_global_rect().get_center()).y]}
		a.cancel()
		check(a.viewport.get_child_count() == 0,"closing selection releases cinematic model nodes")
		a.start(items,2)
		a.skip()
		check(a.active and a.age >= 4.2,"early skip jumps to item reveal")
		a.cancel()
	FileAccess.open("res://build/supply-airdrop/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(geometry))
	game.queue_free()
	await process_frame
	Fixture.clean("supply_airdrop_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
