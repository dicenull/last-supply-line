extends Control
## Read-only, unpaged parameter overview. E owns every equipment command.
const Style = preload("res://scripts/ui_style.gd")
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Parameters = preload("res://scripts/vehicle_parameters.gd")
const GOOD = Color("80e5a0")
const BAD = Color("ff7070")
const LABELS = {"speed":"走行速度","turn":"車体旋回","fuel":"走行燃費 / m","reload":"主砲 射撃間隔","range":"主砲 射程","splash":"主砲 爆発範囲","power":"主砲 威力","ammo":"主砲 消費弾数","shot_fuel":"主砲 消費燃料","damage":"被害倍率","blast_damage":"爆発被害倍率","offroad":"悪路速度倍率","turret":"砲塔旋回","salvage":"追加回収率"}
var font: Font
var state: Dictionary = {}
var close_button: Button
static func delta_color(key: String, after, before) -> Color:
	var benefit = Parameters.benefit(key,after,before)
	return GOOD if benefit > 0 else BAD if benefit < 0 else Style.MUTED
func visible_metrics() -> Array:
	return LABELS.keys()
func metric_rect(index: int) -> Rect2:
	var columns = maxi(2,int((size.x-24)/190))
	var rows = ceili(LABELS.size()/float(columns))
	var width = (size.x-24)/columns
	var height = minf(62,(size.y-64)/rows)
	return Rect2(12+(index%columns)*width,60+(index/columns)*height,width-8,height)
func delta_text(key: String, value) -> String:
	return "("+Parameters.number(key,value,true)+")" if value != null else "(—)"
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "パラメータを閉じる（Q）"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	add_child(close_button)
	update_state({})
func update_state(value: Dictionary):
	state = value
	tooltip_text = "現在値 (基礎性能からの装備補正) (選択品へ変更したときの差分)。緑は良い効果、赤は悪い効果。\n設置物の比較は同系統を外す想定。装備操作はEの倉庫。"
	var activation: Dictionary = state.get("comparison",{}).get("activation",{})
	if not activation.get("requirement","").is_empty(): tooltip_text += "\n発動条件："+activation.requirement+" / "+activation.reason
	if not is_node_ready(): return
	close_button.position = Vector2(size.x-46,8)
	close_button.size = Vector2(34,30)
	queue_redraw()
func _draw():
	draw_style_box(Style.style(Style.PANEL,Style.EDGE),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(16,30),"パラメータ  [Q]",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Style.GOLD)
	draw_string(font,Vector2(16,51),"現在値 (装備補正) (選択差)",HORIZONTAL_ALIGNMENT_LEFT,size.x-32,14,Style.MUTED)
	var comparison: Dictionary = state.get("comparison",{})
	var activation: Dictionary = comparison.get("activation",{})
	if comparison.get("selected",false) and not activation.get("requirement","").is_empty():
		draw_string(font,Vector2(202,29),"効果有効" if activation.active else "効果なし",HORIZONTAL_ALIGNMENT_LEFT,size.x-254,14,GOOD if activation.active else BAD)
	var metrics = visible_metrics()
	for i in range(metrics.size()):
		var key: String = metrics[i]
		var values: Dictionary = comparison.get("rows",{}).get(key,{})
		if values.is_empty(): continue
		var rect = metric_rect(i)
		var unit: String = Parameters.METRICS[key].unit
		draw_line(rect.position,rect.position+Vector2(rect.size.x,0),Style.EDGE)
		draw_string(font,rect.position+Vector2(0,14),LABELS[key]+(" "+unit if not unit.is_empty() else ""),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x,14,Style.MUTED)
		var texts = [Parameters.number(key,values.current),delta_text(key,values.bonus)]
		var colors = [Style.INK,delta_color(key,values.current,values.base)]
		if comparison.get("selected",false):
			texts.append(delta_text(key,values.change))
			colors.append(delta_color(key,values.after,values.current))
		var x = rect.position.x
		for j in range(texts.size()):
			draw_string(font,Vector2(x,rect.position.y+30),texts[j],HORIZONTAL_ALIGNMENT_LEFT,rect.end.x-x,14,colors[j])
			x += font.get_string_size(texts[j],HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+3
