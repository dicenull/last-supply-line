extends RefCounted
## Deterministic two-deck arrangement of the enlarged exposed weapons.
const GUN_SCALE = 2.0
const GUN_HEIGHT = 2.6
const UPPER_Y = 9.0
static func tiers(mounts: Dictionary, main_anchor: Vector2i) -> Dictionary:
	var result = {}
	var rectangles = {}
	var main_center = Vector2(main_anchor)+Vector2.ONE
	var main_rect = Rect2(main_center-Vector2.ONE*3.55,Vector2.ONE*7.1)
	var ids = mounts.keys()
	ids.sort()
	for id in ids:
		if id not in preload("res://scripts/equipment_catalog.gd").Content.ALL_GUNS: continue
		var area = Rect2(Vector2(mounts[id])-Vector2.ONE*0.95,Vector2.ONE*3.9)
		var collisions = [10 if area.intersects(main_rect) else 0,0]
		for previous in result:
			if area.intersects(rectangles[previous]): collisions[result[previous]] += 1
		result[id] = 1 if collisions[0] > collisions[1] else 0
		rectangles[id] = area
	return result
