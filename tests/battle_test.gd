extends SceneTree
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS battle: ",label)
func _initialize(): call_deferred("run")
func advance(seconds: float):
	for i in range(int(seconds/0.025)):
		game.factory.step(0.025)
		game.battlefield.tick_battle(game.factory,0.025)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.factory.example()
	var layout = game.factory.layout()
	game.toggle_battle()
	check(not game.started and not game.factory.running,"B previews exterior without starting simulation")
	game.toggle_running()
	check(game.battle_mode and not game.factory.auto_fire,"battle mode disables test firing")
	check(game.factory.layout() == layout,"entering battle preserves factory layout")
	check(game.battlefield.roof_closed and game.battlefield.mats.turret_armor.albedo_color.a == 1.0,"battle presents opaque tank exterior")
	check(game.cell_at(Vector2(550,400)) == Vector2i(-1,-1),"battlefield clicks cannot edit factory")
	advance(1)
	check(game.battlefield.distance == 0,"tank cannot move before first manufactured fuel arrives")
	advance(11)
	check(game.battlefield.distance > 0 and game.factory.fuel_used > 0,"manufactured fuel powers real movement")
	check(is_equal_approx(game.battlefield.distance*game.battlefield.FUEL_PER_METER,game.factory.fuel_used),"straight-line travel consumes fuel in proportion to distance")
	check(game.battlefield.enemies[0].active and not game.battlefield.enemies[4].active,"enemies arrive in stages instead of a stationary ring")
	check(game.factory.shots > 0 and game.battlefield.visual_shots == game.factory.shots,"each battle shot consumes one manufactured round")
	game.queue_redraw()
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-battle.png")
	var combat_time = game.battlefield.elapsed
	var hp = game.battlefield.hull
	game.toggle_battle()
	check(game.factory.running and not game.factory.auto_fire,"interior view leaves simulation running")
	game.paint(Vector2i(10,7),false)
	check(game.factory.cells.has(Vector2i(10,7)) and game.factory.running,"live placement preserves running state")
	game.last_paint = Vector2i(-1,-1)
	game.paint(Vector2i(10,7),true)
	check(not game.factory.cells.has(Vector2i(10,7)) and game.factory.running,"live removal preserves running state")
	var before_progress = game.battlefield.elapsed
	game._process(0.1)
	check(game.battlefield.elapsed > before_progress,"battle advances while viewing interior")
	combat_time = game.battlefield.elapsed
	hp = game.battlefield.hull
	check(game.factory.layout() == layout,"return preserves layout")
	check(game.battlefield.elapsed == combat_time and game.battlefield.hull == hp,"return preserves encounter state")
	game.toggle_battle()
	game.toggle_running()
	game.toggle_battle()
	check(not game.factory.running,"B preserves paused state")
	game.paint(Vector2i(11,7),false)
	check(game.factory.cells.has(Vector2i(11,7)) and not game.factory.running,"editing while paused preserves paused state")
	advance(3)
	check(game.battlefield.elapsed == combat_time,"pause freezes combat and production")
	game.toggle_running()
	advance(110)
	check(game.battlefield.result == 1 and game.battlefield.kills == 6,"sample factory travels route and defeats all six opponents")
	check(not game.factory.running,"victory stops encounter")
	game.reset_battle()
	check(not game.started and not game.factory.running,"retry returns to preparation")
	game.toggle_running()
	check(game.battlefield.result == 0 and game.battlefield.hull == 100 and game.factory.shots == 0,"retry resets encounter and stock without changing layout")
	game.factory.clear_layout(false)
	game.factory.running = true
	game.factory.ammo = 2
	advance(2)
	check(game.factory.shots > 0 and game.battlefield.distance == 0,"fuel-starved tank can still fire stocked ammunition")
	game.reset_battle()
	check(not game.started and not game.factory.running,"retry returns to preparation")
	game.toggle_running()
	game.factory.clear_layout(false)
	game.factory.running = true
	game.factory.fuel = 12.0
	game.battlefield.enemies[0].cooldown = 1.5
	advance(0.05)
	var locked = game.battlefield.enemies[0].aim
	check(game.battlefield.enemies[0].locked and game.battlefield.enemies[0].mark.visible,"enemy marks a fixed impact location before firing")
	advance(4.5)
	check(game.battlefield.hull == 100 and game.battlefield.player.position.distance_to(locked) > 6,"moving beyond warning zone avoids the enemy shell")
	var before_click = game.battlefield.player.position
	var click_event = InputEventMouseButton.new()
	click_event.position = Vector2(900,650)
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	game._unhandled_input(click_event)
	advance(1)
	check(game.battlefield.player.position.x > before_click.x and game.battlefield.player.position.z == 0,"battlefield clicks do not steer or change automatic advance")
	game.reset_battle()
	check(not game.started and not game.factory.running,"retry returns to preparation")
	game.toggle_running()
	game.factory.clear_layout(false)
	game.factory.running = true
	advance(100)
	check(game.factory.shots == 0 and game.battlefield.kills == 0,"empty factory never fires or defeats opponents")
	check(game.battlefield.result == -1 and game.battlefield.hull == 0,"unsupplied tank reaches defeat")
	game.toggle_running()
	check(not game.factory.running,"finished encounter cannot resume with Space")
	print("BATTLE RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
