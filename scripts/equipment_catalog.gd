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
const DEFINITIONS = {
	"left_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"right_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"rapid_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"long_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"mortar_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"rear_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"scatter_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"arc_gun":{"genre":"secondary","size":Vector2i(2,2)},
	"armor":{"genre":"protection","size":Vector2i(2,1)},
	"skirts":{"genre":"protection","size":Vector2i(2,1)},
	"supercharger":{"genre":"engine","size":Vector2i(2,1)},
	"economizer":{"genre":"engine","size":Vector2i(2,1)},
	"rangefinder":{"genre":"support","size":Vector2i(2,1)},
	"servo":{"genre":"support","size":Vector2i(1,1)},
	"salvage_arm":{"genre":"support","size":Vector2i(2,2)},
	"blast_fuse":{"genre":"support","size":Vector2i(1,1)},
	"drum_loader":{"genre":"support","size":Vector2i(2,1)}
}
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
