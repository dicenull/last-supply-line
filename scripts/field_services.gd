extends RefCounted
## Shared identifiers and prices for route encounters and repair services.
const ENCOUNTERS = ["standard","rich","hostile","shop"]
const ICONS = {"rich":"rich_site","hostile":"hostile_site","shop":"shop"}
const COAL_PRICE = 12
const COAL_AMOUNT = 24
const SHELL_PRICE = 10
const SHELL_AMOUNT = 12
const GEAR_PRICE = 32

static func icon(site: Dictionary) -> String:
	return ICONS.get(site.get("encounter","standard"),preload("res://scripts/pixel_icons.gd").DESTINATIONS[site.kind])

static func price(id: String) -> int:
	if id.begins_with("gear:"): return int(preload("res://scripts/equipment_data.gd").ITEMS.get(id.trim_prefix("gear:"),{}).get("shop_price",GEAR_PRICE))
	return COAL_PRICE if id == "coal" else SHELL_PRICE if id == "shell" else GEAR_PRICE

static func repair_cost(factory) -> int:
	var parts = factory.wrecks.size()
	for cell in factory.cells.values():
		if cell.kind == "armor_block" and cell.armor_hp < factory.ARMOR_HITS: parts += 1
	return parts*2
