extends SceneTree
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS Japanese font: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var path = ProjectSettings.get_setting("gui/theme/custom")
	var theme: Theme = load(path)
	var Style = preload("res://scripts/ui_style.gd")
	var font: Font = theme.default_font
	check(font == Style.create_font(),"native and Web share the bundled UI theme")
	check(font.resource_path.ends_with("BIZUDPGothic-Regular.ttf"),"body uses readable BIZ UDPGothic")
	check(Style.BOLD_FONT.resource_path.ends_with("BIZUDPGothic-Bold.ttf") and Style.HEADING_FONT.resource_path.ends_with("DelaGothicOne-Regular.ttf"),"controls and display titles have distinct font roles")
	for face in [font,Style.BOLD_FONT,Style.HEADING_FONT]:
		check(face.multichannel_signed_distance_field and face.msdf_size >= 96,"bundled fonts remain sharp when scaled")
	for family in ["BIZUDPGothic","DelaGothicOne"]:
		check(FileAccess.file_exists("res://assets/fonts/"+family+"-OFL.txt"),"bundled family includes its license")
	var sample = "日本語 全画面を終了 装備一覧 解体 倉庫 廃材 石炭 砲弾 難易度 戦車 工廠 装甲 読み込み中"
	var glyphs = true
	var supported: String = font.get_supported_chars()
	for character in sample: glyphs = glyphs and character in supported
	check(glyphs,"bundled font contains Japanese glyphs for page, game and tooltips")
	var parent = Control.new()
	parent.theme = theme
	root.add_child(parent)
	for type in ["Label","Button","TooltipLabel"]:
		var label = Button.new() if type == "Button" else Label.new()
		label.theme_type_variation = type
		label.text = sample
		parent.add_child(label)
		check(label.get_theme_font("font") == (Style.BOLD_FONT if type == "Button" else font),"standard UI inherits Japanese font: "+type)
	parent.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
