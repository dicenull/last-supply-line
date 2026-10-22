extends SceneTree
const F = preload("res://scripts/factory.gd")
const Layout = preload("res://scripts/factory_layout.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS factory layout: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	for blueprint in ["standard","parallel","buffered"]:
		var f = F.new(2)
		check(f.restore(Blueprints.layout(blueprint,2),false),"new hull accepts "+blueprint)
		f.auto_fire = false
		f.finite_resources = true
		f.running = true
		for i in range(600): f.step(0.1)
		check(f.ammo == f.ammo_capacity and f.fuel > 0,"central stocks feed magazine and rear engine: "+blueprint)
		for p in Layout.PORTS:
			check(f.cells[p].kind == Layout.PORTS[p] and f.cells[p].dir == Layout.DIRECTIONS.get(p,0),"fixed fitting retains identity and direction: "+str(p))
		var before = f.layout()
		for p in Layout.WALLS:
			f.edit(p,"belt",0)
			f.edit(p,"erase",0)
		check(f.layout() == before,"central walls cannot be replaced or erased")
	var f = F.new(2)
	f.auto_fire = false
	var entries = [Vector2i(9,2),Vector2i(11,3),Vector2i(9,5),Vector2i(10,5)]
	var directions = [1,2,3,3]
	for i in range(entries.size()):
		f.cells[entries[i]] = f.make_cell("belt",directions[i])
		f.cells[entries[i]].items = ["shell"]
	f.ammo = 11
	f.simulate_tick()
	check(f.ammo == 12 and entries.reduce(func(n,p): return n+f.cells[p].items.size(),0) == 3,"four simultaneous inputs share a single capacity without losing shells")
	for target in Layout.AMMO_CELLS:
		var solo = F.new(2)
		solo.auto_fire = false
		var origin = target+Vector2i(0,-1 if target.y == 3 else 1)
		solo.cells[origin] = solo.make_cell("belt",1 if target.y == 3 else 3)
		solo.cells[origin].items = ["shell"]
		solo.simulate_tick()
		check(solo.ammo == 1,"every magazine quadrant accepts a shell: "+str(target))
	check(f.place_equipment("left_gun",Vector2i(0,0)),"empty 2×2 mounting footprint is accepted")
	check(not f.place_equipment("armor",Vector2i(1,1)),"passive gear cannot overlap a weapon footprint")
	check(not f.place_equipment("armor",Vector2i(13,1)),"wide passive gear cannot overhang hull")
	f.cells[Vector2i(0,0)].items = ["shell","shell"]
	check(f.move_auxiliary("left_gun",Vector2i(1,0)) and f.auxiliary_ammo("left_gun") == 2,"partial-footprint move preserves loaded rounds")
	f.edit(Vector2i(4,0),"belt",0)
	var undo_before = f.undo_stack.duplicate(true)
	check(f.place_equipment("left_gun",Vector2i(1,0)) and f.undo_stack == undo_before,"clicking an installed weapon in place preserves line undo history")
	var rows = f.layout()
	for row in rows:
		if row[2] == "left_gun": row[0] = 3
	var before = f.layout()
	check(not f.restore(rows,false) and f.layout() == before,"layout import cannot relocate reserved equipment independently")
	f.loadout_locked = true
	check(not f.place_equipment("armor",Vector2i(4,0)) and not f.remove_equipment("left_gun"),"departure prevents adding or removing any equipment genre")
	f.clear_layout(false,false)
	check(f.auxiliary_position("left_gun") == Vector2i(1,0),"clearing lines retains locked equipment footprint")
	var old = F.new()
	check(old.layout_version == 1 and old.ports == F.PORTS and old.blocks.is_empty(),"legacy factory retains its original fittings")
	old.example(false)
	check(old.restore(Blueprints.layout("parallel"),false),"legacy blueprints still work on legacy hull")
	print("FACTORY LAYOUT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
