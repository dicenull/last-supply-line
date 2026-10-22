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
	if not data.battle.is_empty():
		result.player = [data.battle.player.origin.x,data.battle.player.origin.y,data.battle.player.origin.z]
		result.kills = data.battle.kills
	print("WEB SAVE: ",JSON.stringify(result))
	quit()
