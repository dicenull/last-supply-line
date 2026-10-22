extends SceneTree
const F = preload("res://scripts/factory.gd")
const Run = preload("res://scripts/run_state.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment bulk: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	var run = Run.new(42)
	run.enable_items()
	var f = F.new(2)
	var rare = run.add_item({"kind":"left_gun","rarity":"rare"})
	var loaded = run.add_item({"kind":"right_gun","rarity":"normal"})
	Inventory.find_item(run,loaded).ammo = 2
	check(Inventory.normal_candidates(run.gear_items) == [1,2],"batch candidates exclude high quality and stored ammunition")
	check(Inventory.normal_candidates(run.gear_items,"protection") == [2],"genre filter scopes the reviewed normal equipment")
	var before = run.gear_items.duplicate(true)
	var stock = f.reserves.duplicate()
	for selection in [[],[1,1],[1,rare],[1,loaded],[1,999],[1,"2"]]:
		check(not Inventory.dismantle_normals(run,f,selection) and run.gear_items == before and f.reserves == stock,"invalid selection is atomic: "+str(selection))
	var selected = Inventory.normal_candidates(run.gear_items)
	check(Inventory.place(run,f,1,Vector2i(0,0)),"fixture installs a previously reviewed item")
	before = run.gear_items.duplicate(true)
	check(not Inventory.dismantle_normals(run,f,selected) and run.gear_items == before and f.reserves == stock,"mounting one reviewed item prevents the entire stale batch")
	Inventory.stow(run,f,1)
	var quote = Inventory.quote_normals(run.gear_items,selected)
	var new_loot = run.add_item({"kind":"armor","rarity":"normal"})
	check(quote.count == 2 and quote.scrap == 9 and quote.coal == 5,"preview shows exact combined yields")
	run.start_sector()
	f.loadout_locked = true
	check(Inventory.dismantle_normals(run,f,selected) and f.reserves.scrap == stock.scrap+9 and f.reserves.coal == stock.coal+5,"reviewed stowed items can be dismantled during travel")
	check(not Inventory.find_item(run,new_loot).is_empty() and not Inventory.find_item(run,rare).is_empty() and Inventory.find_item(run,loaded).ammo == 2,"new arrivals and protected equipment survive batch dismantling")
	stock = f.reserves.duplicate()
	check(not Inventory.dismantle_normals(run,f,selected) and f.reserves == stock,"confirming an already consumed selection cannot duplicate materials")
	for phase in ["won","lost","retreated"]:
		run.phase = phase
		check(not Inventory.dismantle_normals(run,f,[new_loot]) and not Inventory.find_item(run,new_loot).is_empty(),"terminal phase rejects bulk dismantling: "+phase)
	print("EQUIPMENT BULK RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
