extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
const Save = preload("res://scripts/run_save.gd")
var checks = 0
var failures = 0
var game
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("logistics_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS logistics: ",label)
	else:
		failures += 1
		push_error(label)
func status(f, pos: Vector2i) -> String: return f.diagnostic(pos).code
func run():
	var f = Factory.new()
	var p = Vector2i(2,2)
	f.finite_resources = true
	check(status(f,p) == "idle","empty floor is not a fault")
	f.edit(p,"press",0)
	check(status(f,p) == "waiting" and f.diagnostic(p).item == "steel","idle press identifies missing input")
	f.cells[p].items = ["steel"]
	f.cells[p].work = 4
	check(status(f,p) == "processing","working press is distinct from a blockage")
	f.cells[p].items = ["shell"]
	f.cells[p].work = 0
	check(status(f,p) == "disconnected","completed item identifies absent downstream cell")
	f.edit(p+Vector2i.RIGHT,"furnace",0)
	check(status(f,p) == "incompatible","wrong receiver reports material mismatch")
	f.edit(p+Vector2i.RIGHT,"belt",0)
	check(status(f,p) == "ready","matching empty receiver permits flow")
	f.cells[p+Vector2i.RIGHT].items = ["shell"]
	check(status(f,p) == "blocked","occupied matching receiver reports backpressure")
	f.edit(p,"splitter",0)
	f.cells[p].items = ["shell"]
	f.edit(p+Vector2i.DOWN,"belt",0)
	check(status(f,p) == "ready","free splitter branch takes priority over blocked branch")
	f.edit(p+Vector2i.RIGHT,"furnace",0)
	f.cells[p+Vector2i.DOWN].items = ["shell"]
	check(status(f,p) == "blocked","usable but occupied splitter branch is not a mismatch")
	f.edit(p,"depot",0)
	f.cells[p].items = ["shell","shell","shell","shell","shell","shell","shell","shell"]
	f.edit(p+Vector2i.RIGHT,"belt",0)
	f.cells[p+Vector2i.RIGHT].items = ["shell"]
	check(status(f,p) == "full","full depot distinguishes storage saturation")
	f.reserves.scrap = 0
	check(status(f,Vector2i(0,2)) == "empty","depleted raw source reports empty")
	f.cells[Vector2i(0,2)].items = ["scrap"]
	check(status(f,Vector2i(0,2)) == "disconnected","last source item retains its actual output fault")
	f.finite_resources = false
	f.cells[Vector2i(0,2)].items.clear()
	check(status(f,Vector2i(0,2)) == "ready","unlimited unit-test source is not falsely depleted")
	check(status(f,Factory.AMMO_PORT) == "empty" and status(f,Factory.FUEL_PORT) == "empty","empty consumers identify missing shell and fuel")
	f.ammo = f.ammo_capacity
	f.fuel = 11.4
	check(status(f,Factory.AMMO_PORT) == "full" and status(f,Factory.FUEL_PORT) == "full","full consumers match actual whole-item acceptance")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"logistics_test")
	game.show_start_menu = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.toggle_running()
	game.toggle_battle()
	game.factory.elapsed = 10
	game.factory.cells[Vector2i(6,2)].items = ["shell"]
	game.factory.edit(Vector2i(7,2),"erase",0)
	game.factory.reserves.coal = 0
	game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0)
	game.hover = Vector2i(6,2)
	game._process(0)
	var badge_count = game.logistics.badges().size()
	check(badge_count > 0,"interior diagnostics place visible problem badges")
	var before = Save.new().snapshot(game)
	for i in range(5): game.logistics.badges()
	check(Save.new().snapshot(game) == before,"diagnostic queries do not change factory or battle")
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-logistics.png")
	game.factory.edit(Vector2i(7,2),"belt",0)
	check(status(game.factory,Vector2i(6,2)) == "ready","reconnecting output clears its fault immediately")
	game.world.toggle_roof()
	check(game.logistics.badges().is_empty(),"closed armor hides internal badges")
	game.world.toggle_roof()
	game.toggle_battle()
	check(game.logistics.badges().is_empty(),"exterior view hides internal badges")
	game.factory.reserves = {"scrap":98,"coal":99}
	game.factory.ammo = 11
	game.battlefield.recover(game.factory,{"scrap":8,"coal":4,"shell":5})
	game.logistics.sync(0)
	check(game.factory.reserves == {"scrap":100,"coal":100} and game.factory.ammo == 12,"pickup honors real capacities")
	check(game.logistics.notices.scrap.accepted == 2 and game.logistics.notices.scrap.lost == 6 and game.logistics.notices.coal.lost == 3 and game.logistics.notices.shell.lost == 4,"notices distinguish accepted and discarded material")
	game.battlefield.recover(game.factory,{"scrap":2})
	game.logistics.sync(0)
	check(game.logistics.notices.scrap.accepted == 2 and game.logistics.notices.scrap.lost == 8,"nearby salvage events aggregate by material")
	game.factory.running = false
	game.logistics.sync(10)
	check(game.logistics.notices.size() == 3,"pause keeps pickup feedback readable")
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-pickup.png")
	var pickup_save = Save.new().snapshot(game)
	game.factory.running = true
	game.logistics.sync(4.1)
	check(game.logistics.notices.is_empty(),"active playback expires feedback after four seconds")
	check(Save.new().apply(game,pickup_save),"pickup state remains valid for checkpoint restoration")
	game.logistics.sync(0)
	check(game.logistics.notices.is_empty() and game.factory.reserves.scrap == 100,"resume retains inventory without replaying old pickup notices")
	game.factory.running = true
	game.battlefield.distance = 17.99
	game.battlefield.player.position.x = 17.99
	game.factory.fuel = 1
	game.factory.reserves = {"scrap":0,"coal":0}
	game.battlefield.tick_battle(game.factory,0.1)
	game.logistics.sync(0)
	check(game.battlefield.resource_sites[0].taken and game.logistics.notices.has("scrap") and game.logistics.notices.has("coal"),"actual roadside crossing produces pickup feedback")
	var before_salvage = game.factory.collected.scrap
	var enemy = game.battlefield.enemies[0]
	enemy.hp = 1
	enemy.node.position = game.battlefield.player.position+Vector3(8,0,0)
	game.factory.ammo = 1
	for tick in range(15): game.battlefield.tick_battle(game.factory,0.1)
	game.logistics.sync(0)
	check(game.battlefield.kills == 1 and game.factory.collected.scrap == before_salvage+2 and game.logistics.notices.scrap.accepted >= 2,"actual enemy destruction produces salvage feedback")
	game.reset_battle()
	game.logistics.sync(0)
	check(game.logistics.notices.is_empty(),"new expedition clears old pickup feedback")
	game.toggle_running()
	game.toggle_battle()
	game.selected = "belt"
	var target = Vector2i(6,6)
	var at = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(target))
	var e = InputEventMouseButton.new()
	e.position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame
	check(game.factory.cells.has(target) and game.factory.running,"overlay permits actual construction click while running")
	print("LOGISTICS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
