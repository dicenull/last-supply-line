extends RefCounted
## Data-only Variant payload (objects disabled), bounded size, checksum, atomic replacement.
const Factory = preload("res://scripts/factory.gd")
const RunState = preload("res://scripts/run_state.gd")
const VERSION = 1
const MAX_BYTES = 2000000
const FIELDS = ["cells","clock","elapsed","ticks","fuel","fuel_used","ammo","rate","fire_clock","shots","supplied","injected","manufactured","missed","history","moves","completed","undo_stack","reserves","collected","reserve_capacity","work_multiplier","ammo_capacity"]
const RUN_FIELDS = ["run_seed","sector","phase","hull","cleared","rewards_taken","modifiers","route_options","reward_options","current"]
const BATTLE_FIELDS = ["hull","kills","elapsed","cooldown","result","distance","speed","trail_clock","shake","recoil","shot_time","visual_shots","target_angle"]
const ENEMY_FIELDS = ["hp","max_hp","cooldown","active","role","wave","locked","aim"]
const ITEMS = ["scrap","steel","shell","coal","fuel"]
var error = ""

func fields(object, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in names: result[key] = object.get(key)
	return result.duplicate(true)

func snapshot(game) -> Dictionary:
	var data = {"version":VERSION,"factory":fields(game.factory,FIELDS),"run":fields(game.expedition,RUN_FIELDS),
		"rng_state":game.expedition.rng.state,"started":game.started,"battle_mode":game.battle_mode,
		"view":{"yaw":game.world.yaw,"pitch":game.world.pitch,"zoom":game.world.zoom,"roof":game.world.roof_closed},"battle":{}}
	if game.battlefield == null: return data
	var b = game.battlefield
	var state = fields(b,BATTLE_FIELDS)
	state.player = b.player.transform
	state.turret = b.turret.rotation.y
	state.enemies = []
	for enemy in b.enemies:
		var e: Dictionary = {}
		for key in ENEMY_FIELDS: e[key] = enemy[key]
		e.transform = enemy.node.transform
		e.pivot = enemy.pivot.rotation.y
		e.mark_position = enemy.mark.position
		e.mark_visible = enemy.mark.visible
		state.enemies.append(e)
	state.sites = []
	for site in b.resource_sites: state.sites.append(site.taken)
	state.projectiles = []
	for shot in b.projectiles:
		state.projectiles.append({"origin":shot.origin,"dir":shot.dir,"age":shot.age,"duration":shot.duration,"target":b.enemies.find(shot.target),"position":shot.node.position})
	state.bolts = []
	for bolt in b.bolts:
		var mark_index = -1
		for i in range(b.enemies.size()):
			if b.enemies[i].mark == bolt.mark: mark_index = i
		state.bolts.append({"origin":bolt.origin,"target":bolt.target,"age":bolt.age,"duration":bolt.duration,"mark":mark_index,"position":bolt.node.position})
	state.trails = []
	for tread in b.trails: state.trails.append(tread.transform)
	state.impacts = []
	for effect in b.impacts: state.impacts.append({"position":effect.node.position,"life":effect.life})
	data.battle = state
	return data

func safe_value(value, depth: int = 0) -> bool:
	if depth > 14: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME: return not (value is String and value.length() > 1024)
		TYPE_FLOAT: return is_finite(value) and absf(value) < 1e12
		TYPE_VECTOR2I: return absi(value.x) < 100000 and absi(value.y) < 100000
		TYPE_VECTOR3: return value.is_finite() and value.length() < 100000
		TYPE_TRANSFORM3D: return value.is_finite() and value.origin.length() < 100000
		TYPE_ARRAY:
			if value.size() > 2000: return false
			for entry in value:
				if not safe_value(entry,depth+1): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 256: return false
			for key in value:
				if not (key is String or key is StringName or key is Vector2i) or not safe_value(value[key],depth+1): return false
			return true
	return false

func numeric(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

func valid_route(route) -> bool:
	if not route is Dictionary or not route.has_all(["kind","seed","sector","length","scrap","coal","shells","enemy_hp","damage","attack_period","boss","opening"]): return false
	if route.get("terrain","road") not in RunState.CONDITIONS or route.get("formation","patrol") not in RunState.FORMATIONS: return false
	return route.kind in RunState.ROUTES and route.seed is int and numeric(route.sector,1,5) and numeric(route.length,80,200) and numeric(route.scrap,0,100) and numeric(route.coal,0,100) and numeric(route.shells,0,100) and numeric(route.enemy_hp,1,10) and numeric(route.damage,1,100) and numeric(route.attack_period,1,30) and route.boss is bool and route.opening is bool

func validate(data) -> bool:
	if not data is Dictionary or not safe_value(data) or not data.has_all(["version","factory","run","rng_state","started","battle_mode","view","battle"]): return invalid("validation_1")
	if data.version != VERSION or not data.rng_state is int or not data.started is bool or not data.battle_mode is bool: return invalid("validation_2")
	var f = data.factory
	var r = data.run
	if not f is Dictionary or not f.has_all(FIELDS) or not r is Dictionary or not r.has_all(RUN_FIELDS): return invalid("validation_5")
	if not numeric(r.sector,1,5) or not numeric(r.hull,0,100) or not numeric(r.cleared,0,5) or not numeric(r.rewards_taken,0,4) or not r.run_seed is int: return invalid("validation_6")
	if r.phase not in ["prepare","travel","reward","route","won","lost","retreated"] or not valid_route(r.current): return invalid("validation_7")
	if not r.modifiers is Dictionary or not r.modifiers.has_all(["work","fuel","magazine"]): return invalid("validation_8")
	if not numeric(r.modifiers.work,0.4,1) or not numeric(r.modifiers.fuel,0.4,1) or not numeric(r.modifiers.magazine,12,28): return invalid("validation_9")
	if not numeric(r.modifiers.get("reload",1.0),0.4,1) or r.modifiers.get("cargo",100) not in [100,125,150,175,200]: return invalid("new_modifiers")
	if not r.route_options is Array or not r.reward_options is Array: return invalid("validation_10")
	if r.route_options.size() != (2 if r.phase == "route" else 0): return invalid("validation_11")
	for route in r.route_options:
		if not valid_route(route): return invalid("validation_13")
	if r.reward_options.size() != (3 if r.phase == "reward" else 0): return invalid("reward_count")
	var seen_rewards = []
	for reward in r.reward_options:
		if reward not in RunState.REWARDS or reward in seen_rewards: return invalid("reward_id")
		seen_rewards.append(reward)
	if r.phase == "travel" and not data.started: return invalid("validation_15")
	for key in ["sector","hull","cleared","rewards_taken"]:
		if not r[key] is int: return invalid("run_integer")
	if r.phase == "prepare" and data.started: return invalid("phase")
	if r.phase in ["travel","reward","route","won","lost"] and not data.started: return invalid("phase")
	for key in ["ticks","ammo","rate","shots","supplied","injected","manufactured","missed","ammo_capacity","reserve_capacity"]:
		if not f[key] is int: return invalid("factory_integer")
	if not f.cells is Dictionary or f.cells.size() > 112 or not f.reserves is Dictionary or not f.collected is Dictionary: return invalid("validation_16")
	for raw in ["scrap","coal"]:
		if not numeric(f.reserves.get(raw),0,f.reserve_capacity) or not numeric(f.collected.get(raw),0,1000000): return invalid("validation_18")
	if not numeric(f.work_multiplier,0.4,1) or f.ammo_capacity != r.modifiers.magazine or not is_equal_approx(float(f.work_multiplier),float(r.modifiers.work)): return invalid("validation_19")
	if not numeric(f.ammo,0,f.ammo_capacity) or not numeric(f.fuel,0,12.001) or f.rate not in [30,60,90] or f.reserve_capacity != r.modifiers.get("cargo",100): return invalid("validation_20")
	for key in ["clock","elapsed","ticks","fuel_used","fire_clock","shots","supplied","injected","manufactured","missed"]:
		if not numeric(f[key],0,1e9): return invalid("validation_22")
	var rows: Array = []
	for pos in f.cells:
		var c = f.cells[pos]
		if not pos is Vector2i or not c is Dictionary or not c.has_all(["kind","dir","items","work","turn","incoming","made","busy"]): return invalid("validation_26")
		if not c.items is Array or not numeric(c.dir,0,3) or not numeric(c.work,0,8) or not numeric(c.turn,0,1) or not numeric(c.incoming,0,3) or not numeric(c.made,0,1e9) or not numeric(c.busy,0,1e9): return invalid("validation_27")
		for key in ["dir","work","turn","incoming","made","busy"]:
			if not c[key] is int: return invalid("cell_integer")
		if c.items.size() > (8 if c.kind == "depot" else 1): return invalid("validation_28")
		for item in c.items:
			if item not in ITEMS: return invalid("validation_30")
		if c.work > 0 and (not Factory.RECIPES.has(c.kind) or c.items.size() != 1): return invalid("validation_31")
		if Factory.PORTS.has(pos):
			if Factory.PORTS[pos] != c.kind: return invalid("validation_33")
		else: rows.append([pos.x,pos.y,c.kind,c.dir])
	for pos in Factory.PORTS:
		if not f.cells.has(pos): return invalid("validation_36")
	var candidate = Factory.new()
	if not candidate.restore(rows): return invalid("validation_38")
	for key in ["history","moves","completed","undo_stack"]:
		if not f[key] is Array: return invalid("validation_40")
	for move in f.moves:
		if not move is Dictionary or not move.has_all(["from","to","item"]) or not move.from is Vector2i or not move.to is Vector2i or move.item not in ITEMS: return invalid("validation_42")
	for h in f.history:
		if not h is Array or h.size() != 2 or not numeric(h[0],0,1e9) or not h[1] is bool: return invalid("validation_44")
	for rows_before in f.undo_stack:
		if not rows_before is Array or not candidate.restore(rows_before): return invalid("validation_46")
	var v = data.view
	if not v is Dictionary or not v.has_all(["yaw","pitch","zoom","roof"]) or not numeric(v.yaw,-100000,100000) or not numeric(v.pitch,0.5,1.5) or not numeric(v.zoom,8,50) or not v.roof is bool: return invalid("validation_48")
	return validate_battle(data.battle,data.started,r)

func validate_battle(b, started: bool, run: Dictionary) -> bool:
	if not b is Dictionary: return invalid("validation_52")
	if b.is_empty(): return not started and run.phase == "prepare"
	if not b.has_all(BATTLE_FIELDS) or not b.has_all(["player","turret","enemies","sites","projectiles","bolts","trails","impacts"]): return invalid("validation_54")
	for key in BATTLE_FIELDS:
		if not numeric(b[key],-100000,1e9): return invalid("validation_56")
	if b.hull < 0 or b.hull > 100 or b.kills < 0 or b.kills > 6 or b.result not in [-1,0,1]: return invalid("validation_57")
	if not b.player is Transform3D or not numeric(b.turret,-100000,100000): return invalid("validation_58")
	if not b.enemies is Array or b.enemies.size() != 6 or not b.sites is Array or b.sites.size() != 3: return invalid("validation_59")
	var dead = 0
	for i in range(6):
		var e = b.enemies[i]
		if not e is Dictionary or not e.has_all(ENEMY_FIELDS) or not e.has_all(["transform","pivot","mark_position","mark_visible"]): return invalid("validation_63")
		if not e.hp is int: return invalid("enemy_integer")
		var hp = RunState.enemy_health(run.current,i)
		if e.max_hp != hp or not numeric(e.hp,0,hp) or not numeric(e.cooldown,-1,100) or e.role != RunState.enemy_role(run.current,i) or e.wave != int(i/2): return invalid("validation_65")
		if not e.transform is Transform3D or not e.aim is Vector3 or not e.mark_position is Vector3 or not numeric(e.pivot,-100000,100000): return invalid("validation_66")
		if not e.active is bool or not e.locked is bool or not e.mark_visible is bool: return invalid("validation_67")
		if e.hp == 0: dead += 1
	if dead != b.kills: return invalid("validation_69")
	for taken in b.sites:
		if not taken is bool: return invalid("validation_71")
	for key in ["projectiles","bolts"]:
		if not b[key] is Array or b[key].size() > 128: return invalid("validation_73")
		for shot in b[key]:
			if not shot is Dictionary or not shot.has_all(["origin","target","age","duration","position"]): return invalid("validation_75")
			if not shot.origin is Vector3 or not shot.position is Vector3 or not numeric(shot.age,0,1000) or not numeric(shot.duration,0.001,1000) or shot.age > shot.duration: return invalid("validation_76")
			if key == "projectiles":
				if not shot.has("dir") or not shot.dir is Vector3 or not shot.target is int or shot.target < 0 or shot.target >= 6: return invalid("validation_78")
			elif not shot.target is Vector3 or not shot.has("mark") or not shot.mark is int or shot.mark < 0 or shot.mark >= 6: return invalid("validation_79")
	if not b.trails is Array or b.trails.size() > 90 or not b.impacts is Array or b.impacts.size() > 128: return invalid("validation_80")
	for trail in b.trails:
		if not trail is Transform3D: return invalid("validation_82")
	for impact in b.impacts:
		if not impact is Dictionary or not impact.has_all(["position","life"]) or not impact.position is Vector3 or not numeric(impact.life,0,0.4): return invalid("validation_84")
	return true

func write_file(path: String, data: Dictionary) -> bool:
	error = ""
	if not validate(data):
		error = "invalid_state"
		return false
	var bytes = var_to_bytes(data)
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var digest = hash.finish()
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		error = "write_failed"
		return false
	file.store_buffer("MFV1".to_ascii_buffer())
	file.store_buffer(digest)
	file.store_buffer(bytes)
	file.flush()
	var status = file.get_error()
	file.close()
	if status != OK:
		error = "write_failed"
		return false
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(path,path+".bak") != OK:
			error = "backup_failed"
			return false
	if DirAccess.rename_absolute(path+".tmp",path) != OK:
		error = "replace_failed"
		return false
	return true

func read_file(path: String) -> Dictionary:
	error = ""
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null:
		error = "missing"
		return {}
	if file.get_length() < 36 or file.get_length() > MAX_BYTES or file.get_buffer(4).get_string_from_ascii() != "MFV1":
		error = "corrupt"
		return {}
	var digest = file.get_buffer(32)
	var bytes = file.get_buffer(file.get_length()-36)
	file.close()
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish() != digest:
		error = "checksum"
		return {}
	var data = bytes_to_var(bytes)
	if not validate(data):
		error = "invalid_state"
		return {}
	return data

func apply(game, data: Dictionary) -> bool:
	if not validate(data):
		error = "invalid_state"
		return false
	game.sound.stop_all()
	var restored_factory = Factory.new()
	for key in FIELDS: restored_factory.set(key,data.factory[key].duplicate(true) if data.factory[key] is Array or data.factory[key] is Dictionary else data.factory[key])
	restored_factory.finite_resources = true
	restored_factory.auto_fire = false
	restored_factory.running = false
	var restored_run = RunState.new(data.run.run_seed)
	for key in RUN_FIELDS: restored_run.set(key,data.run[key].duplicate(true) if data.run[key] is Array or data.run[key] is Dictionary else data.run[key])
	restored_run.rng.state = data.rng_state
	if game.battlefield != null: game.battle_container.queue_free()
	game.battlefield = null
	game.battle_container = null
	game.factory = restored_factory
	game.expedition = restored_run
	game.started = data.started
	game.battle_mode = data.battle_mode
	game.world.playback_only = data.started
	game.world.rendered_layout = ""
	game.world.old_shots = restored_factory.shots
	game.world.pending_shots = 0
	for key in ["yaw","pitch","zoom"]: game.world.set(key,data.view[key])
	if game.world.roof_closed != data.view.roof: game.world.toggle_roof()
	game.world.update_camera()
	if not data.battle.is_empty():
		game.ensure_battle()
		apply_battle(game.battlefield,data.battle)
	game.refresh_view()
	game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0)
	game.queue_redraw()
	return true

func apply_battle(b, state: Dictionary):
	for key in BATTLE_FIELDS: b.set(key,state[key])
	b.player.transform = state.player
	b.turret.rotation.y = state.turret
	b.barrel.position.x = b.BARREL_REST-b.recoil
	b.muzzle.visible = b.shot_time > 0
	for i in range(6):
		var enemy = b.enemies[i]
		var e = state.enemies[i]
		for key in ENEMY_FIELDS: enemy[key] = e[key]
		enemy.node.transform = e.transform
		enemy.node.visible = e.active
		enemy.pivot.rotation.y = e.pivot
		enemy.mark.position = e.mark_position
		enemy.mark.visible = e.mark_visible
		for pip in range(enemy.health.size()): enemy.health[pip].visible = pip < enemy.hp
	for i in range(b.resource_sites.size()):
		b.resource_sites[i].taken = state.sites[i]
		b.resource_sites[i].node.visible = not state.sites[i]
	for shot in state.projectiles:
		var node = Node3D.new()
		b.add_child(node)
		node.position = shot.position
		b.beam(node,Vector3.ZERO,-shot.dir*1.8,0.085,"fire")
		b.projectiles.append({"node":node,"origin":shot.origin,"dir":shot.dir,"age":shot.age,"duration":shot.duration,"target":b.enemies[shot.target]})
	for bolt in state.bolts:
		var node = Node3D.new()
		b.add_child(node)
		node.position = bolt.position
		b.beam(node,Vector3.ZERO,(bolt.origin-bolt.target).normalized()*1.5,0.11,"fire")
		b.bolts.append({"node":node,"origin":bolt.origin,"target":bolt.target,"age":bolt.age,"duration":bolt.duration,"mark":b.enemies[bolt.mark].mark})
	for transform in state.trails:
		var tread = b.box(b,Vector3.ZERO,Vector3(0.65,0.025,1),"dark")
		tread.transform = transform
		b.trails.append(tread)
	for effect in state.impacts:
		b.impact(effect.position)
		b.impacts.back().life = effect.life
	var target = b.nearest_enemy()
	b.target_marker.visible = target != null and b.result == 0
	if target != null: b.target_marker.position = target.node.position+Vector3(0,0.12,0)
	b.update_camera()

func invalid(reason: String) -> bool:
	error = reason
	return false
