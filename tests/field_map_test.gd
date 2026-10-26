extends SceneTree
const Map = preload("res://scripts/field_map.gd")
const Course = preload("res://scripts/field_course.gd")
class Battle extends Node3D:
	var field_course
	var player = Node3D.new()
	var progress = preload("res://scripts/battle_progress.gd").new()
	func _init(seed_value: int):
		field_course = Course.new({"seed":seed_value,"length":140,"destination_count":2})
		add_child(player)
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS field map: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	root.size = Vector2i(1440,940)
	var state = {"battle":null,"visible":true}
	var map = Map.new()
	map.icons = preload("res://scripts/pixel_icons.gd").new()
	map.state_provider = func(): return state
	root.add_child(map)
	map.set_process(false)
	map._process(0)
	check(not map.visible and map.course == null,"missing battlefield hides and clears the map")
	var consistent = true
	var released = true
	for index in range(24):
		var battle = Battle.new(41+index)
		root.add_child(battle)
		battle.player.position = Vector3(index*2,0,-index)
		battle.player.rotation.y = index*0.2
		battle.progress.arrived_destination = index%2
		state.battle = battle
		map._process(0)
		var position = battle.player.position
		var forward = Vector2(battle.player.basis.x.x,battle.player.basis.x.z).normalized()
		consistent = consistent and map.visible and map.player_position == position and map.player_forward.is_equal_approx(forward) and map.arrived_destination == index%2
		var course_ref = weakref(battle.field_course)
		# Force the lifetime gap that occurred during overnight checkpoint
		# replacement: the pending CanvasItem draw runs after its model is gone.
		battle.free()
		map.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		consistent = consistent and map.course == course_ref.get_ref() and map.player_position == position
		map._process(0)
		released = released and not map.visible and map.course == null and course_ref.get_ref() == null
	check(consistent,"24 queued redraws retain pose, heading, selected yard and course after battlefield disposal")
	check(released,"refreshing a freed battlefield hides the map and releases retained course data")
	var replacement = Battle.new(2064)
	root.add_child(replacement)
	state.battle = replacement
	map._process(0)
	check(map.visible and map.arrived_destination == -1 and map.player_position == Vector3.ZERO,"a new battlefield replaces every part of the previous snapshot")
	state.visible = false
	map._process(0)
	check(not map.visible and map.course == null,"menu visibility clears the retained course")
	state.visible = true
	replacement.player.free()
	map._process(0)
	check(not map.visible,"a missing player cannot enter the drawing snapshot")
	replacement.free()
	map.free()
	await process_frame
	print("FIELD MAP RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
