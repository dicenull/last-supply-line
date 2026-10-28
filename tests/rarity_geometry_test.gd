extends SceneTree
const Models = preload("res://scripts/item_model.gd")
const Fixture = preload("res://tests/profile_fixture.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS rarity geometry: ",label)
	else:
		failures += 1
		push_error(label)
func shape(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D: result.append([node.transform,node.mesh.get_class(),node.mesh.get_aabb()])
	for child in node.get_children(): result.append_array(shape(child))
	return result
func run():
	var builder = Models.new()
	for kind in Models.Catalog.Data.ITEMS:
		var previous: Array = []
		for rarity in Models.Catalog.RARITIES:
			var model = builder.build(kind,rarity)
			var signature = shape(model)
			check(signature != previous and model.has_node("QualityUpgrade/RarityAccent"),"quality changes geometry with a small badge: "+kind+"/"+rarity)
			previous = signature
			if Models.Catalog.part_slot(kind).is_empty() and kind not in Models.Catalog.Content.ALL_GUNS:
				var mounted = builder.build_mounted(kind,rarity)
				var low = Vector3(INF,INF,INF)
				var high = -low
				for point in Models.vertices(mounted):
					low = low.min(point)
					high = high.max(point)
				var footprint = Vector2(Models.Catalog.DEFINITIONS[kind].size)
				check(is_equal_approx(high.x-low.x,footprint.x-0.09) and is_equal_approx(high.z-low.z,footprint.y-0.09) and high.y <= Models.MOUNT_HEIGHT+0.001,"module fills its reservation without overhang: "+kind+"/"+rarity)
				mounted.free()
			model.free()
	var game = load("res://main.tscn").instantiate()
	Fixture.assign(game,"rarity_geometry_test",2)
	game.show_start_menu = false
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for rarity in Models.Catalog.RARITIES:
		var uid = game.expedition.add_item({"kind":"left_gun","rarity":rarity})
		for item in game.expedition.gear_items.duplicate():
			if item.kind == "left_gun" and item.position != Vector2i(-1,-1): game.stow_item(item.uid)
		check(game.place_item(uid,Vector2i.ZERO) and game.world.auxiliary_guns[0].pivot.get_meta("rarity") == rarity,"same model ID rebuilds when quality changes: "+rarity)
	game.free()
	Fixture.clean("rarity_geometry_test")
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
