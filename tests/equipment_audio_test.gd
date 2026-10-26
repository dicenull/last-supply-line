extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("equipment_audio_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment audio: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_audio_test",2)
	game.audio_enabled = true
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.toggle_running()
	game._process(0)
	var sound = game.sound
	var before = sound.played.get("pickup",0)
	var enemy = game.battlefield.enemies[0]
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	game.battlefield.drive_poses = [{"position":enemy.node.position,"yaw":0.0}]
	game.battlefield.update_ground_items(game.factory)
	game._process(0)
	check(sound.played.get("pickup",0) == before+1,"enemy material drop produces one collection cue")
	sound.stop_all()
	before = sound.played.get("pickup",0)
	var item_count = game.expedition.gear_items.size()
	game.battlefield.sector_config.encounter = "rich"
	game.battlefield.player.position = game.battlefield.resource_sites[0].node.position
	game._process(0)
	check(game.expedition.gear_items.size() == item_count,"supply opening leaves equipment on the ground")
	game._process(0)
	check(game.expedition.gear_items.size() == item_count+6 and sound.played.get("pickup",0) == before+1,"six-item rich site uses one collection voice")
	game._process(0)
	check(sound.played.get("pickup",0) == before+1,"unchanged collection does not replay on the next frame")
	sound.set_volume(0,false)
	game.receive_item({"kind":"armor","rarity":"normal"})
	game._process(0)
	sound.set_volume(0.35,false)
	game._process(0)
	check(sound.played.get("pickup",0) == before+1 and not sound.pending_pickup,"unmuting does not replay drops collected while muted")
	game.receive_item({"kind":"armor","rarity":"normal"})
	game.open_menu()
	game._process(0)
	game.close_menu()
	game._process(0)
	check(sound.played.get("pickup",0) == before+1,"menu pause discards queued collection audio")
	game.factory.running = false
	game.expedition.phase = "shop"
	game.expedition.current.shop_offers = ["gear:armor"]
	game.expedition.current.shop_purchased = [false]
	game.factory.reserves.scrap = 100
	sound.stop_all()
	var rewards = sound.played.get("reward",0)
	check(game.buy_shop_item(0) and sound.played.get("reward",0) == rewards+1,"successful purchase emits one confirmation cue")
	game._process(0)
	check(sound.voices.any(func(voice): return voice.playing and voice.get_meta("kind","") == "reward") and not sound.motor.playing,"shop sync lets confirmation finish while the motor stays silent")
	check(not game.buy_shop_item(0) and sound.played.get("reward",0) == rewards+1,"rejected duplicate purchase does not play success feedback")
	game.open_menu()
	check(sound.voices.all(func(voice): return not voice.playing),"menu interrupts shop audio immediately")
	game.close_menu()
	game.reset_battle(42)
	check(not sound.pending_pickup and sound.voices.all(func(voice): return not voice.playing),"new run clears queued and active feedback")
	game.queue_free()
	await process_frame
	print("EQUIPMENT AUDIO RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
