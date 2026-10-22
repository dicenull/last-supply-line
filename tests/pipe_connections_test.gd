extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS pipe connections: ",label)
	else:
		failures += 1
		push_error(label)
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	var f = Factory.new()
	f.example(false)
	check(f.connection_sides(Vector2i(1,2)).inputs == [2] and f.connection_sides(Vector2i(1,2)).connected == [0,2],"source and furnace form both ends of a straight pipe")
	check(f.connection_sides(Vector2i(2,2)).inputs == [2] and f.connection_sides(Vector2i(2,2)).connected == [0,2],"furnace uses a matching inlet and outlet")
	check(f.connection_sides(Vector2i(9,2)).inputs == [1] and f.connection_sides(Vector2i(9,2)).connected == [0,1],"corner receives from west and exits south without extra rear branch")
	check(f.connection_sides(Factory.AMMO_PORT).inputs == [3] and f.connection_sides(Factory.AMMO_PORT).outputs.is_empty(),"main gun socket connects on actual receiving side only")
	for direction in range(4):
		var isolated = Factory.new()
		var p = Vector2i(6,4)
		isolated.cells[p] = isolated.make_cell("belt",direction)
		var incoming = (direction+1)%4
		isolated.cells[p+Factory.DIRS[incoming]] = isolated.make_cell("belt",(incoming+2)%4)
		isolated.cells[p+Factory.DIRS[direction]] = isolated.make_cell("belt",direction)
		check(isolated.connection_sides(p).inputs == [1] and isolated.connection_sides(p).connected == [0,1],"elbow topology rotates with every orientation: "+str(direction))
	var filter = f.make_cell("fuel_filter",0)
	check(not f.can_link(filter,f.make_cell("gun",0),0) and f.can_link(filter,f.make_cell("engine",0),0),"connector compatibility follows actual accepted cargo")
	var smart = f.make_cell("smart_splitter",0)
	check(f.can_link(smart,f.make_cell("engine",0),1) and not f.can_link(smart,f.make_cell("engine",0),0),"smart splitter fuel branch uses the simulation routing rule")
	check(not f.can_link(f.make_cell("belt",0),f.make_cell("source",0),0) and not f.can_link(f.make_cell("gun",0),f.make_cell("belt",0),0),"fixed source and sink have no fictitious reverse connection")
	var full = f.make_cell("furnace",0)
	full.items = ["scrap"]
	full.work = 4
	check(f.can_link(f.make_cell("belt",0),full,0),"busy receiving machine retains its physical connection")
	var p = Vector2i(6,5)
	f.cells[p] = f.make_cell("belt",0)
	f.cells[p+Vector2i.LEFT] = f.make_cell("belt",0)
	f.cells[p+Vector2i.UP] = f.make_cell("belt",1)
	check(f.connection_sides(p).inputs == [2,3],"merging inputs form a T junction")
	f.cells[p].kind = "router"
	check(f.connection_sides(p).outputs == [0,1,3],"router exposes all three real exits")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"pipe_connections_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(960,628)
	game._process(0)
	var world = game.world
	f = game.factory
	check(world.machines[Vector2i(9,2)].ports == [1,0] and 2 not in world.machines[Vector2i(9,2)].ports,"rendered corner is an elbow rather than a capped straight plus extra arm")
	var layout_before = f.layout()
	var reserves_before = f.reserves.duplicate()
	game.hover = Vector2i(-1,-1)
	await capture("res://preview-connected-factory-960.png")
	# Existing downstream machine is replaced with a candidate: topology must be previewed without spending.
	game.selected = "belt"
	game.hover = Vector2i(2,2)
	game.direction = 1
	game._process(0)
	check(world.preview_topology == "[1]" and world.placement_preview.visible,"preview shows incoming west pipe as a rotated elbow")
	check(f.layout() == layout_before and f.reserves == reserves_before,"topology preview does not modify the real line or materials")
	await capture("res://preview-connected-elbow-960.png")
	# Connect another direction and ensure the rendered topology updates immediately.
	f.edit(Vector2i(3,1),"belt",1)
	game.hover = Vector2i(-1,-1)
	game._process(0)
	check(world.machines[Vector2i(3,2)].inputs == [2,3] and world.machines[Vector2i(3,2)].ports.size() == 3,"adding feeder immediately changes installed pipe into T junction")
	await capture("res://preview-connected-branch-960.png")
	f.rotate(Vector2i(3,1))
	game._process(0)
	check(world.machines[Vector2i(3,2)].inputs == [2] and world.machines[Vector2i(3,2)].ports.size() == 2,"rotating feeder away removes false branch")
	f.undo()
	game._process(0)
	check(world.machines[Vector2i(3,2)].inputs == [2,3],"undo reconstructs neighboring connection geometry")
	f.damage_at(Vector2(3-6.5,1-3.5))
	game._process(0)
	check(world.machines[Vector2i(3,2)].inputs == [2] and not world.machines.has(Vector2i(3,1)),"local destruction also removes adjacent connection")
	# Rebuild only geometry repeatedly: real processing must remain deterministic.
	var original = Factory.new()
	original.example(false)
	var observed = Factory.new()
	observed.example(false)
	for tick in range(120):
		original.simulate_tick()
		observed.simulate_tick()
		world.sync(observed,Vector2i(-1,-1),"belt",0,0)
	check(original.cells == observed.cells and original.shots == observed.shots and observed.shots > 0,"connected geometry preserves real material routing and ammunition production")
	print("PIPE CONNECTIONS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("pipe_connections_test")
