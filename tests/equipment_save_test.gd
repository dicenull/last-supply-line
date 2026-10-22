extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const PATH = "user://equipment_save_test.mfv"
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment save: ",label)
	else:
		failures += 1
		push_error(label)
func reject(data: Dictionary, label: String):
	var before = game.checkpoint.snapshot(game)
	check(not game.checkpoint.apply(game,data) and game.checkpoint.snapshot(game) == before,label+" rejects atomically")
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_save_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.place_item(game.expedition.gear_items[0].uid,Vector2i(0,0))
	game.place_item(game.expedition.gear_items[1].uid,Vector2i(2,0))
	game.expedition.gear_items[0].rarity = "legendary"
	game.factory.cells[Vector2i(0,0)].items = ["shell","shell"]
	var data = game.checkpoint.snapshot(game)
	check(game.checkpoint.write_file(PATH,data) and game.checkpoint.read_file(PATH) == data,"disk round-trip preserves rarity, identity, footprint and loaded ammunition")
	for section in ["factory","run"]:
		var fields = ["layout_version","equipment_mounts"] if section == "factory" else ["item_mode","gear_items","next_item_uid"]
		for field in fields:
			var bad = data.duplicate(true)
			bad[section].erase(field)
			reject(bad,"missing "+field)
	for field in ["recipes","equipment","stage_recipes"]:
		for value in [0,{},"wrong",null,[123]]:
			var bad = data.duplicate(true)
			bad.run[field] = value
			reject(bad,"malformed "+field+" "+str(value))
	for value in [0,{},"wrong",null,[123]]:
		var bad = data.duplicate(true)
		bad.run.gear_items = value
		reject(bad,"malformed item collection "+str(value))
	for key in ["uid","kind","rarity","position"]:
		var bad = data.duplicate(true)
		bad.run.gear_items[0].erase(key)
		reject(bad,"missing item "+key)
	for value in [0,-1,1.5,"4",1]:
		var bad = data.duplicate(true)
		bad.run.next_item_uid = value
		reject(bad,"invalid next identity "+str(value))
	for at in [Vector2i(1,0),Vector2i(9,3),Vector2i(11,0),Vector2i(13,7),Vector2i(-1,0)]:
		var bad = data.duplicate(true)
		bad.factory.equipment_mounts.left_gun = at
		bad.run.gear_items[0].position = at
		var cell: Dictionary = bad.factory.cells[Vector2i(0,0)]
		bad.factory.cells.erase(Vector2i(0,0))
		bad.factory.cells[at] = cell
		reject(bad,"invalid matching footprint "+str(at))
	for value in [-1,1.5,"2",29]:
		var bad = data.duplicate(true)
		bad.run.gear_items[2].ammo = value
		reject(bad,"invalid stored ammunition "+str(value))
	var duplicated_rounds = data.duplicate(true)
	duplicated_rounds.run.gear_items[0].ammo = 2
	reject(duplicated_rounds,"installed ammunition cannot also live in the inventory item")
	game.factory.ammo = game.factory.ammo_capacity
	check(game.stow_item(1),"full main magazine still permits stowing a loaded weapon")
	var stowed = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,stowed) and game.expedition.gear_items[0].ammo == 2 and game.factory.auxiliary_ids.is_empty(),"stowed loaded weapon survives checkpoint")
	check(game.place_item(1,Vector2i(0,0)) and game.factory.auxiliary_ammo("left_gun") == 2,"loaded weapon can be reinstalled after checkpoint")
	var duplicate = data.duplicate(true)
	duplicate.run.gear_items[2] = duplicate.run.gear_items[0].duplicate()
	duplicate.run.gear_items[2].uid = 3
	reject(duplicate,"two installed copies of one equipment family")
	var mismatched = data.duplicate(true)
	mismatched.factory.cells[Vector2i(0,0)].kind = "right_gun"
	reject(mismatched,"ammunition port differs from equipment kind")
	var legacy = load("res://main.tscn").instantiate()
	Fixture.assign(legacy,"equipment_save_legacy",1)
	legacy.show_start_menu = false
	root.add_child(legacy)
	legacy.set_process(false)
	await process_frame
	var old = legacy.checkpoint.snapshot(legacy)
	old.version = 9
	for key in ["layout_version","equipment_mounts"]: old.factory.erase(key)
	for key in ["item_mode","gear_items","next_item_uid"]: old.run.erase(key)
	check(game.checkpoint.apply(game,old) and game.factory.layout_version == 1 and not game.expedition.item_mode and game.expedition.gear_items.is_empty(),"version-nine run restores original hull and loot economy")
	check(game.checkpoint.apply(game,data) and game.factory.auxiliary_ammo("left_gun") == 2 and game.expedition.gear_items == data.run.gear_items,"switching back to modern save restores gear without extra grants")
	game.toggle_running()
	var combat = game.checkpoint.snapshot(game)
	check(game.checkpoint.write_file(PATH,combat) and game.checkpoint.apply(game,game.checkpoint.read_file(PATH)) and game.factory.loadout_locked,"travel save reloads with immutable loadout")
	check(not game.factory.move_auxiliary("left_gun",Vector2i(0,2)) and not game.stow_item(1),"reload cannot bypass movement or removal lock")
	game.reset_battle(42)
	var mortar = game.expedition.add_item({"kind":"mortar_gun","rarity":"legendary"})
	var fuse = game.expedition.add_item({"kind":"blast_fuse","rarity":"legendary"})
	game.place_item(mortar,Vector2i(0,0))
	game.place_item(fuse,Vector2i(2,0))
	game.toggle_running()
	game.factory.cells[Vector2i(0,0)].items = ["shell","shell"]
	var target: Dictionary = game.battlefield.enemies[0]
	target.node.position = Vector3(12,0,0)
	target.node.visible = true
	target.active = true
	game.battlefield.update_auxiliary_guns(game.factory,0.1)
	check(game.battlefield.projectiles.size() == 1 and game.battlefield.projectiles[0].splash == 10.0,"legendary mortar and fuse produce a ten-meter splash")
	check(game.checkpoint.validate(game.checkpoint.snapshot(game)),"strongest equipment combination remains saveable mid-flight")
	legacy.queue_free()
	game.queue_free()
	await process_frame
	for suite in ["equipment_save_test","equipment_save_legacy"]: Fixture.clean(suite)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print("EQUIPMENT SAVE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
