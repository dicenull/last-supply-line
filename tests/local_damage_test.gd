extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
var game
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS local damage: ",label)
	else:
		failures += 1
		push_error(label)
func local_position(p: Vector2i) -> Vector2:
	return Vector2(p.x-6.5,p.y-3.5)
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	var f = Factory.new()
	f.example(false)
	f.cells[Vector2i(2,2)].items = ["scrap"]
	f.cells[Vector2i(2,2)].work = 4
	f.moves = [{"from":Vector2i(1,2),"to":Vector2i(2,2),"item":"scrap"}]
	f.completed = [Vector2i(2,2)]
	var stock = f.reserves.duplicate()
	f.layout_locked = true
	f.running = true
	check(f.damage_at(local_position(Vector2i(2,2))) == Vector2i(2,2),"local hit identifies furnace inside combat lock")
	check(not f.cells.has(Vector2i(2,2)) and f.wrecks[Vector2i(2,2)] == "furnace","destroyed machine and in-process item are removed")
	check(f.reserves == stock and f.running and f.layout_locked,"damage gives no salvage and does not pause or unlock combat")
	check(f.moves.is_empty() and f.completed.is_empty() and f.undo_stack.is_empty(),"hit clears stale item animations and pre-hit undo")
	f.edit(Vector2i(2,2),"furnace",0)
	f.undo()
	check(not f.cells.has(Vector2i(2,2)),"combat edit and undo cannot repair a destroyed line")
	for tick in range(80): f.simulate_tick()
	check(f.manufactured == 0 and f.cells[Vector2i(1,2)].items == ["scrap"],"destroyed furnace stops its production chain and backs up its feeder")
	check(f.fuel > 0,"undamaged fuel line continues to work")
	check(f.damage_at(Vector2(40,40)) == Vector2i(-1,-1),"distant empty hit does not destroy unrelated equipment")
	f.layout_locked = false
	f.reserves = {"scrap":0,"coal":0}
	f.edit(Vector2i(2,2),"furnace",0)
	check(f.wrecks.has(Vector2i(2,2)) and not f.cells.has(Vector2i(2,2)),"insufficient funds leave destruction intact")
	f.reserves = {"scrap":6,"coal":1}
	f.edit(Vector2i(2,2),"furnace",0)
	check(f.cells.has(Vector2i(2,2)) and not f.wrecks.has(Vector2i(2,2)) and f.reserves == {"scrap":0,"coal":0},"construction phase rebuild pays full cost and removes wreck")
	f.undo()
	check(not f.cells.has(Vector2i(2,2)) and f.reserves == {"scrap":6,"coal":1},"undo of paid rebuild refunds only what was spent")
	var empty = Factory.new()
	empty.install_auxiliary("left_gun")
	check(empty.damage_at(local_position(Factory.AMMO_PORT)) == Vector2i(-1,-1) and empty.damage_at(local_position(empty.auxiliary_position("left_gun"))) == Vector2i(-1,-1),"fixed vehicle ports and weapon mounts are not line facilities")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"local_damage_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(960,628)
	game.toggle_running()
	var b = game.battlefield
	f = game.factory
	b.player.position = Vector3(20,0,5)
	b.player.rotation.y = PI/2
	var cell = Vector2i(4,2)
	f.cells[cell].dir = 3
	f.cells[cell].items = ["steel"]
	f.cells[cell].work = 3
	var hit = b.player.to_global(b.cell_position(cell))
	check(b.receive_shell(f,hit,6,10) and not f.cells.has(cell) and f.wrecks[cell] == "press","translated rotated vehicle maps world impact to correct local machine")
	check(b.hull == 90 and f.cells.has(Vector2i(2,2)),"hull damage and local damage occur together without hitting distant furnace")
	var count = f.wrecks.size()
	check(not b.receive_shell(f,b.player.position+Vector3(30,0,0),6,10) and b.hull == 90 and f.wrecks.size() == count,"dodging outside blast radius avoids both hull and line damage")
	check(not b.receive_shell(f,b.player.position,6,0) and f.wrecks.size() == count,"zero-damage hits cannot destroy a line")
	# A real projectile uses its saved target at impact time; moving after launch changes local hit.
	var second = Vector2i(5,2)
	var target = b.player.to_global(b.cell_position(second))
	var node = Node3D.new()
	b.add_child(node)
	var mark = Node3D.new()
	b.add_child(mark)
	b.bolts.append({"node":node,"origin":target+Vector3(20,0,0),"target":target,"age":0.0,"duration":0.05,"mark":mark,"radius":6.0,"damage":10.0,"style":"heavy"})
	for enemy in b.enemies:
		enemy.active = true
		enemy.cooldown = 100
	b.tick_battle(f,0.1)
	check(not f.cells.has(second) and f.wrecks.has(second) and b.hull == 80 and b.bolts.is_empty(),"normal enemy projectile impact invokes local destruction exactly once")
	check(b.damage_layer.get_child_count() == 10,"each destroyed cell has visible wreckage on vehicle")
	var saved = game.checkpoint.snapshot(game)
	check(saved.version == game.checkpoint.VERSION and game.checkpoint.validate(saved) and saved.factory.wreck_directions[cell] == 3,"destroyed factory saves original orientation in current checkpoint")
	check(game.checkpoint.apply(game,saved) and game.factory.wrecks == saved.factory.wrecks and not game.factory.cells.has(cell) and not game.factory.layout_locked and game.factory.combat_editing,"loading preserves destruction and live editing without resurrecting machinery")
	game.toggle_battle()
	game._process(0)
	game.hover = cell
	await capture("res://preview-local-damage-interior-960.png")
	game.toggle_battle()
	game.battlefield.update_camera()
	await capture("res://preview-local-damage-exterior-960.png")
	var bad = saved.duplicate(true)
	bad.factory.wrecks[Factory.AMMO_PORT] = "belt"
	check(not game.checkpoint.validate(bad),"save rejects wreck overlapping intact fixed port")
	bad = saved.duplicate(true)
	bad.factory.wrecks[Vector2i(99,99)] = "belt"
	check(not game.checkpoint.validate(bad),"save rejects wreck outside grid")
	bad = saved.duplicate(true)
	bad.factory.wreck_directions[cell] = 4
	check(not game.checkpoint.validate(bad),"save rejects invalid repair orientation")
	bad = saved.duplicate(true)
	bad.factory.erase("wreck_directions")
	check(not game.checkpoint.validate(bad),"new save requires repair orientations")
	bad.version = 6
	check(game.checkpoint.apply(game,bad) and game.factory.wreck_directions[cell] == 0,"version-six wrecks without orientation migrate to default direction")
	bad = saved.duplicate(true)
	bad.factory.erase("wrecks")
	check(not game.checkpoint.validate(bad),"new checkpoint requires damage field")
	bad.version = 5
	bad.factory.erase("wreck_directions")
	check(game.checkpoint.apply(game,bad) and game.factory.wrecks.is_empty(),"version-five saves load with no cosmetic wrecks")
	game.checkpoint.apply(game,saved)
	f = game.factory
	f.reserves = {"scrap":0,"coal":0}
	var kept = f.cells[Vector2i(2,2)].duplicate(true)
	var ammo_before = f.ammo
	var fuel_before = f.fuel
	game.battlefield.player.position = game.battlefield.goals[0].position+Vector3(2,0,0)
	game.battlefield.arrived_destination = 0
	game.battlefield.result = 1
	game._process(0)
	check(game.expedition.phase == "reward" and not f.layout_locked and f.wrecks.is_empty() and f.wreck_directions.is_empty(),"stage clear repairs every destroyed cell and releases construction lock")
	check(game.expedition.hull == 80 and game.battlefield.hull == 80,"stage clear preserves damaged hull in both states before reward selection")
	check(f.cells[cell].kind == "press" and f.cells[cell].dir == 3 and f.cells[second].kind == "belt","repair restores original machine types positions and orientation after save load")
	check(f.cells[cell].items.is_empty() and f.cells[cell].work == 0 and f.cells[Vector2i(2,2)] == kept,"repair loses destroyed cargo but preserves intact processing")
	check(f.reserves == {"scrap":0,"coal":0} and f.ammo == ammo_before and f.fuel == fuel_before,"repair is free even without resources and does not refill ammunition or fuel")
	check(game.world.damage_layer.get_child_count() == 0 and game.battlefield.damage_layer.get_child_count() == 0,"clear removes damage visuals immediately in both views")
	var repaired_layout = f.layout()
	game._process(0)
	check(f.layout() == repaired_layout and f.reserves == {"scrap":0,"coal":0},"clear repair is not repeated while choosing rewards")
	check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"repaired reward screen is saveable")
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	preload("res://tests/profile_fixture.gd").claim_reward(game,0)
	check(f.cells.has(cell) and f.cells[cell].dir == 3 and f.reserves == {"scrap":0,"coal":0},"next-stage construction starts with the repaired line at no material cost")
	check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"repaired next-stage state remains saveable")
	game.checkpoint.apply(game,saved)
	game.battlefield.result = -1
	game._process(0)
	check(game.expedition.phase == "lost" and game.battlefield.hull == 80 and game.factory.wrecks.has(cell),"defeat never triggers clear repair")
	game.reset_battle()
	check(game.factory.wrecks.is_empty() and game.factory.cells.has(cell),"new run resets battle damage with fresh starter line")
	f = game.factory
	for y in range(Factory.H):
		for x in range(Factory.W):
			var p = Vector2i(x,y)
			if f.cells.has(p): continue
			for kind in Factory.LIMITS:
				if f.count_kind(kind) < Factory.LIMITS[kind]:
					f.cells[p] = f.make_cell(kind,0)
					break
	check(not game.has_mount_space(),"full layout fixture has no equipment mount space")
	game.toggle_running()
	f.damage_at(local_position(cell))
	check(game.has_mount_space(),"destroyed full-layout cell temporarily appears vacant")
	game.battlefield.player.position = game.battlefield.goals[0].position+Vector3(2,0,0)
	game.battlefield.arrived_destination = 0
	game.battlefield.result = 1
	game._process(0)
	check(not game.has_mount_space() and game.expedition.reward_options.all(func(id): return id.trim_prefix("gear:") not in Factory.AUXILIARY),"repair occurs before reward draft so restored cells cannot be offered as free mounts")
	print("LOCAL DAMAGE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("local_damage_test")
