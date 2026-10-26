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
	var path = ProjectSettings.get_setting("gui/theme/custom.web")
	var theme: Theme = load(path)
	check(theme != null and theme.default_font is FontVariation,"Web has a project-wide bundled font theme")
	var font: FontVariation = theme.default_font
	check(font.variation_opentype.get(TextServerManager.get_primary_interface().name_to_tag("weight")) == 600.0,"theme uses the original 600 weight through the OpenType axis tag")
	check(font.base_font is FontFile and font.base_font.resource_path == "res://assets/fonts/NotoSansJP.ttf","theme loads bundled Noto Sans JP without OS fonts")
	var sample = "日本語 全画面を終了 装備一覧 解体 倉庫 廃材 石炭 砲弾 難易度 戦車 工廠 装甲 読み込み中"
	var glyphs = true
	var supported: String = font.base_font.get_supported_chars()
	for character in sample: glyphs = glyphs and character in supported
	check(glyphs,"bundled font contains Japanese glyphs for page, game and tooltips")
	var parent = Control.new()
	parent.theme = theme
	root.add_child(parent)
	for type in ["Label","Button","TooltipLabel"]:
		var label = Label.new()
		label.theme_type_variation = type
		label.text = sample
		parent.add_child(label)
		check(label.get_theme_font("font") == font,"standard UI inherits Japanese font: "+type)
	parent.free()
	print("RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
