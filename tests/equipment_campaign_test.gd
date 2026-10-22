extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
const Blueprints = preload("res://scripts/blueprints.gd")
var game
var checks = 0
var failures = 0
var outcomes: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment campaign: ",label)
	else:
		failures += 1
		push_error(label)
func prepare():
	for kind in ["armor","economizer","skirts","drum_loader"]:
		var best: Dictionary = {}
		var installed: Dictionary = {}
		for item in game.expedition.gear_items:
			if Gear.family(item.kind) != kind: continue
			if item.position != Inventory.STOWED: installed = item
			if best.is_empty() or Gear.RARITIES[item.rarity].power*(1+0.025*(Gear.level(item.kind)-1)) > Gear.RARITIES[best.rarity].power*(1+0.025*(Gear.level(best.kind)-1)): best = item
		if best.is_empty() or best.position != Inventory.STOWED: continue
		var at = {"armor":Vector2i(0,0),"economizer":Vector2i(2,0),"skirts":Vector2i(0,1),"drum_loader":Vector2i(2,1)}[kind]
		if not installed.is_empty(): game.stow_item(installed.uid)
		game.place_item(best.uid,at)
	for item in game.expedition.gear_items.duplicate():
		if item.position == Inventory.STOWED: game.dismantle_item(item.uid)
	game.factory.restore(Blueprints.layout("parallel",2))
	for p in [Vector2i(5,1),Vector2i(10,1),Vector2i(4,3),Vector2i(6,6),Vector2i(9,7)]:
		if not game.factory.cells.has(p): game.factory.edit(p,"armor_block",0)
func run():
	DirAccess.make_dir_recursive_absolute("res://build/equipment-audit")
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_campaign_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	for seed_value in [42,117,991]:
		game.reset_battle(seed_value)
		var valid_saves = true
		var scraps = 0
		for sector in range(1,6):
			prepare()
			game.toggle_running()
			for tick in range(4500):
				Fixture.drive(game,0.1,seed_value%game.battlefield.goals.size())
				if tick%20 == 0:
					for item in game.expedition.gear_items.duplicate():
						if item.position == Inventory.STOWED and game.dismantle_item(item.uid): scraps += 1
					if not game.factory.wrecks.is_empty() or game.battlefield.hull < 70: game.repair_vehicle()
				if game.expedition.phase != "travel": break
			valid_saves = valid_saves and game.checkpoint.validate(game.checkpoint.snapshot(game))
			if game.expedition.phase != "reward": break
			game.choose_run_option(0)
			if game.expedition.phase == "shop": game.leave_shop()
			valid_saves = valid_saves and game.checkpoint.validate(game.checkpoint.snapshot(game))
			if game.expedition.phase == "won": break
		var row = {"seed":seed_value,"phase":game.expedition.phase,"cleared":game.expedition.cleared,"salvaged":scraps,"hull":game.battlefield.hull,"position":str(game.battlefield.player.position),"reserves":game.factory.reserves.duplicate(),"wrecks":str(game.factory.wrecks),"fuel":game.factory.fuel}
		outcomes.append(row)
		print("CAMPAIGN OUTCOME ",JSON.stringify(row))
		check(game.expedition.phase == "won","protected new-layout campaign completes five sectors: "+str(seed_value))
		check(scraps > 0 and game.factory.collected.scrap > 0 and game.factory.collected.coal > 0,"dismantled equipment supplies the entire campaign economy")
		check(valid_saves,"new loot and installed equipment remain saveable across sector transitions")
		await process_frame
	var file = FileAccess.open("res://build/equipment-audit/campaign.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(outcomes,"  "))
	file.close()
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_campaign_test")
	print("EQUIPMENT CAMPAIGN RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
