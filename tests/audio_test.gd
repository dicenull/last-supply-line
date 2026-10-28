extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Audio = preload("res://scripts/game_audio.gd")
var game
var failures = 0
var checks = 0
func _initialize(): call_deferred("run")
func _finalize(): Fixture.clean("audio_test")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS audio: ",label)
	else:
		failures += 1
		push_error(label)
func silent() -> bool:
	if game.sound.motor.playing: return false
	for voice in game.sound.voices:
		if voice.playing: return false
	return true
func click_at(pos: Vector2):
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = pos
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame
func run():
	var original_bus_count = AudioServer.bus_count
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"audio_test")
	game.expedition = preload("res://scripts/run_state.gd").new(42)
	game.audio_enabled = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var sound = game.sound
	check(silent() and is_equal_approx(sound.volume,0.35),"title starts silent with conservative default gain")
	check(sound.streams.size() == 11 and sound.motor.stream.loop_end == 22050 and sound.motor.stream.format == AudioStreamWAV.FORMAT_16_BITS,"eleven PCM effects and exact one-second motor loop")
	for kind in sound.KINDS:
		var stream = sound.streams[kind]
		check(stream.get_length() > 0.1 and stream.get_length() <= (2.71 if kind == "airdrop" else 1.01),"bounded nonempty sound asset: "+kind)
	await click_at(game.menu.navigation.settings.get_rect().get_center())
	await click_at(game.menu.mute_button.get_rect().get_center())
	check(sound.volume == 0 and silent(),"speaker button mutes immediately")
	await click_at(game.menu.mute_button.get_rect().get_center())
	check(is_equal_approx(sound.volume,0.35),"speaker button restores prior volume")
	await click_at(game.menu.volume_slider.get_rect().get_center())
	check(sound.volume >= 0.4 and sound.volume <= 0.6,"slider click changes volume")
	var saved_volume = sound.read_volume(sound.settings_path)
	check(saved_volume == sound.volume,"UI setting persists to disk")
	var settings = Audio.new()
	settings.settings_path = sound.settings_path
	settings.load_settings()
	check(settings.volume == sound.volume,"next instance restores audio preference")
	settings.free()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-audio-menu.png")
	game.close_menu()
	game.factory.edit(Vector2i(6,6),"belt",0)
	game._process(0.01)
	game.factory.edit(Vector2i(7,6),"belt",0)
	game._process(0.01)
	check(sound.played.get("place",0) == 2 and sound.played.get("connect",0) > 0,"successful construction and connection emit their distinct sounds before departure")
	var construction_sounds = sound.played.duplicate()
	game._process(0.01)
	check(sound.played == construction_sounds,"unchanged construction does not replay its feedback")
	game.factory.edit(Vector2i(4,1),"armor_block",0)
	game._process(0.01)
	game.factory.damage_at(Vector2(-2.5,-1.5))
	game._process(0.01)
	check(sound.played.get("armor",0) == 1,"real armor absorption emits a mechanical deflection sound")
	game.toggle_running()
	for i in range(400):
		preload("res://tests/profile_fixture.gd").drive(game,0.1)
		await process_frame
		if sound.played.get("machine",0) > 0 and sound.played.get("shot",0) > 0 and sound.motor.playing: break
	check(sound.played.get("machine",0) > 0 and sound.played.get("shot",0) > 0,"real factory completion and firing emit corresponding effects")
	check(sound.motor.playing,"fuel-powered movement runs motor loop")
	game.toggle_running()
	check(silent(),"Space-style pause stops every active voice immediately")
	var played_before = sound.played.duplicate()
	preload("res://tests/profile_fixture.gd").drive(game,0.1)
	check(sound.played == played_before,"paused simulation emits no sounds")
	game.toggle_running()
	preload("res://tests/profile_fixture.gd").drive(game,0.1)
	check(sound.motor.playing,"movement resumes motor after pause")
	game.open_menu()
	check(silent(),"menu pause stops all sounds")
	game.close_menu()
	sound.stop_all()
	game.battlefield.recover(game.factory,{"scrap":2})
	sound.sync()
	check(sound.played.get("pickup",0) > 0,"accepted salvage triggers pickup effect")
	sound.stop_all()
	game.battlefield.hull -= 1
	sound.sync()
	check(sound.played.get("impact",0) > 0,"actual hull change triggers impact effect")
	var impacts_before = sound.played.get("impact",0)
	sound.stop_all()
	game.battlefield.impact(Vector3.ZERO)
	sound.sync()
	check(sound.played.get("impact",0) == impacts_before+1,"ground impact emits sound even without damage or kill")
	for enemy in game.battlefield.enemies.slice(0,2):
		enemy.active = true
		enemy.hp = 1
		game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	sound.sync()
	check(sound.played.get("combo",0) > 0,"successive real kills trigger pitched combo feedback")
	sound.set_volume(0)
	preload("res://tests/profile_fixture.gd").drive(game,0.1)
	check(silent() and game.factory.running,"mute does not pause gameplay")
	sound.set_volume(0.5)
	sound.stop_all()
	for i in range(100): sound.play_effect("shot")
	var active = 0
	for voice in sound.voices:
		if voice.playing: active += 1
	check(active == 8 and sound.get_child_count() == 9,"effect bursts cannot allocate unbounded voices")
	sound.stop_all()
	for i in range(8): sound.play_effect("machine")
	var priority_shots = sound.played.get("shot",0)
	sound.play_effect("shot")
	check(sound.played.get("shot",0) == priority_shots+1 and sound.voices.filter(func(v): return v.get_meta("kind","") == "shot").size() == 1,"cannon fire replaces one production voice when the pool is busy")
	for i in range(8): sound.play_effect("reward")
	var quiet_before = sound.played.get("machine",0)
	sound.play_effect("machine")
	check(sound.played.get("machine",0) == quiet_before and sound.voices.all(func(v): return v.get_meta("kind","") == "reward"),"low-priority production cannot interrupt reward audio")
	sound.stop_all()
	var bus = AudioServer.get_bus_index(sound.bus_name)
	var capture = AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus,capture)
	for i in range(8): sound.play_effect("shot")
	await create_timer(0.15).timeout
	var samples = capture.get_buffer(capture.get_frames_available())
	var peak = 0.0
	for sample in samples: peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(samples.size() > 0 and peak > 0.001 and peak < 1,"limited eight-voice mix produces nonzero output below clipping")
	sound.stop_all()
	await create_timer(0.12).timeout
	capture.clear_buffer()
	await create_timer(0.12).timeout
	samples = capture.get_buffer(capture.get_frames_available())
	peak = 0.0
	for sample in samples: peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(peak < 0.00001,"stopped voices produce silence in the mixer")
	AudioServer.remove_bus_effect(bus,1)
	game.reset_battle()
	check(silent(),"new run stops old sounds")
	var f = FileAccess.open(sound.settings_path,FileAccess.WRITE)
	f.store_string("broken")
	f.close()
	sound.load_settings()
	check(not sound.settings_error and sound.volume == 0,"corrupt primary recovers previous valid mute setting")
	DirAccess.remove_absolute(sound.settings_path+".bak")
	sound.load_settings()
	check(sound.settings_error and is_equal_approx(sound.volume,0.35),"corrupt settings without backup use default and expose error")
	sound.settings_path = "user://missing_audio_directory/settings.json"
	check(not sound.set_volume(0.2) and sound.settings_error and is_equal_approx(sound.volume,0.2),"save failure keeps current session volume and reports failure")
	check(not sound.set_volume(NAN),"nonfinite volume rejected")
	game.queue_free()
	await create_timer(0.15).timeout
	check(AudioServer.bus_count == original_bus_count,"disposing game removes its private audio bus")
	print("AUDIO RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
