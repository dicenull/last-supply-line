extends RefCounted
## Stylized mechanisms informed by the sources in data/historical_parts.json.
## Shared by the field, encyclopedia, results, warehouse and fitted vehicle.
static func build(b, root: Node3D, spec: Dictionary):
	var id: String = spec.historical_model
	root.set_meta("historical_model",id)
	match spec.slot:
		"cannon": cannon(b,root,spec)
		"engine": engine(b,root,id)
		"gear": gearbox(b,root,id)
		"tracks":
			for side in [-1,1]:
				var group = Node3D.new()
				root.add_child(group)
				group.position.z = side*0.48
				track_side(b,group,id,side)

static func cannon(b, root: Node3D, spec: Dictionary):
	var id: String = spec.historical_model
	var length = float(spec.barrel_length)
	var radius = 0.15 if id == "de_kwk36" else 0.12 if id == "gb_6pdr" else 0.075
	b.box(root,Vector3(-0.34,0.72,0),Vector3(0.62,0.40,0.40),"iron")
	b.beam(root,Vector3(-0.1,0.72,0),Vector3(length,0.72,0),radius,"iron")
	b.beam(root,Vector3(length-0.10,0.72,0),Vector3(length,0.72,0),radius*1.15,"dark")
	root.set_meta("muzzle",Vector3(length,0.72,0))
	match id:
		"gb_6pdr":
			b.cylinder(root,Vector3(-0.25,0.38,0),0.42,0.40,"paint")
			for side in [-1,1]:
				var shield = b.box(root,Vector3(0.0,0.8,side*0.38),Vector3(0.18,0.85,0.48),"paint")
				shield.rotation.y = side*0.35
				b.beam(root,Vector3(-0.5,0.47,side*0.21),Vector3(0.8,0.47,side*0.21),0.09,"brass")
			b.box(root,Vector3(-0.7,0.66,0.23),Vector3(0.22,0.18,0.18),"dark")
		"fr_sa18":
			b.box(root,Vector3(0.05,0.75,0),Vector3(0.12,0.52,0.57),"paint")
			b.beam(root,Vector3(-0.38,0.61,0),Vector3(-0.9,0.5,0),0.06,"iron")
			b.box(root,Vector3(-0.92,0.57,0),Vector3(0.12,0.36,0.38),"rust")
			b.beam(root,Vector3(-0.5,0.9,-0.22),Vector3(0.28,0.9,-0.22),0.055,"dark")
			b.spur_gear(root,Vector3(-0.28,0.53,0.32),0.12,"iron")
		"de_kwk36":
			b.box(root,Vector3(0,0.73,0),Vector3(0.25,0.78,1.03),"paint")
			for z in [-0.31,0.31]: b.beam(root,Vector3(-0.55,1.03,z),Vector3(0.85,1.03,z),0.10,"paint")
			for x in [length-0.29,length-0.10]:
				b.box(root,Vector3(x,0.72,0),Vector3(0.10,0.38,0.68),"iron")
				b.box(root,Vector3(x,0.72,0.35),Vector3(0.065,0.20,0.015),"dark")
			for x in [0.55,1.3]:
				var sleeve = b.cylinder(root,Vector3(x,0.72,0),radius*1.15,0.10,"paint")
				sleeve.rotation.z = PI/2
		"jp_type1":
			var shield = b.box(root,Vector3(-0.02,0.75,0),Vector3(0.19,0.57,0.63),"paint")
			shield.rotation.z = 0.12
			b.beam(root,Vector3(-0.6,0.96,0),Vector3(0.65,0.96,0),0.085,"paint")
			b.beam(root,Vector3(-0.58,0.49,0.18),Vector3(0.48,0.49,0.18),0.065,"brass")
			b.box(root,Vector3(-0.64,0.75,0.26),Vector3(0.16,0.16,0.24),"iron")

static func engine(b, root: Node3D, id: String):
	if id == "us_a57":
		b.beam(root,Vector3(-0.7,0.83,0),Vector3(0.7,0.83,0),0.29,"iron")
		for bank in range(5):
			var angle = bank*TAU/5
			var center = Vector3(0,0.83+cos(angle)*0.43,sin(angle)*0.43)
			var cover = b.box(root,center,Vector3(1.50,0.26,0.27),"paint")
			cover.rotation.x = angle
			for i in range(6):
				var head = b.cylinder(root,center+Vector3(-0.6+i*0.24,0,0),0.11,0.40,"iron")
				head.rotation.x = angle
			b.beam(root,center+Vector3(-0.75,0.10,0),center+Vector3(0.75,0.10,0),0.065,"brass")
		b.spur_gear(root,Vector3(0.78,0.83,0),0.30,"iron")
		for x in [-0.45,0,0.45]: b.box(root,Vector3(x,1.48,0),Vector3(0.25,0.22,0.25),"dark")
	elif id == "gb_daimler":
		b.box(root,Vector3(0,0.45,0),Vector3(1.6,0.3,0.55),"paint")
		for i in range(6):
			b.cylinder(root,Vector3(-0.6+i*0.24,0.85,0),0.12,0.65,"iron")
			b.box(root,Vector3(-0.6+i*0.24,1.2,0),Vector3(0.20,0.1,0.26),"paint")
		b.beam(root,Vector3(-0.7,0.95,0.30),Vector3(0.7,0.95,0.30),0.065,"rust")
		var flywheel = b.cylinder(root,Vector3(0.88,0.6,0),0.42,0.12,"dark")
		flywheel.rotation.z = PI/2
		for i in range(8):
			var angle = i*TAU/8
			b.beam(root,Vector3(0.96,0.6,0),Vector3(0.96,0.6+cos(angle)*0.34,sin(angle)*0.34),0.035,"iron")
	else: # V-2: a low, splayed V12 with separate long intake manifolds.
		b.box(root,Vector3(0,0.43,0),Vector3(1.6,0.30,0.55),"iron")
		for side in [-1,1]:
			for i in range(6):
				var cylinder = b.cylinder(root,Vector3(-0.64+i*0.25,0.78,side*0.28),0.12,0.55,"iron")
				cylinder.rotation.x = side*0.65
			var cover = b.box(root,Vector3(0,1.0,side*0.44),Vector3(1.55,0.15,0.25),"paint")
			cover.rotation.x = side*0.65
			b.beam(root,Vector3(-0.7,0.67,side*0.55),Vector3(0.7,0.67,side*0.55),0.10,"dark")
		b.box(root,Vector3(0.05,1.12,0),Vector3(0.7,0.18,0.2),"brass")
		b.beam(root,Vector3(-0.85,0.52,0),Vector3(-1.03,0.52,0),0.17,"iron")

static func gearbox(b, root: Node3D, id: String):
	if id == "gb_wilson":
		b.beam(root,Vector3(-0.8,0.7,0),Vector3(0.8,0.7,0),0.10,"iron")
		for x in [-0.48,0.48]:
			var ring = TorusMesh.new()
			ring.inner_radius = 0.25
			ring.outer_radius = 0.33
			var rim = b.part(root,ring,Vector3(x,0.77,0.04),"paint")
			rim.rotation.x = PI/2
			b.spur_gear(root,Vector3(x,0.77,0.08),0.12,"brass")
			for angle in [0,TAU/3,2*TAU/3]: b.spur_gear(root,Vector3(x+cos(angle)*0.2,0.77+sin(angle)*0.2,0.1),0.07,"iron")
			b.beam(root,Vector3(x,0.4,-0.25),Vector3(x-0.15,1.35,-0.25),0.035,"dark")
			b.box(root,Vector3(x-0.15,1.36,-0.25),Vector3(0.18,0.07,0.10),"rust")
	else:
		b.box(root,Vector3(0,0.45,-0.13),Vector3(1.65,0.30,0.62),"paint")
		for i in range(8):
			b.spur_gear(root,Vector3(-0.68+i*0.19,0.72,0.18),0.23-i*0.014,"iron")
			b.box(root,Vector3(-0.68+i*0.19,0.94,-0.15),Vector3(0.06,0.18,0.48),"brass")
		b.beam(root,Vector3(-0.7,1.14,-0.1),Vector3(0.7,1.14,-0.1),0.13,"paint")
		for x in [-0.48,0.48]: b.beam(root,Vector3(x,0.7,-0.34),Vector3(x,1.18,-0.34),0.035,"brass")
		b.spur_gear(root,Vector3(0.85,0.62,0.05),0.30,"dark")

static func track_side(b, root: Node3D, id: String, side: int):
	b.box(root,Vector3(0,0.54,0),Vector3(1.70,0.12,0.18),"paint")
	var wheels: Array = []
	if id == "fr_ft_tracks":
		wheels = [[-0.82,0.55,0.31,"rust"],[0.80,0.45,0.23,"iron"]]
		for i in range(8): wheels.append([-0.53+i*0.15,0.35,0.12,"iron"])
		b.beam(root,Vector3(-0.65,0.81,0),Vector3(0.68,0.81,0),0.05,"iron")
		for i in range(5): b.box(root,Vector3(-0.84+i*0.07,0.55,side*0.17),Vector3(0.045,0.47,0.035),"paint")
	elif id == "us_vvss":
		for x in [-0.55,0,0.55]:
			for dx in [-0.13,0.13]: wheels.append([x+dx,0.40,0.18,"iron"])
			b.box(root,Vector3(x,0.65,0),Vector3(0.21,0.32,0.30),"paint")
			for n in range(4): b.cylinder(root,Vector3(x,0.67+n*0.055,side*0.18),0.12-n*0.015,0.03,"iron")
	else:
		for i in range(5):
			var x = -0.65+i*0.325
			wheels.append([x,0.50,0.25,"dark"])
			for n in range(5): b.cylinder(root,Vector3(x,0.73+n*0.05,0),0.08,0.025,"iron")
	for wheel in wheels:
		var node = b.cylinder(root,Vector3(wheel[0],wheel[1],side*0.11),wheel[2],0.15,wheel[3])
		node.rotation.x = PI/2
		var hub = b.cylinder(root,Vector3(wheel[0],wheel[1],side*0.20),wheel[2]*0.35,0.05,"brass" if id == "fr_ft_tracks" else "iron")
		hub.rotation.x = PI/2
	for i in range(12):
		var x = -0.88+i*0.16
		for y in [0.16,0.90 if id == "fr_ft_tracks" else 0.82]:
			b.box(root,Vector3(x,y,0),Vector3(0.14,0.06,0.28 if id == "fr_ft_tracks" else 0.40),"iron")
			if id == "su_christie": b.box(root,Vector3(x,y+0.045,0),Vector3(0.06,0.04,0.40),"paint")
	for x in [-0.95,0.96]:
		for i in range(4):
			var link = b.box(root,Vector3(x,0.25+i*0.16,0),Vector3(0.07,0.14,0.28 if id == "fr_ft_tracks" else 0.4),"iron")
			link.rotation.z = 0.15*signf(x)
