extends RefCounted
## Transient automatic gearbox. Distance integration is independent of frame rate.
const Data = preload("res://scripts/equipment_data.gd")
const PROFILES = {
	"vehicle_gear":{"ratios":[0.28,0.52,0.77,1.0],"acceleration":0.42},
	"vehicle_gear_speed":{"ratios":[0.22,0.40,0.60,0.80,1.0],"acceleration":0.32},
	"vehicle_gear_torque":{"ratios":[0.38,0.70,1.0],"acceleration":0.62},
}
var kind = "vehicle_gear"
var gear = 1
var ratio = 0.0
var direction = 0

func reset():
	gear = 1
	ratio = 0.0
	direction = 0

func configure(id: String):
	if kind == id: return
	kind = id
	reset()

func profile() -> Dictionary:
	return specification(kind)

func travel(throttle: float, delta: float, powered: bool) -> float:
	if not powered or is_zero_approx(throttle):
		reset()
		return 0.0
	if delta <= 0: return 0.0
	var sign_value = int(signf(throttle))
	if sign_value != direction: reset()
	direction = sign_value
	var spec = profile()
	var ratios: Array = spec.ratios if direction > 0 else [0.32]
	var remaining = delta
	var distance = 0.0
	while remaining > 0.00000001:
		var cap = float(ratios[gear-1])*absf(throttle)
		var acceleration = float(spec.acceleration)/(1.0+0.22*(gear-1))
		ratio = minf(ratio,cap)
		var step = minf(remaining,maxf(0,(cap-ratio)/acceleration))
		distance += ratio*step+0.5*acceleration*step*step
		ratio = minf(cap,ratio+acceleration*step)
		remaining -= step
		if ratio >= cap-0.00000001:
			if gear < ratios.size(): gear += 1
			else:
				distance += ratio*remaining
				break
	return distance*direction

func applied(requested: float, actual: float, delta: float):
	if delta <= 0 or absf(requested) <= 0.00000001: return
	if actual <= minf(0.00001,absf(requested)*0.01):
		reset()
		return

func label() -> String:
	return "後退" if direction < 0 else "%d速 / %d" % [gear,profile().ratios.size()]

static func description(id: String) -> String:
	var spec = specification(id)
	return "自動%d速 / %s / 停止時1速" % [spec.ratios.size(),Data.ITEMS[id].transmission_note if Data.ITEMS.get(id,{}).has("transmission_note") else "高速巡航型・発進は緩やか" if id == "vehicle_gear_speed" else "低速高トルク・加速重視" if id == "vehicle_gear_torque" else "標準加速"]

func snapshot() -> Dictionary:
	return {"kind":kind,"gear":gear,"ratio":ratio,"direction":direction}

func restore(data: Dictionary):
	reset()
	if data.is_empty(): return
	kind = data.kind
	gear = data.gear
	ratio = float(data.ratio)
	direction = data.direction

static func valid(data) -> bool:
	if not data is Dictionary or not data.has_all(["kind","gear","ratio","direction"]): return false
	if not data.kind is String or data.kind not in PROFILES and not Data.ITEMS.get(data.kind,{}).has("transmission"): return false
	if not data.gear is int or data.gear < 1 or data.gear > specification(data.kind).ratios.size(): return false
	if not data.direction is int or data.direction not in [-1,0,1]: return false
	if not (data.ratio is float or data.ratio is int) or not is_finite(float(data.ratio)) or data.ratio < 0 or data.ratio > 1: return false
	if data.direction == 0: return data.gear == 1 and data.ratio == 0
	if data.direction < 0: return data.gear == 1 and data.ratio <= 0.32
	return data.ratio <= specification(data.kind).ratios[data.gear-1]

static func specification(id: String) -> Dictionary:
	return Data.ITEMS.get(id,{}).get("transmission",PROFILES.get(id,PROFILES.vehicle_gear))
