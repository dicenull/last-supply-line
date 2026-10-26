extends SceneTree
const Preview = preload("res://scripts/item_model_preview.gd")
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize():
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS item models: ",label)
	else:
		failures += 1
		push_error(label)
func capture(path: String):
	await process_frame
	await process_frame
	# Also render when macOS throttles an unfocused test window.
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(path)
func run():
	DirAccess.make_dir_recursive_absolute("res://build/item-models")
	root.size = Vector2i(1440,940)
	var gallery = ColorRect.new()
	gallery.color = Color("202b30")
	gallery.size = Vector2(1440,940)
	root.add_child(gallery)
	var families = Catalog.Content.BASE_EQUIPMENT.keys()+["scrap","coal","shell"]
	for i in range(families.size()):
		var preview = Preview.new()
		preview.position = Vector2(24+(i%5)*280,16+(i/5)*220)
		preview.size = Vector2(248,180)
		gallery.add_child(preview)
		preview.show_item({"kind":families[i],"rarity":"rare"})
		var label = Label.new()
		label.text = families[i]
		label.position = preview.position+Vector2(0,180)
		label.size.x = 248
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gallery.add_child(label)
		check(preview.model.get_meta("kind") == families[i] and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE,"preview uses shared model without capturing pointer: "+families[i])
	await capture("res://build/item-models/catalog.png")
	gallery.queue_free()
	await process_frame
	root.size = Vector2i(1440,940)
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"item_models_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.ensure_battle()
	if not game.battle_mode: game.toggle_battle()
	var b = game.battlefield
	for i in range(4):
		b.drop_item({"kind":"armor","rarity":Catalog.RARITIES.keys()[i]},Vector3(18+i*7,0,-10))
	game._process(0)
	for width in [1440,960]:
		root.size = Vector2i(width,940 if width == 1440 else 628)
		await capture("res://build/item-models/rarity-drops-"+str(width)+".png")
	b.restore_ground_items([])
	root.size = Vector2i(1440,940)
	var kinds = ["left_gun_focus_l05","salvage_arm","economizer","armor","arc_gun"]
	for i in range(kinds.size()):
		b.drop_item({"kind":kinds[i],"rarity":Catalog.RARITIES.keys()[i%4]},Vector3(18+i*5,0,5))
	b.drop_materials({"scrap":8,"coal":4},Vector3(26,0,-5))
	game._process(0)
	await capture("res://build/item-models/field-drops.png")
	for dimensions in [Vector2i(1440,940),Vector2i(960,628)]:
		root.size = dimensions
		for kind in kinds: game.expedition.add_item({"kind":kind,"rarity":"rare"})
		game.inventory_panel.show()
		game.inventory_panel.refresh()
		await capture("res://build/item-models/inventory-"+str(dimensions.x)+".png")
		for i in range(game.inventory_panel.rows.size()):
			var preview = game.inventory_panel.model_previews[i]
			check(preview.model.get_meta("kind") == game.inventory_panel.rows[i].kind,"inventory row and rendered model agree")
	root.size = Vector2i(1440,940)
	game.reset_battle(42)
	var mounts = {"long_gun_focus_l05":Vector2i(0,0),"scatter_gun":Vector2i(2,0),"servo":Vector2i(0,2),"blast_fuse":Vector2i(1,2),"armor":Vector2i(2,2),"economizer":Vector2i(0,3),"rangefinder":Vector2i(2,3),"salvage_arm":Vector2i(2,5)}
	for id in mounts:
		var uid = game.expedition.add_item({"kind":id,"rarity":"rare"})
		check(game.place_item(uid,mounts[id]),"dense neighboring model layout: "+id)
	game._process(0)
	await capture("res://build/item-models/adjacent-mounts.png")
	game.ensure_battle()
	game.toggle_battle()
	b = game.battlefield
	b.zoom = 38
	b.update_camera()
	game._process(0)
	b.camera.position -= Vector3(14,0,0)
	b.muzzle.show()
	for gun in b.auxiliary_guns: gun.muzzle.show()
	var rounds: Array = []
	for i in range(3):
		var round_model = Node3D.new()
		b.add_child(round_model)
		round_model.position = Vector3(15+i*4,4.5,(i-1)*4)
		b.build_shell(round_model,Vector3.RIGHT,["heavy","standard","electric"][i])
		rounds.append(round_model)
	await capture("res://build/item-models/enlarged-exterior.png")
	for round_model in rounds: round_model.queue_free()
	b.muzzle.hide()
	for gun in b.auxiliary_guns: gun.muzzle.hide()
	b.player.position = b.goals[0].position-Vector3(20,0,0)
	b.zoom = 78
	b.update_camera()
	game._process(0)
	await capture("res://build/item-models/fortified-destination.png")
	game.queue_free()
	await process_frame
	Fixture.clean("item_models_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
