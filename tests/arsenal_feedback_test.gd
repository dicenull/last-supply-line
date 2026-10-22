extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var battle
var factory
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS arsenal: ",label)
	else:
		failures += 1
		push_error(label)
func isolate(positions: Dictionary):
	for shot in battle.projectiles: shot.node.queue_free()
	for shot in battle.bolts: shot.node.queue_free()
	battle.projectiles.clear()
	battle.bolts.clear()
	for effect in battle.impacts: effect.node.queue_free()
	battle.impacts.clear()
	if battle.feedback != null: battle.feedback.clear()
	for enemy in battle.enemies:
		enemy.active = true
		enemy.hp = 0
		enemy.node.visible = false
		enemy.node.position = Vector3(500+20*enemy.role,0,100)
		enemy.node.scale = Vector3.ONE
		enemy.mark.visible = false
		enemy.cooldown = 60
		enemy.locked = false
	for role in positions:
		var enemy = battle.enemies[role]
		enemy.hp = 1
		enemy.node.visible = true
		enemy.node.position = positions[role]
	battle.kills = battle.total-positions.size()
	battle.combo = 0
	battle.hull = 100
	battle.result = 0
	battle.distance = 0
	battle.player.position = Vector3.ZERO
	battle.player.rotation = Vector3.ZERO
	battle.movement_direction = Vector3.ZERO
	battle.cooldown = 0
	factory.ammo = 0
	factory.fuel = 0
	factory.running = true
	for id in factory.auxiliary_ids: factory.cells[factory.auxiliary_position(id)].items.clear()
	for gun in battle.auxiliary_guns: gun.cooldown = 0
	battle.update_camera()
func load_gun(id: String, count: int):
	for i in range(count): factory.cells[factory.auxiliary_position(id)].items.append("shell")
func aim_gun(id: String, role: int):
	for gun in battle.auxiliary_guns:
		if gun.id != id: continue
		var offset: Vector3 = battle.enemies[role].node.position-gun.pivot.global_position
		gun.pivot.rotation.y = atan2(-offset.z,offset.x)
func run():
	var line_factory = preload("res://scripts/factory.gd").new()
	line_factory.auto_fire = false
	line_factory.install_auxiliary("scatter_gun")
	line_factory.install_auxiliary("arc_gun")
	line_factory.move_auxiliary("scatter_gun",Vector2i(5,2))
	line_factory.move_auxiliary("arc_gun",Vector2i(5,5))
	for y in [2,5]:
		line_factory.edit(Vector2i(1,y),"belt",0)
		line_factory.edit(Vector2i(2,y),"furnace",0)
		line_factory.edit(Vector2i(3,y),"belt",0)
		line_factory.edit(Vector2i(4,y),"press",0)
	for i in range(160): line_factory.simulate_tick()
	check(line_factory.auxiliary_ammo("scatter_gun") == 12 and line_factory.auxiliary_ammo("arc_gun") == 12 and line_factory.ammo == 0,"two constructed production lines fill the new guns independently from raw material")
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"arsenal_feedback_test")
	game.show_start_menu = false
	game.expedition = Run.new(42)
	game.expedition.current.enemies = range(Run.Content.ENEMIES.size())
	game.expedition.current.enemies.append(13)
	root.add_child(game)
	game.set_process(false)
	factory = game.factory
	check(factory.install_auxiliary("scatter_gun") and factory.install_auxiliary("arc_gun"),"new guns create separate movable output ports")
	game.expedition.equipment = ["scatter_gun","arc_gun"]
	game.expedition.recipes = ["scatter_gun","arc_gun","blast_fuse","drum_loader"]
	game.sync_equipment()
	game.selected = "erase"
	for id in ["scatter_gun","arc_gun"]:
		game.hover = factory.auxiliary_position(id)
		await capture("res://preview-inspector-"+id+".png")
	game.selected = "belt"
	game.toggle_running()
	battle = game.battlefield
	isolate({0:Vector3(24,0,0),1:Vector3(24,0,-7),2:Vector3(24,0,7)})
	load_gun("scatter_gun",2)
	load_gun("arc_gun",1)
	aim_gun("scatter_gun",0)
	var shots_before = factory.shots
	battle.update_auxiliary_guns(factory,0.001)
	check(battle.projectiles.size() == 3 and factory.shots == shots_before+2,"scatter fires three real projectiles for exactly two shells")
	check(factory.auxiliary_ammo("scatter_gun") == 0 and factory.auxiliary_ammo("arc_gun") == 1,"scatter cannot consume the other gun's stock")
	await capture("res://preview-arsenal-scatter-shot.png")
	battle.update_gun(factory,0.8)
	check(battle.enemies[0].hp == 0 and battle.enemies[1].hp == 0 and battle.enemies[2].hp == 0,"three separated vehicles are destroyed by one forward volley")
	isolate({0:Vector3(24,0,0),1:Vector3(31,0,0),2:Vector3(38,0,0),3:Vector3(53,0,0)})
	load_gun("arc_gun",2)
	aim_gun("arc_gun",0)
	battle.update_auxiliary_guns(factory,0.001)
	check(battle.projectiles.size() == 1 and battle.projectiles[0].chain == 2 and battle.projectiles[0].style == "electric","charged gun launches a two-hop electric round")
	await capture("res://preview-arsenal-electric-shot.png")
	var snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot) and game.checkpoint.write_file("user://arsenal_feedback_test.mfv",snapshot),"new equipment and airborne chain round form a valid on-disk checkpoint: "+game.checkpoint.error)
	var invalid = snapshot.duplicate(true)
	invalid.battle.projectiles[0].chain = 3
	check(not game.checkpoint.validate(invalid),"out-of-range chain counts cannot enter a checkpoint")
	invalid.battle.projectiles[0].chain = 1.5
	check(not game.checkpoint.validate(invalid),"fractional chain counts cannot enter a checkpoint")
	var legacy = snapshot.duplicate(true)
	legacy.battle.projectiles[0].erase("chain")
	check(game.checkpoint.validate(legacy) and game.checkpoint.apply(game,legacy) and game.battlefield.projectiles[0].chain == 0,"older projectiles without a chain field restore with no new hops")
	var from_disk = game.checkpoint.read_file("user://arsenal_feedback_test.mfv")
	check(not from_disk.is_empty() and game.checkpoint.apply(game,from_disk),"airborne chain shot restores from disk")
	battle = game.battlefield
	factory = game.factory
	battle.update_gun(factory,0.8)
	check(battle.enemies[0].hp == 0 and battle.enemies[1].hp == 0 and battle.enemies[2].hp == 0 and battle.enemies[3].hp == 1,"restored shot jumps twice and stops before an out-of-range vehicle")
	check(battle.feedback.emitted.get("arc",0) == 2,"both real chain hits generate connecting electric arcs")
	await capture("res://preview-arsenal-chain.png")
	game.expedition.equipment.append_array(["blast_fuse","drum_loader"])
	game.sync_equipment()
	isolate({0:Vector3(24,0,0),1:Vector3(30.5,0,0),2:Vector3(40,0,0)})
	factory.ammo = 1
	battle.turret.rotation.y = 0
	battle.update_gun(factory,0.001)
	check(battle.projectiles.size() == 1 and battle.projectiles[0].splash == 4 and is_equal_approx(battle.cooldown,60.0/factory.rate*battle.reload_multiplier*0.8),"fuse and drum change actual main-gun splash and reload")
	battle.update_gun(factory,0.8)
	check(battle.enemies[0].hp == 0 and battle.enemies[1].hp == 0 and battle.enemies[2].hp == 1,"blast reaches a nearby hull without needing overlapping vehicles")
	isolate({13:Vector3(24,0,0),0:Vector3(31,0,0),1:Vector3(40,0,0)})
	var scrap_before = factory.reserves.scrap
	battle.kill_enemy(battle.enemies[13],factory,Vector3(24,1,0))
	check(battle.enemies[0].hp == 0 and battle.enemies[1].hp == 1 and battle.combo == 2,"powder carrier detonates nearby enemies within its blast radius")
	check(factory.reserves.scrap == scrap_before+7,"detonation awards salvage for each destroyed vehicle exactly once")
	battle.kill_enemy(battle.enemies[13],factory,Vector3(24,1,0))
	check(factory.reserves.scrap == scrap_before+7 and battle.combo == 2,"a wreck cannot trigger repeated detonations or rewards")
	isolate({13:Vector3(24,0,0),16:Vector3(34,0,0),0:Vector3(43,0,0),1:Vector3(58,0,0)})
	scrap_before = factory.reserves.scrap
	battle.kill_enemy(battle.enemies[13],factory,Vector3(24,1,0))
	check(battle.enemies[16].hp == 0 and battle.enemies[0].hp == 0 and battle.enemies[1].hp == 1 and battle.combo == 3,"a second powder carrier propagates the blast beyond the first radius")
	check(factory.reserves.scrap == scrap_before+12,"recursive powder detonations award each vehicle exactly once")
	isolate({14:Vector3(30,0,0)})
	var rocket = battle.enemies[14]
	rocket.cooldown = 0.01
	battle.tick_battle(factory,0.05)
	check(rocket.locked and rocket.mark.visible and battle.bolts.is_empty(),"rocket volley gives a warning before firing")
	var footprints = []
	for child in rocket.mark.get_children(): footprints.append(child.position.z)
	check(footprints == [-8.0,-4.0,4.0,8.0],"rocket warning reveals all five impact areas before launch")
	await capture("res://preview-arsenal-volley-warning.png")
	rocket.cooldown = 0.01
	battle.tick_battle(factory,0.05)
	check(battle.bolts.size() == 5 and battle.bolts.all(func(b): return b.style == "mortar"),"rocket vehicle launches five actual mortar-profile projectiles")
	var spread = []
	for bolt in battle.bolts: spread.append(bolt.target.z)
	check(spread == [-8.0,-4.0,0.0,4.0,8.0],"five-shot volley is centered on the telegraphed target")
	isolate({15:Vector3(24,0,0)})
	var ram = battle.enemies[15]
	battle.tick_battle(factory,0.1)
	check(ram.node.position.x < 24 and ram.mark.visible and battle.bolts.is_empty(),"rammer approaches with a visible warning and no ranged shots")
	ram.node.position = Vector3(9,0,0)
	battle.tick_battle(factory,0.01)
	check(battle.hull < 100 and ram.hp == 0,"rammer detonates once upon hull contact")
	var damaged_hull = battle.hull
	battle.tick_battle(factory,0.1)
	check(battle.hull == damaged_hull,"destroyed rammer cannot repeat contact damage")
	isolate({13:Vector3(24,0,-9),14:Vector3(28,0,0),15:Vector3(24,0,9)})
	await capture("res://preview-arsenal-enemies.png")
	check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"new enemies and passive gear remain checkpoint-compatible")
	print("ARSENAL RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func capture(path: String):
	if DisplayServer.get_name() == "headless": return
	game._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func _finalize():
	Fixture.clean("arsenal_feedback_test")
	for suffix in ["",".bak",".tmp"]:
		var path = "user://arsenal_feedback_test.mfv"+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
