extends RefCounted
## Campaign totals are settled once per sector, independently of presentation.
var kills = 0
var best_combo = 0
var elapsed = 0.0
var shells = 0
var settled: Array = []
var legacy = false

func settle(sector: int, score, progress, produced: int):
	if sector in settled: return
	settled.append(sector)
	kills += score.kills
	best_combo = maxi(best_combo,score.best_combo)
	elapsed += progress.elapsed
	# Factory production is cumulative across sectors, unlike battle counters.
	shells = maxi(shells,produced)

func points(cleared: int) -> int:
	return cleared*1000+kills*100+best_combo*50

func snapshot() -> Dictionary:
	return {"kills":kills,"best_combo":best_combo,"elapsed":elapsed,"shells":shells,"settled":settled.duplicate(),"legacy":legacy}

func restore(data: Dictionary):
	kills = int(data.get("kills",0))
	best_combo = int(data.get("best_combo",0))
	elapsed = float(data.get("elapsed",0.0))
	shells = int(data.get("shells",0))
	settled = data.get("settled",[]).duplicate()
	legacy = data.get("legacy",true)

static func valid(data) -> bool:
	if not data is Dictionary or not data.has_all(["kills","best_combo","elapsed","shells","settled","legacy"]): return false
	for key in ["kills","best_combo","shells"]:
		if not data[key] is int or data[key] < 0 or data[key] > 1000000000: return false
	if data.best_combo > data.kills or not (data.elapsed is float or data.elapsed is int) or not is_finite(float(data.elapsed)) or data.elapsed < 0 or data.elapsed > 1e9: return false
	if not data.legacy is bool or not data.settled is Array or data.settled.size() > 5: return false
	var seen: Array = []
	for sector in data.settled:
		if not sector is int or sector not in range(1,6) or sector in seen: return false
		seen.append(sector)
	return true
