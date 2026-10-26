extends Node3D
## Short, bounded mechanical feedback. It never changes gameplay or its RNG.
const LIMIT = 48
var world
var active: Array = []
var serial = 0
var emitted: Dictionary = {}
var scrape_clock = 0.0

func setup(owner_world):
	world = owner_world
	world.material("fx_brass","c3a36a",0,0.35)
	world.material("fx_steam","9da89b")
	world.material("fx_fuel","76a999",0,0.25)
	world.material("fx_iron","6b7162")
	world.material("fx_spark","ffad45",0,0.35)
	world.mats.fx_spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func clear():
	for effect in active:
		remove_child(effect.node)
		effect.node.queue_free()
	active.clear()
	scrape_clock = 0.0

func scrape(contacts: Array, delta: float):
	if delta <= 0: return
	if contacts.is_empty():
		scrape_clock = 0
		return
	scrape_clock = maxf(0,scrape_clock-delta)
	if scrape_clock > 0: return
	scrape_clock = 0.09
	for contact in contacts.slice(0,2):
		var effect = burst("scrape",contact.position)
		for part in effect.parts:
			# Throw sparks away from the solid surface, into the visible free space.
			var normal: Vector3 = contact.normal
			if part.velocity.dot(normal) < 0: part.velocity = part.velocity.bounce(normal)
			part.velocity += normal*1.5
			part.mesh.quaternion = Quaternion(Vector3.BACK,part.velocity.normalized())
			part.spin = Vector3.ZERO

func burst(kind: String, at: Vector3, strength: float = 1.0) -> Dictionary:
	while active.size() >= LIMIT:
		var oldest = active.pop_front()
		remove_child(oldest.node)
		oldest.node.queue_free()
	serial += 1
	emitted[kind] = emitted.get(kind,0)+1
	var node = Node3D.new()
	add_child(node)
	node.position = at
	var heavy = kind in ["kill","salvo","reward"]
	var life = 0.32 if kind == "scrape" else 1.1 if heavy else 0.55 if kind in ["place","connect","armor"] else 0.7
	var effect = {"node":node,"kind":kind,"age":0.0,"life":life,"parts":[]}
	var count = 10 if heavy else 8 if kind == "scrape" else 6 if kind in ["place","connect","armor"] else 4
	for i in range(count):
		var angle = TAU*i/count+serial*0.73
		var steam = kind in ["fuel","production"] and i%2 == 0
		var debris = kind == "kill" or kind == "remove"
		var mat = "fx_spark" if kind == "scrape" else "fx_fuel" if kind in ["connect","fuel","armor"] else "fx_iron" if debris else "fx_steam" if steam else "fx_brass"
		var size_value = Vector3.ONE*(0.11 if not heavy else 0.25)*strength
		if debris: size_value = Vector3(0.3,0.12,0.6)*strength
		if kind == "shot": size_value = Vector3(0.12,0.12,0.35)*strength
		if kind == "scrape": size_value = Vector3(0.14,0.14,0.9)
		var piece = world.box(node,Vector3.ZERO,size_value,mat)
		var material = piece.material_override.duplicate()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		piece.material_override = material
		if kind == "scrape": piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var speed = (1.2 if not heavy else 5.0)*strength
		if kind == "scrape": speed = 4.0+(i%3)*1.5
		var velocity = Vector3(cos(angle)*speed,(1.2+(i%3)*0.6)*strength,sin(angle)*speed)
		if kind == "scrape": velocity.y = 4.5+(i%3)*1.5
		if kind in ["connect","armor"]: velocity.y = 0.12
		if steam: velocity = Vector3(cos(angle)*0.25,0.8+(i%3)*0.3,sin(angle)*0.25)
		effect.parts.append({"mesh":piece,"velocity":velocity,"steam":steam,"debris":debris,"spin":Vector3(1+i%3,0.7+i%2,0.5+i%4)})
	if kind in ["place","connect","armor","load","reward"]:
		for side in range(4):
			var rim = world.box(node,Vector3.ZERO,Vector3(0.8,0.035,0.055)*strength,"fx_fuel" if kind in ["connect","armor"] else "fx_brass")
			rim.rotation.y = side*PI/2
			rim.material_override = rim.material_override.duplicate()
			rim.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			effect.parts.append({"mesh":rim,"velocity":Vector3(sin(side*PI/2),0,cos(side*PI/2))*0.9*strength,"steam":false,"debris":false,"spin":Vector3.ZERO})
	active.append(effect)
	return effect

func tick(delta: float):
	if delta <= 0: return
	for effect in active.duplicate():
		effect.age += delta
		var progress = clampf(effect.age/effect.life,0,1)
		for part in effect.parts:
			var t: float = effect.age
			part.mesh.position = part.get("origin",Vector3.ZERO)+part.velocity*t
			if part.debris:
				part.mesh.position.y = maxf(0.03,part.mesh.position.y-3.5*t*t)
			elif not part.steam and effect.kind not in ["connect","armor"]:
				part.mesh.position.y -= 0.9*t*t
			part.mesh.rotation += part.spin*delta
			if part.steam: part.mesh.scale = Vector3.ONE*(0.7+progress*2.5)
			part.mesh.material_override.albedo_color.a = (1-progress)*(0.5 if part.steam else 1.0)
		if progress >= 1:
			remove_child(effect.node)
			effect.node.queue_free()
			active.erase(effect)

func arc(from: Vector3, to: Vector3):
	var effect = burst("arc",from,0.6)
	effect.life = 0.24
	for part in effect.parts:
		effect.node.remove_child(part.mesh)
		part.mesh.queue_free()
	effect.parts.clear()
	var difference = to-from
	var side = difference.cross(Vector3.UP).normalized()
	var previous = Vector3.ZERO
	for i in range(1,9):
		var point = difference*(i/8.0)
		if i < 8: point += side*(0.35 if i%2 else -0.35)+Vector3.UP*(0.2 if i%3 else -0.2)
		var beam = world.beam(effect.node,previous,point,0.06,"fx_fuel",6)
		beam.material_override = beam.material_override.duplicate()
		beam.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		effect.parts.append({"mesh":beam,"origin":beam.position,"velocity":Vector3.ZERO,"steam":false,"debris":false,"spin":Vector3.ZERO})
		previous = point
