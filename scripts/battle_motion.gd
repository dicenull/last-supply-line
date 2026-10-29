extends RefCounted
## Applied movement telemetry. Scene nodes and collision planning stay in the world.
const SAVE_FIELDS = ["distance","speed"]
var transmission = preload("res://scripts/battle_transmission.gd").new()
var command: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var speed: float = 0.0
var distance: float = 0.0
var poses: Array = []
var contacts: Array = []

func record_plan(from: Vector3, plan: Dictionary, delta: float, route_length: float):
	velocity = (plan.position-from)/maxf(delta,0.001)
	speed = velocity.length()
	distance = clampf(plan.position.x,0,route_length)
	poses = plan.poses
	contacts = plan.get("contacts",[])

func clear_command():
	command = Vector3.ZERO

func snapshot() -> Dictionary:
	return {"distance":distance,"speed":speed,"transmission":transmission.snapshot()}

func restore(data: Dictionary):
	distance = float(data.distance)
	speed = float(data.speed)
	# Held controls and the previous frame's swept path are never replayed.
	clear_command()
	transmission.restore(data.get("transmission",{}))
	velocity = Vector3.ZERO
	poses = []
	contacts = []
