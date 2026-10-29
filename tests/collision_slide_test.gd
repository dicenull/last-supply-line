extends SceneTree
const Battle = preload("res://scripts/battle_world.gd")
const Run = preload("res://scripts/run_state.gd")
const Factory = preload("res://scripts/factory.gd")
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS collision slide: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var b = Battle.new()
	b.sector_config = Run.new(42).current.duplicate(true)
	for key in ["obstacles_version","field_version","encounters_version","defenses_version"]: b.sector_config.erase(key)
	root.add_child(b)
	var wall = Rect2(60,-100,2,200)
	b.obstacles.barriers = [wall]
	var f = Factory.new()
	f.fuel = 1000
	f.running = true
	for yaw in [0.0,0.35,-0.35,PI/2]:
		var slide = b.obstacles.slide_hull(Vector3(40,0,0),yaw,Vector3(80,0,12))
		check(slide.position.x < 60 and is_equal_approx(slide.position.z,12) and b.obstacles.clear_pose(slide.position,yaw),"large swept step slides without tunneling, yaw="+str(yaw))
		check(not slide.contacts.is_empty() and slide.contacts[0].normal == Vector3.LEFT and absf(slide.contacts[0].position.x-60) < 0.01,"contact lies on the blocking face, yaw="+str(yaw))
		check(slide.distance <= Vector3(80,0,12).length()+0.001,"slide never adds movement energy")
	b.obstacles.barriers.append(Rect2(0,20,100,2))
	var corner = b.obstacles.slide_hull(Vector3(40,0,0),0,Vector3(80,0,80))
	check(corner.contacts.size() == 2 and corner.position.x < 60 and corner.position.z < 20 and b.obstacles.clear_pose(corner.position,0),"two perpendicular walls stop at the corner without jitter or penetration")
	var retreat = b.obstacles.slide_hull(corner.position,0,Vector3(-4,0,-4))
	check(retreat.position.is_equal_approx(corner.position+Vector3(-4,0,-4)) and retreat.contacts.is_empty(),"moving away from a corner releases both contacts")
	b.obstacles.barriers = [wall]
	b.player.position = Vector3(48,0,0)
	b.player.rotation.y = -0.35
	b.motion.command = Vector3.RIGHT
	b.move_player(f,2)
	var transmission = b.motion.transmission.snapshot()
	var before = b.player.position
	var fuel = f.fuel
	b.move_player(f,1)
	check(b.player.position.z > before.z+0.5 and absf(b.player.position.x-before.x) < 0.01,"holding diagonal forward input keeps scraping along a wall")
	check(b.motion.poses.all(func(p): return b.obstacles.clear_pose(p.position,p.yaw)),"every recorded pickup and mine pose stays outside the wall")
	check(is_equal_approx(fuel-f.fuel,b.player.position.distance_to(before)*b.FUEL_PER_METER),"scraping charges fuel for actual tangential movement")
	check(not b.motion.contacts.is_empty() and b.feedback.emitted.get("scrape",0) > 0,"applied collision emits sparks")
	var full = b.player.position
	b.player.position = before
	b.motion.transmission.restore(transmission)
	for i in range(10): b.move_player(f,0.1)
	check(b.player.position.distance_to(full) < 0.01,"steady sliding is consistent across simulation step sizes")
	var emissions = b.feedback.emitted.scrape
	for i in range(10): b.drive_plan(3,0.2)
	check(b.feedback.emitted.scrape == emissions,"speculative collision and fuel plans never emit effects")
	b.player.position = Vector3(51.199,0,0)
	b.player.rotation.y = 0
	fuel = f.fuel
	for i in range(60):
		b.move_player(f,1.0/60)
		b.tick_feedback(1.0/60)
	check(b.player.position.distance_to(Vector3(51.199,0,0)) < 0.002 and absf(fuel-f.fuel) < 0.0003,"head-on pressure cannot penetrate or spend travel fuel")
	check(b.feedback.emitted.scrape-emissions >= 8 and b.feedback.emitted.scrape-emissions <= 12,"sustained pressure emits rate-limited spark bursts")
	check(b.feedback.active.size() <= 5,"expired scrape effects remain bounded during continuous contact")
	var contact = b.motion.contacts[0].position
	check(absf(contact.x-60) < 0.01 and absf(contact.z) <= b.CourseObstacles.HULL_HALF.y,"spark origin is at the hull contact, not its center")
	b.motion.command = Vector3.ZERO
	emissions = b.feedback.emitted.scrape
	b.move_player(f,1)
	b.tick_feedback(1)
	check(b.motion.contacts.is_empty() and b.feedback.active.is_empty() and b.feedback.emitted.scrape == emissions,"releasing controls stops sparks and cleans up particles")
	b.motion.command = Vector3.RIGHT
	f.fuel = 0
	b.move_player(f,1)
	check(b.feedback.emitted.scrape == emissions and b.motion.contacts.is_empty(),"empty fuel cannot produce powered scrape effects")
	f.fuel = 10
	f.running = false
	b.tick_battle(f,1)
	check(b.feedback.emitted.scrape == emissions,"paused simulation emits no contact sparks")
	f.running = true
	b.motion.command = Vector3.LEFT
	b.move_player(f,0.1)
	check(b.player.position.x < 51.198 and b.motion.contacts.is_empty(),"reverse disengages a head-on collision")
	b.player.position = Vector3(51.199,0,0)
	b.motion.command = Vector3.BACK
	b.move_player(f,0.1)
	check(b.obstacles.clear_pose(b.player.position,b.player.rotation.y) and not b.motion.contacts.is_empty(),"blocked hull rotation cannot clip a corner through a wall")
	b.motion.restore({"distance":0,"speed":0})
	check(b.motion.contacts.is_empty(),"restore discards transient contacts")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440,940)
		b.player.position = Vector3(51.199,0,0)
		b.player.rotation.y = 0
		b.motion.command = Vector3.RIGHT
		b.box(b,Vector3(61,1.5,0),Vector3(2,3,35),"machine_iron")
		b.feedback.clear()
		b.move_player(f,0.1)
		b.tick_feedback(0.16)
		b.zoom = 38
		b.update_camera()
		b.camera.position -= Vector3(14,0,0)
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		DirAccess.make_dir_recursive_absolute("res://build/collision-slide")
		root.get_texture().get_image().save_png("res://build/collision-slide/contact.png")
	b.queue_free()
	await process_frame
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
