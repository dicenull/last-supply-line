extends RefCounted
## Independent, bounded journal. The first terminal result for a seed is authoritative.
const LIMIT = 100
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

func read_entries(path: String):
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 100000: return null
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK: return null
	var data = parser.data
	if not data is Dictionary or data.get("version") != 1: return null
	var rows = data.get("entries")
	if not valid(rows): return null
	for row in rows:
		row.cleared = int(row.cleared)
		row.shells = int(row.shells)
	return rows

func load_file(path: String):
	var rows = read_entries(path)
	if rows == null: rows = read_entries(path+".bak")
	error = rows == null and (FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"))
	entries = [] if rows == null else rows

func record(path: String, seed: int, phase: String, cleared: int, shells: int) -> bool:
	if phase not in ["won","lost","retreated"]: return false
	for row in entries:
		if row.seed == str(seed): return true
	var next = entries.duplicate(true)
	next.push_front({"seed":str(seed),"phase":phase,"cleared":cleared,"shells":shells})
	if next.size() > LIMIT: next.resize(LIMIT)
	if not valid(next): return false
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		error = true
		return false
	file.store_string(JSON.stringify({"version":1,"entries":next}))
	file.flush()
	var ok = file.get_error() == OK
	file.close()
	if ok and read_entries(path) != null:
		ok = DirAccess.copy_absolute(path,path+".bak") == OK
	if ok: ok = DirAccess.rename_absolute(path+".tmp",path) == OK
	error = not ok
	if ok: entries = next
	return ok
