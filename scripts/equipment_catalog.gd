extends RefCounted
## Equipment definitions, rarity and seeded enemy loot. No live game state.
const Content = preload("res://scripts/content.gd")
const RARITIES = {
	"normal":{"name":"ノーマル","color":"b0b7a4","weight":65,"power":1.0,"salvage":1.0},
	"uncommon":{"name":"アンコモン","color":"87bc80","weight":25,"power":1.1,"salvage":1.5},
	"rare":{"name":"レア","color":"7dadd2","weight":9,"power":1.25,"salvage":2.5},
	"legendary":{"name":"レジェンダリー","color":"e4b35c","weight":1,"power":1.5,"salvage":4.0}
}
const GENRES = {"secondary":"副砲","protection":"防御装備","engine":"動力装備","support":"支援装備"}
const Data = preload("res://scripts/equipment_data.gd")
const DEFINITIONS = Data.DEFINITIONS
const DROP_TABLES = {
	"frontline":[["left_gun",16],["right_gun",16],["rapid_gun",10],["rear_gun",8],["armor",16],["skirts",12],["supercharger",10],["servo",12]],
	"artillery":[["long_gun",18],["mortar_gun",18],["scatter_gun",12],["arc_gun",8],["rangefinder",16],["blast_fuse",14],["drum_loader",14]],
	"support":[["economizer",20],["salvage_arm",20],["supercharger",16],["servo",12],["drum_loader",12],["armor",10],["left_gun",10]]
}
const ROLE_TABLES = ["frontline","frontline","artillery","frontline","artillery","artillery","frontline","frontline","artillery","support","frontline","support","support","artillery","artillery","frontline"]

static func roll(seed_value: int, source: int, role: int = 0, boss: bool = false) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value+104729*(source+1)+8677
	var table = DROP_TABLES[ROLE_TABLES[posmod(role,ROLE_TABLES.size())]]
	var pick = rng.randi_range(1,100)
	var kind: String = table.back()[0]
	for row in table:
		pick -= row[1]
		if pick <= 0:
			kind = row[0]
			break
	var weights = [0,20,65,15] if boss else [65,25,9,1]
	pick = rng.randi_range(1,100)
	var rarity = "normal"
	for i in range(weights.size()):
		pick -= weights[i]
		if pick <= 0:
			rarity = RARITIES.keys()[i]
			break
	return {"kind":kind,"rarity":rarity}

static func salvage(item: Dictionary) -> Dictionary:
	var gear: Dictionary = Content.EQUIPMENT[item.kind]
	var multiplier: float = RARITIES[item.rarity].salvage
	return {"scrap":ceili(gear.scrap/4.0*multiplier),"coal":ceili(gear.coal/2.0*multiplier)}

static func valid(item) -> bool:
	return item is Dictionary and item.get("kind") in DEFINITIONS and item.get("rarity") in RARITIES

static func family(id: String) -> String:
	return str(Data.ITEMS.get(id,{}).get("family",id))

static func level(id: String) -> int:
	return int(Data.ITEMS[id].level)

static func effect_values(item: Dictionary) -> Dictionary:
	var values: Dictionary = Data.ITEMS[item.kind].effects.duplicate()
	var power: float = RARITIES[item.rarity].power
	for key in values:
		# Quality improves benefits; operating costs and tradeoffs stay explicit.
		if (key == "fuel_bonus" and values[key] < 0) or (key != "fuel_bonus" and values[key] > 0): values[key] *= power
	if item.kind == "salvage_arm": values.salvage_rate = 1.0/maxi(2,roundi(3/power))
	return values

static func description(item: Dictionary) -> String:
	var kind: String = item.kind
	var power: float = RARITIES[item.rarity].power
	if kind in Content.ALL_GUNS:
		var spec: Dictionary = Content.EQUIPMENT[kind]
		var lines = ["Lv.%d · %.2f秒間隔 / 射程%.1fm / 砲弾%d発" % [level(kind),spec.interval/power,spec.range,spec.ammo],"旋回 %.2frad/秒" % spec.turn]
		if spec.get("splash",0) > 0: lines.append("爆発半径 %.2fm" % spec.splash)
		if spec.get("pellets",1) > 1: lines.append("同時標的 %d両" % spec.pellets)
		if spec.get("chain",0) > 0: lines.append("追加連鎖 %d回" % spec.chain)
		return " / ".join(lines)
	var labels = {"damage_reduction":"被ダメージ","speed_bonus":"走行速度","fuel_bonus":"燃料消費","turn_bonus":"砲塔旋回速度","reload_bonus":"射撃間隔"}
	var lines = ["装備 Lv.%d" % level(kind)]
	var values = effect_values(item)
	for key in values:
		var value: float = values[key]
		if key in labels:
			if key in ["damage_reduction","reload_bonus"]: value = -value
			lines.append("%s %s%.1f%%" % [labels[key],"+" if value >= 0 else "−",absf(value)*100])
		elif key == "range_bonus": lines.append("全砲の射程 +%.2fm" % value)
		elif key == "splash_bonus": lines.append("爆発範囲 +%.2fm" % value)
		elif key == "salvage_rate": lines.append("敵100体あたり装備 %.1f個を追加回収" % (value*100))
	return " / ".join(lines)
