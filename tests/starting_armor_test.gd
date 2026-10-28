extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS starting armor: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"starting_armor_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var f = game.factory
	check(f.Layout.WALLS.all(func(at): return f.cells[at].kind == "armor_block" and f.cells[at].armor_hp == 3),"all nine initial walls are three-hit defense blocks")
	var guard: Vector2i = f.Layout.WALLS[0]
	var stock = f.reserves.duplicate()
	f.damage_at(Vector2(guard)-Vector2(6.5,3.5))
	check(f.last_damage_blocked and f.cells[guard].armor_hp == 2,"initial block absorbs real damage")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,saved) and game.factory.cells[guard].armor_hp == 2,"partial starting armor survives save and load")
	f = game.factory
	f.damage_at(Vector2(guard)-Vector2(6.5,3.5))
	f.damage_at(Vector2(guard)-Vector2(6.5,3.5))
	check(not f.cells.has(guard) and f.wrecks.get(guard) == "armor_block","starting armor breaks on its third hit")
	check(f.repair_line() == 1 and f.cells[guard].armor_hp == 3 and f.reserves == stock,"repair restores the initial block through the normal system")
	f.edit(guard,"erase",0)
	saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,saved) and not game.factory.cells.has(guard),"removed initial block does not respawn on reload")
	var legacy = saved.duplicate(true)
	legacy.version = 13
	for at in f.Layout.WALLS: legacy.factory.cells.erase(at)
	check(game.checkpoint.apply(game,legacy) and f.Layout.WALLS.all(func(at): return game.factory.cells.get(at,{}).get("kind","") == "armor_block"),"old implicit walls migrate to defense blocks")
	var migrated = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(migrated) and game.checkpoint.apply(game,migrated) and game.factory.count_kind("armor_block") == 9,"migration is valid and never duplicates the ring")
	game.free()
	Fixture.clean("starting_armor_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
