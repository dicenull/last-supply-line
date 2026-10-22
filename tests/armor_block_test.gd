extends SceneTree
const Factory = preload("res://scripts/factory.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
const Run = preload("res://scripts/run_state.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS armor: ",label)
	else:
		failures += 1
		push_error(label)
func local_at(p: Vector2i) -> Vector2:
	return Vector2(p.x-6.5,p.y-3.5)
func run():
	var f = Factory.new()
	var target = Vector2i(6,4)
	var guard = Vector2i(6,3)
	var stock = f.reserves.duplicate()
	f.edit(guard,"armor_block",0)
	check(f.cells.has(guard) and f.cells[guard].armor_hp == 3 and f.reserves.scrap == stock.scrap-5 and f.reserves.coal == stock.coal,"available from start and built for five scrap")
	f.edit(guard,"erase",0)
	check(f.reserves == stock,"demolition returns construction materials")
	f.edit(guard,"armor_block",0)
	f.cells[target] = f.make_cell("furnace",0)
	f.cells[target].items = ["scrap"]
	f.cells[target].work = 4
	f.layout_locked = true
	for hit in range(1,4):
		f.damage_at(local_at(target))
		check(f.last_damage_blocked and f.cells[target].items == ["scrap"] and f.cells[target].work == 4,"protected machine retains its cargo and processing on hit "+str(hit))
		if hit < 3: check(f.cells[guard].armor_hp == 3-hit,"armor loses exactly one plate on hit "+str(hit))
	check(not f.cells.has(guard) and f.wrecks[guard] == "armor_block" and f.undo_stack.is_empty(),"third hit destroys armor and cannot be undone")
	f.damage_at(local_at(target))
	check(not f.last_damage_blocked and not f.cells.has(target),"next hit destroys the exposed machine")
	var after_damage = f.reserves.duplicate()
	check(f.repair_line() == 2 and f.cells[guard].armor_hp == 3 and f.cells.has(target) and f.reserves == after_damage,"clear repair restores destroyed armor and machine without cost")
	f.damage_at(local_at(target))
	check(f.repair_line() == 1 and f.cells[guard].armor_hp == 3,"clear repair also restores partially depleted armor")
	f.cells[Vector2i(5,3)] = f.make_cell("armor_block",0)
	f.damage_at(local_at(target))
	check(f.cells[guard].armor_hp == 2 and f.cells[Vector2i(5,3)].armor_hp == 3,"overlapping armor consumes only the nearest block")
	f.cells[Vector2i(10,4)] = f.make_cell("belt",0)
	f.damage_at(local_at(Vector2i(10,4)))
	check(not f.last_damage_blocked and not f.cells.has(Vector2i(10,4)),"distant equipment remains unprotected")
	for offset in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]:
		var nearby = Factory.new()
		nearby.cells[target] = nearby.make_cell("belt",0)
		nearby.cells[target+offset] = nearby.make_cell("armor_block",0)
		nearby.damage_at(local_at(target))
		check(nearby.last_damage_blocked and nearby.cells.has(target),"protects adjacent cell "+str(offset))
	var armor = f.make_cell("armor_block",0)
	var belt = f.make_cell("belt",0)
	check(not f.can_receive(armor,"scrap") and not f.can_link(armor,belt,0) and not f.can_link(belt,armor,0) and f.connection_sides(guard).outputs.is_empty(),"armor has no cargo or pipe connections")
	f.edit(guard,"erase",0)
	check(f.cells.has(guard),"combat lock prevents replacing depleted armor")
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"armor_block_test")
	game.show_start_menu = false
	game.expedition = Run.new(42)
	root.add_child(game)
	game.set_process(false)
	var legacy = game.checkpoint.snapshot(game)
	legacy.factory.inventory = game.factory.inventory.duplicate()
	legacy.factory.inventory.erase("armor_block")
	var key = InputEventKey.new()
	key.keycode = KEY_9
	key.pressed = true
	root.push_input(key)
	await process_frame
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)
	check("armor_block" in game.tool_kinds() and game.selected == "armor_block","9 key selects armor and reveals its available palette page")
	check("armor_block" in game.tool_kinds() and not game.tool_buttons.armor_block.disabled,"construction palette exposes an unlocked defense block")
	game.tool_buttons.armor_block.pressed.emit()
	game.hover = Vector2i(2,6)
	game._process(0)
	check(game.selected == "armor_block" and game.world.placement_preview.visible and game.world.preview_arrows.get_child_count() == 0,"shield tool previews solid armor without an output arrow")
	game.paint(game.hover,false)
	f = game.factory
	game._process(0)
	check(f.cells[game.hover].kind == "armor_block" and game.world.machines[game.hover].armor_plates.size() == 3,"UI places three layered metal plates")
	game.toggle_running()
	var b = game.battlefield
	b.player.rotation.y = PI/2
	var fuel_cell = Vector2i(2,7)
	var local = local_at(fuel_cell)
	var hit_at = b.player.position+Basis(Vector3.UP,b.player.rotation.y)*Vector3(local.x,0,local.y)
	b.receive_shell(f,hit_at,10,10)
	check(b.hull == 95 and f.cells[Vector2i(2,6)].armor_hp == 2 and f.cells.has(fuel_cell),"rotated vehicle takes half hull damage and protects fuel line")
	game.world.sync(f,Vector2i(-1,-1),"armor_block",0,0,false)
	check(game.world.machines[Vector2i(2,6)].armor_plates.filter(func(p): return p.visible).size() == 2,"remaining plates reflect actual durability")
	var saved = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved) and game.factory.cells[Vector2i(2,6)].armor_hp == 2,"partial armor durability survives checkpoint restoration")
	for invalid_hp in [0,4,1.5,"2"]:
		var bad = saved.duplicate(true)
		bad.factory.cells[Vector2i(2,6)].armor_hp = invalid_hp
		check(not game.checkpoint.validate(bad),"invalid armor durability rejected: "+str(invalid_hp))
	var missing = saved.duplicate(true)
	missing.factory.cells[Vector2i(2,6)].erase("armor_hp")
	check(not game.checkpoint.validate(missing),"missing armor durability rejected")
	var loaded = saved.duplicate(true)
	loaded.factory.cells[Vector2i(2,6)].items = ["coal"]
	check(not game.checkpoint.validate(loaded),"armor cannot load hidden cargo from a save")
	b = game.battlefield
	f = game.factory
	f.running = true
	for enemy in b.enemies:
		enemy.hp = 0
		enemy.active = true
	b.player.rotation = Vector3.ZERO
	b.player.position = b.obstacles.mines[0].position+Vector3(-8,0,0)
	f.cells[Vector2i(13,4)] = f.make_cell("belt",0)
	f.cells[Vector2i(13,3)] = f.make_cell("armor_block",0)
	var before_hull = b.hull
	b.tick_battle(f,0)
	check(b.hull == before_hull-ceili(b.hit_damage()*1.4*0.5) and f.cells[Vector2i(13,3)].armor_hp == 2 and f.cells.has(Vector2i(13,4)),"mine blast also consumes armor and reduces hull damage")
	check(game.checkpoint.apply(game,legacy) and "armor_block" in game.factory.unlocked_blocks,"old save without armor inventory loads and unlocks the new block")
	# Capture the integrated palette, three / two / one plates and placement ghost.
	f = game.factory
	game.selected = "armor_block"
	game.hover = Vector2i(5,6)
	for i in range(3):
		var p = Vector2i(1+i,6)
		f.edit(p,"armor_block",0)
		f.cells[p].armor_hp = 3-i
	if game.world.roof_closed: game.world.toggle_roof()
	game._process(0)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440,940)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview-armor-block.png")
		root.size = Vector2i(960,628)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview-armor-block-960.png")
	print("ARMOR BLOCK RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("armor_block_test")
