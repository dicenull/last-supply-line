extends SceneTree
const Battle = preload("res://scripts/battle_world.gd")
const Factory = preload("res://scripts/factory.gd")
const Run = preload("res://scripts/run_state.gd")
var checks = 0
var failures = 0
var b
var f
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS tank steering: ",label)
	else:
		failures += 1
		push_error(label)
func reset_pose():
	b.player.position = Vector3(40,0,0)
	b.player.rotation = Vector3.ZERO
	f.fuel = 12
	f.fuel_used = 0
	f.running = true
	b.motion.transmission.reset()
func run():
	b = Battle.new()
	b.sector_config = Run.new(42).current
	# Isolate control/fuel math on open terrain; obstacle contact has its own suite.
	b.sector_config.erase("obstacles_version")
	b.sector_config.erase("field_version") # Isolate steering from generated field geometry.
	b.sector_config.erase("encounters_version")
	root.add_child(b)
	f = Factory.new()
	reset_pose()
	b.movement_direction = Vector3.FORWARD
	b.move_player(f,0.5)
	check(b.player.position == Vector3(40,0,0) and is_equal_approx(b.player.rotation.y,0.6),"left command counter-rotates tracks around hull center")
	check(is_zero_approx(b.velocity.length()) and b.speed == 0 and is_equal_approx(b.distance,40),"pivot has zero translational velocity and route progress")
	check(is_equal_approx(f.fuel_used,0.6*b.TRACK_HALF_WIDTH*0.12),"pivot fuel measures absolute travel of both tracks")
	b.movement_direction = Vector3.BACK
	b.move_player(f,0.5)
	check(b.player.position == Vector3(40,0,0) and is_zero_approx(b.player.rotation.y),"right pivot reverses the heading without sideways movement")
	b.player.rotation.y = PI/2
	b.movement_direction = Vector3.RIGHT
	b.move_player(f,0.1)
	check(b.player.position.is_equal_approx(Vector3(40,0,-3.3*0.5*0.42*0.1*0.1)),"forward follows a ninety-degree hull heading")
	b.movement_direction = Vector3.LEFT
	b.move_player(f,0.1)
	check(b.player.position.is_equal_approx(Vector3(40,0,0)) and is_equal_approx(b.player.rotation.y,PI/2),"reverse backs along hull heading without turning around")
	reset_pose()
	b.movement_direction = Vector3(1,0,1)
	b.move_player(f,0.5)
	var full = b.player.transform
	var full_fuel = f.fuel_used
	check(b.player.position.x > 40 and b.player.position.z > 0 and b.player.rotation.y < 0,"forward plus right steering traces a right-hand arc")
	reset_pose()
	for i in range(10): b.move_player(f,0.05)
	check(b.player.transform.is_equal_approx(full) and is_equal_approx(f.fuel_used,full_fuel),"arc and fuel are independent of simulation step size")
	reset_pose()
	f.fuel = b.TURN_SPEED*b.TRACK_HALF_WIDTH*0.12*0.05
	b.movement_direction = Vector3.BACK
	b.move_player(f,0.1)
	check(is_equal_approx(b.player.rotation.y,-0.06) and is_zero_approx(f.fuel),"last fuel produces only an affordable partial pivot")
	var before = b.player.transform
	b.movement_direction = Vector3(1,0,1)
	b.move_player(f,0.1)
	check(b.player.transform == before,"empty tank prevents both rotation and translation")
	reset_pose()
	b.player.position = Vector3(0,0,18)
	b.movement_direction = Vector3.LEFT
	b.move_player(f,0.1)
	check(b.player.position == Vector3(0,0,18) and f.fuel_used == 0,"blocked reverse movement spends no fuel")
	b.movement_direction = Vector3.BACK
	b.move_player(f,0.1)
	check(b.player.position == Vector3(0,0,18) and b.player.rotation.y < 0 and f.fuel_used > 0,"pivot remains possible at battlefield boundary")
	reset_pose()
	b.movement_direction = Vector3.BACK
	f.running = false
	before = b.player.transform
	b.tick_battle(f,0.1)
	check(b.player.transform == before and f.fuel_used == 0,"paused combat freezes steering as well as translation")
	reset_pose()
	b.result = 1
	b.tick_battle(f,0.1)
	check(b.player.transform == before and f.fuel_used == 0,"finished combat cannot rotate or consume fuel")
	reset_pose()
	b.movement_direction = Vector3(1,0,-1)
	f.fuel = 0.01
	b.move_player(f,0.1)
	check(f.fuel >= 0 and f.fuel_used <= 0.010001 and b.player.position.x > 40 and b.player.rotation.y > 0,"partial fuel scales forward and angular motion together")
	print("TANK STEERING RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
