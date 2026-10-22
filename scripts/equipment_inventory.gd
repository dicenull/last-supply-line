extends RefCounted
## Atomic inventory commands shared by UI, save validation and simulation tests.
const Catalog = preload("res://scripts/equipment_catalog.gd")
const STOWED = Vector2i(-1,-1)

static func find_item(run, uid: int) -> Dictionary:
	for item in run.gear_items:
		if item.uid == uid: return item
	return {}

static func editable(run, factory) -> bool:
	return run.item_mode and run.phase == "prepare" and not factory.loadout_locked and not factory.layout_locked

static func can_place(run, factory, uid: int, at: Vector2i) -> bool:
	var item = find_item(run,uid)
	if item.is_empty() or not editable(run,factory): return false
	if item.position == STOWED and item.kind in run.equipment: return false
	return factory.can_place_equipment(item.kind,at)

static func place(run, factory, uid: int, at: Vector2i) -> bool:
	if not can_place(run,factory,uid,at): return false
	var item = find_item(run,uid)
	var was_stowed: bool = item.position == STOWED
	if not factory.place_equipment(item.kind,at): return false
	if was_stowed and item.kind in factory.AUXILIARY:
		factory.cells[at].items.resize(int(item.get("ammo",0)))
		factory.cells[at].items.fill("shell")
		item.ammo = 0
	item.position = at
	if item.kind not in run.equipment: run.equipment.append(item.kind)
	return true

static func stow(run, factory, uid: int) -> bool:
	var item = find_item(run,uid)
	if item.is_empty() or not editable(run,factory) or item.position == STOWED: return false
	# Loaded rounds stay with the removed weapon, so a full main magazine never
	# prevents changing the loadout between departures or discards ammunition.
	var rounds = factory.auxiliary_ammo(item.kind) if item.kind in factory.auxiliary_ids else 0
	if not factory.remove_equipment(item.kind): return false
	item.ammo = rounds
	item.position = STOWED
	run.equipment.erase(item.kind)
	return true

static func dismantle(run, factory, uid: int) -> bool:
	var item = find_item(run,uid)
	if not run.item_mode or item.is_empty() or item.position != STOWED or run.phase in ["lost","won","retreated"]: return false
	var materials = Catalog.salvage(item)
	run.gear_items.erase(item)
	for raw in materials: factory.collect(raw,materials[raw])
	return true

static func normal_candidates(items: Array, genre: String = "") -> Array:
	var result: Array = []
	for item in items:
		if item.rarity == "normal" and item.position == STOWED and item.get("ammo",0) == 0 and (genre == "" or Catalog.DEFINITIONS[item.kind].genre == genre): result.append(item.uid)
	return result

static func quote_normals(items: Array, uids: Array) -> Dictionary:
	if uids.is_empty() or uids.size() > items.size(): return {}
	var lookup: Dictionary = {}
	for item in items: lookup[item.uid] = item
	var quote = {"count":uids.size(),"scrap":0,"coal":0}
	var seen: Dictionary = {}
	for uid in uids:
		if not uid is int or seen.has(uid) or not lookup.has(uid): return {}
		seen[uid] = true
		var item: Dictionary = lookup[uid]
		if item.rarity != "normal" or item.position != STOWED or item.get("ammo",0) != 0: return {}
		var materials = Catalog.salvage(item)
		quote.scrap += materials.scrap
		quote.coal += materials.coal
	return quote

static func dismantle_normals(run, factory, uids: Array) -> bool:
	if not run.item_mode or run.phase in ["lost","won","retreated"]: return false
	var quote = quote_normals(run.gear_items,uids)
	if quote.is_empty(): return false
	# Validate the complete reviewed selection before removing any item. New loot
	# received since the preview is deliberately outside this explicit selection.
	for index in range(run.gear_items.size()-1,-1,-1):
		if run.gear_items[index].uid in uids: run.gear_items.remove_at(index)
	for raw in ["scrap","coal"]: factory.collect(raw,quote[raw])
	return true

static func powers(run) -> Dictionary:
	var result = {}
	for item in run.gear_items:
		if item.position != STOWED: result[item.kind] = Catalog.RARITIES[item.rarity].power
	return result
