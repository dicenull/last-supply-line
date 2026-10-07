extends Node
## Bounded original mechanical sounds on an owned bus; never changes simulation or Master.
const KINDS = ["engine","machine","shot","impact","pickup"]
const GAINS = {"engine":0.18,"machine":0.25,"shot":0.65,"impact":0.5,"pickup":0.3}
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
var last_factory = 0
var last_battle = 0
var last_ticks = 0
var last_shots = 0
var last_kills = 0
var last_hull = 100
var last_impacts = 0
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
	motor.stream = streams.engine
	motor.bus = bus_name
	add_child(motor)
	for i in range(8):
		var voice = AudioStreamPlayer.new()
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
	if motor != null: motor.stop()
	for voice in voices: voice.stop()
func play_effect(kind: String):
	if not enabled or volume <= 0 or not streams.has(kind): return
	for voice in voices:
		if voice.playing: continue
		voice.stream = streams[kind]
		voice.set_meta("kind",kind)
		voice.volume_db = linear_to_db(volume*GAINS[kind])
		voice.play()
		played[kind] = played.get(kind,0)+1
		return
func sync():
	var f = game.factory
	var b = game.battlefield
	var factory_id = f.get_instance_id()
	var battle_id = b.get_instance_id() if b != null else 0
	var changed = factory_id != last_factory or battle_id != last_battle or f.ticks < last_ticks or f.shots < last_shots
	var kills = b.kills if b != null else 0
	var hull = b.hull if b != null else 100
	if changed: stop_all()
	if enabled and volume > 0 and f.running:
		if b != null and b.speed > 0.05:
			motor.pitch_scale = 0.8+minf(b.speed/3.3,1)*0.3
			if not motor.playing: motor.play()
		else: motor.stop()
		if not changed:
			if f.ticks > last_ticks and not f.completed.is_empty(): play_effect("machine")
			if f.shots > last_shots: play_effect("shot")
			if kills > last_kills or hull < last_hull or (b != null and b.impact_serial > last_impacts): play_effect("impact")
			if b != null:
				for event in b.collection_events:
					if event.accepted > 0:
						play_effect("pickup")
						break
	else: stop_all()
	last_factory = factory_id
	last_battle = battle_id
	last_ticks = f.ticks
	last_shots = f.shots
	last_kills = kills
	last_hull = hull
	last_impacts = b.impact_serial if b != null else 0

func _exit_tree():
	stop_all()
	if bus_name != "Master":
		var bus = AudioServer.get_bus_index(bus_name)
		if bus >= 0: AudioServer.remove_bus(bus)
