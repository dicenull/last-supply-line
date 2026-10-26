extends RefCounted
## Hull damage, simulation time and terminal outcome for one encounter.
enum Outcome { DEFEAT = -1, ACTIVE = 0, VICTORY = 1 }
const SAVE_FIELDS = ["hull","elapsed","result"]
var hull: int = 100
var elapsed: float = 0.0
var result: int = Outcome.ACTIVE
var arrived_destination: int = -1

func is_finished() -> bool:
	return result != Outcome.ACTIVE

func has_won() -> bool:
	return result == Outcome.VICTORY

func has_lost() -> bool:
	return result == Outcome.DEFEAT

func advance(delta: float):
	if not is_finished(): elapsed += maxf(0,delta)

func take_damage(amount: float):
	hull = maxi(0,hull-ceili(maxf(0,amount)))

func resolve(destination: int = -1):
	if is_finished(): return
	# A lethal hit on the arrival frame takes precedence over reaching a yard.
	if hull <= 0: result = Outcome.DEFEAT
	elif destination >= 0:
		arrived_destination = destination
		result = Outcome.VICTORY

func snapshot() -> Dictionary:
	return {"hull":hull,"elapsed":elapsed,"result":result}

func restore(data: Dictionary):
	hull = int(data.hull)
	elapsed = float(data.elapsed)
	result = int(data.result)
	arrived_destination = -1 # Reconstructed from the saved pose and course.
