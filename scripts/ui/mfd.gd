class_name MFD
extends Control
## The command display layout. Sections snap to a grid of halves and quarters; presets are
## switched with the physical buttons on the chair; dragging a section's header onto
## another section swaps them (design doc: Command screens > Display).

signal preset_changed(name: String)

const STRIP := 40.0
const GAP := 8.0
const PRESETS := {
	"COMBAT": {"tactical": Rect2(0, 0, 0.58, 1), "feed": Rect2(0.58, 0, 0.42, 0.56), "contacts": Rect2(0.58, 0.56, 0.42, 0.44)},
	"RECON": {"feed": Rect2(0, 0, 0.6, 1), "tactical": Rect2(0.6, 0, 0.4, 0.62), "comms": Rect2(0.6, 0.62, 0.4, 0.38)},
	"TRANSIT": {"tactical": Rect2(0, 0, 0.5, 1), "helm": Rect2(0.5, 0, 0.5, 0.5), "extcam": Rect2(0.5, 0.5, 0.25, 0.5), "comms": Rect2(0.75, 0.5, 0.25, 0.5)},
	"LOGISTICS": {"tactical": Rect2(0, 0, 0.52, 1), "logistics": Rect2(0.52, 0, 0.48, 0.64), "comms": Rect2(0.52, 0.64, 0.48, 0.36)},
	"FITTING": {"fitting": Rect2(0, 0, 0.55, 1), "tactical": Rect2(0.55, 0, 0.45, 0.58), "logistics": Rect2(0.55, 0.58, 0.45, 0.42)},
}
const TITLES := {
	"tactical": "TACTICAL", "feed": "DRONE FEED", "contacts": "SENSORS / CONTACTS",
	"helm": "HELM / TIME", "comms": "COMMS LOG", "extcam": "FWD CAMERA",
	"logistics": "LOGISTICS", "fitting": "FITTING",
}

var frames := {}
var layout := {}
var preset := "COMBAT"
var world: WorldView
var _t := 0.0
var _alarm := 0.0
var _alarm_text := ""


func _ready() -> void:
	theme = UiTheme.get_theme()
	size = Vector2(CmdProjection.RES)
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(w: WorldView) -> void:
	world = w
	var builders := {
		"tactical": func(): return TacticalPanel.new(),
		"feed": func(): return FeedPanel.new(w),
		"contacts": func(): return ContactsPanel.new(),
		"helm": func(): return HelmPanel.new(),
		"comms": func(): return CommsPanel.new(),
		"extcam": func(): return ExtCamPanel.new(w),
		"logistics": func(): return LogisticsPanel.new(),
		"fitting": func(): return FittingPanel.new(),
	}
	for k in builders:
		var f := PanelFrame.new(k, TITLES[k], builders[k].call())
		f.drag_released.connect(_on_drag)
		add_child(f)
		frames[k] = f
	apply_preset("COMBAT", false)
	Sim.event.connect(_on_event)


func _on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"contact_new":
			_alarm = 3.0
			_alarm_text = "%s  BRG %03d  RNG %.1f KM" % ["MULTIPLE CONTACTS" if data.get("count", 1) > 1 else "NEW CONTACT", int(data.bearing), data.range / 1000.0]
			for k in ["tactical", "contacts"]:
				frames[k].flash = 1.2
		"node_found":
			_alarm = 4.0
			_alarm_text = "ALIEN STRUCTURE  BRG %03d" % int(data.bearing)
		"under_fire", "breaking_off", "drone_lost":
			_alarm = 2.5
			_alarm_text = "%s %s" % [data.drone.callsign, {"under_fire": "UNDER FIRE", "breaking_off": "BREAKING OFF", "drone_lost": "LOST"}[kind]]
			if frames.has("feed"):
				frames["feed"].flash = 1.2
		"link_lost":
			_alarm = 2.0
			_alarm_text = "LINK LOST  %s  ORDERS LOCKED" % data.drone.callsign
		"structure_attacked":
			_alarm = 3.0
			_alarm_text = ("%s UNDER ATTACK" % data.site.name) if data.site else ("%s UNDER ATTACK" % data.s.name())
			_flash(["logistics", "tactical"])
		"structure_lost":
			_alarm = 3.0
			_alarm_text = ("%s: %s LOST" % [data.site.name, Logi.KIND_NAMES[data.s.kind]]) if data.site else ("%s LOST: NETWORK CUT" % data.s.name())
			_flash(["logistics", "tactical"])
		"veh_lost":
			_alarm = 2.5
			_alarm_text = "%s LOST" % data.veh.callsign
			_flash(["logistics"])
		"veh_fire", "veh_breaking":
			_alarm = 2.0
			_alarm_text = "%s UNDER FIRE" % data.veh.callsign
		"hub_dark":
			_alarm = 2.0
			_alarm_text = "%s GONE DARK" % data.site.name
		"alien_outpost":
			if data.seen:
				_alarm = 3.5
				_alarm_text = "ALIEN OUTPOST AT %s" % data.site.name
		"objective":
			_alarm = 2.5
			_alarm_text = "OBJECTIVE: " + data.text


func _flash(keys: Array) -> void:
	for k in keys:
		if frames.has(k):
			frames[k].flash = 1.2


func apply_preset(name: String, animate := true) -> void:
	if not PRESETS.has(name):
		return
	preset = name
	layout = PRESETS[name].duplicate()
	_apply(animate)
	preset_changed.emit(name)


func _area() -> Rect2:
	return Rect2(Vector2(GAP, STRIP + GAP), size - Vector2(GAP * 2, STRIP + GAP * 2))


func _px(r: Rect2) -> Rect2:
	var a := _area()
	return Rect2(a.position + r.position * a.size + Vector2(GAP, GAP) * 0.5,
		r.size * a.size - Vector2(GAP, GAP))


func _apply(animate: bool) -> void:
	for k in frames:
		var f: PanelFrame = frames[k]
		if layout.has(k):
			var target := _px(layout[k])
			var was_hidden := not f.visible
			f.visible = true
			f.process_mode = Node.PROCESS_MODE_INHERIT
			if animate and not was_hidden:
				var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(f, "position", target.position, 0.35)
				tw.tween_property(f, "size", target.size, 0.35)
			else:
				f.position = target.position
				f.size = target.size
				if animate:
					f.modulate.a = 0.0
					create_tween().tween_property(f, "modulate:a", 1.0, 0.3)
			f.flash = 0.6 if animate else 0.0
		else:
			f.visible = false
			f.process_mode = Node.PROCESS_MODE_DISABLED
		if f.content.has_method("set_active"):
			f.content.set_active(layout.has(k))


func _on_drag(frame: PanelFrame, at: Vector2) -> void:
	for k in frames:
		var other: PanelFrame = frames[k]
		if other == frame or not other.visible:
			continue
		if Rect2(other.position, other.size).has_point(at):
			var a: Rect2 = layout[frame.key]
			layout[frame.key] = layout[k]
			layout[k] = a
			preset = "CUSTOM"
			Sfx.ui("ok")
			_apply(true)
			return
	# dropped on empty space: nothing changes


func swap_in(key: String) -> void:
	# put `key` in the biggest section of the current layout (used by hotkeys)
	if layout.has(key):
		return
	var biggest := ""
	var area := 0.0
	for k in layout:
		var r: Rect2 = layout[k]
		if r.get_area() > area:
			area = r.get_area()
			biggest = k
	layout[key] = layout[biggest]
	layout.erase(biggest)
	preset = "CUSTOM"
	_apply(true)


func _strip(f: Font, x: float, text: String, col: Color, sz: int) -> float:
	draw_string(f, Vector2(x, 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


func _process(delta: float) -> void:
	_t += delta
	_alarm = maxf(0.0, _alarm - delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Pal.UI_BG)
	# top status strip
	draw_rect(Rect2(0, 0, size.x, STRIP), Color(1, 0.69, 0, 0.1))
	draw_line(Vector2(0, STRIP), Vector2(size.x, STRIP), Pal.UI_LINE, 2)
	var f := UiTheme.font
	var hf := UiTheme.font_head
	var x := 14.0
	x = _strip(hf, x, "LANDSHIP // COMMAND", Pal.UI_HOT, 22) + 26
	x = _strip(f, x, Sim.clock_text(), Pal.UI_TEXT, 22) + 22
	var tc := Sim.time_scale()
	x = _strip(f, x, "TIME x%d" % tc, Pal.UI_WARN if tc > 1 else Pal.UI_TEXT, 22) + 22
	var sel := Sim.selected_name()
	x = _strip(f, x, "CMD " + sel, Pal.UI_FRIEND, 22) + 22
	var live := 0
	var ghosts := 0
	for c in Sim.contacts.values():
		if c.live:
			live += 1
		else:
			ghosts += 1
	x = _strip(f, x, "CONTACTS %d/%d" % [live, ghosts], Pal.UI_ENEMY if live > 0 else Pal.UI_TEXT, 22) + 20
	var st := Sim.stores
	x = _strip(f, x, "F %d" % int(st.fuel), Pal.UI_TEXT if st.frac(0) > 0.2 else Pal.UI_ENEMY, 22) + 12
	x = _strip(f, x, "M %d" % int(st.mat), Pal.UI_TEXT if st.mat > 30 else Pal.UI_WARN, 22) + 20
	x = _strip(f, x, preset, Pal.UI_DIM, 20) + 20
	# objective, right-hand end of the strip
	var obj := "OBJ: " + Sim.objective()
	var ow := f.get_string_size(obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	if not Sim.alert and x + ow < size.x - 10:
		draw_string(f, Vector2(size.x - ow - 14, 27), obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Pal.UI_DIM)
	# the jolt: a red banner and frame pulse when something happens out there
	if _alarm > 0.0:
		var a := clampf(_alarm, 0.0, 1.0) * (0.55 + 0.45 * sin(_t * 14.0))
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(1, 0.25, 0.15, a), false, 4.0)
		var bw := hf.get_string_size(_alarm_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 40
		var br := Rect2(Vector2(size.x * 0.5 - bw * 0.5, STRIP + 14), Vector2(bw, 40))
		draw_rect(br, Color(0.25, 0.04, 0.02, 0.92 * clampf(_alarm, 0.0, 1.0)))
		draw_rect(br, Color(1, 0.35, 0.2, clampf(_alarm, 0.0, 1.0)), false, 2.0)
		draw_string(hf, br.position + Vector2(20, 29), _alarm_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.55, 0.4, clampf(_alarm, 0.0, 1.0)))
	if Sim.alert:
		var blink := 0.5 + 0.5 * sin(_t * 8.0)
		draw_rect(Rect2(size.x - 300, 4, 290, STRIP - 8), Color(1, 0.2, 0.1, 0.2 + 0.3 * blink))
		draw_string(hf, Vector2(size.x - 286, 29), "ACTION STATIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Pal.UI_ENEMY)
	else:
		pass
