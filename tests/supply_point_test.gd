extends SceneTree
const Run = preload("res://scripts/run_state.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS supply point: ",label)
	else:
		failures += 1
		push_error(label)

func capture(game, path: String):
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run():
	root.size = Vector2i(1440,940)
	for kind in Run.ROUTES:
		var game = load("res://main.tscn").instantiate()
		Fixture.assign(game,"supply_point_test")
		game.show_start_menu = false
		game.expedition = Run.new(42)
		game.expedition.current = game.expedition.make_route(kind,true)
		root.add_child(game)
		game.set_process(false)
		game.toggle_battle()
		var b = game.battlefield
		check(b.resource_sites.size() == 3,"three existing recovery stops remain: "+kind)
		for i in range(3):
			var site = b.resource_sites[i]
			check(is_equal_approx(site.distance,b.route_length*[0.14,0.30,0.46][i]) and is_equal_approx(site.node.position.x,site.distance) and site.node.route_kind == kind,"route model uses actual recovery location: "+kind+" "+str(i))
			check(site.node.has_node({"scrapyard":"RecoveryHoist","coalfield":"CoalLoader","arsenal":"AmmoShelter"}[kind]),"stop has appropriate loading equipment: "+kind+" "+str(i))
			check(site.node.cargo.visible and not site.node.taken,"uncollected stop shows cargo: "+kind+" "+str(i))
		b.player.position.x = 4
		b.update_camera()
		await capture(game,"res://preview-supply-"+kind+"-loaded.png")
		game.toggle_running()
		game.factory.reserves = {"scrap":0,"coal":0}
		game.factory.ammo = 0
		b.player.position = Vector3(b.resource_sites[-1].distance+1,0,b.field_course.bounds.end.y-2)
		game._process(0)
		check(b.resource_sites.all(func(site): return not site.taken) and game.factory.reserves == {"scrap":0,"coal":0},"passing all X milestones outside the areas grants nothing: "+kind)
		var missed = game.checkpoint.snapshot(game)
		check(game.checkpoint.apply(game,missed) and game.battlefield.resource_sites.all(func(site): return not site.taken),"save beyond the stops preserves uncollected cargo: "+kind)
		b = game.battlefield
		var first = b.resource_sites[0]
		var radius: float = first.node.COLLECTION_RADIUS
		b.player.position = first.node.position+Vector3(-radius-0.01,0,0)
		game.factory.running = true
		game._process(0)
		check(not first.taken and first.node.collection_ring.visible,"just outside the visible boundary leaves cargo available: "+kind)
		b.player.position = first.node.position+Vector3(-radius,0,0)
		game.factory.running = false
		game._process(0)
		check(not first.taken,"paused simulation does not collect cargo: "+kind)
		game.factory.running = true
		game._process(0)
		check(first.taken and first.node.visible and not first.node.cargo.visible,"recovery removes cargo and retains depot structure: "+kind)
		check(not first.node.collection_ring.visible and b.distance < first.distance,"entering from behind the milestone collects and hides its range: "+kind)
		check(is_equal_approx(first.node.semaphore.rotation.z,-PI/2) and first.node.signal_lamp.material_override == first.node.empty_material,"empty depot lowers its signal and extinguishes its lamp: "+kind)
		check(game.factory.reserves.scrap == first.scrap and game.factory.reserves.coal == first.coal and game.factory.ammo == first.shells,"modeled supplies retain original recovery quantities: "+kind)
		check(b.result == 0 and b.resource_sites[1].node.cargo.visible,"middle stop does not clear course or consume later stops: "+kind)
		var stock = game.factory.reserves.duplicate()
		var ammo = game.factory.ammo
		b.player.position.x = 0
		game._process(0)
		b.player.position = first.node.position
		game._process(0)
		check(game.factory.reserves == stock and game.factory.ammo == ammo,"revisiting empty depot never grants supplies again: "+kind)
		var saved = game.checkpoint.snapshot(game)
		check(game.checkpoint.validate(saved) and game.checkpoint.apply(game,saved),"checkpoint preserves recovered stop: "+kind)
		b = game.battlefield
		check(b.resource_sites[0].node.visible and not b.resource_sites[0].node.cargo.visible and b.resource_sites[1].node.cargo.visible,"resume restores empty and loaded depot models: "+kind)
		var second = b.resource_sites[1].node
		var at: Vector3 = second.position
		check(second.crossed_by([{"position":at+Vector3(-20,5,0)},{"position":at+Vector3(20,5,0)}]) and second.crossed_by([{"position":at+Vector3(20,0,0)},{"position":at+Vector3(-20,0,0)}]),"swept entry works in both directions and ignores visual height: "+kind)
		check(not second.crossed_by([{"position":at+Vector3(-20,0,radius+0.01)},{"position":at+Vector3(20,0,radius+0.01)}]),"parallel movement outside the radius does not collect: "+kind)
		b.player.position.x = 4
		b.update_camera()
		await capture(game,"res://preview-supply-"+kind+"-empty.png")
		game.queue_free()
		await process_frame
	print("SUPPLY POINT RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _finalize(): Fixture.clean("supply_point_test")
