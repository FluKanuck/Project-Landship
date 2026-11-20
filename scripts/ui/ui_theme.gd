class_name UiTheme
## Phosphor-amber theme for every in-world screen.

static var _theme: Theme
static var font: Font
static var font_head: Font


static func get_theme() -> Theme:
	if _theme:
		return _theme
	font = load("res://assets/fonts/ShareTechMono-Regular.ttf")
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Oxanium.ttf")
	fv.variation_opentype = {"wght": 600}
	font_head = fv
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 21
	for cls in ["Label", "Button", "CheckBox", "HSlider", "OptionButton"]:
		t.set_color("font_color", cls, Pal.UI_TEXT)
	t.set_color("font_hover_color", "Button", Pal.UI_HOT)
	t.set_color("font_pressed_color", "Button", Pal.UI_BG)
	t.set_color("font_hover_pressed_color", "Button", Pal.UI_BG)
	t.set_color("font_focus_color", "Button", Pal.UI_HOT)
	t.set_color("font_disabled_color", "Button", Color(Pal.UI_TEXT, 0.3))
	t.set_stylebox("normal", "Button", box(Color(0, 0, 0, 0.0), Pal.UI_DIM))
	t.set_stylebox("hover", "Button", box(Color(1, 0.7, 0.1, 0.08), Pal.UI_TEXT))
	t.set_stylebox("pressed", "Button", box(Pal.UI_TEXT, Pal.UI_TEXT))
	t.set_stylebox("hover_pressed", "Button", box(Pal.UI_HOT, Pal.UI_HOT))
	t.set_stylebox("disabled", "Button", box(Color(0, 0, 0, 0), Color(Pal.UI_DIM, 0.15)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var grab := StyleBoxFlat.new()
	grab.bg_color = Pal.UI_TEXT
	t.set_stylebox("slider", "HSlider", box(Color(1, 0.7, 0.1, 0.1), Pal.UI_DIM))
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var img := Image.create(18, 28, false, Image.FORMAT_RGBA8)
	img.fill(Pal.UI_HOT)
	var gt := ImageTexture.create_from_image(img)
	t.set_icon("grabber", "HSlider", gt)
	t.set_icon("grabber_highlight", "HSlider", gt)
	_theme = t
	return t


static func box(bg: Color, border: Color, w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func button(text: String, toggle := false, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.ui("beep"))
	return b


static func label(text: String, size := 21, col := Pal.UI_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Corner-bracket frame used by panels and markers.
static func brackets(ci: CanvasItem, r: Rect2, col: Color, len := 16.0, w := 2.0) -> void:
	var p := r.position
	var s := r.size
	for c in [[p, Vector2(1, 0), Vector2(0, 1)], [p + Vector2(s.x, 0), Vector2(-1, 0), Vector2(0, 1)],
			[p + Vector2(0, s.y), Vector2(1, 0), Vector2(0, -1)], [p + s, Vector2(-1, 0), Vector2(0, -1)]]:
		ci.draw_line(c[0], c[0] + c[1] * len, col, w)
		ci.draw_line(c[0], c[0] + c[2] * len, col, w)


static func dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, w := 1.5, dash := 10.0) -> void:
	var n := maxi(12, int(TAU * r / dash))
	for i in range(0, n, 2):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		ci.draw_line(c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, col, w)


static func dashed_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w := 2.0, dash := 10.0) -> void:
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var d := (b - a) / L
	var t := 0.0
	while t < L:
		ci.draw_line(a + d * t, a + d * minf(t + dash, L), col, w)
		t += dash * 2.0
