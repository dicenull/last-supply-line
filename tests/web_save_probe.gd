extends SceneTree

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var save = preload("res://scripts/run_save.gd").new()
	var data = save.read_file(args[0])
	if data.is_empty():
		push_error("Browser save failed validation: "+save.error)
		quit(1)
		return
	var result = {"valid":true,"started":data.started,"phase":data.run.phase,"hull":data.run.hull,
		"ticks":data.factory.ticks,"manufactured":data.factory.manufactured,"fuel":data.factory.fuel,
		"cells":data.factory.cells.size(),"seed":str(data.run.run_seed),"battle":not data.battle.is_empty()}
	result.results = data.run.get("results",{})
	result.map_shape = data.run.current.get("map_shape","")
	result.map_shape_version = data.run.current.get("map_shape_version",0)
	result.map_geometry = str(preload("res://scripts/field_course.gd").new(data.run.current).segments)
	result.empty_slots = data.run.get("empty_part_slots",[])
	var camera_offset = data.view.get("camera_offset",Vector3.ZERO)
	result.camera_offset = [camera_offset.x,camera_offset.y,camera_offset.z]
	result.layout_version = data.factory.get("layout_version",1)
	result.item_mode = data.run.get("item_mode",false)
	result.reserves = data.factory.reserves
	result.gear_items = []
	for item in data.run.get("gear_items",[]):
		result.gear_items.append({"uid":item.uid,"kind":item.kind,"rarity":item.rarity,"position":[item.position.x,item.position.y],"ammo":item.get("ammo",0),"direction":item.get("direction",0),"stock":item.get("stock",false)})
	if not data.battle.is_empty():
		result.player = [data.battle.player.origin.x,data.battle.player.origin.y,data.battle.player.origin.z]
		result.kills = data.battle.kills
	print("WEB SAVE: ",JSON.stringify(result))
	quit()
