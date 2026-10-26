extends "res://scripts/tank_world.gd"
## A display model only: no factory, battle simulation, loot, or player input.
var elapsed = 0.0

func _ready():
	layout_version = 2
	yaw = 0.92
	pitch = 0.48
	zoom = 25.5
	super._ready()
	camera.far = 600
	toggle_roof()
	camera.h_offset = -6.4
	camera.v_offset = 2.4
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("202c29")
			child.environment.ambient_light_color = Color("a9bcb5")
			child.environment.ambient_light_energy = 0.6
		if child is DirectionalLight3D:
			child.light_energy *= 1.25

func terrain():
	material("title_ground","27332e",0.1)
	box(self,Vector3(0,-0.27,0),Vector3(500,0.3,500),"title_ground")
	for z in [-5.1,5.1]:
		for i in range(18):
			box(self,Vector3(-10-i*0.75,-0.1,z),Vector3(0.2,0.02,1.2),"dark")

func _process(delta: float):
	elapsed += delta
	yaw = 0.92+sin(elapsed*0.12)*0.045
	var dimensions = get_viewport().get_visible_rect().size
	var aspect = dimensions.x/maxf(1,dimensions.y)
	zoom = maxf(25.5,23.0/aspect) if aspect < 1 else 25.5
	camera.h_offset = 0.0 if aspect < 1 else -0.18*aspect*zoom
	camera.v_offset = -0.12*zoom if aspect < 1 else 0.1*zoom
	update_camera()
