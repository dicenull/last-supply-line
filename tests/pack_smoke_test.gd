extends SceneTree
## Run this external harness with --main-pack; it must not be present inside the pack.
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS pack: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	check(not FileAccess.file_exists("res://tests/factory_test.gd"),"test source is excluded from distribution")
	check(not ResourceLoader.exists("res://preview-tank.png"),"preview images are excluded from distribution")
	var scene = load("res://main.tscn")
	check(scene != null,"packed main scene loads")
	var game = scene.instantiate()
	game.history_path = "user://pack_smoke_profile_fixture.json"
	game.audio_settings_path = "user://pack_smoke_audio_fixture.json"
	game.audio_enabled = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	check(game.menu.visible and game.menu.blueprint_buttons.size() == 3,"pack opens title with blueprint previews")
	check(game.sound.streams.size() == 5,"dynamically loaded sound assets are present")
	game.close_menu()
	game.toggle_running()
	for i in range(180): game._process(0.1)
	check(game.factory.manufactured > 0 and game.factory.shots > 0,"packed factory produces and supplies real rounds")
	check(game.battlefield.distance > 0 and game.factory.fuel_used > 0,"packed battle drives on manufactured fuel")
	check(game.factory.finite_resources and game.factory.injected > 0 and game.factory.reserves.scrap+game.factory.reserves.coal == 80+game.factory.collected.scrap+game.factory.collected.coal-game.factory.injected,"packed sources consume finite raw materials")
	game.open_menu()
	check(not game.factory.running,"packed menu pauses gameplay")
	game.queue_free()
	await process_frame
	await process_frame
	for base in ["user://pack_smoke_profile_fixture.json","user://pack_smoke_audio_fixture.json"]:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(base+suffix): DirAccess.remove_absolute(base+suffix)
	print("PACK RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
