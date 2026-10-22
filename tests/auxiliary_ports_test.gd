extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
const PATH = "user://auxiliary_ports_test.mfv"
var game
var checks = 0
var failures = 0

func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS auxiliary ports: ",title)
	else:
		failures += 1
		push_error(title)

func _initialize(): call_deferred("run")

func domain_checks():
	var f = Factory.new()
	f.auto_fire = false
	check(f.install_auxiliary("left_gun") and f.install_auxiliary("right_gun") and not f.install_auxiliary("left_gun"),"paid weapon installs exactly one dedicated output")
	f.move_auxiliary("left_gun",Vector2i(5,2))
	f.move_auxiliary("right_gun",Vector2i(5,5))
	for y in [2,5]:
		for x in [1,3]: f.edit(Vector2i(x,y),"belt",0)
		f.edit(Vector2i(2,y),"furnace",0)
		f.edit(Vector2i(4,y),"press",0)
	for i in range(160): f.simulate_tick()
	check(f.auxiliary_ammo("left_gun") == 12 and f.auxiliary_ammo("right_gun") == 12 and f.ammo == 0,"two real production lines fill their own magazines without feeding main gun")
	check(f.diagnostic(Vector2i(5,2)).code == "full" and not f.can_receive(f.cells[Vector2i(5,2)],"shell"),"auxiliary magazine capacity stops upstream delivery")
	check(not f.accepts_kind(f.cells[Vector2i(5,2)],"fuel") and f.output_item(f.cells[Vector2i(5,2)]) == "","auxiliary output consumes shells and cannot forward stored ammunition")
	f.fire_round("left_gun")
	check(f.auxiliary_ammo("left_gun") == 11 and f.auxiliary_ammo("right_gun") == 12 and f.ammo == 0,"firing one gun never drains another magazine")
	f.cells[Vector2i(5,5)].items.clear()
	f.ammo = 4
	check(not f.fire_round("right_gun") and f.auxiliary_ammo("left_gun") == 11 and f.ammo == 4,"empty gun cannot borrow ammunition from main or other auxiliary output")
	var before = f.cells[Vector2i(5,2)].duplicate(true)
	f.running = true
	check(f.move_auxiliary("left_gun",Vector2i(7,1)) and f.cells[Vector2i(7,1)] == before and f.running,"moving a loaded gun preserves its complete magazine and playback")
	for dest in [Factory.AMMO_PORT,Vector2i(4,2),Vector2i(5,5),Vector2i(-1,2),Vector2i(14,2)]:
		check(not f.move_auxiliary("left_gun",dest) and f.auxiliary_position("left_gun") == Vector2i(7,1),"occupied or out-of-grid move is atomic: "+str(dest))
	f.edit(Vector2i(7,1),"erase",0)
	f.edit(Vector2i(7,1),"belt",0)
	check(f.auxiliary_ammo("left_gun") == 11,"erase and ordinary placement cannot destroy a crafted gun")
	var replacement = Factory.new()
	check(not replacement.restore(f.layout()),"layout import cannot grant uncrafted equipment")
	f.undo()
	check(f.auxiliary_position("left_gun") == Vector2i(5,2) and f.auxiliary_ammo("left_gun") == 0,"preparation undo restores weapon position with normal trial reset")
	f.clear_layout()
	check(f.auxiliary_position("left_gun") == Vector2i(5,2) and f.count_kind("left_gun") == 1,"clearing production equipment retains crafted output cells")
	f.remove_auxiliary()
	check(f.count_kind("left_gun") == 0 and f.auxiliary_ids.is_empty(),"new-run cleanup removes paid outputs")

func cell_screen(p: Vector2i) -> Vector2:
	return game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(p)+Vector3(0,0.03,0))

func drag(from: Vector2, to: Vector2):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	event.position = root.get_final_transform()*from
	root.push_input(event,false)
	await process_frame
	var motion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform()*to
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,false)
	game._process(0)
	await process_frame
	event = event.duplicate()
	event.position = motion.position
	event.pressed = false
	event.button_mask = 0
	root.push_input(event,false)
	game._process(0)
	await process_frame

func capture(path: String):
	game.queue_redraw()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run():
	domain_checks()
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"auxiliary_ports_test")
	# The drag fixture requires a won opening sector, not a wall-clock-seeded battle.
	game.expedition = preload("res://scripts/run_state.gd").new(42)
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.toggle_running()
	for tick in range(1800):
		preload("res://tests/profile_fixture.gd").drive(game,0.1)
		if game.expedition.phase != "travel": break
	# Two independently selected reward fixtures build the two-gun test setup.
	for id in ["left_gun","right_gun"]:
		game.expedition.phase = "reward"
		game.expedition.sector = 1
		game.expedition.route_options.clear()
		game.expedition.reward_options = ["gear:"+id,"block:belt","block:press"]
		preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	check(game.factory.auxiliary_ids == ["left_gun","right_gun"],"item awards create both independent outputs")
	check(game.factory.auxiliary_ammo("left_gun") == 0 and game.factory.auxiliary_ammo("right_gun") == 0,"new gun outputs start empty")
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	game._process(0)
	var stock = game.factory.ammo
	var original = game.factory.auxiliary_position("left_gun")
	game.factory.cells[original].items = ["shell","shell"]
	await drag(cell_screen(original),cell_screen(Vector2i(6,0)))
	check(game.factory.auxiliary_position("left_gun") == Vector2i(6,0) and game.factory.auxiliary_ammo("left_gun") == 2 and game.factory.ammo == stock,"real drag moves loaded output without changing any ammunition")
	var at = game.world.cell_position(Vector2i(6,0))
	check(game.world.auxiliary_guns[0].pivot.position.is_equal_approx(Vector3(at.x,3.2,at.z)) and game.battlefield.auxiliary_guns[0].pivot.position.is_equal_approx(Vector3(at.x,3.2,at.z)),"interior and battle weapon models align exactly above the moved grid cell")
	await drag(cell_screen(Vector2i(6,0)),cell_screen(Vector2i(4,2)))
	check(game.factory.auxiliary_position("left_gun") == Vector2i(6,0) and game.factory.cells[Vector2i(4,2)].kind == "press","dragging onto equipment preserves both gun and production machine")
	await drag(cell_screen(Vector2i(6,0)),Vector2(720,900))
	check(game.factory.auxiliary_position("left_gun") == Vector2i(6,0) and game.dragging_auxiliary == "","release outside grid cancels drag without painting or removing gun")
	root.size = Vector2i(960,628)
	await process_frame
	await process_frame
	await drag(cell_screen(Vector2i(6,0)),cell_screen(Vector2i(8,6)))
	check(game.factory.auxiliary_position("left_gun") == Vector2i(8,6),"minimum-window transformed mouse input moves weapon cell")
	game.hover = Vector2i(8,6)
	await capture("res://preview-auxiliary-ports-960.png")
	game.open_menu()
	check(not game.move_auxiliary("left_gun",Vector2i(8,0)),"pause menu blocks weapon movement")
	game.close_menu()
	game.world.toggle_roof()
	check(not game.move_auxiliary("left_gun",Vector2i(8,0)),"closed roof blocks edits to hidden output cells")
	game.world.toggle_roof()
	game.toggle_running()
	game.toggle_battle()
	game.battlefield.auxiliary_guns[0].cooldown = 1.2
	await drag(cell_screen(Vector2i(8,6)),cell_screen(Vector2i(7,6)))
	check(game.factory.running and game.factory.auxiliary_position("left_gun") == Vector2i(7,6) and game.factory.auxiliary_ammo("left_gun") == 2 and game.battlefield.auxiliary_guns[0].cooldown == 1.2,"in-travel dragging moves the output while ammunition cooldown and playback are preserved")
	game.factory.running = false
	var codec = game.checkpoint
	var saved = codec.snapshot(game)
	check(codec.write_file(PATH,saved) and codec.apply(game,codec.read_file(PATH)),"dedicated output positions and ammunition round-trip through disk")
	check(game.factory.auxiliary_position("left_gun") == Vector2i(7,6) and game.factory.auxiliary_ammo("left_gun") == 2 and game.factory.ammo == stock,"restored magazines remain separate with their original contents")
	at = game.world.cell_position(Vector2i(7,6))
	check(game.battlefield.auxiliary_guns[0].pivot.position.is_equal_approx(Vector3(at.x,3.2,at.z)),"saved position drives restored battle mount")
	var legacy = saved.duplicate(true)
	legacy.version = 1
	legacy.factory.undo_stack.clear()
	for p in legacy.factory.cells.keys():
		if Factory.AUXILIARY.has(legacy.factory.cells[p].kind): legacy.factory.cells.erase(p)
	check(codec.apply(game,legacy) and game.factory.auxiliary_ids.size() == 2 and game.factory.ammo == stock and game.factory.auxiliary_ammo("left_gun") == 0,"legacy shared-ammo save gains empty dedicated outputs without duplicating ammunition")
	var invalid = saved.duplicate(true)
	invalid.factory.cells.erase(Vector2i(7,6))
	check(not codec.validate(invalid),"new saves cannot omit a crafted gun's output cell")
	invalid = saved.duplicate(true)
	invalid.factory.cells[Vector2i(7,6)].items = ["fuel"]
	check(not codec.validate(invalid),"save rejects non-shell cargo in auxiliary magazine")
	invalid = saved.duplicate(true)
	invalid.factory.cells[Vector2i(7,6)].items.resize(saved.factory.ammo_capacity+1)
	invalid.factory.cells[Vector2i(7,6)].items.fill("shell")
	check(not codec.validate(invalid),"save rejects over-capacity auxiliary magazines")
	invalid = saved.duplicate(true)
	invalid.factory.cells[Vector2i(8,0)] = invalid.factory.cells[Vector2i(7,6)].duplicate(true)
	check(not codec.validate(invalid),"save rejects duplicate outputs for the same weapon")
	game.reset_battle(42)
	check(game.factory.auxiliary_ids.is_empty() and game.factory.count_kind("left_gun") == 0,"new run removes output cells with their equipment")
	game.toggle_running()
	for tick in range(1800):
		preload("res://tests/profile_fixture.gd").drive(game,0.1)
		if game.expedition.phase != "travel": break
	for y in range(Factory.H):
		for x in range(Factory.W):
			var p = Vector2i(x,y)
			if not game.factory.cells.has(p): game.factory.cells[p] = game.factory.make_cell("belt",0)
	var resources = game.factory.reserves.duplicate()
	game.expedition.reward_options = ["gear:left_gun","block:belt","gear:armor"]
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	check(not game.can_claim_reward("gear:left_gun") and game.factory.reserves == resources and game.expedition.equipment.is_empty(),"full deck prevents claiming an unplaceable weapon without losing the reward")
	game.choice_popup.refresh()
	check(game.choice_buttons[0].disabled,"full deck disables unplaceable weapon reward")
	print("AUXILIARY PORTS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize():
	Fixture.clean("auxiliary_ports_test")
	for suffix in ["",".tmp",".bak"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
