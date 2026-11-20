class_name Hud
extends CanvasLayer
## The only non-diegetic layer: a centre dot, the interaction hint, subtitles, a help card,
## and the fade at start-up.

var player: Player
var hint: Label
var sub: Label
var help: Label
var help_tag: Label
var help_panel: PanelContainer
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
	help_tag = _label(root, 18, Color(1, 0.85, 0.6, 0.9))
	help_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help_tag.position = Vector2(24, 20)
	_help_tag_text()
	# the full key card: a dark panel in the middle of the screen
	help_panel = PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.035, 0.025, 0.9)
	sb.border_color = Color(1, 0.7, 0.3, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(22)
	help_panel.add_theme_stylebox_override("panel", sb)
	help_panel.visible = false
	root.add_child(help_panel)
	help = Label.new()
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color(1, 0.85, 0.6, 0.95))
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.text = help_text()
	help_panel.add_child(help)
	Prefs.keys_changed.connect(func():
		help.text = help_text()
		_help_tag_text())
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
	tsub.text = "THE WEDGE  //  CLICK TO TAKE COMMAND  //  [%s] ALL KEYS" % Prefs.key_name("help")
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
		help_panel.visible = _help_on
		_help_tag_text()


func _help_tag_text() -> void:
	help_tag.text = "[%s] %s" % [Prefs.key_name("help"), "HIDE KEYS" if _help_on else "ALL KEYS"]


func _process(delta: float) -> void:
	_sub_t -= delta
	sub.modulate.a = clampf(_sub_t, 0.0, 1.0)
	dot.visible = not player.cursor_active() and player.mode in [Player.Mode.SEATED, Player.Mode.WALK]
	dot.queue_redraw()


## The keys card, filled with the current bindings (rebindable on the settings terminal).
static func help_text() -> String:
	var k := {}
	for b in Prefs.BINDABLE:
		k[b[0]] = Prefs.key_name(b[0])
	return HELP.format(k)


const HELP := """ALL KEYS                    {help} or [?] to close      rebind: settings terminal > CONTROLS
SEATED
  mouse             look around (the display stays where it is)
  ALT or {cursor_toggle}       toggle the cursor: use the display and the chair buttons
  {preset_1} {preset_2} {preset_3} {preset_4}           chair buttons: COMBAT / RECON / TRANSIT layouts, ACTION STATIONS
  drag a header     swap two display sections
  {interact}                 stand up
  ESC               cursor off (or free the mouse)
ORDERS  (tactical map or holo table)
  {select_1} {select_2} {select_3}          select SWIFT-1 / SWIFT-2 / LANDSHIP
  click a unit      select it
  left click        add a waypoint (uses the ACT and ROE you last picked)
  right click       remove the last waypoint
  LAUNCH / RTB      buttons on the tactical toolbar
  mouse wheel       tactical map: zoom
  drag the map      pan (left or middle button)
  {map_centre}                 tactical map: back to the whole operational area (CENTRE)
DRONE FEED  (gimbal camera, with the cursor on)
  drag              slew the camera (holds that compass direction)
  click a contact   lock on and track it
  click the ground  lock that spot
  right click       back to AUTO (or the AUTO button)
  {gimbal_auto}                 gimbal back to AUTO
  mouse wheel       camera zoom
  {thermal}                 thermal: off / white hot / ironbow (THERMAL button)
TIME
  {time_down}  or  -          slower      x64 > x16 > x4 > x1
  {time_up}  or  =          faster      (drops to x1 on any new contact)
WALKING
  {move_forward}{move_left}{move_back}{move_right} / arrows     walk        {run}  run
  {interact}                 sit in the chair / use the holo table / settings terminal
HOLO TABLE
  left click        select a unit, or order    right drag  pan    wheel  zoom
  {select_1} {select_2} {select_3}          unit        {interact} or ESC    step back
SETTINGS TERMINAL
  click             adjust      {interact} or ESC    step back"""
