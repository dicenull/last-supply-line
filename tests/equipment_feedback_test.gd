extends SceneTree
const Feed = preload("res://scripts/equipment_loot_feed.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment feedback: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var feed = Feed.new()
	feed.icons = preload("res://scripts/pixel_icons.gd").new()
	feed.font = ThemeDB.fallback_font
	root.add_child(feed)
	var item = {"kind":"armor","rarity":"rare"}
	feed.push_item(item)
	feed.push_item(item)
	item.rarity = "legendary"
	check(feed.entries.size() == 1 and feed.entries[0].count == 2 and feed.entries[0].rarity == "rare","receipts aggregate a burst without retaining a mutable item reference")
	feed.advance(1,true)
	check(feed.visible and feed.entries[0].time == 3,"active feedback counts down")
	feed.advance(0,false)
	check(not feed.visible and feed.entries[0].time == 3,"covered or paused feedback can be hidden without aging")
	feed.advance(0,true)
	check(feed.visible,"uncovering restores the receipt")
	feed.advance(3,true)
	check(feed.entries.is_empty() and not feed.visible,"expired feedback releases its entries")
	for i in range(100): feed.push_item({"kind":"armor" if i%2 == 0 else "skirts","rarity":"normal"})
	check(feed.entries.size() == Feed.MAX_ENTRIES and feed.get_child_count() == 0,"loot bursts use a bounded receipt list without growing nodes")
	feed.push_item({"kind":"unknown","rarity":"rare"})
	check(feed.entries.size() == Feed.MAX_ENTRIES,"unknown equipment does not enter the display")
	feed.clear()
	check(feed.entries.is_empty() and not feed.visible,"reset clears transient receipts")
	feed.queue_free()
	await process_frame
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"equipment_feedback_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	game.toggle_running()
	var count = game.expedition.gear_items.size()
	var stock = game.factory.reserves.duplicate()
	var enemy = game.battlefield.enemies[0]
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	game.battlefield.drive_poses = [{"position":enemy.node.position,"yaw":0.0}]
	game.battlefield.update_ground_items(game.factory)
	game._process(0)
	check(game.expedition.gear_items.size() == count and game.factory.reserves.scrap == stock.scrap+2 and game.loot_feed.entries.is_empty(),"ordinary enemy grants materials without an equipment receipt")
	check(game.logistics.notices.scrap.accepted == 2,"enemy material gain appears in the resource header")
	game.battlefield.sector_config.boss = true
	enemy = game.battlefield.enemies.back()
	game.battlefield.kill_enemy(enemy,game.factory,enemy.node.position)
	game.battlefield.drive_poses = [{"position":enemy.node.position,"yaw":0.0}]
	game.battlefield.update_ground_items(game.factory)
	game._process(0)
	check(game.expedition.gear_items.size() == count+1 and game.loot_feed.entries.size() == 1,"boss equipment appears in the loot feed")
	game.factory.running = false
	var receipt = game.loot_feed.entries.duplicate(true)
	game._process(2)
	check(game.loot_feed.entries == receipt,"combat pause preserves the remaining receipt duration")
	game.open_menu()
	game._process(1)
	check(not game.loot_feed.visible and game.loot_feed.entries == receipt,"menu hides loot receipts without expiring them")
	game.close_menu()
	game._process(0)
	check(game.loot_feed.visible,"closing the menu reveals pending receipts")
	game.receive_item({"kind":"mortar_gun","rarity":"legendary"})
	game.receive_item({"kind":"armor","rarity":"rare"})
	game._process(0)
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		await process_frame
		check(game.inventory_button.get_rect().end.x < game.icon_buttons[1].rect.position.x,"inventory count and view switch have separate hit regions at "+str(dimensions.x))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/equipment-audit")
			root.get_texture().get_image().save_png("res://build/equipment-audit/loot-feedback-"+str(dimensions.x)+".png")
	var data = game.checkpoint.snapshot(game)
	check(game.checkpoint.apply(game,data) and game.loot_feed.entries.is_empty(),"restore does not replay already awarded loot")
	game.receive_item({"kind":"armor","rarity":"normal"})
	game.reset_battle(42)
	check(game.loot_feed.entries.is_empty(),"new run clears receipts from the previous inventory")
	game.queue_free()
	await process_frame
	Fixture.clean("equipment_feedback_test")
	print("EQUIPMENT FEEDBACK RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
