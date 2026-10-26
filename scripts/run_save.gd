extends RefCounted
## Data-only Variant payload (objects disabled), bounded size, checksum, atomic replacement.
const Factory = preload("res://scripts/factory.gd")
const RunState = preload("res://scripts/run_state.gd")
const SnapshotSchema = preload("res://scripts/run_snapshot_schema.gd")
const VERSION = SnapshotSchema.VERSION
const MAX_BYTES = 2000000
const FIELDS = SnapshotSchema.FIELDS
const RUN_FIELDS = SnapshotSchema.RUN_FIELDS
const CRAFT_FIELDS = SnapshotSchema.CRAFT_FIELDS
const BATTLE_FIELDS = SnapshotSchema.BATTLE_FIELDS
const BATTLE_VIEW_FIELDS = SnapshotSchema.BATTLE_VIEW_FIELDS
const ENEMY_FIELDS = SnapshotSchema.ENEMY_FIELDS
var error = ""

func fields(object, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in names: result[key] = object.get(key)
	return result.duplicate(true)

func snapshot(game) -> Dictionary:
	var data = {"version":VERSION,"factory":fields(game.factory,FIELDS),"run":fields(game.expedition,RUN_FIELDS),
		"rng_state":game.expedition.rng.state,"started":game.started,"battle_mode":game.battle_mode,
		"view":{"yaw":game.world.yaw,"pitch":game.world.pitch,"zoom":game.world.zoom,"roof":game.world.roof_closed},"battle":{}}
	data.run.merge(fields(game.expedition,CRAFT_FIELDS))
	data.factory.wrecks = game.factory.wrecks.duplicate()
	data.factory.layout_version = game.factory.layout_version
	data.factory.equipment_mounts = game.factory.equipment_mounts.duplicate()
	data.factory.equipment_rotations = game.factory.equipment_rotations.duplicate()
	data.factory.wreck_directions = game.factory.wreck_directions.duplicate()
	data.run.difficulty = game.expedition.difficulty
	data.run.item_mode = game.expedition.item_mode
	data.run.empty_part_slots = game.expedition.empty_part_slots.duplicate()
	data.view.camera_offset = game.world.camera_offset
	data.run.gear_items = game.expedition.gear_items.duplicate(true)
	data.run.next_item_uid = game.expedition.next_item_uid
	if game.battlefield == null: return data
	var b = game.battlefield
	var state = fields(b,BATTLE_VIEW_FIELDS)
	state.merge(b.score.snapshot())
	state.merge(b.progress.snapshot())
	state.merge(b.motion.snapshot())
	state.player = b.player.transform
	state.turret = b.turret.rotation.y
	state.auxiliary = []
	for gun in b.auxiliary_guns:
		state.auxiliary.append({"id":gun.id,"angle":gun.pivot.rotation.y,"cooldown":gun.cooldown,"flash":gun.flash,"recoil":gun.recoil})
	state.enemies = []
	for enemy in b.enemies:
		var e: Dictionary = {}
		for key in ENEMY_FIELDS: e[key] = enemy[key]
		e.transform = enemy.node.transform
		e.pivot = enemy.pivot.rotation.y
		e.mark_position = enemy.mark.position
		e.mark_visible = enemy.mark.visible
		state.enemies.append(e)
	state.ground_items = b.ground_item_snapshot()
	state.sites = []
	for site in b.resource_sites: state.sites.append(site.taken)
	state.mines = []
	for mine in b.obstacles.mines: state.mines.append(mine.spent)
	state.projectiles = []
	for shot in b.projectiles:
		state.projectiles.append({"origin":shot.origin,"dir":shot.dir,"age":shot.age,"duration":shot.duration,"target":b.enemies.find(shot.target),"position":shot.node.position,"splash":shot.get("splash",0.0),"style":shot.get("style","heavy"),"chain":shot.get("chain",0)})
	state.bolts = []
	for bolt in b.bolts:
		var mark_index = -1
		for i in range(b.enemies.size()):
			if b.enemies[i].mark == bolt.mark: mark_index = i
		state.bolts.append({"origin":bolt.origin,"target":bolt.target,"age":bolt.age,"duration":bolt.duration,"mark":mark_index,"position":bolt.node.position,"radius":bolt.get("radius",6.0),"damage":bolt.get("damage",b.hit_damage()),"style":bolt.get("style","heavy")})
	state.trails = []
	for tread in b.trails: state.trails.append(tread.transform)
	state.impacts = []
	for effect in b.impacts: state.impacts.append({"position":effect.node.position,"life":effect.life,"style":effect.get("style","heavy")})
	data.battle = state
	return data

func validate(data) -> bool:
	var schema = SnapshotSchema.new()
	var valid = schema.validate(data)
	error = schema.error
	return valid

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
	if game.loot_feed != null: game.loot_feed.clear()
	if game.world.feedback != null: game.world.feedback.clear()
	var restored_factory = Factory.new(data.factory.get("layout_version",1))
	restored_factory.equipment_mounts = data.factory.get("equipment_mounts",{}).duplicate()
	restored_factory.equipment_rotations = data.factory.get("equipment_rotations",{}).duplicate()
	restored_factory.loadout_locked = data.started
	for key in FIELDS: restored_factory.set(key,data.factory[key].duplicate(true) if data.factory[key] is Array or data.factory[key] is Dictionary else data.factory[key])
	restored_factory.wrecks = data.factory.get("wrecks",{}).duplicate()
	for pos in restored_factory.wrecks:
		restored_factory.wreck_directions[pos] = data.factory.get("wreck_directions",{}).get(pos,0)
	if data.factory.has("inventory"):
		restored_factory.inventory = data.factory.inventory.duplicate()
		if not restored_factory.inventory.has("armor_block"): restored_factory.inventory.armor_block = 0
	else:
		# Preserve legacy layouts and undo history without granting every old cap.
		var layouts: Array = [restored_factory.layout()]+restored_factory.undo_stack
		for rows in layouts:
			var counts = {}
			for row in rows:
				var kind = row[2]
				if not Factory.LIMITS.has(kind): continue
				counts[kind] = counts.get(kind,0)+1
				restored_factory.inventory[kind] = maxi(restored_factory.inventory[kind],counts[kind])
	restored_factory.unlocked_blocks = RunState.Content.STARTING_BLOCKS.keys()+game.history.researched_blocks
	restored_factory.finite_resources = true
	restored_factory.auto_fire = false
	restored_factory.running = false
	var restored_run = RunState.new(data.run.run_seed,data.run.get("difficulty","normal"))
	for key in RUN_FIELDS: restored_run.set(key,data.run[key].duplicate(true) if data.run[key] is Array or data.run[key] is Dictionary else data.run[key])
	for key in CRAFT_FIELDS: restored_run.set(key,data.run.get(key,[]).duplicate())
	for id in restored_run.equipment:
		if not Factory.AUXILIARY.has(id): continue
		if data.version == 1: restored_factory.install_auxiliary(id)
		else: restored_factory.auxiliary_ids.append(id)
	restored_run.item_mode = data.run.get("item_mode",false)
	restored_run.empty_part_slots = data.run.get("empty_part_slots",[]).duplicate()
	restored_run.gear_items = data.run.get("gear_items",[]).duplicate(true)
	restored_run.next_item_uid = data.run.get("next_item_uid",1)
	restored_run.rng.state = data.rng_state
	game.release_battle()
	game.factory = restored_factory
	game.expedition = restored_run
	game.started = data.started
	game.clear_movement()
	restored_factory.layout_locked = data.run.phase in ["lost","retreated","won"]
	restored_factory.combat_editing = data.run.phase == "travel" or (data.run.phase == "prepare" and data.run.sector > 1)
	game.battle_mode = data.battle_mode
	game.world.playback_only = data.started
	game.world.rendered_layout = ""
	game.world.old_shots = restored_factory.shots
	game.world.pending_shots = 0
	game.world.set_layout_version(restored_factory.layout_version)
	game.clear_equipment_selection()
	game.world.configure_equipment(restored_run.equipment,restored_factory.auxiliary_positions(),restored_factory.equipment_mounts,restored_factory.equipment_rotations)
	game.world.configure_vehicle_parts(preload("res://scripts/equipment_inventory.gd").vehicle_parts(restored_run),restored_run.empty_part_slots)
	game.world.camera_offset = data.view.get("camera_offset",Vector3.ZERO)
	for key in ["yaw","pitch","zoom"]: game.world.set(key,data.view[key])
	if game.world.roof_closed != data.view.roof: game.world.toggle_roof()
	game.world.update_camera()
	if not data.battle.is_empty():
		game.ensure_battle()
		apply_battle(game.battlefield,data.battle)
	if restored_run.phase == "craft":
		restored_run.finish_crafting({},restored_factory.inventory,game.has_mount_space())
	elif data.version < 5 and restored_run.phase == "reward":
		restored_run.offer_rewards({},game.has_mount_space())
	game.refresh_view()
	game.world.sync(game.factory,Vector2i(-1,-1),"belt",0,0)
	game.queue_redraw()
	return true

func apply_battle(b, state: Dictionary):
	for key in BATTLE_VIEW_FIELDS: b.set(key,state[key])
	b.score.restore(state)
	b.progress.restore(state)
	b.motion.restore(state)
	b.player.transform = state.player
	b.restore_ground_items(state.get("ground_items",[]))
	if b.progress.has_won():
		for i in range(b.goals.size()):
			if b.goals[i].contains_position(b.player.position): b.progress.arrived_destination = i
	b.turret.rotation.y = state.turret
	b.barrel.position.x = b.BARREL_REST-b.recoil
	b.muzzle.visible = b.shot_time > 0
	for i in range(b.auxiliary_guns.size()):
		var gun = b.auxiliary_guns[i]
		var saved = state.auxiliary[i]
		for key in ["cooldown","flash","recoil"]: gun[key] = saved[key]
		gun.pivot.rotation.y = b.clamp_gun_angle(gun,saved.angle)
		gun.barrel.position.x = 0.6-gun.recoil
		gun.muzzle.visible = gun.flash > 0
	for i in range(b.enemies.size()):
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
		b.resource_sites[i].node.set_taken(state.sites[i])
	for i in range(b.obstacles.mines.size()):
		b.obstacles.set_spent(i,state.mines[i])
	for shot in state.projectiles:
		var node = Node3D.new()
		b.add_child(node)
		node.position = shot.position
		b.build_shell(node,shot.dir,shot.get("style","heavy"))
		b.projectiles.append({"node":node,"origin":shot.origin,"dir":shot.dir,"age":shot.age,"duration":shot.duration,"target":b.enemies[shot.target],"splash":shot.get("splash",0.0),"style":shot.get("style","heavy"),"chain":shot.get("chain",0)})
	for bolt in state.bolts:
		var node = Node3D.new()
		b.add_child(node)
		node.position = bolt.position
		b.build_shell(node,(bolt.target-bolt.origin).normalized(),bolt.get("style","heavy"))
		b.bolts.append({"node":node,"origin":bolt.origin,"target":bolt.target,"age":bolt.age,"duration":bolt.duration,"mark":b.enemies[bolt.mark].mark,"radius":bolt.get("radius",6.0),"damage":bolt.get("damage",b.hit_damage()),"style":bolt.get("style","heavy")})
	for transform in state.trails:
		var tread = b.box(b,Vector3.ZERO,Vector3(0.65,0.025,1),"dark")
		tread.transform = transform
		b.trails.append(tread)
	for effect in state.impacts:
		b.impact(effect.position,effect.get("style","heavy"),false)
		b.impacts.back().life = effect.life
		b.update_impact(b.impacts.back())
	b.update_camera()
	var target = b.nearest_enemy()
	b.target_marker.visible = target != null and not b.progress.is_finished()
	if target != null: b.target_marker.position = target.node.position+Vector3(0,0.12,0)
