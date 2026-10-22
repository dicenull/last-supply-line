extends RefCounted
const Content = preload("res://scripts/content.gd")
## Deterministic, fixed-step production and local equipment damage.
const W = 14
const H = 8
const TICK = 0.25
const DIRS = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const BLOCKS: Array[Vector2i] = []
const AMMO_PORT = Vector2i(9,4)
const FUEL_PORT = Vector2i(4,7)
const PORTS = {Vector2i(0,2): "source", Vector2i(0,5): "source", AMMO_PORT: "gun", Vector2i(0,7): "coal_source", FUEL_PORT: "engine"}
const LIMITS = Content.BLOCK_LIMITS
const ARMOR_HITS = 3
const ARMOR_DAMAGE_MULTIPLIER = 0.5
const RECIPES = {"furnace":["scrap","steel",6],"press":["steel","shell",8],"refinery":["coal","fuel",8],"blast_furnace":["scrap","steel",3],"auto_press":["steel","shell",4]}
const FILTERS = {"scrap_filter":"scrap","shell_filter":"shell","fuel_filter":"fuel"}
const AUXILIARY = {"left_gun":Vector2i(11,1),"right_gun":Vector2i(11,6),"rapid_gun":Vector2i(8,0),"long_gun":Vector2i(12,4),"mortar_gun":Vector2i(6,6),"rear_gun":Vector2i(2,0),"scatter_gun":Vector2i(10,6),"arc_gun":Vector2i(10,0)}
var auxiliary_ids: Array = []
var cells: Dictionary = {}
# Destroyed buildable cells; no salvage value or functioning inventory remains.
var wrecks: Dictionary = {}
var wreck_directions: Dictionary = {}
var last_damage_blocked = false
# Retained only to read equipment inventories from version 4 saves.
var inventory: Dictionary = {}
var unlocked_blocks: Array = Content.STARTING_BLOCKS.keys()
var running = false
var layout_locked = false
var auto_fire = true
var finite_resources = false
var reserves = {"scrap":48,"coal":32}
var collected = {"scrap":0,"coal":0}
# Legacy save/reward metadata only; raw resource storage has no gameplay cap.
var reserve_capacity = 100
var work_multiplier = 1.0
var ammo_capacity = 12
var clock = 0.0
var elapsed = 0.0
var ticks = 0
var fuel = 0.0
var fuel_used = 0.0
var ammo = 0
var rate = 60
var fire_clock = 0.0
var shots = 0
var supplied = 0
var injected = 0
var manufactured = 0
var missed = 0
var history: Array = []
var moves: Array = []
var completed: Array = []
var message = "空の車内です。入口から精錬炉・砲弾機・試射口をつないでください。"
var undo_stack: Array = []
var feedback_events: Array = []

func feedback_event(kind: String, cell: Vector2i):
	feedback_events.append({"kind":kind,"cell":cell})
	while feedback_events.size() > 64: feedback_events.pop_front()

func _init():
	for kind in LIMITS: inventory[kind] = Content.STARTING_BLOCKS.get(kind,0)
	clear_layout(false)
	message = "空の車内です。入口から精錬炉・砲弾機・試射口をつないでください。"

func make_cell(kind: String, direction: int) -> Dictionary:
	var cell = {"kind":kind, "dir":direction, "items":[], "work":0, "turn":0, "incoming":0, "made":0, "busy":0}
	if kind == "armor_block": cell.armor_hp = ARMOR_HITS
	return cell

func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < W and p.y >= 0 and p.y < H

func auxiliary_position(id: String) -> Vector2i:
	for p in cells:
		if cells[p].kind == id: return p
	return Vector2i(-1,-1)

func auxiliary_positions() -> Dictionary:
	var result = {}
	for id in auxiliary_ids: result[id] = auxiliary_position(id)
	return result

func install_position(id: String) -> Vector2i:
	if not AUXILIARY.has(id) or id in auxiliary_ids: return Vector2i(-1,-1)
	if not cells.has(AUXILIARY[id]): return AUXILIARY[id]
	for y in range(H):
		for x in range(W):
			var p = Vector2i(x,y)
			if not cells.has(p) and p not in BLOCKS: return p
	return Vector2i(-1,-1)

func install_auxiliary(id: String) -> bool:
	if layout_locked: return false
	var p = install_position(id)
	if not inside(p): return false
	auxiliary_ids.append(id)
	cells[p] = make_cell(id,0)
	wrecks.erase(p)
	wreck_directions.erase(p)
	# Older undo layouts predate this paid equipment and its reserved cell.
	undo_stack.clear()
	return true

func remove_auxiliary():
	if layout_locked: return
	for p in cells.keys():
		if AUXILIARY.has(cells[p].kind): cells.erase(p)
	auxiliary_ids.clear()
	undo_stack.clear()

func can_move_auxiliary(id: String, destination: Vector2i) -> bool:
	return not layout_locked and id in auxiliary_ids and inside(destination) and destination not in BLOCKS and not cells.has(destination)

func move_auxiliary(id: String, destination: Vector2i) -> bool:
	var source = auxiliary_position(id)
	if not inside(source) or not can_move_auxiliary(id,destination): return false
	remember()
	cells[destination] = cells[source]
	wrecks.erase(destination)
	wreck_directions.erase(destination)
	cells.erase(source)
	moves.clear()
	return true

func auxiliary_ammo(id: String) -> int:
	var p = auxiliary_position(id)
	return cells[p].items.size() if cells.has(p) else 0

func count_kind(kind: String) -> int:
	var n = 0
	for c in cells.values():
		if c.kind == kind: n += 1
	return n

func available(kind: String) -> int:
	if kind not in unlocked_blocks or not LIMITS.has(kind): return 0
	var amount = LIMITS[kind]-count_kind(kind)
	for raw in Content.BUILD_COSTS[kind]:
		var cost: int = Content.BUILD_COSTS[kind][raw]
		if cost > 0: amount = mini(amount,int(reserves[raw]/cost))
	return maxi(0,amount)

func construction_cost(layout_cells: Dictionary) -> Dictionary:
	var total = {"scrap":0,"coal":0}
	for cell in layout_cells.values():
		if not Content.BUILD_COSTS.has(cell.kind): continue
		for raw in total: total[raw] += Content.BUILD_COSTS[cell.kind][raw]
	return total

func construction_balance(pending: Dictionary) -> Dictionary:
	var old_cost = construction_cost(cells)
	var new_cost = construction_cost(pending)
	var balance = {}
	for raw in reserves:
		balance[raw] = reserves[raw]+old_cost[raw]-new_cost[raw]
	return balance

func pay_construction(pending: Dictionary) -> bool:
	var balance = construction_balance(pending)
	for raw in balance:
		if balance[raw] < 0:
			message = "設置に必要な素材がありません。"
			return false
	for raw in balance: reserves[raw] = balance[raw]
	return true

func can_place(p: Vector2i, kind: String) -> bool:
	if layout_locked or not inside(p) or PORTS.has(p) or p in BLOCKS: return false
	if cells.has(p) and AUXILIARY.has(cells[p].kind): return false
	if kind == "erase": return cells.has(p)
	if not LIMITS.has(kind): return false
	if not cells.has(p) or cells[p].kind != kind:
		if kind not in unlocked_blocks or count_kind(kind) >= LIMITS[kind]: return false
	var pending = cells.duplicate()
	pending[p] = make_cell(kind,0)
	for value in construction_balance(pending).values():
		if value < 0: return false
	return true

func damage_at(local_hit: Vector2) -> Vector2i:
	last_damage_blocked = false
	# One local breach per damaging shell. Empty space and fixed vehicle ports
	# do not redirect a hit to an unrelated line elsewhere in the vehicle.
	var target = Vector2i(-1,-1)
	var nearest = 1.75 * 1.75
	for p in cells:
		if not LIMITS.has(cells[p].kind): continue
		var center = Vector2(p.x-(W-1)*0.5,p.y-(H-1)*0.5)
		var distance = center.distance_squared_to(local_hit)
		if distance < nearest:
			nearest = distance
			target = p
	if not inside(target): return target
	# The closest adjacent armor absorbs this hit, including its final hit.
	# Overlapping protection never stacks or charges two blocks at once.
	var guard = Vector2i(-1,-1)
	var guard_distance = INF
	for p in cells:
		if cells[p].kind != "armor_block" or maxi(absi(p.x-target.x),absi(p.y-target.y)) > 1: continue
		var distance = Vector2(p.x-(W-1)*0.5,p.y-(H-1)*0.5).distance_squared_to(local_hit)
		if distance < guard_distance:
			guard_distance = distance
			guard = p
	if inside(guard):
		last_damage_blocked = true
		feedback_event("armor",guard)
		cells[guard].armor_hp -= 1
		undo_stack.clear()
		if cells[guard].armor_hp > 0:
			message = "防御ブロックが被弾を防ぎました。残り%d回" % cells[guard].armor_hp
			return Vector2i(-1,-1)
		target = guard
	wrecks[target] = cells[target].kind
	feedback_event("remove",target)
	wreck_directions[target] = cells[target].dir
	cells.erase(target)
	# A combat event bypasses editing locks, without pausing production. It must
	# never offer salvage or allow pre-hit undo to resurrect the destroyed part.
	undo_stack.clear()
	moves = moves.filter(func(move): return move.from != target and move.to != target)
	completed.erase(target)
	message = Content.reward_info("block:"+wrecks[target]).name+"が部位破壊されました。"
	return target

func repair_line() -> int:
	# Clear service restores hardware, never lost cargo or spent ammunition.
	var repaired = 0
	for p in cells:
		if cells[p].kind == "armor_block" and cells[p].armor_hp < ARMOR_HITS:
			cells[p].armor_hp = ARMOR_HITS
			repaired += 1
	for p in wrecks:
		if cells.has(p): continue
		cells[p] = make_cell(wrecks[p],int(wreck_directions.get(p,0)))
		repaired += 1
	wrecks.clear()
	wreck_directions.clear()
	undo_stack.clear()
	return repaired

func grant_blocks(kind: String, amount: int) -> int:
	if not LIMITS.has(kind) or amount <= 0: return 0
	var accepted = mini(amount,LIMITS[kind]-int(inventory.get(kind,0)))
	inventory[kind] = int(inventory.get(kind,0))+accepted
	return accepted

func reset_inventory():
	for kind in LIMITS: inventory[kind] = Content.STARTING_BLOCKS.get(kind,0)
	var kept = {}
	for p in cells.keys():
		var kind: String = cells[p].kind
		if not LIMITS.has(kind): continue
		kept[kind] = kept.get(kind,0)+1
		if kept[kind] > inventory[kind]: cells.erase(p)
	undo_stack.clear()

func layout() -> Array:
	var result: Array = []
	for p in cells:
		if not PORTS.has(p): result.append([p.x,p.y,cells[p].kind,cells[p].dir])
	return result

func remember():
	undo_stack.append(layout())
	if undo_stack.size() > 50: undo_stack.pop_front()

func reset_trial():
	feedback_events.clear()
	running = false
	clock = 0
	elapsed = 0
	ticks = 0
	ammo = 0
	fuel = 0.0
	fuel_used = 0.0
	fire_clock = 0
	shots = 0
	supplied = 0
	injected = 0
	manufactured = 0
	missed = 0
	history.clear()
	moves.clear()
	completed.clear()
	for p in cells:
		cells[p] = make_cell(cells[p].kind, cells[p].dir)
	message = "配置を保ったまま、物資・計測値をリセットしました。"

func clear_layout(record: bool = true, pay: bool = true):
	if layout_locked: return
	var mounts = auxiliary_positions()
	var rows: Array = []
	for id in mounts: rows.append([mounts[id].x,mounts[id].y,id,0])
	var before = layout()
	if not restore(rows,pay): return
	wrecks.clear()
	wreck_directions.clear()
	if record:
		undo_stack.append(before)
		if undo_stack.size() > 50: undo_stack.pop_front()

func restore(rows: Array, pay: bool = true) -> bool:
	if layout_locked: return false
	# Validate the whole layout before changing anything, including saved files.
	var pending: Dictionary = {}
	var counts: Dictionary = {}
	for row in rows:
		if not row is Array or row.size() != 4: return false
		if not (row[0] is float or row[0] is int) or not (row[1] is float or row[1] is int): return false
		if not row[2] is String or not (row[3] is int or row[3] is float): return false
		if float(row[0]) != floor(float(row[0])) or float(row[1]) != floor(float(row[1])) or float(row[3]) != floor(float(row[3])): return false
		var p = Vector2i(int(row[0]),int(row[1]))
		var kind: String = row[2]
		var direction = int(row[3])
		if not inside(p) or PORTS.has(p) or p in BLOCKS or pending.has(p) or (not LIMITS.has(kind) and kind not in auxiliary_ids) or direction < 0 or direction > 3: return false
		counts[kind] = counts.get(kind, 0) + 1
		if counts[kind] > LIMITS.get(kind,1): return false
		pending[p] = make_cell(kind, direction)
	for id in auxiliary_ids:
		if counts.has(id): continue
		var p = auxiliary_position(id)
		if not inside(p) or pending.has(p): return false
		pending[p] = make_cell(id,0)
	if pay:
		for kind in counts:
			if LIMITS.has(kind) and kind not in unlocked_blocks and counts[kind] > count_kind(kind):
				message = "この設備の設計図は未解放です。"
				return false
		if not pay_construction(pending): return false
	cells = pending
	for p in cells:
		wrecks.erase(p)
		wreck_directions.erase(p)
	for p in PORTS: cells[p] = make_cell(PORTS[p], 0)
	reset_trial()
	if pay:
		for p in cells:
			if LIMITS.has(cells[p].kind): feedback_event("place",p)
	return true

func undo():
	if layout_locked: return
	if undo_stack.is_empty(): return
	if not restore(undo_stack.back()): return
	undo_stack.pop_back()
	message = "配置を1操作戻しました。物資・計測値はリセット。"

func edit(p: Vector2i, kind: String, direction: int):
	if layout_locked: return
	if not inside(p) or PORTS.has(p) or p in BLOCKS: return
	if cells.has(p) and AUXILIARY.has(cells[p].kind): return
	if kind == "erase":
		if not cells.has(p): return
		var pending = cells.duplicate()
		pending.erase(p)
		if not pay_construction(pending): return
		remember()
		cells.erase(p)
		feedback_event("remove",p)
	else:
		if not LIMITS.has(kind): return
		if cells.has(p) and cells[p].kind == kind and cells[p].dir == direction: return
		if not can_place(p,kind):
			message = "この設備の設計図は未解放です。" if kind not in unlocked_blocks else "素材不足または搭載上限で設置できません。"
			return
		var pending = cells.duplicate()
		pending[p] = make_cell(kind,direction)
		if not pay_construction(pending): return
		remember()
		cells[p] = make_cell(kind, direction)
		wrecks.erase(p)
		wreck_directions.erase(p)
		feedback_event("place",p)
		if not connection_sides(p).connected.is_empty(): feedback_event("connect",p)
	moves.clear()
	completed.clear()
	running = false
	message = "配置変更で一時停止。変更したマスの物資は破棄。開始で続きを試せます。"

func rotate(p: Vector2i):
	if cells.has(p) and not PORTS.has(p): edit(p, cells[p].kind, (cells[p].dir + 1) % 4)

func can_receive(c: Dictionary, item: String) -> bool:
	if not accepts_kind(c,item): return false
	if c.kind == "engine": return fuel <= 11.0
	if c.kind == "gun": return ammo < ammo_capacity
	if AUXILIARY.has(c.kind): return c.items.size() < ammo_capacity
	if c.kind in ["depot","fuel_depot","overflow_gate"]: return c.items.size() < storage_capacity(c.kind)
	if not c.items.is_empty(): return false
	return true

func output_item(c: Dictionary) -> String:
	if c.kind == "armor_block": return ""
	if AUXILIARY.has(c.kind): return ""
	if c.kind == "overflow_gate" and c.turn == 0: return ""
	if c.items.is_empty(): return ""
	var item: String = c.items[0]
	if RECIPES.has(c.kind) and item != RECIPES[c.kind][1]: return ""
	return item

func storage_capacity(kind: String) -> int:
	if AUXILIARY.has(kind): return ammo_capacity
	return 8 if kind in ["depot","fuel_depot"] else 4 if kind == "overflow_gate" else 1

func output_directions(c: Dictionary, item: String) -> Array:
	if c.kind == "splitter": return [c.dir,(c.dir+1)%4] if c.turn == 0 else [(c.dir+1)%4,c.dir]
	if c.kind == "priority_splitter": return [c.dir,(c.dir+1)%4]
	if c.kind == "smart_splitter": return [(c.dir+1)%4] if item in ["coal","fuel"] else [c.dir]
	if c.kind == "router":
		var sides = [c.dir,(c.dir+1)%4,(c.dir+3)%4]
		return [sides[c.turn%3],sides[(c.turn+1)%3],sides[(c.turn+2)%3]]
	return [c.dir]

func can_link(source: Dictionary, target: Dictionary, direction: int) -> bool:
	if source.kind == "armor_block" or target.kind == "armor_block": return false
	if source.kind in ["gun","engine"] or AUXILIARY.has(source.kind): return false
	var possible: Array = ["scrap","steel","shell","coal","fuel"]
	if RECIPES.has(source.kind): possible = [RECIPES[source.kind][1]]
	elif FILTERS.has(source.kind): possible = [FILTERS[source.kind]]
	elif source.kind == "source": possible = ["scrap"]
	elif source.kind == "coal_source": possible = ["coal"]
	elif source.kind == "depot": possible = ["shell"]
	elif source.kind == "fuel_depot": possible = ["fuel"]
	for item in possible:
		if direction in output_directions(source,item) and accepts_kind(target,item): return true
	return false

func connection_sides(p: Vector2i, candidate: Dictionary = {}) -> Dictionary:
	var cell: Dictionary = candidate if not candidate.is_empty() else cells.get(p,{})
	var info = {"inputs":[],"outputs":[],"connected":[],"display_inputs":[]}
	if cell.is_empty(): return info
	if cell.kind == "armor_block": return info
	if cell.kind not in ["gun","engine"] and not AUXILIARY.has(cell.kind):
		info.outputs.append(0)
		if cell.kind in ["splitter","smart_splitter","priority_splitter","router"]: info.outputs.append(1)
		if cell.kind == "router": info.outputs.append(3)
	for side in range(4):
		var neighbor = cells.get(p+DIRS[side],{})
		if neighbor.is_empty(): continue
		var local_side = posmod(side-cell.dir,4)
		if can_link(neighbor,cell,(side+2)%4): info.inputs.append(local_side)
		if can_link(neighbor,cell,(side+2)%4) or can_link(cell,neighbor,side): info.connected.append(local_side)
	info.inputs.sort()
	info.connected.sort()
	info.display_inputs = info.inputs.duplicate()
	# An isolated module has a rear socket, but a wrong-facing/incompatible
	# occupied neighbor must not look like a working input connection.
	if info.inputs.is_empty() and cell.kind not in ["source","coal_source"] and not cells.has(p+DIRS[(cell.dir+2)%4]): info.display_inputs.append(2)
	return info

func start_processing(c: Dictionary):
	if not RECIPES.has(c.kind) or c.work > 0 or c.items.is_empty() or c.items[0] != RECIPES[c.kind][0]: return
	if c.kind == "blast_furnace":
		if reserves.coal < 1: return
		reserves.coal -= 1
	if c.kind == "auto_press":
		if fuel < 0.08: return
		consume_fuel(0.08)
	c.work = maxi(1,int(ceil(RECIPES[c.kind][2]*work_multiplier)))

func simulate_tick():
	ticks += 1
	elapsed = ticks * TICK
	moves.clear()
	completed.clear()
	# Collect proposals from a snapshot; no item can jump multiple cells in a tick.
	var proposals: Dictionary = {}
	for p in cells:
		var c: Dictionary = cells[p]
		var item = output_item(c)
		if item == "": continue
		var directions = output_directions(c,item)
		for d in directions:
			var dest: Vector2i = p + DIRS[d]
			if cells.has(dest) and can_receive(cells[dest], item):
				if not proposals.has(dest): proposals[dest] = []
				proposals[dest].append({"from":p, "item":item, "dir":d})
				break
	# Fair arbitration at merges: rotate input-side priority after a successful move.
	for dest in proposals:
		var candidates: Array = proposals[dest]
		var target: Dictionary = cells[dest]
		var winner: Dictionary = candidates[0]
		var best = 5
		for candidate in candidates:
			var side = DIRS.find(candidate.from - dest)
			var priority = posmod(side - int(target.incoming), 4)
			if priority < best:
				best = priority
				winner = candidate
		var source: Dictionary = cells[winner.from]
		source.items.pop_front()
		if source.kind == "splitter": source.turn = 1 if winner.dir == source.dir else 0
		if source.kind == "router": source.turn = ([source.dir,(source.dir+1)%4,(source.dir+3)%4].find(winner.dir)+1)%3
		if source.kind == "overflow_gate" and source.items.is_empty(): source.turn = 0
		target.incoming = (DIRS.find(winner.from - dest) + 1) % 4
		if target.kind == "gun":
			ammo += 1
			supplied += 1
			feedback_event("load",dest)
		elif target.kind == "engine":
			fuel += 1.0
			feedback_event("fuel",dest)
		else:
			target.items.append(winner.item)
			if AUXILIARY.has(target.kind):
				supplied += 1
				feedback_event("load",dest)
			start_processing(target)
		moves.append({"from":winner.from,"to":dest,"item":winner.item})
	for p in cells:
		var c: Dictionary = cells[p]
		if c.kind == "overflow_gate" and c.items.size() >= 4: c.turn = 1
		start_processing(c)
		if c.kind in ["source","coal_source"] and ticks % 4 == 0 and c.items.is_empty():
			var raw = "coal" if c.kind == "coal_source" else "scrap"
			if finite_resources and reserves[raw] <= 0: continue
			if finite_resources: reserves[raw] -= 1
			c.items.append(raw)
			injected += 1
		if RECIPES.has(c.kind) and c.work > 0:
			c.work -= 1
			c.busy += 1
			if c.work == 0:
				c.items[0] = RECIPES[c.kind][1]
				c.made += 1
				completed.append(p)
				feedback_event("fuel" if c.kind == "refinery" else "production",p)
				if c.kind in ["press","auto_press"]: manufactured += 1
	if auto_fire:
		fire_clock += TICK
		var interval = 60.0 / rate
		while fire_clock + 0.00001 >= interval:
			fire_clock -= interval
			fire_round()
	else:
		fire_clock = 0.0
	while not history.is_empty() and history[0][0] <= elapsed - 30.0: history.pop_front()

func fire_round(weapon: String = "gun") -> bool:
	var success = ammo > 0 if weapon == "gun" else auxiliary_ammo(weapon) > 0
	if success:
		if weapon == "gun": ammo -= 1
		else: cells[auxiliary_position(weapon)].items.pop_front()
		shots += 1
	else: missed += 1
	history.append([elapsed,success])
	return success

func step(dt: float):
	if not running: return
	clock += dt
	while clock >= TICK:
		clock -= TICK
		simulate_tick()

func recent_rate() -> float:
	var n = 0
	for h in history:
		if h[1]: n += 1
	return n * 60.0 / minf(30.0, maxf(elapsed, 1))

func availability() -> int:
	if history.is_empty(): return 0
	var n = 0
	for h in history:
		if h[1]: n += 1
	return int(100.0 * n / history.size())

func cell_status(p: Vector2i) -> String:
	if wrecks.has(p): return "部位破壊：コースクリア時に一括修復"
	if not cells.has(p): return "空き区画"
	var c: Dictionary = cells[p]
	if c.kind == "armor_block": return "防御 %d/%d回 / 周囲8マスを防護・車体被害半減" % [c.armor_hp,ARMOR_HITS]
	if c.kind == "source": return "廃材を最大60個/分供給"
	if c.kind == "gun": return "砲弾専用入力 → 試射用在庫"
	if AUXILIARY.has(c.kind): return "副砲 %d/%d発 / ドラッグで移動" % [c.items.size(),ammo_capacity]
	if c.work > 0: return "加工中  %.2f秒" % (c.work * TICK)
	if c.items.is_empty(): return "入力待ち"
	var item = output_item(c)
	for d in output_directions(c,item):
		var dest: Vector2i = p + DIRS[d]
		if cells.has(dest) and can_receive(cells[dest],item): return "搬送可能"
	return "出口待ち：向き・接続・素材・満杯を確認"

func example(pay: bool = true):
	if layout_locked: return
	var rows: Array = []
	for x in [1,3]: rows.append([x,2,"belt",0])
	rows.append([2,2,"furnace",0])
	rows.append([4,2,"press",0])
	for x in range(5,AMMO_PORT.x+1): rows.append([x,2,"belt",1 if x == AMMO_PORT.x else 0])
	rows.append([AMMO_PORT.x,3,"belt",1])
	rows.append([1,7,"belt",0])
	rows.append([2,7,"refinery",0])
	rows.append([3,7,"belt",0])
	var before = layout()
	if not restore(rows,pay):
		message = "見本配置に必要な設備や空き区画がありません。"
		return
	undo_stack.append(before)
	if undo_stack.size() > 50: undo_stack.pop_front()
	message = "見本は1系統だけ。60発/分には足りません。分配や並列化を試してください。"

func consume_fuel(amount: float) -> float:
	var consumed = minf(fuel,maxf(amount,0.0))
	fuel -= consumed
	fuel_used += consumed
	return consumed

func collect(raw: String, amount: int) -> int:
	if not reserves.has(raw) or amount <= 0: return 0
	reserves[raw] += amount
	collected[raw] += amount
	return amount

func accepts_kind(c: Dictionary, item: String) -> bool:
	if c.kind == "armor_block": return false
	if c.kind in ["source","coal_source"]: return false
	if c.kind in ["gun","depot"] or AUXILIARY.has(c.kind): return item == "shell"
	if c.kind == "engine": return item == "fuel"
	if c.kind == "fuel_depot": return item == "fuel"
	if FILTERS.has(c.kind): return item == FILTERS[c.kind]
	if RECIPES.has(c.kind): return item == RECIPES[c.kind][0]
	return true

func diagnostic(p: Vector2i) -> Dictionary:
	if wrecks.has(p): return {"code":"defeat","item":""}
	if not cells.has(p): return {"code":"idle","item":""}
	var c: Dictionary = cells[p]
	if c.kind == "armor_block": return {"code":"shield","item":""}
	if AUXILIARY.has(c.kind): return {"code":"empty" if c.items.is_empty() else "full" if c.items.size() >= ammo_capacity else "ready","item":"shell"}
	if c.kind in ["gun","engine"]:
		var amount = ammo if c.kind == "gun" else fuel
		var capacity = ammo_capacity if c.kind == "gun" else 12
		return {"code":"empty" if amount <= 0 else "full" if (amount > capacity-1 if c.kind == "engine" else amount >= capacity) else "ready","item":"shell" if c.kind == "gun" else "fuel"}
	if c.work > 0: return {"code":"processing","item":RECIPES[c.kind][0]}
	if not c.items.is_empty() and c.work == 0:
		if c.kind == "blast_furnace" and c.items[0] == "scrap" and reserves.coal < 1: return {"code":"empty","item":"coal"}
		if c.kind == "auto_press" and c.items[0] == "steel" and fuel < 0.08: return {"code":"empty","item":"fuel"}
	if c.kind == "overflow_gate" and c.turn == 0: return {"code":"waiting","item":c.items[0] if not c.items.is_empty() else ""}
	if c.items.is_empty():
		if c.kind in ["source","coal_source"]:
			var raw = "scrap" if c.kind == "source" else "coal"
			return {"code":"empty" if finite_resources and reserves[raw] <= 0 else "ready","item":raw}
		return {"code":"waiting","item":RECIPES[c.kind][0] if RECIPES.has(c.kind) else FILTERS[c.kind] if FILTERS.has(c.kind) else "shell" if c.kind == "depot" else "fuel" if c.kind == "fuel_depot" else ""}
	var item = output_item(c)
	if item == "": return {"code":"incompatible","item":c.items[0]}
	var connected = false
	var compatible = false
	for d in output_directions(c,item):
		var dest: Vector2i = p+DIRS[d]
		if not cells.has(dest): continue
		connected = true
		if not accepts_kind(cells[dest],item): continue
		compatible = true
		if can_receive(cells[dest],item): return {"code":"ready","item":item}
	return {"code":"disconnected" if not connected else "incompatible" if not compatible else "full" if c.kind in ["depot","fuel_depot","overflow_gate"] and c.items.size() >= storage_capacity(c.kind) else "blocked","item":item}
