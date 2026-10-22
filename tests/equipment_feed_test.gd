extends SceneTree
const F = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
const INPUTS = [Vector2i(0,1),Vector2i(0,2),Vector2i(1,3),Vector2i(2,3),Vector2i(3,2),Vector2i(3,1),Vector2i(2,0),Vector2i(1,0)]
const DIRECTIONS = [0,0,3,3,2,2,1,1]
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment feed: ",label)
	else:
		failures += 1
		push_error(label)
func belt(f, p: Vector2i, direction: int, item: String = "shell"):
	f.cells[p] = f.make_cell("belt",direction)
	f.cells[p].items = [item]
func run():
	for kind in F.AUXILIARY:
		var f = F.new(2)
		f.auto_fire = false
		check(f.place_equipment(kind,Vector2i(1,1)),"mount accepts feed fixture: "+kind)
		var all_edges = true
		for i in range(INPUTS.size()):
			belt(f,INPUTS[i],DIRECTIONS[i])
			all_edges = all_edges and f.diagnostic(INPUTS[i]).code == "ready" and 0 in f.connection_sides(INPUTS[i]).connected
			var before = f.auxiliary_ammo(kind)
			f.simulate_tick()
			all_edges = all_edges and f.auxiliary_ammo(kind) == before+1 and f.cells[INPUTS[i]].items.is_empty()
			f.cells.erase(INPUTS[i])
		check(all_edges,"all eight perimeter inputs reach one magazine and connect visibly: "+kind)
	var f = F.new(2)
	f.auto_fire = false
	f.place_equipment("left_gun",Vector2i(1,1))
	var served: Dictionary = {}
	for tick in range(16):
		for i in range(INPUTS.size()): belt(f,INPUTS[i],DIRECTIONS[i])
		f.cells[Vector2i(1,1)].items.clear()
		f.simulate_tick()
		check(f.auxiliary_ammo("left_gun") == 1,"one arbitration winner supplies the shared magazine")
		for p in INPUTS:
			if f.cells[p].items.is_empty(): served[p] = served.get(p,0)+1
	check(served.size() == 8 and served.values().all(func(value): return value == 2),"continuous contention serves every perimeter inlet fairly")
	f.cells[Vector2i(1,1)].items.resize(f.ammo_capacity-1)
	f.cells[Vector2i(1,1)].items.fill("shell")
	for i in range(INPUTS.size()): belt(f,INPUTS[i],DIRECTIONS[i])
	f.simulate_tick()
	check(f.auxiliary_ammo("left_gun") == f.ammo_capacity and INPUTS.reduce(func(n,p): return n+f.cells[p].items.size(),0) == 7,"near-full magazine accepts exactly one round without losing other proposals")
	var layout = f.layout()
	f.simulate_tick()
	check(f.auxiliary_ammo("left_gun") == f.ammo_capacity and f.layout() == layout,"full magazine blocks further input")
	for p in INPUTS: f.cells.erase(p)
	f.cells[Vector2i(1,1)].items.clear()
	belt(f,Vector2i(3,2),2,"coal")
	f.simulate_tick()
	check(f.diagnostic(Vector2i(3,2)).code == "incompatible" and f.auxiliary_ammo("left_gun") == 0,"non-anchor inlet rejects non-ammunition")
	var corner = F.new(2)
	corner.auto_fire = false
	corner.place_equipment("left_gun",Vector2i(0,0))
	belt(corner,Vector2i(2,1),2)
	corner.simulate_tick()
	check(corner.auxiliary_ammo("left_gun") == 1,"corner-mounted weapon receives ammunition from its exposed edge")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_feed_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.place_item(game.expedition.gear_items[0].uid,Vector2i(0,0))
	belt(game.factory,Vector2i(2,1),2)
	game.factory.simulate_tick()
	game.factory.clock = F.TICK/2
	var frames = game.world.item_frames(game.factory)
	check(frames.any(func(frame): return frame.kind == "shell" and frame.pos.x > game.world.cell_position(Vector2i(1,1)).x),"feeding a non-anchor quadrant still animates the incoming shell")
	game.hover = Vector2i(1,1)
	game._process(0)
	await process_frame
	check(game.factory.diagnostic(game.hover).item == "shell" and game.factory.receiving_cell(game.hover).items.size() == 1,"every quadrant exposes the shared ammunition inspector")
	check(game.logistics.badges().filter(func(entry): return entry.pos in F.Layout.AMMO_CELLS).size() == 1,"shared main magazine displays only one empty-stock warning")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/equipment-audit")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/equipment-audit/equipment-feed.png")
	var data = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,data) and game.factory.auxiliary_ammo("left_gun") == 1,"non-anchor movement and feed arbitration survive checkpoint restore")
	for invalid in [-1,8,"2",1.5]:
		var bad = data.duplicate(true)
		bad.factory.cells[Vector2i(0,0)].feed_cursor = invalid
		check(not game.checkpoint.validate(bad),"malformed feed arbitration state is rejected: "+str(invalid))
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_feed_test")
	print("EQUIPMENT FEED RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
