extends RefCounted
## One deterministic perimeter plan for visible fences, collision and saved mines.
const GUARDS_PER_SITE = 6
const FRONT = -2.0
const BACK = 30.0
const HALF_WIDTH = 18.0
const GATE_HALF_WIDTH = 9.0
const THICKNESS = 1.0

static func fences(at: Vector3) -> Array:
	var origin = Vector2(at.x,at.z)
	var result: Array = []
	for side in [-1,1]:
		result.append(Rect2(origin+Vector2(FRONT,side*HALF_WIDTH-THICKNESS/2),Vector2(BACK-FRONT+THICKNESS,THICKNESS)))
		var z = GATE_HALF_WIDTH if side == 1 else -HALF_WIDTH
		result.append(Rect2(origin+Vector2(FRONT-THICKNESS/2,z),Vector2(THICKNESS,HALF_WIDTH-GATE_HALF_WIDTH)))
	result.append(Rect2(origin+Vector2(BACK-THICKNESS/2,-HALF_WIDTH),Vector2(THICKNESS,HALF_WIDTH*2)))
	return result

static func mines(at: Vector3) -> Array:
	var result: Array = []
	for side in [-1,1]:
		for x in [4.0,12.0,20.0,28.0]: result.append(at+Vector3(x,0,side*22))
		for z in [14.0,21.0]: result.append(at+Vector3(-8,0,side*z))
	for z in [-16.0,-8.0,0.0,8.0,16.0]: result.append(at+Vector3(35,0,z))
	return result

static func guard_position(at: Vector3, slot: int) -> Vector3:
	return at+Vector3(-20.0-(slot/2)*9,0,-10.0 if slot%2 == 0 else 10.0)
