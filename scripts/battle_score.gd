extends RefCounted
## Encounter-local scoring rules, independent of enemies, rendering and UI.
const COMBO_WINDOW = 2.8
const SAVE_FIELDS = ["kills"]
var kills: int = 0
var total: int = 6
var combo: int = 0
var combo_time: float = 0.0
var best_combo: int = 0

func advance(delta: float):
	combo_time = maxf(0,combo_time-maxf(0,delta))
	if combo_time == 0: combo = 0

func record_kill():
	kills += 1
	combo += 1
	combo_time = COMBO_WINDOW
	best_combo = maxi(best_combo,combo)

func combo_drop_bonus() -> int:
	return floori(combo/2.0) if combo_time > 0 else 0

func earned_salvage(rate: float) -> bool:
	# Compare successive cumulative totals to retain fractional-rate cadence.
	return kills > 0 and floori(kills*rate+0.0000001) > floori((kills-1)*rate+0.0000001)

func combo_visible() -> bool:
	return combo >= 2 and combo_time > 0

func snapshot() -> Dictionary:
	return {"kills":kills,"best_combo":best_combo}

func restore(data: Dictionary):
	kills = int(data.kills)
	# The current combo expires on load, but its record is part of the result.
	combo = 0
	combo_time = 0
	best_combo = int(data.get("best_combo",0))
