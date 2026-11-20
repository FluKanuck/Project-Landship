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
	v.add_child(UiTheme.label("MAINTENANCE TERMINAL // SETTINGS", 26, Pal.UI_HOT))
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


func _toggle(parent: Control, text: String, key: String) -> void:
	var b := UiTheme.button(text, true, 160)
	b.button_pressed = Prefs.get(key)
	b.toggled.connect(func(on): Prefs.set_value(key, on))
	parent.add_child(b)
