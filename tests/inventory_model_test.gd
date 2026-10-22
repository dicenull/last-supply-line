extends SceneTree
const F = preload("res://scripts/factory.gd")
const Run = preload("res://scripts/run_state.gd")
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var rarities = {}
	var kinds = {}
	for role in range(16):
		for i in range(256):
			var item = Gear.roll(42,i,role)
			rarities[item.rarity] = true
			kinds[item.kind] = true
	check(rarities.size() == 4 and kinds.size() == Gear.DEFINITIONS.size(),"all four rarities and 17 definitions are reachable through enemy tables")
	for table in Gear.DROP_TABLES.values():
		var weight = 0
		for row in table: weight += row[1]
		check(weight == 100,"enemy table weights sum to 100")
	check(Gear.roll(42,7,2) == Gear.roll(42,7,2),"enemy loot is stable across reload")
	check(not Gear.valid({"kind":"made_up","rarity":"normal"}) and not Gear.valid({"kind":"armor","rarity":"mythic"}),"unknown definitions and rarities are rejected")
	var f = F.new(2)
	f.example(false)
	f.finite_resources = true
	f.auto_fire = false
	f.running = true
	for i in range(400): f.step(0.1)
	check(f.ammo == 12 and f.fuel > 0,"central starter line supplies both 2×2 magazine and rear engine")
	check(f.ports == F.Layout.PORTS and f.blocks == F.Layout.WALLS,"new fixed fittings and central walls use shared layout data")
	var filled = F.new(2)
	filled.auto_fire = false
	filled.ammo = 11
	for at in [Vector2i(9,2),Vector2i(10,2)]:
		filled.cells[at] = filled.make_cell("belt",1)
		filled.cells[at].items.append("shell")
	filled.simulate_tick()
	check(filled.ammo <= 12,"simultaneous magazine inputs cannot exceed shared capacity")
	var r = Run.new(42)
	r.enable_items()
	var uid = r.gear_items[0].uid
	check(r.gear_items.size() == 3 and r.equipment.is_empty(),"issued gear starts stowed and inactive")
	check(not Inventory.place(r,f,uid,Vector2i(6,3)) and not Inventory.place(r,f,uid,Vector2i(13,7)) and not Inventory.place(r,f,uid,Vector2i(4,2)),"gear rejects stock, out-of-bounds and wall overlap")
	check(Inventory.place(r,f,uid,Vector2i(0,0)),"2×2 gun mounts on a free footprint")
	check(f.mounted_at(Vector2i(1,1)) == "left_gun" and not f.can_place(Vector2i(1,1),"belt"),"every footprint cell reserves space against construction")
	var duplicate = r.add_item({"kind":"left_gun","rarity":"rare"})
	check(not Inventory.place(r,f,duplicate,Vector2i(2,0)),"same-kind copy cannot overwrite installed item")
	check(not Inventory.dismantle(r,f,uid),"installed equipment cannot be dismantled")
	var before = f.reserves.duplicate()
	var materials = Gear.salvage(Inventory.find_item(r,duplicate))
	check(Inventory.dismantle(r,f,duplicate) and f.reserves.scrap == before.scrap+materials.scrap and f.reserves.coal == before.coal+materials.coal,"dismantling grants precisely the rarity-adjusted materials")
	check(not Inventory.dismantle(r,f,duplicate),"dismantle is one-shot")
	f.ammo = f.ammo_capacity
	f.cells[f.auxiliary_position("left_gun")].items = ["shell","shell"]
	check(Inventory.stow(r,f,uid) and Inventory.find_item(r,uid).ammo == 2 and f.ammo == f.ammo_capacity,"stowing into a full main magazine preserves rounds inside the item")
	check(Inventory.place(r,f,uid,Vector2i(0,0)) and f.auxiliary_ammo("left_gun") == 2 and Inventory.find_item(r,uid).ammo == 0,"reinstalling transfers stored rounds exactly once")
	check(Inventory.place(r,f,uid,Vector2i(1,0)) and f.auxiliary_ammo("left_gun") == 2,"moving an installed item never resets or duplicates ammunition")
	r.start_sector()
	f.loadout_locked = true
	var footprint = f.equipment_mounts.duplicate()
	check(not Inventory.place(r,f,uid,Vector2i(2,0)) and not Inventory.stow(r,f,uid) and not f.move_auxiliary("left_gun",Vector2i(2,0)) and not f.remove_equipment("left_gun"),"departure locks equip, move and stow through model APIs")
	f.remove_auxiliary()
	check(f.equipment_mounts == footprint and "left_gun" in f.auxiliary_ids and not f.install_auxiliary("right_gun"),"legacy installation APIs cannot bypass equipment lock")
	f.combat_editing = true
	f.edit(Vector2i(3,0),"belt",0)
	check(f.cells.has(Vector2i(3,0)),"line construction remains available during travel")
	var distinct_shops = true
	var shops = 0
	var extra_offers: Dictionary = {}
	for seed_value in range(512):
		var model = Run.new(seed_value)
		model.enable_items()
		var course = Run.FieldCourse.new(model.current)
		for i in range(course.destinations.size()):
			if course.destinations[i].encounter != "shop": continue
			model.start_sector()
			model.finish_sector(true,100,{},true,i)
			model.choose_reward(0)
			shops += 1
			var offers: Array = model.current.shop_offers
			distinct_shops = distinct_shops and model.phase == "shop" and offers.size() == 3 and offers[2] not in offers.slice(0,2)
			extra_offers[offers[2]] = true
	check(shops > 300 and distinct_shops,"modern shops offer three distinct equipment families")
	check(extra_offers.size() == Gear.DEFINITIONS.size()-2,"every non-fixed equipment family remains available as the third shop offer")
	print("INVENTORY MODEL RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
