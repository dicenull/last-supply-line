extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS resource storage: ",label)
	else:
		failures += 1
		push_error(label)

func run():
	var f = Factory.new()
	f.example(false)
	f.reserves = {"scrap":2000000000,"coal":3000000000}
	check(f.collect("scrap",2500000000) == 2500000000 and f.reserves.scrap == 4500000000,"collection exceeds both old capacity and 32-bit quantities")
	var before = f.reserves.duplicate()
	check(f.collect("coal",-5) == 0 and f.collect("unknown",100) == 0 and f.reserves == before,"invalid recovery never changes stock")
	f.edit(Vector2i(12,7),"belt",0)
	check(f.reserves.scrap == before.scrap-1 and f.reserves.coal == before.coal,"building only deducts its actual cost from large reserves")
	f.edit(Vector2i(12,7),"erase",0)
	check(f.reserves == before,"demolition returns its full value above the old cap")
	f.undo()
	check(f.reserves.scrap == before.scrap-1,"undo preserves the remaining large stock")
	var refund = f.construction_cost(f.cells)
	var stock = f.reserves.duplicate()
	f.clear_layout()
	check(f.reserves.scrap == stock.scrap+refund.scrap and f.reserves.coal == stock.coal+refund.coal,"clearing the whole line refunds every material without truncation")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"resource_storage_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	game.factory.reserves = {"scrap":4500000000,"coal":3000000000}
	game.factory.collected = {"scrap":5500000000,"coal":6000000000}
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved),"large stock and cumulative salvage validate")
	var path = "user://resource_storage_test.mfv"
	check(game.checkpoint.write_file(path,saved) and game.checkpoint.apply(game,game.checkpoint.read_file(path)),"large resource counts survive disk save and resume")
	check(game.factory.reserves == saved.factory.reserves and game.factory.collected == saved.factory.collected,"resume preserves exact 64-bit quantities")
	check(game.stock_text("scrap",5000,100) == "5000" and game.stock_text("coal",5000,125) == "5000","raw resource counters have no capacity denominator")
	check(game.stock_text("shell",5,12) == "5/12","weapon ammunition keeps its separate loading capacity")
	var bad = saved.duplicate(true)
	bad.factory.reserves.coal = -1
	check(not game.checkpoint.validate(bad),"negative resource stock is rejected")
	bad = saved.duplicate(true)
	bad.factory.reserves.coal = 1.5
	check(not game.checkpoint.validate(bad),"fractional resource stock is rejected")
	var old = saved.duplicate(true)
	old.version = 6
	old.factory.erase("wreck_directions")
	old.factory.reserves = {"scrap":98,"coal":99}
	old.factory.collected = {"scrap":0,"coal":0}
	check(game.checkpoint.apply(game,old),"legacy limited-capacity save still loads")
	game.factory.collect("coal",1000)
	check(game.factory.reserves.coal == 1099,"legacy saves immediately use unlimited storage")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("RESOURCE STORAGE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize(): Fixture.clean("resource_storage_test")
