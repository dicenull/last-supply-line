extends RefCounted
## Keep tests from reading or granting unlocks in the player's profile.
static func path_for(suite: String) -> String:
	return "user://"+suite+"_profile_fixture.json"
static func clean(suite: String):
	for suffix in ["",".bak",".tmp"]:
		var path = path_for(suite)+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
static func assign(game, suite: String):
	clean(suite)
	game.history_path = path_for(suite)
