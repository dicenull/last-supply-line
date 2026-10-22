extends RefCounted
## A presentation snapshot. Contains no live game objects or file paths.
var title = true
var status = ""
var difficulty = "normal"
var difficulty_locked = false
var can_continue = false
var can_manage_layout = false
var can_undo = false
var can_load_layout = false
var can_retreat = true
var can_apply_blueprint = true
var roof_closed = false
var volume = 0.35
var audio_error = false
var history_error = false
var researched_count = 0
var unlocked_blueprints: Array = []
var selected_blueprints: Array = []
var entries: Array = []
