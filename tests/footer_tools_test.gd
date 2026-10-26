extends SceneTree
const Fixture = preload("res://tests/profile_fixture.gd")
const Content = preload("res://scripts/content.gd")
var game
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS footer tools: ",label)
	else:
		failures += 1
		push_error(label)
func key(code):
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)
	game._process(0)
	await process_frame
func click(button):
	var e = InputEventMouseButton.new()
	e.position = root.get_final_transform()*button.get_rect().get_center()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	root.push_input(e,false)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e,false)
	game._process(0)
	await process_frame
func capture(label):
	game.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/tabs-audit/"+label+".png")
func run():
	game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"footer_tools_test")
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		await process_frame
		game.factory.unlocked_blocks = Content.STARTING_BLOCKS.keys()
		game.tool_page = 0
		game.selected = "belt"
		game.refresh_view()
		game._process(0)
		check(game.available_tools().size() == 7 and game.tool_page_count() == 5 and "erase" not in game.available_tools(),"seven starter blocks use five categories; erase is separate")
		check(game.tool_buttons.keys() == ["belt"] and game.icon_buttons.slice(4,8).all(func(entry): return not entry.button.visible) and game.icon_buttons.slice(8,10).all(func(entry): return entry.button.visible),"transport tab hides locked filters and unused slots while keeping storage and roof controls")
		var erase_rect = game.erase_button.get_rect()
		check(game.erase_button.visible and game.icon_buttons[11].key == "0","erase has a dedicated visible zero shortcut")
		await capture("footer-start-"+str(dimensions.x))
		await click(game.tool_tabs[2])
		check(game.tool_buttons.keys() == ["furnace","press","refinery"] and game.selected == "furnace","processing tab selects its first available machine")
		await key(KEY_2)
		check(game.selected == "press","number keys follow the current category")
		await key(KEY_0)
		check(game.selected == "erase" and game.erase_button.get_rect() == erase_rect,"zero selects erase without moving its button")
		await click(game.tool_tabs[3])
		check(game.selected == "erase" and game.tool_buttons.keys() == ["depot"] and game.erase_button.get_rect() == erase_rect,"changing category preserves the fixed erase tool")
		await click(game.tool_buttons.depot)
		await click(game.erase_button)
		check(game.selected == "erase","dedicated erase button accepts real click")
		await key(KEY_9)
		await key(KEY_7)
		check(game.selected == "armor_block","empty slot shortcut cannot select a hidden block")
		check(game.tool_page == 4 and game.tool_kinds() == ["armor_block"],"armor shortcut opens the defense tab")
		await capture("footer-armor-"+str(dimensions.x))
		game.factory.unlocked_blocks.append_array(["router","auto_press"])
		game._process(0)
		await click(game.tool_tabs[1])
		check(game.tool_buttons.keys() == ["splitter","router"],"new routing design appears in branching without locked gaps")
		await key(KEY_2)
		check(game.selected == "router","number shortcut follows the displayed packed slot")
		await click(game.tool_tabs[2])
		check(game.tool_buttons.keys() == ["furnace","press","refinery","auto_press"],"new machine appears only in processing")
		await capture("footer-unlocked-"+str(dimensions.x))
		game.factory.unlocked_blocks = Content.BLOCK_LIMITS.keys()
		game._process(0)
		var seen = []
		game.tool_page = 0
		for i in range(game.tool_page_count()):
			seen.append_array(game.tool_kinds())
			game.cycle_tools()
		check(seen == game.available_tools() and seen.size() == 17,"every unlocked block appears exactly once across five categories")
		for index in range(game.TOOL_TABS.size()):
			await click(game.tool_tabs[index])
			check(game.erase_button.visible and game.erase_button.get_rect() == erase_rect,"erase position is fixed in category "+str(index))
			await capture("footer-all-"+str(index)+"-"+str(dimensions.x))
		game.tool_page = 2
		game.selected = "auto_press"
		game.factory.unlocked_blocks = ["belt"]
		game._process(0)
		check(game.tool_page == 0 and game.tool_buttons.keys() == ["belt"] and game.selected == "belt" and game.tool_tabs.slice(1).all(func(button): return not button.visible),"shrinking availability hides empty tabs and repairs the selected category")
		await key(KEY_8)
		check(game.tool_page == 0,"category shortcut skips empty tabs")
		game.factory.unlocked_blocks.clear()
		game._process(0)
		await key(KEY_8)
		check(game.tool_buttons.is_empty() and game.selected == "erase" and game.erase_button.visible,"erase remains usable even without any unlocked block")
		game.factory.unlocked_blocks = Content.STARTING_BLOCKS.keys()
		game._process(0)
	game.queue_free()
	await process_frame
	print("FOOTER TOOLS RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func _finalize(): Fixture.clean("footer_tools_test")
