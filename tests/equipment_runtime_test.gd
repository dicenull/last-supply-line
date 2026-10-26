extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
var checks = 0
var failures = 0
var game
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment runtime: ",label)
	else:
		failures += 1
		push_error(label)
func clear_shots(b):
	for shot in b.projectiles: shot.node.queue_free()
	b.projectiles.clear()
	if b.feedback != null: b.feedback.clear()
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_runtime_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	# Open road isolates equipment effects from collisions and terrain.
	for key in ["obstacles_version","field_version","encounters_version"]: game.expedition.current.erase(key)
	game.ensure_battle()
	var b = game.battlefield
	var f = game.factory
	b.sector_config.damage = 100
	for index in range(b.enemies.size()):
		b.enemies[index].active = index < 3
		b.enemies[index].node.position = Vector3(48+index*2,0,0)
	game.expedition.gear_items.clear()
	for id in Gear.DEFINITIONS:
		if not Gear.part_slot(id).is_empty(): continue
		var valid = true
		for rarity in Gear.RARITIES:
			var uid = game.expedition.add_item({"kind":id,"rarity":rarity})
			valid = game.place_item(uid,Vector2i(0,0)) and valid
			var effects = Inventory.effects(game.expedition)
			b.player.position = Vector3(40,0,0)
			b.player.rotation = Vector3.ZERO
			b.movement_direction = Vector3.RIGHT
			f.fuel = 12
			f.fuel_used = 0
			b.move_player(f,0.1)
			valid = valid and is_equal_approx(b.player.position.x-40,0.33*effects.speed) and is_equal_approx(f.fuel_used,0.33*effects.speed*0.12*effects.fuel)
			valid = valid and b.hit_damage() == ceili(100*effects.damage) and is_equal_approx(b.weapon_range(36),36+effects.range)
			clear_shots(b)
			if id in Gear.Content.ALL_GUNS:
				var spec = Gear.Data.ITEMS[id]
				var gun = b.auxiliary_guns[0]
				var offset = b.enemies[0].node.position-gun.pivot.global_position
				var angle = atan2(-offset.z,offset.x)
				gun.pivot.rotation.y = angle-0.2
				b.update_auxiliary_guns(f,0.01)
				valid = valid and is_equal_approx(gun.pivot.rotation.y,angle-0.2+spec.turn*0.01)
				gun.pivot.rotation.y = angle
				f.cells[Vector2i(0,0)].items = ["shell","shell"]
				b.update_auxiliary_guns(f,0.001)
				valid = valid and b.projectiles.size() == int(spec.get("pellets",1)) and f.auxiliary_ammo(id) == 2-int(spec.ammo) and is_equal_approx(gun.cooldown,spec.interval/Gear.RARITIES[rarity].power)
				for shot in b.projectiles: valid = valid and shot.style == spec.ballistics and is_equal_approx(shot.splash,spec.get("splash",0.0)) and shot.chain == int(spec.get("chain",0))
			else:
				var offset = b.enemies[0].node.position-b.turret.global_position
				var angle = atan2(-offset.z,offset.x)
				b.turret.rotation.y = angle-0.5
				f.ammo = 0
				b.update_gun(f,0.01)
				valid = valid and is_equal_approx(b.turret.rotation.y,angle-0.5+2.4*effects.turn*0.01)
				b.turret.rotation.y = angle
				b.cooldown = 0
				f.ammo = 1
				b.update_gun(f,0.001)
				valid = valid and b.projectiles.size() == 1 and is_equal_approx(b.projectiles[0].splash,effects.splash) and is_equal_approx(b.cooldown,60.0/f.rate*effects.reload) and f.ammo == 0
			clear_shots(b)
			valid = game.stow_item(uid) and valid
			var before = f.reserves.duplicate()
			var quote = Gear.salvage(Inventory.find_item(game.expedition,uid))
			valid = game.dismantle_item(uid) and valid and f.reserves.scrap == before.scrap+quote.scrap and f.reserves.coal == before.coal+quote.coal
		check(valid,"four qualities mount, affect real combat and movement, stow and salvage: "+id)
		await process_frame
	game.reset_battle(42)
	for id in Gear.DEFINITIONS:
		for rarity in Gear.RARITIES: game.expedition.add_item({"kind":id,"rarity":rarity})
	var snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.validate(snapshot) and game.checkpoint.write_file("user://equipment_runtime_test.mfv",snapshot),"all 1200 level/quality combinations fit the checkpoint contract")
	check(game.checkpoint.apply(game,game.checkpoint.read_file("user://equipment_runtime_test.mfv")) and game.expedition.gear_items == snapshot.run.gear_items,"disk reload preserves all 1200 full model identities")
	var uid = game.expedition.add_item({"kind":"mortar_gun_focus_l10","rarity":"legendary"})
	check(game.place_item(uid,Vector2i(0,0)),"advanced model can be mounted after full inventory reload")
	var copy = game.expedition.add_item({"kind":"mortar_gun_rapid_l07","rarity":"rare"})
	check(not game.place_item(copy,Vector2i(2,0)),"different models from the same family cannot stack")
	game.toggle_running()
	game.factory.running = false
	snapshot = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,snapshot) and game.factory.auxiliary_ids == ["mortar_gun_focus_l10"] and not game.stow_item(uid),"deployed advanced weapon restores its model identity and remains locked")
	b = game.battlefield
	b.sector_config.boss = true
	b.sector_config.sector = 5
	var last = b.enemies.size()-1
	var expected = Gear.roll(b.sector_config.seed,last,b.enemies[last].role,true,10)
	b.kill_enemy(b.enemies[last],game.factory,b.enemies[last].node.position)
	b.drive_poses = [{"position":b.enemies[last].node.position,"yaw":0.0}]
	b.update_ground_items(game.factory)
	var loot = game.expedition.gear_items.back()
	check(loot.kind == expected.kind and loot.rarity == expected.rarity and loot.rarity != "normal","actual last enemy uses boss quality and sector-five model pool")
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_runtime_test")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists("user://equipment_runtime_test.mfv"+suffix): DirAccess.remove_absolute("user://equipment_runtime_test.mfv"+suffix)
	print("EQUIPMENT RUNTIME RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
