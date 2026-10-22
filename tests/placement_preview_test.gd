extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS placement preview: ",label)
	else:
		failures += 1
		push_error(label)
func key(code: int):
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	root.size = Vector2i(960,628)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"placement_preview_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	var world = game.world
	var f = game.factory
	var cell = Vector2i(6,5)
	var before = f.layout()
	var stock = f.reserves.duplicate()
	var history = f.undo_stack.duplicate(true)
	game.hover = cell
	game._process(0)
	check(world.placement_preview.visible and world.preview_valid and world.preview_kind == "belt","hover displays placeable conveyor model")
	check(world.preview_model.find_children("*","MeshInstance3D",true,false).size() >= 12,"square pipe preview contains walls end flanges and directional access plates")
	check(world.preview_model.get_child(0).material_override.albedo_color.a < 1 and world.preview_arrows.get_child_count() == 1,"ghost is translucent and directional cover remains visible")
	check(world.placement_preview.position.is_equal_approx(world.cell_position(cell)+Vector3(0,0.035,0)),"preview is anchored to hovered grid cell")
	var model_id = world.preview_model.get_instance_id()
	for dir in range(4):
		check(game.direction == dir and world.placement_preview.basis.x.is_equal_approx(Vector3(f.DIRS[dir].x,0,f.DIRS[dir].y)),"preview direction agrees with simulation output: "+str(dir))
		await capture("res://preview-pipe-direction-"+str(dir)+"-960.png")
		await key(KEY_R)
		game._process(0)
	check(game.direction == 0 and world.preview_model.get_instance_id() == model_id,"four real R presses wrap direction without rebuilding ghost mesh")
	check(f.layout() == before and f.reserves == stock and f.undo_stack == history,"hover and rotation preview never mutate layout materials or undo")
	game.direction = 1
	game._process(0)
	game.paint(cell,false)
	game._process(0)
	check(f.cells[cell].kind == "belt" and f.cells[cell].dir == 1 and world.machines.has(cell),"placement commits the exact type and direction shown")
	# Model is independent of preview tint; factory pipes keep their original metal materials.
	check(world.mats.steel.albedo_color.a == 1 and f.reserves.scrap == stock.scrap-1,"preview leaves permanent materials alone and charges only actual placement")
	game.selected = "router"
	game.hover = Vector2i(7,5)
	f.unlocked_blocks.append("router")
	game._process(0)
	check(world.preview_arrows.get_child_count() == 3,"three-way router previews every output branch")
	var exits = [0,1,3]
	for i in range(3):
		var dir = (game.direction+exits[i])%4
		check(world.preview_arrows.get_child(i).global_basis.x.is_equal_approx(Vector3(f.DIRS[dir].x,0,f.DIRS[dir].y)),"branch preview rotates with selected output: "+str(i))
	await capture("res://preview-pipe-router-960.png")
	game.selected = "furnace"
	game.hover = Vector2i(6,6)
	f.reserves = {"scrap":0,"coal":0}
	game._process(0)
	check(world.placement_preview.visible and not world.preview_valid and world.preview_model.get_child(0).material_override == world.preview_materials.invalid,"unaffordable placement has red ghost and red direction arrow")
	await capture("res://preview-placement-blocked-960.png")
	game.hover = f.AMMO_PORT
	game._process(0)
	check(not world.preview_valid,"fixed port refuses placement in preview")
	game.hover = Vector2i(-1,-1)
	game._process(0)
	check(not world.placement_preview.visible,"leaving grid hides preview")
	game.hover = cell
	game.selected = "erase"
	game._process(0)
	check(not world.placement_preview.visible,"erase tool does not show an installable ghost")
	game.selected = "belt"
	game._process(0)
	world.toggle_roof()
	check(not world.placement_preview.visible,"closing armor immediately hides ghost")
	world.toggle_roof()
	game._process(0)
	game.open_menu()
	game._process(0)
	check(not world.placement_preview.visible,"Esc menu hides placement preview")
	game.close_menu()
	game.hover = cell
	game.dragging_auxiliary = "left_gun"
	game._process(0)
	check(not world.placement_preview.visible,"auxiliary dragging hides unrelated selected line model")
	game.dragging_auxiliary = ""
	f.reserves = stock
	game.hover = cell
	game._process(0)
	game.toggle_running()
	game.toggle_battle()
	game.hover = cell
	game._process(0)
	check(world.placement_preview.visible and not f.layout_locked,"combat interior shows a construction preview")
	print("PLACEMENT PREVIEW RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("placement_preview_test")
