extends RefCounted
## Deterministic, fixed-step ammunition production sandbox. No combat or damage.
const W = 14
const H = 8
const TICK = 0.25
const DIRS = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const BLOCKS: Array[Vector2i] = []
const AMMO_PORT = Vector2i(9,4)
const FUEL_PORT = Vector2i(4,7)
const PORTS = {Vector2i(0,2): "source", Vector2i(0,5): "source", AMMO_PORT: "gun", Vector2i(0,7): "coal_source", FUEL_PORT: "engine"}
const LIMITS = {"belt": 80, "furnace": 4, "press": 4, "splitter": 6, "depot": 3, "refinery": 3}
const RECIPES = {"furnace": ["scrap", "steel", 6], "press": ["steel", "shell", 8], "refinery": ["coal", "fuel", 8]}
var cells: Dictionary = {}
var running = false
var auto_fire = true
var finite_resources = false
var reserves = {"scrap":48,"coal":32}
var collected = {"scrap":0,"coal":0}
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

func _init():
	clear_layout(false)
	message = "空の車内です。入口から精錬炉・砲弾機・試射口をつないでください。"

func make_cell(kind: String, direction: int) -> Dictionary:
	return {"kind":kind, "dir":direction, "items":[], "work":0, "turn":0, "incoming":0, "made":0, "busy":0}

func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < W and p.y >= 0 and p.y < H

func count_kind(kind: String) -> int:
	var n = 0
	for c in cells.values():
		if c.kind == kind: n += 1
	return n

func layout() -> Array:
	var result: Array = []
	for p in cells:
		if not PORTS.has(p): result.append([p.x,p.y,cells[p].kind,cells[p].dir])
	return result

func remember():
	undo_stack.append(layout())
	if undo_stack.size() > 50: undo_stack.pop_front()

func reset_trial():
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

func clear_layout(record: bool = true):
	if record: remember()
	cells.clear()
	for p in PORTS: cells[p] = make_cell(PORTS[p], 0)
	reset_trial()

func restore(rows: Array) -> bool:
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
		if not inside(p) or PORTS.has(p) or p in BLOCKS or pending.has(p) or not LIMITS.has(kind) or direction < 0 or direction > 3: return false
		counts[kind] = counts.get(kind, 0) + 1
		if counts[kind] > LIMITS[kind]: return false
		pending[p] = make_cell(kind, direction)
	cells = pending
	for p in PORTS: cells[p] = make_cell(PORTS[p], 0)
	reset_trial()
	return true

func undo():
	if undo_stack.is_empty(): return
	restore(undo_stack.pop_back())
	message = "配置を1操作戻しました。物資・計測値はリセット。"

func edit(p: Vector2i, kind: String, direction: int):
	if not inside(p) or PORTS.has(p) or p in BLOCKS: return
	if kind == "erase":
		if not cells.has(p): return
		remember()
		cells.erase(p)
	else:
		if not LIMITS.has(kind): return
		if cells.has(p) and cells[p].kind == kind and cells[p].dir == direction: return
		if (not cells.has(p) or cells[p].kind != kind) and count_kind(kind) >= LIMITS[kind]:
			message = "この設備は搭載上限です。別の設備を移動してください。"
			return
		remember()
		cells[p] = make_cell(kind, direction)
	moves.clear()
	completed.clear()
	running = false
	message = "配置変更で一時停止。変更したマスの物資は破棄。開始で続きを試せます。"

func rotate(p: Vector2i):
	if cells.has(p) and not PORTS.has(p): edit(p, cells[p].kind, (cells[p].dir + 1) % 4)

func can_receive(c: Dictionary, item: String) -> bool:
	if c.kind in ["source","coal_source"]: return false
	if c.kind == "engine": return item == "fuel" and fuel <= 11.0
	if c.kind == "gun": return item == "shell" and ammo < ammo_capacity
	if c.kind == "depot": return item == "shell" and c.items.size() < 8
	if not c.items.is_empty(): return false
	if RECIPES.has(c.kind): return item == RECIPES[c.kind][0]
	return true

func output_item(c: Dictionary) -> String:
	if c.items.is_empty(): return ""
	var item: String = c.items[0]
	if RECIPES.has(c.kind) and item != RECIPES[c.kind][1]: return ""
	return item

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
		var directions = [c.dir]
		if c.kind == "splitter": directions = [c.dir, (c.dir + 1) % 4] if c.turn == 0 else [(c.dir + 1) % 4, c.dir]
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
		target.incoming = (DIRS.find(winner.from - dest) + 1) % 4
		if target.kind == "gun":
			ammo += 1
			supplied += 1
		elif target.kind == "engine":
			fuel += 1.0
		else:
			target.items.append(winner.item)
			if RECIPES.has(target.kind): target.work = maxi(1,int(ceil(RECIPES[target.kind][2]*work_multiplier)))
		moves.append({"from":winner.from,"to":dest,"item":winner.item})
	for p in cells:
		var c: Dictionary = cells[p]
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
				if c.kind == "press": manufactured += 1
	if auto_fire:
		fire_clock += TICK
		var interval = 60.0 / rate
		while fire_clock + 0.00001 >= interval:
			fire_clock -= interval
			fire_round()
	else:
		fire_clock = 0.0
	while not history.is_empty() and history[0][0] <= elapsed - 30.0: history.pop_front()

func fire_round() -> bool:
	var success = ammo > 0
	if success:
		ammo -= 1
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
	if not cells.has(p): return "空き区画"
	var c: Dictionary = cells[p]
	if c.kind == "source": return "廃材を最大60個/分供給"
	if c.kind == "gun": return "砲弾専用入力 → 試射用在庫"
	if c.work > 0: return "加工中  %.2f秒" % (c.work * TICK)
	if c.items.is_empty(): return "入力待ち"
	var item = output_item(c)
	for d in ([c.dir,(c.dir+1)%4] if c.kind == "splitter" else [c.dir]):
		var dest: Vector2i = p + DIRS[d]
		if cells.has(dest) and can_receive(cells[dest],item): return "搬送可能"
	return "出口待ち：向き・接続・素材・満杯を確認"

func example():
	remember()
	clear_layout(false)
	# Deliberately single-lane: a starting example, not a completed optimal factory.
	for x in [1,3]: cells[Vector2i(x,2)] = make_cell("belt",0)
	cells[Vector2i(2,2)] = make_cell("furnace",0)
	cells[Vector2i(4,2)] = make_cell("press",0)
	for x in range(5,AMMO_PORT.x+1): cells[Vector2i(x,2)] = make_cell("belt",0)
	cells[Vector2i(AMMO_PORT.x,2)].dir = 1
	cells[Vector2i(AMMO_PORT.x,3)] = make_cell("belt",1)
	cells[Vector2i(1,7)] = make_cell("belt",0)
	cells[Vector2i(2,7)] = make_cell("refinery",0)
	cells[Vector2i(3,7)] = make_cell("belt",0)
	message = "見本は1系統だけ。60発/分には足りません。分配や並列化を試してください。"

func consume_fuel(amount: float) -> float:
	var consumed = minf(fuel,maxf(amount,0.0))
	fuel -= consumed
	fuel_used += consumed
	return consumed

func collect(raw: String, amount: int) -> int:
	if not reserves.has(raw) or amount <= 0: return 0
	var accepted = mini(amount,reserve_capacity-reserves[raw])
	reserves[raw] += accepted
	collected[raw] += accepted
	return accepted
