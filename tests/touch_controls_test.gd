extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS touch: ",label)
	else:
		failures += 1
		push_error(label)
func touch(index: int, at: Vector2, pressed: bool, cancelled: bool = false):
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_final_transform()*at
	event.pressed = pressed
	event.canceled = cancelled
	root.push_input(event,false)
func tap(button, index = 0):
	var at: Vector2 = button.get_global_rect().get_center()
	touch(index,at,true)
	touch(index,at,false)
	game.touch_controls.refresh()
func world_tap(at: Vector2):
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = root.get_final_transform()*at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,false)
func run():
	root.size = Vector2i(1440,940)
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"touch_controls_test",2)
	game.show_start_menu = false
	game.touch_enabled = true
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game._process(0)
	var controls = game.touch_controls
	controls.refresh()
	check(controls != null and game.inventory_panel.touch_mode,"native touch UI enabled without a web bridge")
	check(controls.buttons.play == game.start_button and game.icon_buttons.any(func(entry): return entry.button.visible),"touch uses the same footer buttons as mouse and keyboard")
	tap(game.tool_tabs[1])
	check(game.tool_page == 1 and game.tool_buttons.has("furnace"),"touch selects the shared construction category")
	tap(game.tool_buttons.furnace)
	check(game.selected == "furnace","touch selects equipment from the original icon row")
	var old_direction = game.direction
	tap(controls.buttons.rotate)
	check(game.direction == (old_direction+1)%4,"rotation works once per touch")
	tap(controls.buttons.loadout)
	check(game.equipment_workspace.loadout.visible,"footer Q opens equipment by native touch")
	tap(controls.buttons.warehouse)
	check(game.inventory_panel.visible,"footer E opens warehouse by native touch")
	tap(controls.buttons.loadout)
	check(not game.equipment_workspace.loadout.visible and game.inventory_panel.visible,"footer Q closes only equipment")
	tap(controls.buttons.warehouse)
	check(not game.inventory_panel.visible,"footer E closes warehouse by native touch")
	tap(controls.buttons.inventory)
	check(game.inventory_panel.visible and not controls.driving(),"inventory suppresses driving input")
	var uid = game.expedition.gear_items[0].uid
	game.inventory_panel.row_buttons[0].pressed.emit()
	check(controls.selected_uid == uid and not game.inventory_panel.visible and game.dragging_item < 0,"tap selects equipment without dragging")
	var at: Vector2 = game.WORLD_RECT.position+game.world.camera.unproject_position(game.world.cell_position(Vector2i(2,0)))
	world_tap(at)
	check(game.factory.equipment_mounts.get("left_gun") == Vector2i(2,0) and controls.selected_uid < 0,"second tap places equipment")
	game._process(0)
	controls.refresh()
	tap(controls.buttons.stow)
	world_tap(at)
	check(game.factory.equipment_mounts.is_empty(),"storage mode replaces right-click on a touchscreen")
	tap(controls.buttons.play)
	check(game.started and game.factory.running and game.battle_mode,"native touch starts the expedition")
	check(controls.mode == "build","departure clears storage selection and its construction hint")
	var center = controls.stick_center
	touch(0,center+Vector2(0,-100),true)
	check(game.battlefield.motion.command.x > 0.5 and controls.stick_index == 0,"stick touch provides forward throttle")
	var drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = root.get_final_transform()*(center+Vector2(90,-70))
	root.push_input(drag,false)
	check(game.battlefield.motion.command.x > 0 and game.battlefield.motion.command.z > 0,"one thumb can drive and turn together")
	tap(controls.buttons.play,1)
	check(not game.factory.running and game.battlefield.motion.command == Vector3.ZERO and controls.stick_index == -1,"second finger pauses and clears the held stick")
	touch(0,center,false)
	tap(controls.buttons.play)
	touch(2,center+Vector2(0,100),true)
	check(game.battlefield.motion.command.x < -0.5,"stick supports reverse")
	touch(2,center,false,true)
	check(game.battlefield.motion.command == Vector3.ZERO,"cancelled touch cannot leave throttle stuck")
	touch(0,center+Vector2(0,-100),true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.battlefield.motion.command == Vector3.ZERO,"focus loss releases touch movement")
	touch(0,center,false)
	tap(controls.buttons.menu)
	check(game.menu.visible and not game.factory.running,"touch menu pauses gameplay")
	touch(0,center+Vector2(0,-100),true)
	check(game.battlefield.motion.command == Vector3.ZERO,"menu blocks driving input")
	touch(0,center,false)
	game.close_menu()
	game.toggle_battle()
	controls.refresh()
	controls.select_item(uid)
	check(controls.selected_uid == -1,"touch selection respects the departed equipment lock")
	root.size = Vector2i(390,844)
	await process_frame
	controls.resized()
	check(not game.factory.running and game.battlefield.motion.command == Vector3.ZERO,"portrait rotation pauses the run")
	game.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("touch_controls_test")
