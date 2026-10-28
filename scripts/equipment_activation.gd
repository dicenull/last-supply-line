extends RefCounted
## Spatial conditions only; no recipes, named builds, or completion bonuses.
const Gear = preload("res://scripts/equipment_catalog.gd")
const RULES = Gear.PLACEMENT_RULES
const HINTS = Gear.PLACEMENT_HINTS
static func requirement(kind: String) -> String:
	return HINTS.get(RULES.get(Gear.family(kind),""),"")
static func perimeter(at: Vector2i, size: Vector2i) -> Array:
	var cells: Array = []
	for x in range(size.x):
		cells.append(at+Vector2i(x,-1))
		cells.append(at+Vector2i(x,size.y))
	for y in range(size.y):
		cells.append(at+Vector2i(-1,y))
		cells.append(at+Vector2i(size.x,y))
	return cells
static func reachable(seeds: Array, graph: Dictionary) -> Dictionary:
	var visited = {}
	var queue = seeds.duplicate()
	for at in queue: visited[at] = true
	var index = 0
	while index < queue.size():
		var at = queue[index]
		index += 1
		for next in graph.get(at,[]):
			if visited.has(next): continue
			visited[next] = true
			queue.append(next)
	return visited
static func ammo_network(factory) -> Dictionary:
	var forward = {}
	var reverse = {}
	var sources: Array = []
	var weapons: Array = []
	for at in factory.cells:
		var cell: Dictionary = factory.cells[at]
		if cell.kind in ["press","auto_press","depot"]: sources.append(at)
		if cell.kind == "gun" or cell.kind in factory.AUXILIARY:
			weapons.append(at)
			continue
		# Only actual shell outputs carry the effect; fuel-only links never count.
		if factory.RECIPES.has(cell.kind) and factory.RECIPES[cell.kind][1] != "shell": continue
		if cell.kind in ["source","coal_source","engine","armor_block"]: continue
		if factory.FILTERS.has(cell.kind) and factory.FILTERS[cell.kind] != "shell": continue
		if cell.kind == "fuel_depot": continue
		for direction in factory.output_directions(cell,"shell"):
			var dest: Vector2i = at+factory.DIRS[direction]
			var receiver: Dictionary = factory.receiving_cell(dest)
			if receiver.is_empty() or not factory.accepts_kind(receiver,"shell"): continue
			dest = factory.equipment_mounts.get(receiver.kind,dest)
			if not forward.has(at): forward[at] = []
			if not reverse.has(dest): reverse[dest] = []
			forward[at].append(dest)
			reverse[dest].append(at)
	var from_source = reachable(sources,forward)
	var to_weapon = reachable(weapons,reverse)
	var result = {}
	for at in from_source:
		if to_weapon.has(at): result[at] = true
	return result
static func status(factory, item: Dictionary, network: Dictionary = {}) -> Dictionary:
	var rule: String = RULES.get(Gear.family(item.kind),"")
	var hint: String = HINTS.get(rule,"")
	if item.position == Vector2i(-1,-1): return {"active":false,"reason":"未設置","requirement":hint}
	if rule.is_empty(): return {"active":true,"reason":"有効","requirement":""}
	var at: Vector2i = item.position
	var size = Gear.footprint(item.kind,item.get("direction",0))
	var neighbors = perimeter(at,size)
	var active = false
	match rule:
		"edge": active = at.x == 0 or at.y == 0 or at.x+size.x == factory.W or at.y+size.y == factory.H
		"engine": active = neighbors.any(func(pos): return factory.ports.get(pos,"") == "engine")
		"ammo_line": active = neighbors.any(func(pos): return network.has(pos) and factory.cells.get(pos,{}).get("kind","") in ["belt","splitter","smart_splitter","priority_splitter","router","shell_filter","overflow_gate"])
	return {"active":active,"reason":"有効" if active else {"edge":"外周が必要","engine":"エンジン隣接が必要","ammo_line":"弾薬パイプ未接続"}[rule],"requirement":hint}
static func all_statuses(factory, items: Array) -> Dictionary:
	var network = ammo_network(factory)
	var result = {}
	for item in items: result[item.uid] = status(factory,item,network)
	return result
