class_name Hud
extends CanvasLayer
## The only non-diegetic layer: a centre dot, the interaction hint, subtitles, a help card,
## and the fade at start-up.

var player: Player
var hint: Label
var sub: Label
var help: Label
var fade: ColorRect
var title: Label
var dot: Control
var _sub_t := 0.0
var _help_on := false


func _init(p: Player) -> void:
	player = p


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	dot = Control.new()
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.draw.connect(func(): dot.draw_circle(Vector2.ZERO, 2.5, Color(1, 0.85, 0.6, 0.7)))
	root.add_child(dot)
	hint = _label(root, 17, Color(1, 0.85, 0.6, 0.75))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -40
	hint.offset_bottom = -14
	sub = _label(root, 22, Color(1, 0.95, 0.85))
	sub.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sub.offset_top = -100
	sub.offset_bottom = -54
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("outline_size", 6)
	help = _label(root, 18, Color(1, 0.85, 0.6, 0.9))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.position = Vector2(24, 20)
	help.text = "[H] HELP"
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	title = _label(root, 44, Pal.UI_HOT)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.add_theme_font_override("font", UiTheme.font_head)
	title.text = "LANDSHIP"
	var tsub := _label(root, 20, Color(1, 0.8, 0.5, 0.8))
	tsub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tsub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tsub.position.y += 60
	tsub.text = "THE WEDGE  //  CLICK TO TAKE COMMAND"
	title.set_meta("sub", tsub)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.grow_vertical = Control.GROW_DIRECTION_BOTH
	player.hint_changed.connect(func(t): hint.text = t)
	Sfx.subtitle.connect(_on_sub)


func _label(root: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _on_sub(who: String, text: String) -> void:
	if not Prefs.subtitles:
		return
	sub.text = "%s:  %s" % [who, text]
	_sub_t = 4.5


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("help"):
		_help_on = not _help_on
		help.text = HELP if _help_on else "[H] HELP"


func _process(delta: float) -> void:
	_sub_t -= delta
	sub.modulate.a = clampf(_sub_t, 0.0, 1.0)
	dot.visible = not player.cursor_active() and player.mode in [Player.Mode.SEATED, Player.Mode.WALK]
	dot.queue_redraw()


const HELP := """[H] HIDE HELP
SEATED
  move mouse        look around (the display stays where it is)
  hold ALT / TAB    cursor: use the display and the chair buttons
  1 2 3 4           chair buttons: COMBAT / RECON / TRANSIT layouts, ACTION STATIONS
  drag a header     swap two display sections
  E                 stand up
ORDERS (tactical map or holo table)
  F1 F2 F3          select SWIFT-1 / SWIFT-2 / LANDSHIP
  left click        add waypoint (uses the ACT and ROE you last picked)
  right click       remove last waypoint
  LAUNCH / RTB      on the tactical toolbar
TIME
  , and .           slower / faster: x1 x4 x16 x64 (drops to x1 on new contacts)
WALKING
  WASD, SHIFT       walk, run      E   sit / use holo table / settings terminal"""
