class_name SettingsUI
extends Node
## The game settings, on a maintenance terminal in the corner of the bridge (design doc:
## sixth screen, hiding off in the corner).

var viewport: SubViewport


func _ready() -> void:
	pass


func _init() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(760, 552)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = true
	add_child(viewport)
	var root := Control.new()
	root.size = Vector2(viewport.size)
	root.theme = UiTheme.get_theme()
	viewport.add_child(root)
	var bg := ColorRect.new()
	bg.color = Pal.UI_BG
	bg.size = root.size
	root.add_child(bg)
	var v := VBoxContainer.new()
	v.position = Vector2(30, 20)
	v.size = root.size - Vector2(60, 40)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title := UiTheme.label("MAINTENANCE TERMINAL", 24, Pal.UI_HOT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var gen := VBoxContainer.new()
	gen.add_theme_constant_override("separation", 10)
	var ctl := VBoxContainer.new()
	ctl.add_theme_constant_override("separation", 6)
	ctl.visible = false
	v.add_child(gen)
	v.add_child(ctl)
	var tab_g := UiTheme.button("SETTINGS", true, 130)
	var tab_c := UiTheme.button("CONTROLS", true, 130)
	tab_g.button_pressed = true
	tab_g.pressed.connect(func():
		gen.visible = true; ctl.visible = false
		tab_g.set_pressed_no_signal(true); tab_c.set_pressed_no_signal(false)
		Prefs.capturing = "")
	tab_c.pressed.connect(func():
		gen.visible = false; ctl.visible = true
		tab_g.set_pressed_no_signal(false); tab_c.set_pressed_no_signal(true))
	top.add_child(tab_g)
	top.add_child(tab_c)
	_controls(ctl)
	v = gen
	_slider(v, "MASTER VOLUME", "master", 0.0, 1.0)
	_slider(v, "VOICE", "voice", 0.0, 1.0)
	_slider(v, "AMBIENCE", "ambience", 0.0, 1.0)
	_slider(v, "MOUSE SENSITIVITY", "sensitivity", 0.3, 2.5)
	_slider(v, "FIELD OF VIEW", "fov", 60.0, 95.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_toggle(row, "INVERT Y", "invert_y")
	_toggle(row, "SUBTITLES", "subtitles")
	var q := UiTheme.button("QUALITY: " + ("HIGH" if Prefs.quality else "LOW"), false, 200)
	q.pressed.connect(func():
		Prefs.set_value("quality", 1 - Prefs.quality)
		q.text = "QUALITY: " + ("HIGH" if Prefs.quality else "LOW"))
	row.add_child(q)
	v.add_child(UiTheme.label("ESC / E TO STEP BACK.  HIGH QUALITY ADDS VOLUMETRIC DUST AND SSAO (DESKTOP).", 16, Pal.UI_DIM))
	if OS.get_name() != "Web":
		var quit := UiTheme.button("LEAVE THE BRIDGE (QUIT)", false, 300)
		quit.pressed.connect(func(): get_tree().quit())
		v.add_child(quit)


func _slider(parent: Control, text: String, key: String, lo: float, hi: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := UiTheme.label(text, 20)
	l.custom_minimum_size = Vector2(260, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = Prefs.get(key)
	s.custom_minimum_size = Vector2(300, 36)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var val := UiTheme.label("", 20, Pal.UI_HOT)
	val.custom_minimum_size = Vector2(70, 0)
	var fmt := func(x: float) -> String: return "%d" % int(x) if hi > 10.0 else "%d%%" % int(x * 100.0) if hi <= 1.0 else "%.1f" % x
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(x):
		Prefs.set_value(key, x)
		val.text = fmt.call(x))
	h.add_child(s)
	h.add_child(val)


## CONTROLS page: every rebindable action with its key. Click a key, then press the new one
## (ESC cancels). A key already in use swaps over to the other action.
var _key_btns := {}


func _controls(parent: Control) -> void:
	parent.add_child(UiTheme.label("CLICK A KEY, THEN PRESS THE NEW ONE.  ESC CANCELS.  A KEY IN USE SWAPS.", 15, Pal.UI_DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	parent.add_child(cols)
	var half := int(ceil(Prefs.BINDABLE.size() / 2.0))
	var col: VBoxContainer
	for i in Prefs.BINDABLE.size():
		if i % half == 0:
			col = VBoxContainer.new()
			col.add_theme_constant_override("separation", 4)
			cols.add_child(col)
		var action: String = Prefs.BINDABLE[i][0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var l := UiTheme.label(Prefs.BINDABLE[i][1], 16)
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var b := UiTheme.button("", false, 110)
		b.custom_minimum_size.y = 34
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			Prefs.capturing = action
			_refresh_keys())
		row.add_child(b)
		_key_btns[action] = b
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	parent.add_child(bottom)
	var reset := UiTheme.button("RESET TO DEFAULTS", false, 220)
	reset.custom_minimum_size.y = 34
	reset.pressed.connect(func():
		Prefs.capturing = ""
		Prefs.reset_keys())
	bottom.add_child(reset)
	bottom.add_child(UiTheme.label("FIXED: ESC, ALT CURSOR TAP, ARROWS, = -", 15, Pal.UI_DIM))
	Prefs.keys_changed.connect(_refresh_keys)
	_refresh_keys()


func _refresh_keys() -> void:
	for a in _key_btns:
		var b: Button = _key_btns[a]
		if Prefs.capturing == a:
			b.text = "PRESS KEY"
			b.add_theme_color_override("font_color", Pal.UI_WARN)
		else:
			b.text = Prefs.key_name(a)
			b.remove_theme_color_override("font_color")


func _toggle(parent: Control, text: String, key: String) -> void:
	var b := UiTheme.button(text, true, 160)
	b.button_pressed = Prefs.get(key)
	b.toggled.connect(func(on): Prefs.set_value(key, on))
	parent.add_child(b)
