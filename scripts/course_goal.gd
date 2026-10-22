extends Node3D
## The visible receiving yard and its arrival area share the same dimensions.
const DEPTH = 16.0
const HALF_WIDTH = 8.0
var route_kind = "scrapyard"
var stage = 1

func contains_position(at: Vector3) -> bool:
	var local = to_local(at)
	return local.x >= 0.0 and local.x <= DEPTH and absf(local.z) <= HALF_WIDTH

func remaining_distance(at: Vector3) -> float:
	var local = to_local(at)
	var dx = maxf(0.0,maxf(-local.x,local.x-DEPTH))
	var dz = maxf(0.0,absf(local.z)-HALF_WIDTH)
	return Vector2(dx,dz).length()

func build(world, route: Dictionary):
	route_kind = route.get("kind","scrapyard")
	stage = int(route.get("sector",1))
	name = "CourseGoal"
	world.material("goal_deck","555b49",0.2)
	world.material("goal_wall","686b54",0.2)
	world.material("goal_roof","414a3f",0.3)
	world.material("goal_signal","8eaa76",0,0.15)
	# Open receiving apron: the gate threshold is exactly the arrival boundary.
	world.box(self,Vector3(DEPTH/2,-0.01,0),Vector3(DEPTH,0.08,HALF_WIDTH*2),"goal_deck")
	for z in [-HALF_WIDTH,HALF_WIDTH]:
		world.box(self,Vector3(DEPTH/2,0.12,z),Vector3(DEPTH,0.24,0.3),"pipe_joint")
	for x in [0.0,4.0,8.0,12.0,DEPTH]:
		world.box(self,Vector3(x,0.05,0),Vector3(0.12,0.03,HALF_WIDTH*2),"pipe_joint")
	for z in [-9.0,9.0]:
		world.box(self,Vector3(0,3.8,z),Vector3(0.8,7.6,0.8),"goal_wall")
		world.box(self,Vector3(0,0.4,z),Vector3(1.4,0.8,1.4),"dark")
		world.box(self,Vector3(-0.45,5.7,z),Vector3(0.16,0.65,0.65),"goal_signal")
	world.box(self,Vector3(0,7.5,0),Vector3(0.9,0.7,19),"goal_roof")
	world.box(self,Vector3(-0.5,7.5,0),Vector3(0.15,1.25,5),"goal_wall")
	for i in range(stage):
		world.box(self,Vector3(-0.59,7.5,(i-(stage-1)*0.5)*0.7),Vector3(0.05,0.65,0.22),"edge")
	# Site furniture sits outside the clear driving apron.
	match route_kind:
		"coalfield": build_coalfield(world)
		"arsenal": build_arsenal(world)
		_: build_scrapyard(world)
	for i in range(stage):
		var x = 3.0+i*2.5
		world.box(self,Vector3(x,0.6,11),Vector3(1.5,1.2,1.3),"wood")
		for z in [10.45,11.55]:
			world.box(self,Vector3(x,0.65,z),Vector3(0.18,1.3,0.08),"pipe_joint")
	if route.get("boss",false):
		for z in [-11.0,11.0]:
			world.box(self,Vector3(DEPTH+2,3.2,z),Vector3(2.6,6.4,2.6),"goal_wall")
			world.box(self,Vector3(DEPTH+2,6.6,z),Vector3(3.2,0.6,3.2),"goal_roof")
			world.box(self,Vector3(DEPTH+0.65,5.4,z),Vector3(0.08,0.6,1.5),"dark")

func build_scrapyard(world):
	# Salvage depot: open gantry crane, hook, and stacked recovered metal.
	for x in [3.0,13.0]:
		world.box(self,Vector3(x,4.8,-13),Vector3(0.65,9.6,0.65),"machine_iron")
		world.beam(self,Vector3(x,1,-14.5),Vector3(x,5,-13),0.18,"pipe_joint",6)
	world.box(self,Vector3(8,9.4,-13),Vector3(12,0.8,1.2),"machine_iron").name = "SalvageGantry"
	world.box(self,Vector3(7,8.8,-13),Vector3(1.5,0.8,1.8),"goal_roof")
	world.beam(self,Vector3(7,8.4,-13),Vector3(7,4,-13),0.055,"dark",6)
	world.beam(self,Vector3(7,4,-13),Vector3(7.6,3.4,-13),0.13,"machine_iron",6)
	world.beam(self,Vector3(7.6,3.4,-13),Vector3(8,3.9,-13),0.13,"machine_iron",6)
	for i in range(5):
		var plate = world.box(self,Vector3(3+i*2.1,0.35+(i%2)*0.45,-12),Vector3(2.4,0.55,3.0),"machine_hot" if i%2 else "machine_iron")
		plate.rotation.y = (i-2)*0.12
	world.box(self,Vector3(15,1.6,-13),Vector3(3.8,3.2,4.5),"goal_wall")
	world.box(self,Vector3(15,3.3,-13),Vector3(4.2,0.3,5),"goal_roof")

func build_coalfield(world):
	# Coal loading station: hopper, conveyor housing, and low coal bins.
	for x in [4.0,10.0]:
		for z in [-15.0,-11.0]:
			world.box(self,Vector3(x,2.2,z),Vector3(0.35,4.4,0.35),"machine_iron")
	world.cylinder(self,Vector3(7,5.7,-13),2.4,4.2,"machine_hot",4,3.8).name = "CoalHopper"
	world.box(self,Vector3(7,7.85,-13),Vector3(5.2,0.2,5.2),"goal_roof")
	world.box(self,Vector3(7,2.8,-13),Vector3(2.2,0.9,1.5),"dark")
	world.box(self,Vector3(12.5,2,-13),Vector3(7,0.7,1.3),"pipe_joint")
	for x in [2.0,6.0,10.0]:
		world.box(self,Vector3(x,0.5,14),Vector3(3.8,1,3.2),"goal_wall")
		world.cylinder(self,Vector3(x,1.05,14),1.65,1.1,"coal",7,0.45)
	world.cylinder(self,Vector3(16,4.5,-14),0.65,9,"dark",8)
	world.cylinder(self,Vector3(16,8.9,-14),0.85,0.4,"pipe_joint",8)

func build_arsenal(world):
	# Fortified ammunition depot: ribbed magazine roof and sheltered crates.
	world.box(self,Vector3(8,2.8,-13),Vector3(13,5.6,6),"goal_wall").name = "AmmunitionMagazine"
	world.box(self,Vector3(8,5.8,-13),Vector3(14,0.5,6.8),"goal_roof")
	for x in [2.0,5.0,8.0,11.0,14.0]:
		world.box(self,Vector3(x,5.95,-13),Vector3(0.18,0.3,7),"pipe_joint")
		world.box(self,Vector3(x,2.5,-9.95),Vector3(0.22,5,0.2),"pipe_joint")
	for x in [4.0,10.0]:
		world.box(self,Vector3(x,1.7,-9.9),Vector3(2.5,3.4,0.12),"dark")
		world.box(self,Vector3(x,1.7,-9.8),Vector3(0.12,3.4,0.08),"machine_iron")
	for x in [3.0,7.0,11.0]:
		world.box(self,Vector3(x,0.6,14),Vector3(2.8,1.2,2),"wood")
		for z in [13.25,14.75]:
			world.box(self,Vector3(x,0.65,z),Vector3(0.2,1.3,0.12),"pipe_joint")
	world.box(self,Vector3(16,1.3,13),Vector3(2.8,2.6,3),"goal_wall")
