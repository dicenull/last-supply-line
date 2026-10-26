extends RefCounted
## One value-only observation used to detect new sounds without replay on reload.
var factory_id: int = 0
var battle_id: int = 0
var ticks: int = 0
var shots: int = 0
var kills: int = 0
var hull: int = 100
var impacts: int = 0

func _init(factory = null, battle = null):
	if factory == null: return
	factory_id = factory.get_instance_id()
	ticks = factory.ticks
	shots = factory.shots
	if battle != null:
		battle_id = battle.get_instance_id()
		kills = battle.score.kills
		hull = battle.progress.hull
		impacts = battle.impact_serial

func changed_source(previous) -> bool:
	return factory_id != previous.factory_id or battle_id != previous.battle_id or ticks < previous.ticks or shots < previous.shots

func has_impact_since(previous) -> bool:
	return kills > previous.kills or hull < previous.hull or impacts > previous.impacts
