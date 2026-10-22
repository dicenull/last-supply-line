extends RefCounted
## Shared gameplay catalog. IDs are save-stable; numbers are consumed by the simulation.
const DIFFICULTIES = {
	"easy":{"name":"イージー","damage":0.65,"period":1.25,"warning":1.25,"enemies":-2,"scrap":64,"coal":44,"salvage":1.25},
	"normal":{"name":"ノーマル","damage":1.0,"period":1.0,"warning":1.0,"enemies":0,"scrap":48,"coal":32,"salvage":1.0},
	"hard":{"name":"ハード","damage":1.25,"period":0.85,"warning":0.85,"enemies":6,"scrap":42,"coal":28,"salvage":0.9}
}
# Gameplay-scaled speeds and distinct visual signatures; not physical ballistics.
const BALLISTICS = {
	"standard":{"speed":95.0,"width":0.12,"tail":1.0,"blast":2.2,"life":0.9,"fire_time":0.18,"column":1.0},
	"heavy":{"speed":75.0,"width":0.19,"tail":1.2,"blast":4.2,"life":1.3,"fire_time":0.3,"column":1.25},
	"rapid":{"speed":140.0,"width":0.08,"tail":0.8,"blast":1.3,"life":0.6,"fire_time":0.12,"column":0.8},
	"sniper":{"speed":160.0,"width":0.10,"tail":1.8,"blast":1.8,"life":0.8,"fire_time":0.16,"column":1.8},
	"mortar":{"speed":45.0,"width":0.22,"tail":0.65,"blast":5.0,"life":1.5,"fire_time":0.22,"column":1.7},
	"demolition":{"speed":55.0,"width":0.24,"tail":0.8,"blast":5.8,"life":1.6,"fire_time":0.4,"column":0.8},
	"electric":{"speed":110.0,"width":0.13,"tail":0.9,"blast":2.4,"life":0.7,"fire_time":0.16,"column":1.4}
}
const EQUIPMENT = {
	"left_gun":{"ballistics":"standard","name":"左舷副砲","icon":"gun","scrap":16,"coal":4,"effect":"独立給弾 / 標準副砲","interval":1.5,"range":36.0,"ammo":1},
	"right_gun":{"ballistics":"standard","name":"右舷副砲","icon":"gun","scrap":16,"coal":4,"effect":"独立給弾 / 標準副砲","interval":1.5,"range":36.0,"ammo":1},
	"armor":{"name":"追加装甲","icon":"shield","scrap":20,"coal":6,"effect":"被ダメージ −25%"},
	"rapid_gun":{"ballistics":"rapid","name":"速射副砲","icon":"autoload","scrap":24,"coal":5,"effect":"0.65秒間隔 / 射程24m","interval":0.65,"range":24.0,"ammo":1},
	"long_gun":{"ballistics":"sniper","name":"長砲身砲","icon":"battery","scrap":26,"coal":6,"effect":"射程48m / 2.4秒間隔","interval":2.4,"range":48.0,"ammo":1},
	"mortar_gun":{"ballistics":"mortar","name":"迫撃砲","icon":"shell","scrap":30,"coal":8,"effect":"半径4mの範囲攻撃 / 砲弾2発","interval":3.0,"range":36.0,"ammo":2,"splash":4.0},
	"rear_gun":{"ballistics":"demolition","name":"近接防御砲","icon":"raiders","scrap":22,"coal":4,"effect":"高速旋回 / 0.9秒間隔・射程20m","interval":0.9,"range":20.0,"ammo":1,"turn":6.0},
	"rangefinder":{"name":"光学測距儀","icon":"camera","scrap":18,"coal":3,"effect":"全砲の射程 +6m"},
	"servo":{"name":"砲塔旋回機","icon":"rotate","scrap":18,"coal":5,"effect":"全砲の旋回速度 +60%"},
	"supercharger":{"name":"過給機","icon":"move","scrap":20,"coal":7,"effect":"走行速度 +20% / 燃料消費 +10%"},
	"economizer":{"name":"排熱回収器","icon":"fuel","scrap":22,"coal":4,"effect":"走行燃料消費 −20%"},
	"salvage_arm":{"name":"回収クレーン","icon":"scrap","scrap":18,"coal":4,"effect":"撃破回収の廃材 +2"},
	"skirts":{"name":"耐爆スカート","icon":"shield","scrap":24,"coal":5,"effect":"被ダメージ −20% / 追加装甲と併用可"},
	"scatter_gun":{"ballistics":"standard","name":"三連散弾砲","icon":"scatter_gun","scrap":28,"coal":6,"effect":"前方3両へ同時射撃 / 砲弾2発","interval":2.1,"range":27.0,"ammo":2,"pellets":3},
	"arc_gun":{"ballistics":"electric","name":"蓄電誘導砲","icon":"arc_gun","scrap":30,"coal":8,"effect":"着弾から9m以内へ2回連鎖 / 砲弾2発","interval":2.6,"range":32.0,"ammo":2,"chain":2},
	"blast_fuse":{"name":"破砕信管","icon":"blast_fuse","scrap":20,"coal":4,"effect":"全砲の爆発範囲 +4m"},
	"drum_loader":{"name":"回転式装填機","icon":"drum_loader","scrap":22,"coal":5,"effect":"主砲・副砲の射撃間隔 −20%"}
}
const GUNS = ["left_gun","right_gun","rapid_gun","long_gun","mortar_gun","rear_gun","scatter_gun","arc_gun"]
const BLOCK_LIMITS = {"belt":80,"furnace":4,"press":4,"splitter":6,"depot":3,"refinery":3,
	"smart_splitter":4,"priority_splitter":4,"overflow_gate":4,"router":3,"scrap_filter":6,"shell_filter":6,"fuel_filter":6,"blast_furnace":2,"auto_press":2,"fuel_depot":3,"armor_block":8}
const STARTING_BLOCKS = {"belt":24,"furnace":2,"press":2,"splitter":2,"depot":2,"refinery":1,"armor_block":2}
const BUILD_COSTS = {
	"belt":{"scrap":1,"coal":0},"furnace":{"scrap":6,"coal":1},"press":{"scrap":6,"coal":1},
	"splitter":{"scrap":3,"coal":0},"depot":{"scrap":4,"coal":0},"refinery":{"scrap":6,"coal":2},
	"armor_block":{"scrap":5,"coal":0},
	"smart_splitter":{"scrap":6,"coal":1},"priority_splitter":{"scrap":5,"coal":1},
	"overflow_gate":{"scrap":6,"coal":1},"router":{"scrap":7,"coal":1},
	"scrap_filter":{"scrap":3,"coal":0},"shell_filter":{"scrap":3,"coal":0},"fuel_filter":{"scrap":3,"coal":0},
	"blast_furnace":{"scrap":10,"coal":3},"auto_press":{"scrap":10,"coal":2},"fuel_depot":{"scrap":6,"coal":1}
}
const BASIC_BLOCKS = {
	"belt":{"name":"搬送路","icon":"belt","effect":"素材を次のマスへ搬送"},
	"furnace":{"name":"精錬炉","icon":"furnace","effect":"廃材から鋼材を生産"},
	"press":{"name":"砲弾プレス","icon":"press","effect":"鋼材から砲弾を生産"},
	"splitter":{"name":"分配器","icon":"splitter","effect":"前方と右へ交互に搬送"},
	"depot":{"name":"備蓄庫","icon":"depot","effect":"素材を8個まで備蓄"},
	"refinery":{"name":"燃料精製機","icon":"refinery","effect":"石炭から燃料を生産"},
	"armor_block":{"name":"防御ブロック","icon":"shield","effect":"周囲8マスを3回防護 / 車体被害半減 / 搬送不可"}
}

static func block_bundle(kind: String) -> int:
	return 8 if kind == "belt" else 2 if kind in ["splitter","scrap_filter","shell_filter","fuel_filter"] else 1

static func reward_info(id: String) -> Dictionary:
	if id.begins_with("block:"):
		var kind = id.trim_prefix("block:")
		return (BASIC_BLOCKS[kind] if BASIC_BLOCKS.has(kind) else BLOCKS[kind]).duplicate()
	if id.begins_with("gear:"): return EQUIPMENT[id.trim_prefix("gear:")].duplicate()
	return REWARDS.get(id,{}).duplicate()
const ENEMIES = [
	{"ballistics":"standard","name":"戦列戦車","recipe":"left_gun","tier":1,"speed":3.0,"intercept":13.0,"warning":1.8,"period":1.0,"damage":1.0,"radius":6.0,"color":"875444"},
	{"ballistics":"rapid","name":"迂回戦車","recipe":"right_gun","tier":1,"speed":4.0,"intercept":8.0,"warning":1.8,"period":1.0,"damage":1.0,"radius":6.0,"flank":true,"color":"996843"},
	{"ballistics":"heavy","name":"重砲戦車","recipe":"armor","tier":1,"speed":1.6,"intercept":22.0,"warning":2.0,"period":1.4,"damage":1.4,"radius":6.0,"color":"765443"},
	{"ballistics":"rapid","name":"偵察車","recipe":"rapid_gun","tier":1,"speed":5.2,"intercept":10.0,"warning":1.5,"period":0.8,"damage":0.6,"radius":4.0,"scale":0.7,"color":"a58850"},
	{"ballistics":"sniper","name":"狙撃砲車","recipe":"long_gun","tier":2,"speed":1.8,"intercept":32.0,"warning":2.6,"period":1.5,"damage":1.8,"radius":3.0,"lead":1.0,"color":"626b58"},
	{"ballistics":"mortar","name":"迫撃砲車","recipe":"mortar_gun","tier":2,"speed":2.0,"intercept":27.0,"warning":2.7,"period":1.6,"damage":1.0,"radius":9.0,"color":"807249"},
	{"ballistics":"standard","name":"突破戦車","recipe":"rear_gun","tier":2,"speed":5.0,"intercept":-7.0,"warning":1.5,"period":0.9,"damage":0.8,"radius":4.5,"flank":true,"color":"a35140"},
	{"ballistics":"heavy","name":"防塞戦車","recipe":"rangefinder","tier":3,"speed":1.2,"intercept":18.0,"warning":2.2,"period":1.1,"damage":1.2,"radius":7.0,"scale":1.2,"color":"575c50"},
	{"ballistics":"demolition","name":"爆雷車","recipe":"servo","tier":3,"speed":4.8,"intercept":4.0,"warning":2.8,"period":1.5,"damage":1.8,"radius":10.0,"scale":0.8,"color":"aa633e"},
	{"ballistics":"standard","name":"物資輸送車","recipe":"supercharger","tier":3,"speed":2.4,"intercept":24.0,"warning":2.0,"period":1.8,"damage":0.5,"radius":4.0,"loot":8,"coal":4,"color":"75835e"},
	{"ballistics":"rapid","name":"連装砲車","recipe":"economizer","tier":4,"speed":2.6,"intercept":20.0,"warning":2.2,"period":1.5,"damage":0.65,"radius":4.0,"burst":3,"color":"835971"},
	{"ballistics":"sniper","name":"観測指揮車","recipe":"salvage_arm","tier":4,"speed":3.4,"intercept":29.0,"warning":2.0,"period":1.0,"damage":0.8,"radius":5.0,"lead":1.8,"command":true,"color":"627a83"},
	{"ballistics":"demolition","name":"工兵突撃車","recipe":"skirts","tier":4,"speed":3.7,"intercept":6.0,"warning":2.1,"period":1.0,"damage":1.0,"radius":7.5,"lead":0.6,"flank":true,"color":"8b8144"},
	{"ballistics":"demolition","name":"火薬運搬車","recipe":"blast_fuse","tier":2,"speed":2.6,"intercept":16.0,"warning":2.4,"period":1.6,"damage":0.8,"radius":6.0,"color":"76634c","detonate":11.0,"loot":5},
	{"ballistics":"mortar","name":"斉射ロケット車","recipe":"scatter_gun","tier":3,"speed":1.8,"intercept":28.0,"warning":3.0,"period":1.8,"damage":0.65,"radius":4.0,"color":"68745e","burst":5},
	{"ballistics":"demolition","name":"爆槍突撃車","recipe":"arc_gun","tier":3,"speed":5.0,"intercept":-2.0,"warning":1.8,"period":1.0,"damage":1.4,"radius":6.0,"color":"847346","ram":true,"scale":0.85}
]
const BLOCKS = {
	"smart_splitter":{"name":"素材分岐器","icon":"splitter","base":"splitter","limit":4,"effect":"燃料・石炭は右 / 他は前"},
	"priority_splitter":{"name":"優先分岐器","icon":"splitter","base":"splitter","limit":4,"effect":"前を優先 / 満杯なら右"},
	"overflow_gate":{"name":"一括搬送庫","icon":"depot","base":"depot","limit":4,"effect":"4個貯めてからまとめて排出"},
	"router":{"name":"三方向分配器","icon":"splitter","base":"splitter","limit":3,"effect":"前・右・左へ順番に分配"},
	"scrap_filter":{"name":"廃材フィルター","icon":"scrap","base":"belt","limit":6,"effect":"廃材だけを通す"},
	"shell_filter":{"name":"砲弾フィルター","icon":"shell","base":"belt","limit":6,"effect":"砲弾だけを通す"},
	"fuel_filter":{"name":"燃料フィルター","icon":"fuel","base":"belt","limit":6,"effect":"燃料缶だけを通す"},
	"blast_furnace":{"name":"高炉","icon":"furnace","base":"furnace","limit":2,"effect":"廃材→鋼材 0.75秒 / 石炭1消費"},
	"auto_press":{"name":"動力プレス","icon":"press","base":"press","limit":2,"effect":"鋼材→砲弾 1秒 / 燃料0.08消費"},
	"fuel_depot":{"name":"燃料備蓄庫","icon":"fuel","base":"depot","limit":3,"effect":"燃料缶8個を備蓄・搬送"}
}
const REWARDS = {
	"production":{"name":"生産速度","icon":"press","effect":"加工時間 ×0.85"},
	"economy":{"name":"燃料効率","icon":"fuel","effect":"走行燃料消費 ×0.80"},
	"magazine":{"name":"装填容量","icon":"depot","effect":"全砲の容量 +4"},
	"autoload":{"name":"装填速度","icon":"autoload","effect":"射撃間隔 ×0.80"},
	"cargo":{"name":"原料積載","icon":"cargo","effect":"原料積載上限 +25"},
	"scrap_cache":{"name":"廃材補給","icon":"scrap","effect":"廃材 +24（積載上限まで）"},
	"coal_cache":{"name":"石炭補給","icon":"coal","effect":"石炭 +18（積載上限まで）"},
	"shell_cache":{"name":"弾薬補給","icon":"shell","effect":"主砲 +8発 / 各副砲 +2発"},
	"field_repair":{"name":"野戦整備","icon":"shield","effect":"車体耐久 +20（上限100）"},
	"scout_maps":{"name":"偵察地図","icon":"road","effect":"以後の経路を3候補から選択"},
	"craft_discount":{"name":"治工具一式","icon":"steel","effect":"装備の製作費用 ×0.80"},
	"salvage_boost":{"name":"回収班","icon":"scrap","effect":"撃破回収の廃材 +1"},
	"range_training":{"name":"測距訓練","icon":"camera","effect":"全砲の射程 +4m"},
	"reinforcement":{"name":"防爆内張り","icon":"shield","effect":"被ダメージ ×0.90"},
	"engine_tuning":{"name":"機関調整","icon":"engine","effect":"走行速度 ×1.10"}
}
