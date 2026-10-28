extends RefCounted
## Equipment definitions, rarity and seeded enemy loot. No live game state.
const Content = preload("res://scripts/content.gd")
const SECONDARY_HALF_ARC = PI/6.0
const RARITIES = {
	"normal":{"name":"ノーマル","color":"b0b7a4","weight":65,"power":1.0,"salvage":1.0},
	"uncommon":{"name":"アンコモン","color":"87bc80","weight":25,"power":1.1,"salvage":1.5},
	"rare":{"name":"レア","color":"7dadd2","weight":9,"power":1.25,"salvage":2.5},
	"legendary":{"name":"レジェンダリー","color":"e4b35c","weight":1,"power":1.5,"salvage":4.0}
}
const GENRES = {"secondary":"副砲","protection":"防御装備","engine":"動力装備","support":"支援装備","vehicle":"車体パーツ"}
const PART_SLOTS = {"gear":"ギア","engine":"エンジン","tracks":"履帯","cannon":"主砲"}
const Data = preload("res://scripts/equipment_data.gd")
const DEFINITIONS = Data.DEFINITIONS
const PLACEMENT_RULES = {"armor":"edge","skirts":"edge","supercharger":"engine","economizer":"engine","blast_fuse":"ammo_line","drum_loader":"ammo_line"}
const PLACEMENT_HINTS = {"edge":"車体の外周に配置","engine":"エンジン口に辺で隣接","ammo_line":"製造機・弾薬庫から砲へ届くパイプに辺で隣接"}

static func footprint(kind: String, direction: int = 0) -> Vector2i:
	var size: Vector2i = DEFINITIONS[kind].size
	return Vector2i(size.y,size.x) if posmod(direction,2) == 1 else size

static func part_slot(kind: String) -> String:
	return Data.ITEMS.get(kind,{}).get("slot","")

static func part_position(kind: String) -> Vector2i:
	return Vector2i(-2,PART_SLOTS.keys().find(part_slot(kind)))
const DROP_TABLES = {
	"frontline":[["left_gun",16],["right_gun",16],["rapid_gun",10],["rear_gun",8],["armor",16],["skirts",12],["supercharger",10],["servo",12]],
	"artillery":[["long_gun",18],["mortar_gun",18],["scatter_gun",12],["arc_gun",8],["rangefinder",16],["blast_fuse",14],["drum_loader",14]],
	"support":[["economizer",20],["salvage_arm",20],["supercharger",16],["servo",12],["drum_loader",12],["armor",10],["left_gun",10]]
}
const ROLE_TABLES = ["frontline","frontline","artillery","frontline","artillery","artillery","frontline","frontline","artillery","support","frontline","support","support","artillery","artillery","frontline"]

static func models(max_level: int, family_id: String = "") -> Array:
	var result: Array = []
	for id in Data.ACTIVE_IDS:
		if level(id) <= clampi(max_level,1,10) and (family_id.is_empty() or family(id) == family_id): result.append(id)
	return result

static func choose_model(rng: RandomNumberGenerator, family_id: String, max_level: int) -> String:
	var candidates = models(max_level,"left_gun" if family_id == "right_gun" else family_id)
	var total = 0
	for id in candidates: total += maxi(1,6-(max_level-level(id)))
	var pick = rng.randi_range(1,total)
	for id in candidates:
		pick -= maxi(1,6-(max_level-level(id)))
		if pick <= 0: return id
	return candidates.back()

static func roll(seed_value: int, source: int, role: int = 0, boss: bool = false, max_level: int = 0) -> Dictionary:
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
	# Default preserves old seeded rolls. Modern callers supply the sector cap.
	if max_level > 0:
		if rng.randf() < 0.25:
			var parts = Data.ITEMS.keys().filter(func(id): return not part_slot(id).is_empty())
			kind = parts[rng.randi_range(0,parts.size()-1)]
		else: kind = choose_model(rng,kind,clampi(max_level,1,10))
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

static func profile_icon(id: String) -> String:
	var spec = Data.ITEMS[id]
	if spec.profile == "focus": return "camera" if spec.genre == "secondary" else "settings"
	return {"balanced":"ready","rapid":"autoload","heavy":"shield","mobile":"move","power":"engine","economy":"fuel","efficient":"fuel"}.get(spec.profile,"ready")

static func effect_values(item: Dictionary) -> Dictionary:
	if item.get("stock",false): return {}
	var values: Dictionary = Data.ITEMS[item.kind].effects.duplicate()
	var power: float = RARITIES[item.rarity].power
	for key in values:
		# Quality improves benefits; operating costs and tradeoffs stay explicit.
		if (key == "fuel_bonus" and values[key] < 0) or (key not in ["fuel_bonus","ammo_tax","shot_fuel"] and values[key] > 0): values[key] *= power
	if item.kind == "salvage_arm": values.salvage_rate = 1.0/maxi(2,roundi(3/power))
	return values

static func weapon_cost(spec: Dictionary, effects: Dictionary) -> Dictionary:
	var ammo = int(spec.get("ammo",1))+int(effects.get("ammo_tax",0))
	return {"ammo":ammo,"fuel":ammo*float(effects.get("shot_fuel",0.0))+float(spec.get("shot_fuel",0.0))}

static func weapon_damage(spec: Dictionary, rarity: String = "normal") -> int:
	return maxi(1,roundi(float(spec.get("damage",1))*RARITIES[rarity].power))

static func description(item: Dictionary) -> String:
	if item.get("stock",false): return PART_SLOTS[part_slot(item.kind)]+"・初期装備 / 基礎性能（追加補正なし）"
	var kind: String = item.kind
	var power: float = RARITIES[item.rarity].power
	if kind in Content.ALL_GUNS:
		var spec: Dictionary = Content.EQUIPMENT[kind]
		var lines = ["%.2f秒間隔 / 射程%.1fm / 砲弾%d発" % [spec.interval/power,spec.range,spec.ammo],"前方 ±30° / 旋回 %.2frad/秒" % spec.turn]
		if spec.get("interceptor",false): lines.append("敵砲弾を迎撃 / 対地攻撃不可")
		else: lines.append("対装甲威力 %d" % weapon_damage(spec,item.rarity))
		if spec.get("shot_fuel",0) > 0: lines.append("1射あたり燃料 %.2f" % spec.shot_fuel)
		if spec.get("splash",0) > 0: lines.append("爆発半径 %.2fm" % spec.splash)
		if spec.get("pellets",1) > 1: lines.append("同時標的 %d両" % spec.pellets)
		if spec.get("chain",0) > 0: lines.append("追加連鎖 %d回" % spec.chain)
		return " / ".join(lines)
	var labels = {"damage_reduction":"被ダメージ","speed_bonus":"走行速度","fuel_bonus":"走行燃料消費","blast_reduction":"爆発・地雷ダメージ","turn_bonus":"砲塔旋回速度","reload_bonus":"射撃間隔","drive_turn_bonus":"車体旋回速度","main_reload_bonus":"主砲の射撃間隔"}
	var lines = [GENRES[Data.ITEMS[kind].genre]]
	if not part_slot(kind).is_empty(): lines = [PART_SLOTS[part_slot(kind)]+"交換パーツ"]
	if part_slot(kind) == "cannon": lines.append("対装甲威力 %d / 砲弾%d発" % [weapon_damage(Data.ITEMS[kind],item.rarity),Data.ITEMS[kind].ammo])
	var values = effect_values(item)
	for key in values:
		var value: float = values[key]
		if key in labels:
			if key in ["damage_reduction","blast_reduction","reload_bonus","main_reload_bonus"]: value = -value
			lines.append("%s %s%.1f%%" % [labels[key],"+" if value >= 0 else "−",absf(value)*100])
		elif key == "ammo_tax": lines.append("1射あたり砲弾 +%d発" % int(value))
		elif key == "shot_fuel": lines.append("消費砲弾1発あたり燃料 %.2f" % value)
		elif key == "range_bonus": lines.append("全砲の射程 +%.2fm" % value)
		elif key == "main_range_bonus": lines.append("主砲の射程 %+.2fm" % value)
		elif key == "main_splash_bonus": lines.append("主砲の爆発範囲 +%.2fm" % value)
		elif key == "offroad_bonus": lines.append("悪路の速度補正 +%.0f%%" % (value*100))
		elif key == "splash_bonus": lines.append("爆発範囲 +%.2fm" % value)
		elif key == "salvage_rate": lines.append("敵100体あたり素材 %.1f回を追加回収（廃材2・石炭1／回）" % (value*100))
	var rule: String = PLACEMENT_RULES.get(family(kind),"")
	if not rule.is_empty(): lines.append("発動条件："+PLACEMENT_HINTS[rule])
	return " / ".join(lines)
