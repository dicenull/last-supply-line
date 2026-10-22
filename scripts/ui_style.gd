extends RefCounted
## Shared visual resources; views do not need a game controller to draw themselves.
const BG = Color("171c18")
const PANEL = Color("2d342b")
const INK = Color("f2eddf")
const MUTED = Color("bdc0aa")
const GOLD = Color("e6bd73")
const MINT = Color("bfcca4")
const BLUE = Color("afc2ba")
const SURFACE = Color("20261f")
const EDGE = Color("68705a")
const DANGER = Color("f29c84")

var font: Font = ThemeDB.fallback_font
var pixel_icons = preload("res://scripts/pixel_icons.gd").new()

static func style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	if border.a > 0:
		s.set_border_width_all(2)
		s.border_color = border
	return s
