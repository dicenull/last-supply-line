extends RefCounted
## Explicit waypoint pilot for simulation regression tests. Real key input
## and no-input stopping are covered separately by phase_movement_test.gd.
static func drive(game, delta: float, destination: int = 0):
	if game.battlefield != null and game.expedition.phase == "travel" and game.factory.running and not game.menu.visible:
		pilot(game.battlefield,destination)
	game._process(delta)

static func claim_reward(game, index: int):
	game.choose_run_option(index)
	if game.expedition.phase == "shop": game.leave_shop()

static func preferred_destination(battle, kind: String) -> int:
	if battle.field_course != null:
		for i in range(battle.field_course.destinations.size()):
			if battle.field_course.destinations[i].kind == kind: return i
	return 0

static func pilot(battle, destination: int = 0):
	var points = battle.obstacles.navigation_points(battle.route_length)
	if battle.field_course != null:
		points = battle.field_course.navigation_points(destination)
		# Approach the loading areas physically; X progress no longer grants cargo.
		for site in battle.resource_sites:
			var center: Vector3 = battle.field_course.center_at(site.distance)
			var approach = site.node.position.move_toward(center,site.node.COLLECTION_RADIUS-1.0)
			var index = 0
			while index < points.size() and points[index].x < approach.x: index += 1
			points.insert(index,approach)
	var key = "pilot_index_"+str(destination)
	var index = int(battle.get_meta(key,0)) if battle.field_course != null else 0
	while index < points.size()-1:
		var reached = battle.player.position.distance_to(points[index]) < 0.6
		var passed = battle.player.position.x > points[index].x+0.4
		var corner = points[index].x == points[index+1].x and battle.player.position.x >= points[index].x-0.4
		if not reached and not passed and not corner: break
		index += 1
	if battle.field_course != null: battle.set_meta(key,index)
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
