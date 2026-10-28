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
# Minimum visible sizes in CSS pixels, independent of device pixel density.
const TEXT_MIN = 16
const CAPTION_MIN = 14
const HEADING_MIN = 24
const ICON_MIN = 24
const PRIMARY_ICON_SIZE = 32


var font: Font = ThemeDB.fallback_font
var pixel_icons = preload("res://scripts/pixel_icons.gd").new()

static func create_font() -> Font:
	if OS.has_feature("web"):
		return ThemeDB.get_project_theme().default_font
	var system_font = SystemFont.new()
	system_font.font_names = PackedStringArray(["Helvetica Neue","Hiragino Sans","sans-serif"])
	system_font.font_weight = 600
	# Menu frames scale independently of the viewport. MSDF keeps their glyphs
	# sharp at fractional scales instead of enlarging a small bitmap cache.
	system_font.multichannel_signed_distance_field = true
	system_font.msdf_size = 96
	return system_font

static func style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	if border.a > 0:
		s.set_border_width_all(2)
		s.border_color = border
	return s

static var density_frame = -1
static var cached_density = 1.0

static func pixel_density() -> float:
	if not OS.has_feature("web"): return 1.0
	var frame = Engine.get_process_frames()
	if frame != density_frame:
		density_frame = frame
		cached_density = maxf(0.1,float(JavaScriptBridge.eval("window.devicePixelRatio || 1.0")))
	return cached_density

static func screen_scale(view: CanvasItem) -> float:
	# Layout uses CSS pixels; rendering still uses all physical device pixels.
	return maxf(0.01,view.get_viewport().get_final_transform().get_scale().x/pixel_density())

static func screen_size(view: CanvasItem) -> Vector2:
	return Vector2(view.get_window().size)/pixel_density()

static func effective_scale(view: CanvasItem) -> float:
	var local_scale = view.get_global_transform_with_canvas().get_scale().abs()
	return maxf(0.01,screen_scale(view)*minf(local_scale.x,local_scale.y))

static func font_size(view: CanvasItem, requested: int, minimum: int = TEXT_MIN) -> int:
	return maxi(requested,ceili(minimum/effective_scale(view)))

static func icon_size(view: CanvasItem, requested: float = ICON_MIN) -> float:
	return maxf(requested,ICON_MIN/effective_scale(view))
