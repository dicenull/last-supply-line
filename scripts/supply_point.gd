extends Node3D
## Roadside supply stop. Cargo disappears on collection; its empty depot remains.
var cargo: Node3D
var signal_lamp: MeshInstance3D
var semaphore: Node3D
var available_material: Material
var empty_material: Material
var route_kind = ""
var taken = false

func build(world, kind: String, index: int, shells: int):
	route_kind = kind
	name = "SupplyPoint"+str(index+1)
	available_material = world.mats.goal_signal
	empty_material = world.mats.dark
	cargo = Node3D.new()
	cargo.name = "Cargo"
	add_child(cargo)
	# Timber loading platform, runners, and steel corner guards.
	world.box(self,Vector3(0,0.16,0),Vector3(7,0.32,4),"goal_roof")
	for x in [-3.0,-2.0,-1.0,0.0,1.0,2.0,3.0]:
		world.box(self,Vector3(x,0.37,0),Vector3(0.94,0.12,3.8),"wood")
	for z in [-1.9,1.9]:
		world.box(self,Vector3(0,0.48,z),Vector3(7,0.18,0.12),"pipe_joint")
	for x in [-3.3,3.3]:
		for z in [-1.7,1.7]:
			world.box(self,Vector3(x,0.7,z),Vector3(0.18,1.2,0.18),"machine_iron")
	# A mechanical availability signal instead of a floating pickup icon.
	world.box(self,Vector3(-3,1.9,-1.6),Vector3(0.18,3.4,0.18),"pipe_joint")
	semaphore = Node3D.new()
	semaphore.position = Vector3(-3,3.3,-1.6)
	add_child(semaphore)
	world.box(semaphore,Vector3(0.55,0,0),Vector3(1.2,0.25,0.12),"edge")
	signal_lamp = world.box(self,Vector3(-3,2.6,-1.75),Vector3(0.42,0.55,0.25),"goal_signal")
	for i in range(index+1):
		world.box(self,Vector3(-2.5+i*0.28,0.48,-2.01),Vector3(0.12,0.2,0.04),"edge")
	# Every stop carries both raw materials, matching its actual recovery bundle.
	world.box(self,Vector3(1.8,0.7,0.8),Vector3(1.8,0.55,1.6),"machine_iron")
	for i in range(4):
		world.cylinder(cargo,Vector3(1.4+(i%2)*0.65,1.12+(i/2)*0.12,0.5+(i/2)*0.55),0.45,0.5,"coal",5,0.25)
	for i in range(3):
		var plate = world.box(cargo,Vector3(-1.0,0.55+i*0.2,1),Vector3(2.4,0.18,0.85),"machine_hot" if i%2 else "machine_iron")
		plate.rotation.y = (i-1)*0.12
	match kind:
		"coalfield": build_loader(world)
		"arsenal": build_magazine(world)
		_: build_hoist(world)
	if shells > 0:
		world.box(self,Vector3(1.6,0.65,-0.9),Vector3(1.9,0.4,1.2),"wood")
		for x in [1.0,1.6,2.2]:
			var shell = world.make_good("shell")
			cargo.add_child(shell)
			shell.position = Vector3(x,1.0,-0.9)
			shell.scale = Vector3.ONE*2.3
	set_taken(false)

func build_hoist(world):
	# Small field crane and suspended empty lifting chain.
	world.box(self,Vector3(2.6,2.4,-1.3),Vector3(0.3,4.2,0.3),"machine_iron")
	world.box(self,Vector3(0.5,4.3,-1.3),Vector3(4.5,0.35,0.4),"machine_iron").name = "RecoveryHoist"
	world.beam(self,Vector3(2.6,2.5,-1.3),Vector3(0.3,4.3,-1.3),0.1,"pipe_joint",6)
	world.beam(self,Vector3(-1.1,4.2,-1.3),Vector3(-1.1,2.2,-1.3),0.045,"dark",6)
	world.beam(self,Vector3(-1.1,2.2,-1.3),Vector3(-0.7,2,-1.3),0.09,"machine_iron",6)
	for x in [-0.9,0.5]:
		world.box(cargo,Vector3(x,0.9,-0.7),Vector3(1.1,0.9,1),"machine_hot")
		world.box(cargo,Vector3(x,1.38,-0.7),Vector3(1.15,0.08,1.05),"pipe_joint")

func build_loader(world):
	for x in [-1.9,0.3]:
		world.box(self,Vector3(x,1.6,-0.9),Vector3(0.22,2.5,0.22),"pipe_joint")
	world.cylinder(self,Vector3(-0.8,2.7,-0.9),0.85,1.5,"machine_hot",4,1.45).name = "CoalLoader"
	world.cylinder(cargo,Vector3(-0.8,3.5,-0.9),1.05,0.6,"coal",7,0.3)
	world.box(self,Vector3(-0.8,1.45,-0.9),Vector3(0.8,0.45,0.7),"dark")
	world.box(self,Vector3(0.2,1.1,-0.9),Vector3(2.2,0.25,0.7),"pipe_joint")

func build_magazine(world):
	for x in [-2.0,2.6]:
		world.box(self,Vector3(x,1.9,-1.5),Vector3(0.22,3,0.22),"machine_iron")
	var roof = world.box(self,Vector3(0.3,3.35,-0.65),Vector3(5.3,0.22,2.5),"goal_roof")
	roof.name = "AmmoShelter"
	roof.rotation.x = -0.12
	for x in [-1.6,-0.2]:
		world.box(cargo,Vector3(x,0.95,-0.7),Vector3(1.2,1,1),"wood")
		for z in [-1.15,-0.25]:
			world.box(cargo,Vector3(x,1,z),Vector3(0.16,1.1,0.08),"pipe_joint")

func set_taken(value: bool):
	taken = value
	cargo.visible = not value
	signal_lamp.material_override = empty_material if value else available_material
	semaphore.rotation.z = -PI/2 if value else 0.0
