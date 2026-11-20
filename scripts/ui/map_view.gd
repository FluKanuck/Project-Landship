class_name MapView
extends Control
## North-up map of the operational area with every overlay the commander needs: sensor and
## link coverage, the carrier and its course, drones and their waypoint chains coloured by
## rules of engagement, live contacts, fading ghost markers with their age, and predicted
## positions of drones that are out of contact.

signal clicked_world(p: Vector2, button: int)

var centre := Vector2.ZERO
var span := 7000.0 # metres across the height of the view
var auto_follow := true
var zoom := 1.0 # player zoom inside the operational area (1 = whole area)
var hover := Vector2(-1, -1)
var bg: ColorRect
var mat: ShaderMaterial
var _t := 0.0
## Centre follows the operational area until the commander pans; CENTRE puts it back.
var follow := true
var centre_btn: Button
var _press = null # left button down position (null when up)
var _dragging := false
var _mid_drag := false
const DRAG_PX := 6.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/tactical_map.gdshader")
	mat.set_shader_parameter("height_tex", Sim.height_tex)
	mat.set_shader_parameter("coarse_tex", Sim.coarse_tex)
	mat.set_shader_parameter("know_tex", Sim.know_tex)
	mat.set_shader_parameter("feat_tex", Sim.feature_tex)
	bg = ColorRect.new()
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	bg.show_behind_parent = true
	centre_btn = UiTheme.button("CENTRE", false, 0)
	centre_btn.add_theme_font_size_override("font_size", 16)
	centre_btn.tooltip_text = "Back to the whole operational area"
	centre_btn.pressed.connect(recentre)
	centre_btn.visible = false
	add_child(centre_btn)


func recentre() -> void:
	follow = true
	zoom = 1.0


func _pan(px: Vector2) -> void:
	follow = false
	centre -= px * (span / maxf(size.y, 1.0))
	centre = centre.clamp(Vector2.ONE * -Terrain.HALF, Vector2.ONE * Terrain.HALF)


## Operational area: the carrier's sensor radius stretched to cover every linked drone.
func operational_area() -> Rect2:
	var c := Sim.carrier.pos2()
	var r := Rect2(c - Vector2.ONE * CarrierSim.SENSOR_RANGE, Vector2.ONE * CarrierSim.SENSOR_RANGE * 2.0)
	for d in Sim.drones:
		if d.airborne() and d.link != DroneSim.Link.LOST:
			var s := d.sensor_range()
			r = r.merge(Rect2(d.pos2() - Vector2.ONE * s, Vector2.ONE * s * 2.0))
		for w in d.plan:
			if d.airborne() and d.link != DroneSim.Link.LOST:
				r = r.expand(w.pos)
	return r.grow(250.0)


func _process(delta: float) -> void:
	_t += delta
	if auto_follow and size.y > 0:
		var a := operational_area()
		var aspect := size.x / size.y
		var want_span := maxf(a.size.y, a.size.x / aspect)
		want_span = clampf(want_span, 4500.0, 11000.0) / zoom
		var want_c := a.get_center() if (follow and zoom <= 1.01) else centre
		span = lerpf(span, want_span, clampf(delta * 3.0, 0.0, 1.0))
		centre = centre.lerp(want_c, clampf(delta * 3.0, 0.0, 1.0))
	centre_btn.visible = not follow or zoom > 1.01
	centre_btn.text = "%s CENTRE" % Prefs.key_name("map_centre")
	centre_btn.position = size - centre_btn.size - Vector2(10, 10) # bottom right
	mat.set_shader_parameter("centre", centre)
	mat.set_shader_parameter("span", span)
	mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	mat.set_shader_parameter("alert", 1.0 if Sim.alert else 0.0)
	queue_redraw()


func w2p(p: Vector2) -> Vector2:
	return size * 0.5 + (p - centre) * (size.y / span)


func p2w(p: Vector2) -> Vector2:
	return centre + (p - size * 0.5) * (span / size.y)


func m2px(m: float) -> float:
	return m * size.y / span


## Left click: order / select (on release, so a drag can pan instead). Left or middle drag:
## pan. Right click: undo. Wheel: zoom.
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover = ev.position
		if _press != null and not _dragging and ev.position.distance_to(_press) > DRAG_PX:
			_dragging = true
		if _dragging or _mid_drag:
			_pan(ev.relative)
			accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press = ev.position
			_dragging = false
		else:
			if _press != null and not _dragging:
				clicked_world.emit(p2w(ev.position), MOUSE_BUTTON_LEFT)
			_press = null
			_dragging = false
		accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_MIDDLE:
		_mid_drag = ev.pressed
		accept_event()
	elif ev is InputEventMouseButton and ev.pressed:
		match ev.button_index:
			MOUSE_BUTTON_RIGHT:
				clicked_world.emit(p2w(ev.position), ev.button_index)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				zoom = clampf(zoom * 1.2, 1.0, 4.0)
				centre = centre.lerp(p2w(ev.position), 0.25)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clampf(zoom / 1.2, 1.0, 4.0)
				accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = Vector2(-1, -1)


# ------------------------------------------------------------------ overlays

func _draw() -> void:
	var f := UiTheme.font
	var c2 := Sim.carrier.pos2()
	var cp := w2p(c2)
	# link range and sensor coverage
	UiTheme.dashed_circle(self, cp, m2px(Sim.LINK_MAX), Color(Pal.UI_FRIEND, 0.25), 1.5, 6.0)
	draw_string(f, cp + Vector2(m2px(Sim.LINK_MAX) * 0.7, -m2px(Sim.LINK_MAX) * 0.7), "LINK LIMIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Pal.UI_FRIEND, 0.45))
	_coverage(cp, m2px(CarrierSim.SENSOR_RANGE), Color(Pal.UI_TEXT, 0.06), Color(Pal.UI_TEXT, 0.35))
	for d in Sim.drones:
		if d.airborne() and d.link != DroneSim.Link.LOST:
			_coverage(w2p(d.pos2()), m2px(d.sensor_range()), Color(Pal.UI_FRIEND, 0.05), Color(Pal.UI_FRIEND, 0.3))
	# alien structure
	if Sim.node_found:
		var np := w2p(Terrain.CAMP)
		draw_circle(np, 13, Color(Pal.UI_ENEMY, 0.25))
		var tri := PackedVector2Array([np + Vector2(0, -10), np + Vector2(9, 7), np + Vector2(-9, 7), np + Vector2(0, -10)])
		draw_polyline(tri, Pal.UI_ENEMY, 2)
		draw_string(f, np + Vector2(16, 5), "RECHARGE NODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_ENEMY)
	# carrier course
	if not Sim.carrier.course.is_empty():
		var prev := cp
		for i in Sim.carrier.course.size():
			var q := w2p(Sim.carrier.course[i])
			UiTheme.dashed_line(self, prev, q, Color(Pal.UI_TEXT, 0.8), 2.0, 8.0)
			draw_rect(Rect2(q - Vector2(6, 6), Vector2(12, 12)), Pal.UI_TEXT, false, 2.0)
			draw_string(f, q + Vector2(9, -8), "C%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Pal.UI_TEXT)
			prev = q
	_carrier_icon(cp)
	# drones (or their predicted positions when we cannot hear them)
	for d in Sim.drones:
		if d.state in [DroneSim.State.REBUILD]:
			continue
		var lost := d.airborne() and d.link == DroneSim.Link.LOST
		var src: DroneSim = Sim.shadows.get(d.id, d) if lost else d
		_plan(src, lost)
		if d.airborne() or d.state == DroneSim.State.DESTROYED:
			_drone_icon(src, lost)
	# contacts and ghosts
	for c in Sim.contacts.values():
		_contact(c)
	_hover_readout()
	_scale_bar()
	# north arrow
	var na := Vector2(size.x - 30, 34)
	draw_colored_polygon(PackedVector2Array([na + Vector2(0, -16), na + Vector2(7, 6), na + Vector2(-7, 6)]), Pal.UI_TEXT)
	draw_string(f, na + Vector2(-5, 26), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_TEXT)


func _coverage(p: Vector2, r: float, fill: Color, line: Color) -> void:
	draw_circle(p, r, fill)
	draw_arc(p, r, 0, TAU, 96, line, 1.5)


func _carrier_icon(p: Vector2) -> void:
	var h := Sim.carrier.heading
	var fwd := Vector2(sin(h), -cos(h))
	var rt := Vector2(-fwd.y, fwd.x)
	var L := maxf(m2px(180.0), 16.0)
	var W := maxf(m2px(55.0), 7.0)
	var pts := PackedVector2Array([p + fwd * L, p + fwd * L * 0.6 + rt * W, p - fwd * L + rt * W, p - fwd * L - rt * W, p + fwd * L * 0.6 - rt * W])
	draw_colored_polygon(pts, Color(Pal.UI_TEXT, 0.35))
	pts.append(pts[0])
	draw_polyline(pts, Pal.UI_HOT, 2.0)
	draw_line(p + fwd * L, p + fwd * (L + 26), Pal.UI_HOT, 2.0)
	if Sim.selected == -1:
		UiTheme.brackets(self, Rect2(p - Vector2(L + 8, L + 8), Vector2(L + 8, L + 8) * 2), Pal.UI_HOT, 10, 2)
	draw_string(UiTheme.font, p + Vector2(L + 10, L * 0.5 + 10), "LANDSHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_HOT)


func _plan(d: DroneSim, lost: bool) -> void:
	if not d.airborne() and d.plan.is_empty():
		return
	var prev := w2p(d.pos2()) if d.airborne() else w2p(Sim.carrier.pos2())
	var start := d.wp if d.airborne() else 0
	for i in range(start, d.plan.size()):
		var w: Dictionary = d.plan[i]
		var q := w2p(w.pos)
		var col: Color = Pal.ROE_COLORS[w.roe]
		if lost:
			col.a = 0.45
		if lost:
			UiTheme.dashed_line(self, prev, q, col, 2.0, 7.0)
		else:
			draw_line(prev, q, col, 2.5 if Sim.selected == d.id else 1.5)
		_waypoint_glyph(q, w, col, i)
		prev = q


func _waypoint_glyph(q: Vector2, w: Dictionary, col: Color, i: int) -> void:
	match w.act:
		DroneSim.Act.MOVE:
			draw_arc(q, 6, 0, TAU, 16, col, 2.0)
		DroneSim.Act.LOIT:
			draw_arc(q, 6, 0, TAU, 16, col, 2.0)
			draw_arc(q, m2px(450.0), 0, TAU, 48, Color(col, 0.5), 1.0)
		DroneSim.Act.SCAN:
			draw_polyline(PackedVector2Array([q + Vector2(0, -8), q + Vector2(8, 0), q + Vector2(0, 8), q + Vector2(-8, 0), q + Vector2(0, -8)]), col, 2.0)
			UiTheme.dashed_circle(self, q, m2px(650.0), Color(col, 0.5), 1.0, 5.0)
	draw_string(UiTheme.font, q + Vector2(9, -7), "%d %s" % [i + 1, Pal.ACT_NAMES[w.act]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _drone_icon(d: DroneSim, predicted: bool) -> void:
	var p := w2p(d.pos2())
	var fwd := Vector2(sin(d.heading), -cos(d.heading))
	var rt := Vector2(-fwd.y, fwd.x)
	var col := Pal.UI_FRIEND
	if d.state == DroneSim.State.DESTROYED:
		col = Color(Pal.UI_ENEMY, 0.8)
	var pts := PackedVector2Array([p + fwd * 13, p - fwd * 8 + rt * 9, p - fwd * 3, p - fwd * 8 - rt * 9, p + fwd * 13])
	if predicted:
		col.a = 0.6
		for i in pts.size() - 1:
			UiTheme.dashed_line(self, pts[i], pts[i + 1], col, 2.0, 4.0)
		draw_arc(p, 18 + 3 * sin(_t * 3.0), 0, TAU, 24, Color(col, 0.35), 1.0)
	else:
		draw_colored_polygon(pts, Color(col, 0.35))
		draw_polyline(pts, col, 2.0)
	if Sim.selected == d.id:
		UiTheme.brackets(self, Rect2(p - Vector2(20, 20), Vector2(40, 40)), Pal.UI_HOT, 8, 2)
	var label := d.callsign
	if predicted:
		label += "  PRED (NO LINK)"
	elif d.state == DroneSim.State.DESTROYED:
		label += "  LOST"
	elif d.under_fire > 0.0:
		label += "  UNDER FIRE"
	draw_string(UiTheme.font, p + Vector2(16, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


func _contact(c: Dictionary) -> void:
	var p := w2p(Vector2(c.pos.x, c.pos.z))
	var name := ("R-%d" if c["class"] == "RAIDER" else "H-%d") % (c.id + 1)
	var d := PackedVector2Array([p + Vector2(0, -9), p + Vector2(9, 0), p + Vector2(0, 9), p + Vector2(-9, 0), p + Vector2(0, -9)])
	if c.live:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_colored_polygon(d, Color(Pal.UI_ENEMY, 0.55 + 0.3 * pulse))
		draw_polyline(d, Pal.UI_ENEMY, 2.0)
		var v := Vector2(c.vel.x, c.vel.z)
		if v.length() > 2.0:
			draw_line(p, p + v.normalized() * m2px(v.length() * 45.0), Pal.UI_ENEMY, 1.5)
		draw_string(UiTheme.font, p + Vector2(12, -8), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_ENEMY)
	else:
		var age: float = Sim.game_time - c.last
		var a := clampf(1.0 - age / Sim.GHOST_FADE, 0.15, 1.0)
		var col := Color(Pal.UI_GHOST, Pal.UI_GHOST.a * a)
		draw_polyline(d, col, 1.5)
		draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 1.0)
		draw_string(UiTheme.font, p + Vector2(12, -8), "%s +%s" % [name, Sim.age_text(age)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _hover_readout() -> void:
	if hover.x < 0:
		return
	var w := p2w(hover)
	var c := Sim.carrier.pos2()
	var col := Color(Pal.UI_HOT, 0.6)
	draw_line(Vector2(hover.x, 0), Vector2(hover.x, size.y), Color(col, 0.25), 1.0)
	draw_line(Vector2(0, hover.y), Vector2(size.x, hover.y), Color(col, 0.25), 1.0)
	draw_arc(hover, 10, 0, TAU, 16, col, 1.5)
	var txt := "BRG %03d  RNG %.2f KM" % [int(Terrain.bearing_deg(c, w)), c.distance_to(w) / 1000.0]
	var known := Sim.known_at(w)
	txt += "  ELEV %dm%s" % [int(Sim.terrain.height_at(w.x, w.y)), "" if known > 0.3 else " (SURVEY)"]
	var at := hover + Vector2(16, -14)
	if at.x > size.x - 360:
		at.x = hover.x - 370
	draw_rect(Rect2(at - Vector2(4, 18), Vector2(360, 24)), Color(0, 0, 0, 0.7))
	draw_string(UiTheme.font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_HOT)


func _scale_bar() -> void:
	var km := m2px(1000.0)
	var o := Vector2(16, size.y - 18)
	draw_line(o, o + Vector2(km, 0), Pal.UI_TEXT, 2)
	draw_line(o, o + Vector2(0, -8), Pal.UI_TEXT, 2)
	draw_line(o + Vector2(km, 0), o + Vector2(km, -8), Pal.UI_TEXT, 2)
	draw_string(UiTheme.font, o + Vector2(km + 8, 4), "1 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Pal.UI_TEXT)
