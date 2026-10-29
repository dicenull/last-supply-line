extends SceneTree
const Transmission = preload("res://scripts/battle_transmission.gd")
const Battle = preload("res://scripts/battle_world.gd")
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS transmission: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func run():
	for kind in Transmission.PROFILES:
		var t = Transmission.new()
		t.configure(kind)
		var stages = [t.gear]
		var previous = 0.0
		var distance = 0.0
		for i in range(600):
			distance += t.travel(1,1.0/60,true)
			if t.gear != stages.back(): stages.append(t.gear)
			if t.ratio < previous: failures += 1
			previous = t.ratio
		check(stages == range(1,t.profile().ratios.size()+1) and is_equal_approx(t.ratio,1),kind+" starts in first and sequentially reaches top gear")
		var coarse = Transmission.new()
		coarse.configure(kind)
		check(is_equal_approx(coarse.travel(1,10,true),distance),kind+" acceleration distance is independent of frame size")
		t.travel(0,0.1,true)
		check(t.gear == 1 and t.ratio == 0,kind+" releasing throttle resets to first")
		t.travel(1,10,true)
		t.applied(1,0,0.1)
		check(t.gear == 1 and t.ratio == 0,kind+" a fully blocked hull cannot retain top gear")
		t.travel(1,10,true)
		t.travel(1,0.1,false)
		check(t.gear == 1 and t.ratio == 0,kind+" fuel exhaustion resets transmission")
		t.travel(-1,10,true)
		check(t.gear == 1 and is_equal_approx(t.ratio,0.32) and t.label() == "後退",kind+" reverse remains in one low-speed gear")
	var state = Transmission.new()
	state.travel(1,2,true)
	var saved = state.snapshot()
	var resumed = Transmission.new()
	resumed.restore(saved)
	check(Transmission.valid(saved) and is_equal_approx(state.travel(1,1,true),resumed.travel(1,1,true)),"saved gearbox resumes the same acceleration curve")
	saved.gear = 999
	check(not Transmission.valid(saved),"corrupt gearbox stage is rejected")
	resumed.restore({})
	check(resumed.gear == 1 and resumed.ratio == 0,"old saves default to first gear at rest")
	var b = Battle.new()
	b.sector_config = Run.new(42).current.duplicate(true)
	for key in ["obstacles_version","field_version","encounters_version","defenses_version"]: b.sector_config.erase(key)
	root.add_child(b)
	var f = Factory.new()
	f.fuel = 100
	b.player.position = Vector3(20,0,0)
	b.motion.command = Vector3.RIGHT
	b.move_player(f,0.1)
	var first = b.motion.speed
	for i in range(50): b.move_player(f,0.1)
	check(b.motion.speed > first*10 and b.motion.transmission.gear == 4,"actual tank accelerates from rest to equipped gearbox top gear")
	b.vehicle_parts.gear = {"kind":"vehicle_gear_torque","rarity":"normal"}
	b.move_player(f,0.1)
	check(b.motion.transmission.kind == "vehicle_gear_torque" and b.motion.transmission.gear == 1,"changing installed gearbox resets its own acceleration curve")
	b.empty_part_slots = ["gear"]
	var position = b.player.position
	b.move_player(f,1)
	check(b.player.position == position and b.motion.speed == 0 and b.motion.poses.is_empty(),"no gearbox cannot move or replay old swept poses")
	b.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
