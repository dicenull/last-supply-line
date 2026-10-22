extends RefCounted
## Explicit waypoint pilot for simulation regression tests. Real key input
## and no-input stopping are covered separately by phase_movement_test.gd.
static func drive(game, delta: float):
	if game.battlefield != null and game.expedition.phase == "travel" and game.factory.running and not game.menu.visible:
		pilot(game.battlefield)
	game._process(delta)

static func pilot(battle):
	var points = battle.obstacles.navigation_points(battle.route_length)
	var index = 0
	while index < points.size()-1:
		var reached = battle.player.position.distance_to(points[index]) < 0.6
		var passed = battle.player.position.x > points[index].x+0.4
		var corner = points[index].x == points[index+1].x and battle.player.position.x >= points[index].x-0.4
		if not reached and not passed and not corner: break
		index += 1
	var offset: Vector3 = points[index]-battle.player.position
	var desired = atan2(-offset.z,offset.x)
	var error = angle_difference(battle.player.rotation.y,desired)
	battle.movement_direction = Vector3(1 if absf(error) < 0.055 else 0,0,clampf(-error/0.12,-1,1))
## Keep tests from reading or granting unlocks in the player's profile.
static func path_for(suite: String) -> String:
	return "user://"+suite+"_profile_fixture.json"
static func clean(suite: String):
	for suffix in ["",".bak",".tmp"]:
		var path = path_for(suite)+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		var audio_path = "user://"+suite+"_audio_fixture.json"+suffix
		if FileAccess.file_exists(audio_path): DirAccess.remove_absolute(audio_path)
		var layout_path = "user://"+suite+"_layout_fixture.json"+suffix
		if FileAccess.file_exists(layout_path): DirAccess.remove_absolute(layout_path)
static func assign(game, suite: String):
	clean(suite)
	game.history_path = path_for(suite)
	game.audio_enabled = false
	game.audio_settings_path = "user://"+suite+"_audio_fixture.json"
	game.layout_path = "user://"+suite+"_layout_fixture.json"
