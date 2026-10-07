extends SceneTree
const Factory = preload("res://scripts/factory.gd")
var failures = 0
var checks = 0
func check(ok: bool, title: String):
	checks += 1
	if ok: print("PASS: ",title)
	else:
		failures += 1
		push_error(title)
func advance(f, seconds: float):
	f.running = true
	for i in int(seconds/Factory.TICK): f.step(Factory.TICK)
func add_second_line(f):
	for x in [1,3]: f.cells[Vector2i(x,5)] = f.make_cell("belt",0)
	f.cells[Vector2i(2,5)] = f.make_cell("furnace",0)
	f.cells[Vector2i(4,5)] = f.make_cell("press",0)
	for x in range(5,9): f.cells[Vector2i(x,5)] = f.make_cell("belt",0)
	f.cells[Vector2i(8,5)].dir = 3
	f.cells[Vector2i(8,4)] = f.make_cell("belt",0)
func _initialize():
	var empty = Factory.new()
	advance(empty,30)
	check(empty.shots == 0 and empty.manufactured == 0,"empty layout never manufactures or fires")
	var single = Factory.new()
	single.example()
	advance(single,120)
	check(single.shots > 35,"single example delivers and fires real manufactured ammunition")
	var baseline = single.recent_rate()
	print("Single line: ",baseline," rounds/min")
	var parallel = Factory.new()
	parallel.example()
	add_second_line(parallel)
	advance(parallel,120)
	print("Parallel lines: ",parallel.recent_rate()," rounds/min")
	check(parallel.recent_rate() > baseline * 1.5,"parallel production measurably improves throughput")
	check(parallel.cells[Vector2i(4,2)].made > 30 and parallel.cells[Vector2i(4,5)].made > 30,"both production branches remain active at merge")
	var inventory = parallel.ammo + parallel.shots + parallel.fuel + parallel.fuel_used
	for c in parallel.cells.values(): inventory += c.items.size()
	check(inventory == parallel.injected,"material conserved through manufacture, merge, storage and firing")
	check(parallel.ammo <= 12,"receiver respects capacity")
	check(single.fuel > 0 and single.fuel <= 12,"example refines coal and fills engine fuel tank")
	check(not single.can_receive(single.make_cell("engine",0),"shell"),"engine rejects ammunition")
	check(not single.can_receive(single.make_cell("refinery",0),"scrap"),"refinery accepts coal only")
	var fuel_before = single.fuel
	var used = single.consume_fuel(0.5)
	check(is_equal_approx(used,0.5) and is_equal_approx(single.fuel,fuel_before-0.5),"fuel consumption removes exactly the requested quantity")
	single.consume_fuel(100)
	check(single.fuel == 0 and single.consume_fuel(1) == 0,"fuel consumption cannot become negative")
	var disconnected = Factory.new()
	disconnected.example()
	disconnected.cells.erase(Vector2i(9,3))
	advance(disconnected,60)
	check(disconnected.manufactured > 0 and disconnected.shots == 0,"a disconnected output cannot magically supply gun")
	var rotate = Factory.new()
	rotate.cells.clear()
	rotate.cells[Vector2i(2,2)] = rotate.make_cell("belt",1)
	rotate.cells[Vector2i(2,3)] = rotate.make_cell("belt",1)
	rotate.cells[Vector2i(2,4)] = rotate.make_cell("belt",1)
	rotate.cells[Vector2i(2,2)].items = ["steel"]
	rotate.simulate_tick()
	check(rotate.cells[Vector2i(2,3)].items == ["steel"] and rotate.cells[Vector2i(2,4)].items.is_empty(),"one tick moves at most one cell in selected direction")
	var split = Factory.new()
	split.cells.clear()
	for p in [Vector2i(2,2),Vector2i(3,2),Vector2i(2,3)]: split.cells[p] = split.make_cell("belt",0)
	split.cells[Vector2i(2,2)].kind = "splitter"
	split.cells[Vector2i(2,2)].items = ["steel"]
	split.simulate_tick()
	split.cells[Vector2i(2,2)].items = ["steel"]
	split.simulate_tick()
	check(split.cells[Vector2i(3,2)].items == ["steel"] and split.cells[Vector2i(2,3)].items == ["steel"],"splitter alternates between forward and right-turn branches")
	check(not split.can_receive(split.make_cell("press",0),"scrap"),"press rejects raw scrap")
	check(not split.can_receive(split.make_cell("depot",0),"steel"),"ammunition depot rejects non-ammunition")
	var depot = split.make_cell("depot",0)
	for i in range(8): depot.items.append("shell")
	check(not split.can_receive(depot,"shell"),"depot capacity is eight shells")
	var merge = Factory.new()
	merge.cells.clear()
	for p in [Vector2i(2,2),Vector2i(3,1),Vector2i(3,2)]: merge.cells[p] = merge.make_cell("belt",0)
	merge.cells[Vector2i(3,1)].dir = 1
	var winners: Array = []
	for i in range(6):
		merge.cells[Vector2i(2,2)].items = ["steel"]
		merge.cells[Vector2i(3,1)].items = ["scrap"]
		merge.cells[Vector2i(3,2)].items = []
		merge.simulate_tick()
		winners.append(merge.cells[Vector2i(3,2)].items[0])
	check(winners.count("steel") == 3 and winners.count("scrap") == 3,"merge arbitration gives both inputs equal turns")
	var stored = Factory.new()
	stored.cells.clear()
	stored.cells[Factory.AMMO_PORT+Vector2i.LEFT] = stored.make_cell("depot",0)
	stored.cells[Factory.AMMO_PORT] = stored.make_cell("gun",0)
	for i in range(8): stored.cells[Factory.AMMO_PORT+Vector2i.LEFT].items.append("shell")
	advance(stored,15)
	check(stored.shots == 8 and stored.ammo == 0,"stored shells sustain firing with no upstream supply, then exhaust")
	var steady = Factory.new()
	steady.cells.clear()
	for i in range(240):
		steady.ammo = 12
		steady.simulate_tick()
	check(steady.recent_rate() == 60 and steady.availability() == 100,"30-second throughput window has no extra boundary shot")
	var edit = Factory.new()
	edit.edit(Vector2i(5,2),"belt",0)
	check(edit.cells.has(Vector2i(5,2)),"former pillar tiles accept equipment")
	check(edit.count_kind("gun") == 1 and edit.cells[Factory.AMMO_PORT].kind == "gun","one ammunition receiver is fixed beneath turret")
	edit.edit(Factory.AMMO_PORT,"erase",0)
	check(edit.cells[Factory.AMMO_PORT].kind == "gun","ammunition receiver cannot be erased")
	edit.edit(Vector2i(0,2),"erase",0)
	check(edit.cells[Vector2i(0,2)].kind == "source","fixed supply ports cannot be erased")
	edit.running = true
	edit.edit(Vector2i(1,1),"furnace",0)
	check(not edit.running,"editing pauses trial")
	edit.rotate(Vector2i(1,1))
	check(edit.cells[Vector2i(1,1)].dir == 1,"existing module rotates in place")
	edit.undo()
	check(edit.cells[Vector2i(1,1)].dir == 0,"undo restores previous layout")
	for x in range(2,6): edit.edit(Vector2i(x,1),"furnace",0)
	check(edit.count_kind("furnace") == 4,"machine inventory limit enforced")
	var snapshot = parallel.layout()
	var restored = Factory.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(snapshot))),"layout survives JSON save/load round trip")
	check(restored.layout().size() == snapshot.size() and restored.shots == 0,"restoring layout resets trial")
	var before = restored.layout()
	check(not restored.restore([[Factory.AMMO_PORT.x,Factory.AMMO_PORT.y,"belt",0]]) and restored.layout() == before,"invalid save rejected atomically")
	parallel.running = false
	var t = parallel.elapsed
	parallel.step(10)
	check(parallel.elapsed == t,"pause freezes production and trial")
	parallel.reset_trial()
	check(parallel.layout() == snapshot and parallel.shots == 0 and parallel.ammo == 0,"reset empties goods and measurements while preserving layout")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
