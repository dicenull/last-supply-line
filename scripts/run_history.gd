extends RefCounted
## Independent, bounded journal. The first terminal result for a seed is authoritative.
const LIMIT = 100
const Content = preload("res://scripts/content.gd")
const Blueprints = preload("res://scripts/blueprints.gd")
var unlocked: Array = ["standard"]
var researched_blocks: Array = []
# At most ten receipts; retained even after the journal drops an old death.
var research_receipts: Dictionary = {}
var entries: Array = []
var error = false

func valid(value) -> bool:
	if not value is Array or value.size() > LIMIT: return false
	var seeds = {}
	for row in value:
		if not row is Dictionary: return false
		for key in ["seed","phase","cleared","shells"]:
			if not row.has(key): return false
		if not row.seed is String or not row.seed.is_valid_int() or seeds.has(row.seed): return false
		seeds[row.seed] = true
		if row.phase not in ["won","lost","retreated"]: return false
		for key in ["cleared","shells"]:
			if typeof(row[key]) not in [TYPE_INT,TYPE_FLOAT]: return false
			if not is_finite(float(row[key])) or row[key] != floor(row[key]) or row[key] < 0: return false
		if row.cleared > 5 or row.shells > 100000000: return false
	return true

func read_document(path: String):
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 100000: return null
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK: return null
	var data = parser.data
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2 and data.get("version") != 3): return null
	var rows = data.get("entries")
	if not valid(rows): return null
	var grants: Array = ["standard"]
	if data.version >= 2:
		if not data.get("unlocked") is Array or data.unlocked.size() > Blueprints.IDS.size(): return null
		for id in data.unlocked:
			if not id is String or id not in Blueprints.IDS: return null
			if id not in grants: grants.append(id)
	var research: Array = []
	var receipts: Dictionary = {}
	if data.version >= 3:
		if not data.get("researched_blocks") is Array or not data.get("research_receipts") is Dictionary: return null
		research = data.researched_blocks
		receipts = data.research_receipts
		if research.size() > Content.BLOCKS.size() or receipts.size() != research.size(): return null
		var seen = []
		for id in research:
			if not id is String or not Content.BLOCKS.has(id) or id in seen: return null
			seen.append(id)
		seen.clear()
		for seed in receipts:
			if not seed is String or not seed.is_valid_int() or receipts[seed] not in research or receipts[seed] in seen: return null
			seen.append(receipts[seed])
	for row in rows:
		row.cleared = int(row.cleared)
		row.shells = int(row.shells)
		for id in Blueprints.IDS:
			if row.cleared >= Blueprints.REQUIREMENTS[id] and id not in grants: grants.append(id)
	return {"entries":rows,"unlocked":grants,"researched_blocks":research,"research_receipts":receipts}

func read_entries(path: String):
	var data = read_document(path)
	return null if data == null else data.entries

func load_file(path: String):
	var data = read_document(path)
	if data == null: data = read_document(path+".bak")
	error = data == null and (FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"))
	entries = [] if data == null else data.entries
	unlocked = ["standard"] if data == null else data.unlocked
	researched_blocks = [] if data == null else data.researched_blocks
	research_receipts = {} if data == null else data.research_receipts

func write_document(path: String, rows: Array, grants: Array, research = null, receipts = null) -> bool:
	if research == null: research = researched_blocks
	if receipts == null: receipts = research_receipts
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		error = true
		return false
	file.store_string(JSON.stringify({"version":3,"entries":rows,"unlocked":grants,"researched_blocks":research,"research_receipts":receipts}))
	file.flush()
	var ok = file.get_error() == OK
	file.close()
	if ok and read_document(path) != null:
		ok = DirAccess.copy_absolute(path,path+".bak") == OK
	if ok: ok = DirAccess.rename_absolute(path+".tmp",path) == OK
	error = not ok
	if ok:
		entries = rows
		unlocked = grants
		researched_blocks = research
		research_receipts = receipts
	return ok

func unlock_for_clear(path: String, cleared: int) -> bool:
	if cleared < 0 or cleared > 5: return false
	var grants = unlocked.duplicate()
	for id in Blueprints.IDS:
		if cleared >= Blueprints.REQUIREMENTS[id] and id not in grants: grants.append(id)
	if grants == unlocked: return true
	return write_document(path,entries,grants)

func record(path: String, seed: int, phase: String, cleared: int, shells: int) -> bool:
	if phase not in ["won","lost","retreated"]: return false
	for row in entries:
		if row.seed == str(seed): return true
	var next = entries.duplicate(true)
	next.push_front({"seed":str(seed),"phase":phase,"cleared":cleared,"shells":shells})
	if next.size() > LIMIT: next.resize(LIMIT)
	if not valid(next): return false
	var grants = unlocked.duplicate()
	for id in Blueprints.IDS:
		if cleared >= Blueprints.REQUIREMENTS[id] and id not in grants: grants.append(id)
	var research = researched_blocks.duplicate()
	var receipts = research_receipts.duplicate()
	if phase == "lost" and not receipts.has(str(seed)):
		var pool: Array = []
		for id in Content.BLOCKS:
			if id not in research: pool.append(id)
		if not pool.is_empty():
			var random = RandomNumberGenerator.new()
			random.seed = seed
			var id: String = pool[random.randi_range(0,pool.size()-1)]
			research.append(id)
			receipts[str(seed)] = id
	return write_document(path,next,grants,research,receipts)
