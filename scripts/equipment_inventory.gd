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

static func place(run, factory, uid: int, at: Vector2i) -> bool:
	var item = find_item(run,uid)
	if item.is_empty() or not editable(run,factory): return false
	if item.position == STOWED and item.kind in run.equipment: return false
	if not factory.place_equipment(item.kind,at): return false
	item.position = at
	if item.kind not in run.equipment: run.equipment.append(item.kind)
	return true

static func stow(run, factory, uid: int) -> bool:
	var item = find_item(run,uid)
	if item.is_empty() or not editable(run,factory) or item.position == STOWED: return false
	# Return loaded ammunition to the main magazine only when it all fits.
	# Otherwise keep the installation intact; silently losing ammunition is unsafe.
	var rounds = factory.auxiliary_ammo(item.kind) if item.kind in factory.auxiliary_ids else 0
	if rounds+factory.ammo > factory.ammo_capacity: return false
	if not factory.remove_equipment(item.kind): return false
	factory.ammo += rounds
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

static func powers(run) -> Dictionary:
	var result = {}
	for item in run.gear_items:
		if item.position != STOWED: result[item.kind] = Catalog.RARITIES[item.rarity].power
	return result
