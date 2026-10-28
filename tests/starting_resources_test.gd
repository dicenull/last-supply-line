extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS starting resources: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"starting_resources_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var f = game.factory
	var initial = game.checkpoint.snapshot(game)
	for at in [Vector2i(6,3),Vector2i(7,4),Vector2i(6,4)]:
		var cell: Dictionary = f.cells[at].duplicate(true)
		var stock = f.reserves.duplicate()
		f.edit(at,"erase",0)
		check(not f.cells.has(at) and not f.ports.has(at),"starting resource block can be removed: "+str(at))
		var paid = f.reserves.duplicate()
		f.edit(at,"erase",0)
		check(f.reserves == paid,"repeated erase cannot duplicate salvage")
		f.undo()
		check(f.cells[at].kind == cell.kind and f.cells[at].dir == cell.dir and f.reserves == stock,"undo restores source direction and charges back its salvage")
		f.edit(at,"erase",0)
		f.edit(at,"belt",1)
		check(f.cells[at].kind == "belt","freed space accepts normal construction")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"removed starting sources round-trip without respawning")
	f = game.factory
	check(f.count_kind("source") == 0 and f.count_kind("coal_source") == 0,"restored factory has no erased resources")
	check(game.save_layout(),"layout-only save records removed resources")
	check(game.checkpoint.apply(game,initial) and game.load_layout() and game.factory.count_kind("source") == 0,"layout reload preserves removal separately from full run save")
	initial.version = 19
	initial.factory.erase("main_gun_anchor")
	check(game.checkpoint.apply(game,initial),"legacy run with fixed starting resources migrates")
	game.factory.edit(Vector2i(6,3),"erase",0)
	check(not game.factory.cells.has(Vector2i(6,3)),"migrated starting resources can also be removed")
	game.free()
	await process_frame
	Fixture.clean("starting_resources_test")
	print("STARTING RESOURCES RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
