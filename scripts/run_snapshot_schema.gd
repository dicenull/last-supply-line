extends RefCounted
## Data-only checkpoint contract. No file IO, scene creation, or live-state mutation.
const Factory = preload("res://scripts/factory.gd")
const RunState = preload("res://scripts/run_state.gd")
const VERSION = 11
const FIELDS = ["cells","clock","elapsed","ticks","fuel","fuel_used","ammo","rate","fire_clock","shots","supplied","injected","manufactured","missed","history","moves","completed","undo_stack","reserves","collected","reserve_capacity","work_multiplier","ammo_capacity"]
const RUN_FIELDS = ["run_seed","sector","phase","hull","cleared","rewards_taken","modifiers","route_options","reward_options","current"]
const CRAFT_FIELDS = ["recipes","equipment","stage_recipes"]
const BATTLE_FIELDS = ["hull","kills","elapsed","cooldown","result","distance","speed","trail_clock","shake","recoil","shot_time","visual_shots","target_angle"]
const ENEMY_FIELDS = ["hp","max_hp","cooldown","active","role","wave","locked","aim"]
const ITEMS = ["scrap","steel","shell","coal","fuel"]
var error = ""

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
	if not route.get("combat_version",1) is int or route.get("combat_version",1) not in [1,2,3]: return false
	if route.get("combat_version",1) == 3 or route.has("enemies"):
		if route.get("difficulty","") not in RunState.Content.DIFFICULTIES or not route.get("enemies") is Array or route.enemies.size() < 6 or route.enemies.size() > 36: return false
		for role in route.enemies:
			if not role is int or role < 0 or role >= RunState.Content.ENEMIES.size(): return false
		if route.get("wave_size",0) not in [2,3,4,5] or not numeric(route.get("wave_delay"),10,40) or not numeric(route.get("warning_scale"),0.5,2): return false
	if not route.get("obstacles_version",0) is int or route.get("obstacles_version",0) not in [0,1]: return false
	if not route.get("field_version",0) is int or route.get("field_version",0) not in [0,1]: return false
	if not route.get("landscape_version",0) is int or route.get("landscape_version",0) not in [0,1]: return false
	if route.get("field_version",0) == 1:
		if not route.get("destination_count") is int or route.destination_count not in [2,3]: return false
		if not route.get("destination_index") is int or not numeric(route.destination_index,-1,route.destination_count-1): return false
	if not route.get("encounters_version",0) is int or route.get("encounters_version",0) not in [0,1]: return false
	if route.get("encounters_version",0) == 1:
		if route.get("encounter") not in RunState.Services.ENCOUNTERS or route.get("field_version",0) != 1: return false
	if not route.get("shop_done",false) is bool: return false
	if route.has("shop_offers") or route.has("shop_purchased"):
		var offers = route.get("shop_offers")
		var purchased = route.get("shop_purchased")
		if not offers is Array or offers.size() not in [2,3] or not purchased is Array or purchased.size() != offers.size(): return false
		if [offers[0],offers[1]] not in [["coal","shell"],["gear:economizer","gear:armor"]]: return false
		if offers.size() == 3 and (not offers[2] is String or not offers[2].begins_with("gear:") or offers[2].trim_prefix("gear:") not in RunState.EQUIPMENT): return false
		for taken in purchased:
			if not taken is bool: return false
	return route.kind in RunState.ROUTES and route.seed is int and numeric(route.sector,1,5) and numeric(route.length,80,200) and numeric(route.scrap,0,200) and numeric(route.coal,0,200) and numeric(route.shells,0,100) and numeric(route.enemy_hp,1,10) and numeric(route.damage,1,100) and numeric(route.attack_period,1,30) and route.boss is bool and route.opening is bool

func validate(data) -> bool:
	if not data is Dictionary or not safe_value(data) or not data.has_all(["version","factory","run","rng_state","started","battle_mode","view","battle"]): return invalid("validation_1")
	if data.version not in [1,2,3,4,5,6,7,8,9,10,VERSION] or not data.rng_state is int or not data.started is bool or not data.battle_mode is bool: return invalid("validation_2")
	var f = data.factory
	var r = data.run
	if not f is Dictionary or not f.has_all(FIELDS) or not r is Dictionary or not r.has_all(RUN_FIELDS): return invalid("validation_5")
	for key in CRAFT_FIELDS:
		var ids = r.get(key,[])
		if not ids is Array or ids.size() > RunState.EQUIPMENT.size(): return invalid("craft_ids")
		var seen = []
		for id in ids:
			if not id is String or not RunState.EQUIPMENT.has(id) or id in seen: return invalid("craft_id")
			if not r.get("item_mode",false) and id not in RunState.Content.BASE_EQUIPMENT: return invalid("legacy_equipment_id")
			if key != "recipes" and id not in r.get("recipes",[]): return invalid("craft_locked")
			seen.append(id)
	if data.version >= 10 and (not r.has_all(["item_mode","gear_items","next_item_uid"]) or not f.has("equipment_mounts")): return invalid("missing_item_state")
	var layout_version = f.get("layout_version",1)
	if not layout_version is int or layout_version not in [1,2] or (data.version < 10 and layout_version != 1): return invalid("factory_layout")
	if data.version >= 10 and not f.has("layout_version"): return invalid("missing_factory_layout")
	var candidate = Factory.new(layout_version)
	var mounts = f.get("equipment_mounts",{})
	if not mounts is Dictionary or mounts.size() > Factory.Gear.DEFINITIONS.size() or (layout_version == 1 and not mounts.is_empty()): return invalid("equipment_mounts")
	for id in mounts:
		if id not in r.get("equipment",[]) or not mounts[id] is Vector2i or not candidate.can_place_equipment(id,mounts[id]): return invalid("equipment_footprint")
		candidate.equipment_mounts[id] = mounts[id]
	var item_mode = r.get("item_mode",false)
	var items = r.get("gear_items",[])
	var next_uid = r.get("next_item_uid",1)
	if not item_mode is bool or not items is Array or items.size() > 2000 or not next_uid is int or next_uid < 1: return invalid("item_inventory")
	if item_mode != (layout_version == 2) or (not item_mode and not items.is_empty()): return invalid("item_layout")
	var seen_uids = []
	var installed = {}
	for item in items:
		if not Factory.Gear.valid(item) or not item.get("uid") is int or item.uid < 1 or item.uid >= next_uid or item.uid in seen_uids or not item.get("position") is Vector2i: return invalid("item_instance")
		var rounds = item.get("ammo",0)
		if not rounds is int or rounds < 0 or rounds > 28 or (rounds > 0 and (item.kind not in Factory.AUXILIARY or item.position != Vector2i(-1,-1))): return invalid("stored_equipment_ammo")
		seen_uids.append(item.uid)
		if item.kind not in r.get("recipes",[]): return invalid("item_recipe")
		if item.position == Vector2i(-1,-1): continue
		if installed.has(item.kind) or mounts.get(item.kind,Vector2i(-1,-1)) != item.position: return invalid("item_installation")
		installed[item.kind] = item.position
	if item_mode and (installed != mounts or mounts.size() != r.get("equipment",[]).size()): return invalid("item_mounts")
	if not numeric(r.sector,1,5) or not numeric(r.hull,0,100) or not numeric(r.cleared,0,5) or not numeric(r.rewards_taken,0,5) or not r.run_seed is int: return invalid("validation_6")
	if data.version == 4 and not f.has("inventory"): return invalid("missing_inventory")
	if f.has("inventory"):
		if not f.inventory is Dictionary or f.inventory.size() not in [Factory.LIMITS.size()-1,Factory.LIMITS.size()]: return invalid("inventory")
		for kind in Factory.LIMITS:
			if kind == "armor_block" and not f.inventory.has(kind): continue
			if not f.inventory.get(kind) is int or not numeric(f.inventory[kind],0,Factory.LIMITS[kind]): return invalid("inventory_count")
		for kind in f.inventory:
			if not Factory.LIMITS.has(kind): return invalid("inventory_kind")
	if r.get("difficulty","normal") not in RunState.Content.DIFFICULTIES: return invalid("difficulty")
	if r.phase not in ["prepare","travel","craft","reward","route","shop","won","lost","retreated"] or not valid_route(r.current): return invalid("validation_7")
	if r.phase == "shop":
		if r.cleared != r.sector or not r.current.has("shop_offers") or r.current.get("shop_done",false) or r.current.get("encounters_version",0) != 1 or r.current.get("destination_index",-1) < 0: return invalid("shop_state")
		if RunState.FieldCourse.new(r.current).destinations[r.current.destination_index].get("encounter","") != "shop": return invalid("shop_destination")
	if r.phase == "craft" and r.cleared != r.sector: return invalid("craft_clear")
	if not r.modifiers is Dictionary or not r.modifiers.has_all(["work","fuel","magazine"]): return invalid("validation_8")
	if not numeric(r.modifiers.work,0.4,1) or not numeric(r.modifiers.fuel,0.4,1) or not numeric(r.modifiers.magazine,12,28): return invalid("validation_9")
	if not numeric(r.modifiers.get("reload",1.0),0.4,1) or r.modifiers.get("cargo",100) not in [100,125,150,175,200]: return invalid("new_modifiers")
	if not numeric(r.modifiers.get("craft",1.0),0.4,1) or not numeric(r.modifiers.get("range",0.0),0,16) or not numeric(r.modifiers.get("salvage",0),0,4) or not numeric(r.modifiers.get("damage",1.0),0.5,1) or not numeric(r.modifiers.get("speed",1.0),1,1.5) or r.modifiers.get("routes",2) not in [2,3]: return invalid("expanded_modifiers")
	if not r.route_options is Array or not r.reward_options is Array: return invalid("validation_10")
	if r.route_options.size() != (r.modifiers.get("routes",2) if r.phase == "route" else 0): return invalid("validation_11")
	for route in r.route_options:
		if not valid_route(route): return invalid("validation_13")
	if (r.phase == "reward" and (r.reward_options.is_empty() or r.reward_options.size() > 3)) or (r.phase != "reward" and not r.reward_options.is_empty()): return invalid("reward_count")
	var seen_rewards = []
	for reward in r.reward_options:
		if not reward is String or reward in seen_rewards: return invalid("reward_id")
		if reward.begins_with("block:"):
			if reward.trim_prefix("block:") not in Factory.LIMITS: return invalid("reward_block")
		elif reward.begins_with("gear:"):
			var gear = reward.trim_prefix("gear:")
			if gear not in RunState.EQUIPMENT or (not item_mode and gear in r.get("equipment",[])): return invalid("reward_gear")
		elif reward not in RunState.REWARDS: return invalid("reward_id")
		seen_rewards.append(reward)
	if r.phase == "travel" and not data.started: return invalid("validation_15")
	for key in ["sector","hull","cleared","rewards_taken"]:
		if not r[key] is int: return invalid("run_integer")
	if r.phase == "prepare" and data.started: return invalid("phase")
	if r.phase in ["travel","craft","reward","route","shop","won","lost"] and not data.started: return invalid("phase")
	for key in ["ticks","ammo","rate","shots","supplied","injected","manufactured","missed","ammo_capacity","reserve_capacity"]:
		if not f[key] is int: return invalid("factory_integer")
	if not f.cells is Dictionary or f.cells.size() > 112 or not f.reserves is Dictionary or not f.collected is Dictionary: return invalid("validation_16")
	for raw in ["scrap","coal"]:
		if not f.reserves.get(raw) is int or f.reserves[raw] < 0 or not f.collected.get(raw) is int or f.collected[raw] < 0: return invalid("validation_18")
	if not numeric(f.work_multiplier,0.4,1) or f.ammo_capacity != r.modifiers.magazine or not is_equal_approx(float(f.work_multiplier),float(r.modifiers.work)): return invalid("validation_19")
	if not numeric(f.ammo,0,f.ammo_capacity) or not numeric(f.fuel,0,12.001) or f.rate not in [30,60,90] or f.reserve_capacity != r.modifiers.get("cargo",100): return invalid("validation_20")
	for item in items:
		if item.get("ammo",0) > f.ammo_capacity: return invalid("stored_equipment_capacity")
	for key in ["clock","elapsed","ticks","fuel_used","fire_clock","shots","supplied","injected","manufactured","missed"]:
		if not numeric(f[key],0,1e9): return invalid("validation_22")
	if data.version >= 6 and not f.has("wrecks"): return invalid("missing_wrecks")
	var wrecks = f.get("wrecks",{})
	if not wrecks is Dictionary or wrecks.size() > Factory.W*Factory.H: return invalid("wrecks")
	for pos in wrecks:
		if not pos is Vector2i or pos.x < 0 or pos.x >= Factory.W or pos.y < 0 or pos.y >= Factory.H or f.cells.has(pos) or not wrecks[pos] is String or not Factory.LIMITS.has(wrecks[pos]): return invalid("wreck_cell")
		if pos in candidate.blocks or candidate.ports.has(pos) or candidate.mounted_at(pos) != "": return invalid("wreck_fixed_cell")
	var wreck_directions = f.get("wreck_directions",{})
	if not wreck_directions is Dictionary: return invalid("wreck_directions")
	if data.version >= 7 and (not f.has("wreck_directions") or wreck_directions.size() != wrecks.size()): return invalid("missing_wreck_direction")
	for pos in wreck_directions:
		if not wrecks.has(pos) or not wreck_directions[pos] is int or not numeric(wreck_directions[pos],0,3): return invalid("wreck_direction")
	var rows: Array = []
	for pos in f.cells:
		var c = f.cells[pos]
		if not pos is Vector2i or not c is Dictionary or not c.has_all(["kind","dir","items","work","turn","incoming","made","busy"]): return invalid("validation_26")
		if not c.items is Array or not numeric(c.dir,0,3) or not numeric(c.work,0,8) or not numeric(c.turn,0,2 if c.kind == "router" else 1) or not numeric(c.incoming,0,3) or not numeric(c.made,0,1e9) or not numeric(c.busy,0,1e9): return invalid("validation_27")
		for key in ["dir","work","turn","incoming","made","busy"]:
			if not c[key] is int: return invalid("cell_integer")
		if c.has("feed_cursor") and (layout_version != 2 or not Factory.AUXILIARY.has(c.kind) or not c.feed_cursor is int or not numeric(c.feed_cursor,0,7)): return invalid("equipment_feed_cursor")
		if c.kind == "armor_block":
			if not c.get("armor_hp") is int or not numeric(c.armor_hp,1,Factory.ARMOR_HITS) or not c.items.is_empty() or c.work != 0: return invalid("armor_state")
		if c.items.size() > (f.ammo_capacity if Factory.AUXILIARY.has(c.kind) else 8 if c.kind in ["depot","fuel_depot"] else 4 if c.kind == "overflow_gate" else 1): return invalid("validation_28")
		if Factory.AUXILIARY.has(c.kind):
			if data.version == 1 or c.kind not in r.get("equipment",[]) or c.work != 0: return invalid("auxiliary_cell")
			for item in c.items:
				if item != "shell": return invalid("auxiliary_ammunition")
		for item in c.items:
			if item not in ITEMS: return invalid("validation_30")
		if c.work > 0 and (not Factory.RECIPES.has(c.kind) or c.items.size() != 1): return invalid("validation_31")
		if candidate.ports.has(pos):
			if candidate.ports[pos] != c.kind: return invalid("validation_33")
			if layout_version == 2 and c.dir != Factory.Layout.DIRECTIONS.get(pos,0): return invalid("fixed_port_direction")
		else: rows.append([pos.x,pos.y,c.kind,c.dir])
	for pos in candidate.ports:
		if not f.cells.has(pos): return invalid("validation_36")
	candidate.inventory = f.get("inventory",Factory.LIMITS).duplicate()
	if data.version >= 2:
		for id in r.get("equipment",[]):
			if Factory.AUXILIARY.has(id): candidate.auxiliary_ids.append(id)
	if not candidate.restore(rows,false): return invalid("validation_38")
	var repair_counts = {}
	for pos in wrecks:
		var kind: String = wrecks[pos]
		repair_counts[kind] = repair_counts.get(kind,0)+1
		if candidate.count_kind(kind)+repair_counts[kind] > Factory.LIMITS[kind]: return invalid("wreck_limit")
	for key in ["history","moves","completed","undo_stack"]:
		if not f[key] is Array: return invalid("validation_40")
	for move in f.moves:
		if not move is Dictionary or not move.has_all(["from","to","item"]) or not move.from is Vector2i or not move.to is Vector2i or move.item not in ITEMS: return invalid("validation_42")
	for h in f.history:
		if not h is Array or h.size() != 2 or not numeric(h[0],0,1e9) or not h[1] is bool: return invalid("validation_44")
	for rows_before in f.undo_stack:
		if not rows_before is Array or not candidate.restore(rows_before,false): return invalid("validation_46")
	if data.version == 1:
		var required = 0
		for id in r.get("equipment",[]):
			if Factory.AUXILIARY.has(id): required += 1
		if Factory.W*Factory.H-f.cells.size() < required: return invalid("legacy_mount_space")
	var v = data.view
	if not v is Dictionary or not v.has_all(["yaw","pitch","zoom","roof"]) or not numeric(v.yaw,-100000,100000) or not numeric(v.pitch,0.5,1.5) or not numeric(v.zoom,8,50) or not v.roof is bool: return invalid("validation_48")
	return validate_battle(data.battle,data.started,r)

func validate_battle(b, started: bool, run: Dictionary) -> bool:
	if not b is Dictionary: return invalid("validation_52")
	if b.is_empty(): return not started and run.phase == "prepare"
	if not b.has_all(BATTLE_FIELDS) or not b.has_all(["player","turret","enemies","sites","projectiles","bolts","trails","impacts"]): return invalid("validation_54")
	var mine_count = preload("res://scripts/course_obstacles.gd").layout(run.current).size()*3
	var mines = b.get("mines",[])
	if not mines is Array or mines.size() != mine_count: return invalid("mine_count")
	for spent in mines:
		if not spent is bool: return invalid("mine_state")
	for key in BATTLE_FIELDS:
		if not numeric(b[key],-100000,1e9): return invalid("validation_56")
	var count = RunState.enemy_count(run.current)
	if b.hull < 0 or b.hull > 100 or b.kills < 0 or b.kills > count or b.result not in [-1,0,1]: return invalid("validation_57")
	if run.current.get("field_version",0) == 1 and b.result == 1:
		var selected = int(run.current.destination_index)
		if selected < 0 or not b.player is Transform3D: return invalid("field_destination")
		var course = RunState.FieldCourse.new(run.current)
		var local: Vector3 = b.player.origin-course.destinations[selected].position
		if local.x < 0 or local.x > 16 or absf(local.z) > 8: return invalid("field_arrival")
	if run.phase in ["craft","shop"] and b.result != 1: return invalid("craft_battle")
	var gun_ids = []
	for id in RunState.Content.ALL_GUNS:
		if id in run.get("equipment",[]): gun_ids.append(id)
	var auxiliary = b.get("auxiliary",[])
	if not auxiliary is Array or auxiliary.size() != gun_ids.size(): return invalid("auxiliary_count")
	for i in range(auxiliary.size()):
		var gun = auxiliary[i]
		if not gun is Dictionary or gun.get("id") != gun_ids[i]: return invalid("auxiliary_id")
		if not numeric(gun.get("angle"),-100000,100000) or not numeric(gun.get("cooldown"),0,60) or not numeric(gun.get("flash"),0,0.14) or not numeric(gun.get("recoil"),0,0.2): return invalid("auxiliary_state")
	if not b.player is Transform3D or not numeric(b.turret,-100000,100000): return invalid("validation_58")
	if not b.enemies is Array or b.enemies.size() != count or not b.sites is Array or b.sites.size() != 3: return invalid("validation_59")
	var dead = 0
	for i in range(count):
		var e = b.enemies[i]
		if not e is Dictionary or not e.has_all(ENEMY_FIELDS) or not e.has_all(["transform","pivot","mark_position","mark_visible"]): return invalid("validation_63")
		if not e.hp is int: return invalid("enemy_integer")
		var hp = RunState.enemy_health(run.current,i)
		if e.max_hp != hp or not numeric(e.hp,0,hp) or not numeric(e.cooldown,-1,100) or e.role != RunState.enemy_role(run.current,i) or e.wave != int(i/int(run.current.get("wave_size",2))): return invalid("validation_65")
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
			if not numeric(shot.get("splash",0.0),0,16 if run.get("item_mode",false) else 8) or not numeric(shot.get("radius",6.0),1,12) or not numeric(shot.get("damage",10.0),0,100): return invalid("projectile_effect")
			if not shot.get("chain",0) is int or not numeric(shot.get("chain",0),0,2): return invalid("projectile_chain")
			if shot.get("style","heavy") not in RunState.Content.BALLISTICS: return invalid("projectile_style")
			if key == "projectiles":
				if not shot.has("dir") or not shot.dir is Vector3 or not shot.target is int or shot.target < 0 or shot.target >= count: return invalid("validation_78")
			elif not shot.target is Vector3 or not shot.has("mark") or not shot.mark is int or shot.mark < 0 or shot.mark >= count: return invalid("validation_79")
	if not b.trails is Array or b.trails.size() > 90 or not b.impacts is Array or b.impacts.size() > 128: return invalid("validation_80")
	for trail in b.trails:
		if not trail is Transform3D: return invalid("validation_82")
	for impact in b.impacts:
		if not impact is Dictionary or not impact.has_all(["position","life"]) or not impact.position is Vector3 or not numeric(impact.life,0,1.6): return invalid("validation_84")
		if impact.get("style","heavy") not in RunState.Content.BALLISTICS or impact.life > RunState.Content.BALLISTICS[impact.get("style","heavy")].life: return invalid("impact_style")
	return true

func invalid(reason: String) -> bool:
	error = reason
	return false
