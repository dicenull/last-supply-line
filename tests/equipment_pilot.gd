extends RefCounted
## Paid actions for long-running modern-hull simulations; never grants stock.
const Inventory = preload("res://scripts/equipment_inventory.gd")
const Gear = Inventory.Catalog
const Blueprints = preload("res://scripts/blueprints.gd")
const POSITIONS = {"armor":Vector2i(0,3),"economizer":Vector2i(2,3),"skirts":Vector2i(0,5),"drum_loader":Vector2i(2,5)}

static func prepare(game, variant: int = 0):
	if game.world.roof_closed: game.world.toggle_roof()
	var chosen: Array = []
	var slots: Dictionary = {}
	for kind in POSITIONS:
		var best = best_item(game.expedition.gear_items,[kind],variant)
		if not best.is_empty():
			chosen.append(best.uid)
			slots[best.uid] = POSITIONS[kind]
	var gun = best_item(game.expedition.gear_items,Gear.Content.GUNS,variant)
	if not gun.is_empty():
		chosen.append(gun.uid)
		slots[gun.uid] = Vector2i(0,0)
	for item in game.expedition.gear_items:
		if item.position != Inventory.STOWED: game.stow_item(item.uid)
	for item in game.expedition.gear_items.duplicate():
		if item.uid not in chosen: game.dismantle_item(item.uid)
	game.factory.restore(Blueprints.layout("parallel",2))
	for uid in chosen: game.place_item(uid,slots[uid])
	if not gun.is_empty():
		game.factory.edit(Vector2i(8,1),"splitter",3)
		for x in range(2,9): game.factory.edit(Vector2i(x,0),"belt",1 if x == 2 else 2)
		game.factory.edit(Vector2i(2,1),"belt",2)
	for p in [Vector2i(5,1),Vector2i(10,1),Vector2i(4,3),Vector2i(6,6),Vector2i(9,7)]:
		if not game.factory.cells.has(p): game.factory.edit(p,"armor_block",0)

static func best_item(items: Array, kinds: Array, variant: int) -> Dictionary:
	var best: Dictionary = {}
	var score = -1
	for item in items:
		if item.kind not in kinds: continue
		var value = Gear.RARITIES.keys().find(item.rarity)*100+posmod(kinds.find(item.kind)+variant,kinds.size())
		if value > score:
			best = item
			score = value
	return best

static func maintain(game):
	# Keep the best copy of each useful family for the next preparation.
	# Dismantle duplicates and other support gear to supply current production.
	var retained: Array = []
	for kind in Gear.Content.GUNS+POSITIONS.keys():
		var best = best_item(game.expedition.gear_items,[kind],0)
		if not best.is_empty(): retained.append(best.uid)
	for item in game.expedition.gear_items.duplicate():
		if item.position == Inventory.STOWED and item.uid not in retained: game.dismantle_item(item.uid)
	if not game.factory.wrecks.is_empty() or game.battlefield.hull < 70: game.repair_vehicle()
