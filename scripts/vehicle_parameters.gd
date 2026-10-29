extends RefCounted
## Read-only loadout projection; shares the live equipment effect calculation.
const Inventory = preload("res://scripts/equipment_inventory.gd")
const RunState = preload("res://scripts/run_state.gd")
const Battle = preload("res://scripts/battle_world.gd")
const METRICS = {
	"power":{"label":"主砲 対装甲威力","unit":"","digits":0,"lower":false},
	"ammo":{"label":"主砲 1射の砲弾消費","unit":"発","digits":0,"lower":true},
	"shot_fuel":{"label":"主砲 1射の燃料消費","unit":"","digits":2,"lower":true},
	"blast_damage":{"label":"爆発・地雷 被害倍率","unit":"%","digits":1,"lower":true},
	"speed":{"label":"最高速度","unit":"m/s","digits":2,"lower":false},
	"turn":{"label":"車体旋回","unit":"°/s","digits":1,"lower":false},
	"fuel":{"label":"燃料消費 / m","unit":"","digits":3,"lower":true},
	"reload":{"label":"主砲 射撃間隔","unit":"秒","digits":2,"lower":true},
	"range":{"label":"主砲 射程","unit":"m","digits":1,"lower":false},
	"splash":{"label":"主砲 爆発範囲","unit":"m","digits":1,"lower":false},
	"damage":{"label":"被ダメージ倍率","unit":"%","digits":1,"lower":true},
	"offroad":{"label":"悪路速度倍率","unit":"%","digits":1,"lower":false},
	"turret":{"label":"砲塔旋回","unit":"°/s","digits":1,"lower":false},
	"salvage":{"label":"撃破時の追加回収率","unit":"%","digits":1,"lower":false},
}

static func values(run, factory, items: Array, empty_slots: Array) -> Dictionary:
	var effects = Inventory.effects_for(items,empty_slots,factory)
	var terrain = RunState.condition(run.current)
	var speed = float(terrain.speed)*run.modifiers.get("speed",1.0)*effects.speed
	var cannon = "cannon" not in empty_slots
	var part: Dictionary = {}
	for item in items:
		if Inventory.Catalog.part_slot(item.kind) == "cannon" and item.position != Inventory.STOWED: part = item
	var spec: Dictionary = Inventory.Catalog.Data.ITEMS[part.kind] if not part.is_empty() else {}
	var cost = Inventory.Catalog.weapon_cost(spec,effects)
	return {"power":Inventory.Catalog.weapon_damage(spec,part.get("rarity","normal")) if cannon else null,"ammo":cost.ammo if cannon else null,"shot_fuel":cost.fuel if cannon else null,"blast_damage":effects.blast_damage*effects.damage*run.modifiers.get("damage",1.0)*100,"speed":speed,"turn":rad_to_deg(Battle.TURN_SPEED*speed/3.3*effects.drive_turn),
		"fuel":Battle.FUEL_PER_METER*run.modifiers.fuel*terrain.fuel*effects.fuel,
		"reload":60.0/factory.rate*run.modifiers.get("reload",1.0)*effects.reload*effects.main_reload if cannon else null,
		"range":Battle.ENGAGEMENT_RANGE+run.modifiers.get("range",0.0)+effects.range+effects.main_range if cannon else null,
		"splash":effects.splash+effects.main_splash if cannon else null,
		"damage":effects.damage*run.modifiers.get("damage",1.0)*100,
		"offroad":minf(1.0,0.65+effects.offroad)*100,
		"turret":rad_to_deg(2.4*effects.turn),"salvage":effects.salvage_rate*100}

static func compare(run, factory, selected_uid: int = -1, at: Vector2i = Vector2i(-1,-1), direction: int = 0) -> Dictionary:
	var baseline = values(run,factory,[],[])
	var current = values(run,factory,run.gear_items,run.empty_part_slots)
	var item = Inventory.find_item(run,selected_uid)
	var candidate = current.duplicate()
	var selected = not item.is_empty()
	var activation = Inventory.Activation.status(factory,item,Inventory.Activation.ammo_network(factory)) if selected else {}
	if selected and (item.position == Inventory.STOWED or (Inventory.Catalog.part_slot(item.kind).is_empty() and factory.inside(at))):
		var projected: Array = run.gear_items.duplicate(true)
		var empty_slots: Array = run.empty_part_slots.duplicate()
		var slot = Inventory.Catalog.part_slot(item.kind)
		for part in projected:
			if part.uid == selected_uid: continue
			if (not slot.is_empty() and Inventory.Catalog.part_slot(part.kind) == slot) or (slot.is_empty() and Inventory.Catalog.family(part.kind) == Inventory.Catalog.family(item.kind)):
				part.position = Inventory.STOWED
		for part in projected:
			if part.uid == selected_uid:
				part.position = Inventory.Catalog.part_position(part.kind) if not slot.is_empty() else at if factory.inside(at) else (Inventory.STOWED if not Inventory.Activation.requirement(part.kind).is_empty() else Vector2i.ZERO)
				part.direction = direction
				activation = Inventory.Activation.status(factory,part,Inventory.Activation.ammo_network(factory))
		empty_slots.erase(slot)
		candidate = values(run,factory,projected,empty_slots)
	var rows = {}
	for key in METRICS:
		rows[key] = {"base":baseline[key],"current":current[key],"after":candidate[key],
			"bonus":difference(current[key],baseline[key]),"change":difference(candidate[key],current[key])}
	return {"rows":rows,"activation":activation,"selected":selected,"item":item.duplicate(true),"editable":Inventory.editable(run,factory)}

static func difference(after, before):
	return null if after == null or before == null else float(after)-float(before)

static func number(key: String, value, signed: bool = false) -> String:
	if value == null: return "—"
	var rounded = snappedf(float(value),pow(10.0,-METRICS[key].digits))
	if is_zero_approx(rounded): rounded = 0.0
	return (("+" if signed and rounded > 0 else "")+(("%."+str(METRICS[key].digits)+"f") % rounded))

static func format_values(run, factory) -> Dictionary:
	var result = values(run,factory,run.gear_items,run.empty_part_slots)
	for key in result:
		result[key] = ("装備なし" if key == "reload" else "—") if result[key] == null else number(key,result[key])+(" "+METRICS[key].unit if not METRICS[key].unit.is_empty() else "")
	return result

static func benefit(key: String, after, before) -> int:
	if after == null: return 0 if before == null else -1
	if before == null: return 1
	var change = float(after)-float(before)
	if is_zero_approx(change): return 0
	return int(signf(change))*(-1 if METRICS[key].lower else 1)
