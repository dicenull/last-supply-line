extends Node
## Bounded original mechanical sounds on an owned bus; never changes simulation or Master.
const Observation = preload("res://scripts/audio_observation.gd")
const KINDS = ["engine","machine","shot","impact","pickup","place","connect","armor","reward","combo"]
const GAINS = {"engine":0.18,"machine":0.25,"shot":0.65,"impact":0.5,"pickup":0.3,"place":0.45,"connect":0.35,"armor":0.5,"reward":0.45,"combo":0.35}
const PRIORITIES = {"machine":0,"place":1,"connect":1,"pickup":1,"combo":2,"shot":3,"impact":3,"armor":3,"reward":4}
var game
var enabled = true
var volume = 0.35
var settings_path = "user://audio_settings.json"
var settings_error = false
var streams: Dictionary = {}
var bus_name = "Master"
var voices: Array = []
var motor: AudioStreamPlayer
var played: Dictionary = {}
var previous: Observation = Observation.new()
var pending_pickup = false
func _ready():
	enabled = enabled and DisplayServer.get_name() != "headless"
	load_settings()
	if enabled:
		bus_name = "MFV_"+str(get_instance_id())
		var bus = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(bus,bus_name)
		var limiter = AudioEffectLimiter.new()
		limiter.ceiling_db = -1
		AudioServer.add_bus_effect(bus,limiter)
	for kind in KINDS:
		var stream = load("res://audio/"+kind+".wav").duplicate()
		if kind == "engine":
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size()/2
		streams[kind] = stream
	motor = AudioStreamPlayer.new()
	if OS.has_feature("web"): motor.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	motor.stream = streams.engine
	motor.bus = bus_name
	add_child(motor)
	for i in range(8):
		var voice = AudioStreamPlayer.new()
		if OS.has_feature("web"): voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		voice.bus = bus_name
		add_child(voice)
		voices.append(voice)
	update_gain()
func read_volume(path: String):
	var f = FileAccess.open(path,FileAccess.READ)
	if f == null or f.get_length() > 1024: return null
	var parser = JSON.new()
	if parser.parse(f.get_as_text()) != OK: return null
	var data = parser.data
	if not data is Dictionary or data.get("version") != 1: return null
	var value = data.get("volume")
	if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value < 0 or value > 1: return null
	return float(value)
func load_settings():
	var value = read_volume(settings_path)
	if value == null: value = read_volume(settings_path+".bak")
	settings_error = value == null and (FileAccess.file_exists(settings_path) or FileAccess.file_exists(settings_path+".bak"))
	volume = 0.35 if value == null else value
func set_volume(value: float, persist: bool = true) -> bool:
	if not is_finite(value): return false
	volume = clampf(value,0,1)
	update_gain()
	if volume == 0: stop_all()
	if not persist: return true
	var file = FileAccess.open(settings_path+".tmp",FileAccess.WRITE)
	if file == null:
		settings_error = true
		return false
	file.store_string(JSON.stringify({"version":1,"volume":volume}))
	file.flush()
	var ok = file.get_error() == OK
	file.close()
	if ok and read_volume(settings_path) != null: ok = DirAccess.copy_absolute(settings_path,settings_path+".bak") == OK
	if ok: ok = DirAccess.rename_absolute(settings_path+".tmp",settings_path) == OK
	settings_error = not ok
	return ok
func update_gain():
	if motor != null: motor.volume_db = linear_to_db(maxf(0.00001,volume*GAINS.engine))
	for voice in voices:
		voice.volume_db = linear_to_db(maxf(0.00001,volume*GAINS.get(voice.get_meta("kind","shot"),0.5)))
func stop_all():
	pending_pickup = false
	if motor != null: motor.stop()
	for voice in voices: voice.stop()
func queue_pickup():
	# A rich site can award six items in one simulation step. Use one cue.
	if enabled and volume > 0: pending_pickup = true
func play_effect(kind: String, pitch: float = 1.0):
	if not enabled or volume <= 0 or not streams.has(kind): return
	var selected_voice = null
	for voice in voices:
		if not voice.playing:
			selected_voice = voice
			break
	# Dense factory activity must not swallow a cannon shot or armor impact.
	# Reuse the quietest-priority voice; the fixed pool never expands.
	if selected_voice == null:
		var lowest = int(PRIORITIES.get(kind,0))
		for voice in voices:
			var priority = int(PRIORITIES.get(voice.get_meta("kind","machine"),0))
			if priority < lowest:
				lowest = priority
				selected_voice = voice
	if selected_voice == null: return
	selected_voice.stream = streams[kind]
	selected_voice.pitch_scale = clampf(pitch,0.8,1.6)
	selected_voice.set_meta("kind",kind)
	selected_voice.volume_db = linear_to_db(volume*GAINS[kind])
	selected_voice.play()
	played[kind] = played.get(kind,0)+1
func sync():
	var equipment_pickup = pending_pickup
	pending_pickup = false
	var f = game.factory
	var b = game.battlefield
	var current: Observation = Observation.new(f,b)
	var changed = current.changed_source(previous)
	if changed: stop_all()
	if enabled and volume > 0 and f.running:
		if equipment_pickup: play_effect("pickup")
		if b != null and b.motion.speed > 0.05:
			motor.pitch_scale = 0.8+minf(b.motion.speed/3.3,1)*0.3
			if not motor.playing: motor.play()
		else: motor.stop()
		if not changed:
			if current.ticks > previous.ticks and not f.completed.is_empty(): play_effect("machine")
			if current.shots > previous.shots: play_effect("shot")
			if current.has_impact_since(previous): play_effect("impact")
			if current.kills > previous.kills and b != null and b.score.combo >= 2: play_effect("combo",1.0+minf(b.score.combo-2,6)*0.06)
			if b != null:
				for event in b.collection_events:
					if event.accepted > 0:
						play_effect("pickup")
						break
	elif enabled and volume > 0 and not game.menu.visible and game.expedition.phase in ["prepare","reward","route","shop","won"]:
		motor.stop()
	else: stop_all()
	previous = current

func _exit_tree():
	stop_all()
	if bus_name != "Master":
		var bus = AudioServer.get_bus_index(bus_name)
		if bus >= 0: AudioServer.remove_bus(bus)
