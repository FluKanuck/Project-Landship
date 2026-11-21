class_name MapView
extends Control
## North-up map of the operational area with every overlay the commander needs: sensor and
## link coverage, the carrier and its course, drones and their waypoint chains coloured by
## rules of engagement, live contacts, fading ghost markers with their age, and predicted
## positions of drones that are out of contact. And the supply war: resource sites and
## who holds them, hub parts, the link network of relays, scanner coverage, haulers and
## lifters with their routes and cargo, and the crane's reach when planting.

signal clicked_world(p: Vector2, button: int)

var centre := Vector2.ZERO
var span := 7000.0 # metres across the height of the view
var auto_follow := true
var zoom := 1.0 # player zoom inside the operational area (1 = whole area)
var hover := Vector2(-1, -1)
var bg: ColorRect
var mat: ShaderMaterial
var _t := 0.0
var plant_kind := -1 # landship crane tool: kit kind to preview, -1 when off


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


## Operational area: the carrier's sensor radius stretched to cover every linked drone.
func operational_area() -> Rect2:
	var c := Sim.carrier.pos2()
	var r := Rect2(c - Vector2.ONE * Sim.carrier_sensor(), Vector2.ONE * Sim.carrier_sensor() * 2.0)
	for d in Sim.drones:
		if d.airborne() and d.link != DroneSim.Link.LOST:
			var s := d.sensor_range()
			r = r.merge(Rect2(d.pos2() - Vector2.ONE * s, Vector2.ONE * s * 2.0))
		for w in d.plan:
			if d.airborne() and d.link != DroneSim.Link.LOST:
				r = r.expand(w.pos)
	for v in Sim.vehicles:
		if v.is_out() and v.link != DroneSim.Link.LOST:
			r = r.expand(v.pos2())
	for s in Sim.hubs():
		r = r.expand(s.pos)
	return r.grow(350.0)


func _process(delta: float) -> void:
	_t += delta
	if auto_follow and size.y > 0:
		var a := operational_area()
		var aspect := size.x / size.y
		var want_span := maxf(a.size.y, a.size.x / aspect)
		want_span = clampf(want_span, 4500.0, 11000.0) / zoom
		var want_c := a.get_center() if zoom <= 1.01 else centre
		span = lerpf(span, want_span, clampf(delta * 3.0, 0.0, 1.0))
		centre = centre.lerp(want_c, clampf(delta * 3.0, 0.0, 1.0))
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


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover = ev.position
	elif ev is InputEventMouseButton and ev.pressed:
		match ev.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
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
	var lr := Sim.link_range()
	UiTheme.dashed_circle(self, cp, m2px(lr), Color(Pal.UI_FRIEND, 0.25), 1.5, 6.0)
	draw_string(f, cp + Vector2(m2px(lr) * 0.7, -m2px(lr) * 0.7), "LINK LIMIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Pal.UI_FRIEND, 0.45))
	_coverage(cp, m2px(Sim.carrier_sensor()), Color(Pal.UI_TEXT, 0.06), Color(Pal.UI_TEXT, 0.35))
	_network()
	_sites()
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
	if plant_kind >= 0 and Sim.selected == -1:
		_crane_reach(cp)
	for v in Sim.vehicles:
		_vehicle(v)
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


# ------------------------------------------------------------------ the supply war

func _network() -> void:
	var f := UiTheme.font
	for e in Sim.net.edges:
		UiTheme.dashed_line(self, w2p(e[0]), w2p(e[1]), Color(Pal.UI_FRIEND, 0.55), 1.5, 5.0)
	for n in Sim.net.nodes:
		if n.src != null:
			UiTheme.dashed_circle(self, w2p(n.pos), m2px(n.range), Color(Pal.UI_FRIEND, 0.16), 1.0, 7.0)
	for s in Sim.structures:
		if s.kind == Logi.Kind.SCANNER and s.online() and not s.is_alien():
			var col := Color(Pal.UI_FRIEND, 0.04 if s.linked else 0.0)
			draw_circle(w2p(s.pos), m2px(s.sensor_range()), col)
			draw_arc(w2p(s.pos), m2px(s.sensor_range()), 0, TAU, 72, Color(Pal.UI_FRIEND if s.linked else Pal.UI_DIM, 0.3), 1.0)
	for s in Sim.structures:
		if s.dead or s.is_alien():
			continue
		_structure(s)


func _structure(s: StructureSim) -> void:
	var p := w2p(s.pos)
	var col := Pal.UI_FRIEND if s.linked else Color(Pal.UI_DIM, 0.8)
	if s.build < 1.0:
		col.a = 0.55
	var r := 6.0
	match s.kind:
		Logi.Kind.EXTRACTOR:
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2), col, false, 2.0)
			draw_line(p + Vector2(0, -r), p + Vector2(0, r), col, 2.0)
		Logi.Kind.TURRET:
			draw_arc(p, r, 0, TAU, 16, col, 2.0)
			draw_line(p, p + Vector2(r + 5, -r - 3), col, 2.0)
		Logi.Kind.PAD:
			draw_rect(Rect2(p - Vector2(r + 3, 3), Vector2(r * 2 + 6, 6)), col, false, 2.0)
		Logi.Kind.RELAY:
			draw_polyline(PackedVector2Array([p + Vector2(-7, 7), p + Vector2(0, -9), p + Vector2(7, 7)]), col, 2.0)
			draw_line(p + Vector2(-4, -4), p + Vector2(4, -4), col, 1.5)
			draw_string(UiTheme.font, p + Vector2(10, 4), "RELAY" + ("" if s.linked or s.build < 1.0 else " DARK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		Logi.Kind.SCANNER:
			draw_arc(p, r, 0, TAU, 16, col, 2.0)
			draw_circle(p, 2.5, col)
			draw_arc(p, r + 4, -0.6, 0.6, 8, col, 1.5)
			draw_string(UiTheme.font, p + Vector2(10, 4), "SCANNER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	if s.build < 1.0:
		draw_string(UiTheme.font, p + Vector2(-12, 20), "%d%%" % int(s.build * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	elif s.hp < s.max_hp:
		draw_line(p + Vector2(-8, 11), p + Vector2(-8 + 16.0 * s.hp / s.max_hp, 11), Pal.UI_WARN, 2.0)


func _hex(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 7:
		var a := TAU * i / 6.0 + PI / 6.0
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	return pts


func _sites() -> void:
	var f := UiTheme.font
	for s in Sim.sites:
		if not s.discovered:
			continue
		var p := w2p(s.pos)
		var owner := s.owner if (s.linked or s.owner != Logi.Owner.PLAYER) else s.known_owner
		var col := Pal.UI_TEXT
		if owner == Logi.Owner.PLAYER:
			col = Pal.UI_FRIEND if s.linked else Color(Pal.UI_FRIEND, 0.45)
		elif owner == Logi.Owner.ALIEN:
			col = Pal.UI_ENEMY
		var r := maxf(12.0, m2px(Logi.SITE_RADIUS))
		var hex := _hex(p, r)
		draw_colored_polygon(hex, Color(col, 0.08))
		draw_polyline(hex, Color(col, 0.75), 1.5)
		var kind_txt: String = Logi.SITE_KIND_SHORT[s.kind]
		draw_string(UiTheme.font_head, p + Vector2(-6 * kind_txt.length(), 7), kind_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col, 0.9))
		var line := s.name
		var line2 := ""
		match owner:
			Logi.Owner.PLAYER:
				var st: Array = s.stock if s.linked else s.known_stock
				line2 = "F%d M%d" % [int(st[0]), int(st[1])]
				if not s.linked:
					line2 += "  DARK +" + Sim.age_text(Sim.game_time - s.known_time)
				elif s.under_attack > 0.0:
					line2 += "  UNDER ATTACK"
			Logi.Owner.ALIEN:
				line2 = "ALIEN"
				if s.known_time >= 0.0 and not Sim.net.covers(s.pos):
					line2 += " +" + Sim.age_text(Sim.game_time - s.known_time)
			_:
				if s.salvage > 1.0 or s.stock[0] + s.stock[1] > 1.0:
					line2 = "SALVAGE %d" % int(s.salvage + s.stock[0] + s.stock[1])
		draw_string(f, p + Vector2(r + 4, -3), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, 0.9))
		if line2 != "":
			var c2 := Pal.UI_ENEMY if s.under_attack > 0.0 and s.linked else Color(col, 0.75)
			if s.under_attack > 0.0 and s.linked and fmod(_t, 0.8) < 0.4:
				draw_arc(p, r + 6, 0, TAU, 24, Pal.UI_ENEMY, 2.0)
			draw_string(f, p + Vector2(r + 4, 13), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c2)
		if owner == Logi.Owner.ALIEN and s.name != "CAMP":
			for st in s.structures(Sim):
				if st.is_alien():
					var q := w2p(st.pos)
					var tri := PackedVector2Array([q + Vector2(0, -9), q + Vector2(8, 6), q + Vector2(-8, 6), q + Vector2(0, -9)])
					draw_polyline(tri, Pal.UI_ENEMY, 2.0)
					if st.build < 1.0:
						draw_string(f, q + Vector2(-10, 20), "%d%%" % int(st.build * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Pal.UI_ENEMY)


func _crane_reach(cp: Vector2) -> void:
	var r := m2px(Sim.CRANE_PLANT_RANGE)
	var ok := Sim.fitting.has("crane") and Sim.carrier.speed <= CarrierSim.SPEEDS[1] + 0.3
	var col := Color(Pal.UI_HOT if ok else Pal.UI_ENEMY, 0.7)
	UiTheme.dashed_circle(self, cp, r, col, 2.0, 5.0)
	draw_string(UiTheme.font, cp + Vector2(r + 6, 0), "CRANE REACH" + ("" if ok else "  (SLOW TO CRAWL)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	if hover.x >= 0:
		var w := p2w(hover)
		var why := Sim.plant_problem(plant_kind, w)
		if w.distance_to(Sim.carrier.pos2()) > Sim.CRANE_PLANT_RANGE:
			why = "out of crane reach"
		var c := Pal.UI_FRIEND if why == "" else Pal.UI_ENEMY
		draw_arc(hover, 9, 0, TAU, 16, c, 2.0)
		draw_string(UiTheme.font, hover + Vector2(14, 20), "PLANT %s%s" % [Logi.KIND_NAMES[plant_kind], "" if why == "" else ": " + why.to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)


func _vehicle(v: VehicleSim) -> void:
	if v.state == VehicleSim.State.STOWED:
		if not v.plan.is_empty() and Sim.selected == Sim.VEH_SEL + v.id:
			_vplan(v, w2p(Sim.carrier.pos2()), 0, false)
		return
	var lost := v.link == DroneSim.Link.LOST and v.is_out()
	var at := v.last_known if lost else v.pos2()
	var p := w2p(at)
	var col := Pal.UI_FRIEND
	if v.state == VehicleSim.State.DESTROYED:
		col = Color(Pal.UI_ENEMY, 0.7)
	if lost:
		col.a = 0.55
	_vplan(v, p, v.wp, lost)
	var fwd := Vector2(sin(v.heading), -cos(v.heading))
	var rt := Vector2(-fwd.y, fwd.x)
	if v.is_hauler():
		var pts := PackedVector2Array([p + fwd * 9 + rt * 6, p + fwd * 9 - rt * 6, p - fwd * 9 - rt * 6, p - fwd * 9 + rt * 6, p + fwd * 9 + rt * 6])
		if not lost:
			draw_colored_polygon(pts, Color(col, 0.3))
		draw_polyline(pts, col, 2.0)
		draw_line(p + fwd * 9, p + fwd * 15, col, 2.0)
	else:
		var pts := PackedVector2Array([p + fwd * 10, p + rt * 8, p - fwd * 6, p - rt * 8, p + fwd * 10])
		if not lost:
			draw_colored_polygon(pts, Color(col, 0.3))
		draw_polyline(pts, col, 2.0)
		draw_arc(p, 4, 0, TAU, 8, col, 1.0)
	if Sim.selected == Sim.VEH_SEL + v.id:
		UiTheme.brackets(self, Rect2(p - Vector2(18, 18), Vector2(36, 36)), Pal.UI_HOT, 7, 2)
	var label := v.callsign
	if lost:
		label += "  NO LINK +%s" % Sim.age_text(Sim.game_time - v.last_known_t)
	elif v.state == VehicleSim.State.DESTROYED:
		label += "  LOST"
	else:
		label += "  " + v.status_text()
		if v.cargo_total() > 0.5:
			label += "  [F%d M%d]" % [int(v.cargo[0]), int(v.cargo[1])]
		if v.under_fire > 0.0:
			label += "  UNDER FIRE"
	draw_string(UiTheme.font, p + Vector2(14, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _vplan(v: VehicleSim, from: Vector2, start: int, lost: bool) -> void:
	var prev := from
	var first := Vector2.INF
	var col_base := Color(Pal.UI_FRIEND, 0.75) if Sim.selected == Sim.VEH_SEL + v.id else Color(Pal.UI_FRIEND, 0.4)
	for i in range(0, v.plan.size()):
		var w: Dictionary = v.plan[i]
		var q := w2p(Sim.carrier.pos2() if w.act == VehicleSim.Act.HOME else w.pos)
		if first == Vector2.INF:
			first = q
		if i < start:
			continue
		var col: Color = Pal.ROE_COLORS[w.roe]
		col.a = col_base.a * (0.6 if lost else 1.0)
		UiTheme.dashed_line(self, prev, q, col, 1.5 if Sim.selected != Sim.VEH_SEL + v.id else 2.0, 4.0)
		match w.act:
			VehicleSim.Act.LOAD:
				draw_colored_polygon(PackedVector2Array([q + Vector2(-7, -5), q + Vector2(7, -5), q + Vector2(0, 6)]), col)
			VehicleSim.Act.BUILD:
				draw_line(q + Vector2(-7, 0), q + Vector2(7, 0), col, 2.5)
				draw_line(q + Vector2(0, -7), q + Vector2(0, 7), col, 2.5)
			VehicleSim.Act.LOOT:
				draw_rect(Rect2(q - Vector2(6, 6), Vector2(12, 12)), col, false, 2.0)
				draw_line(q + Vector2(-6, -6), q + Vector2(6, 6), col, 1.5)
			VehicleSim.Act.HOME:
				draw_arc(q, 9, PI, TAU, 8, col, 2.0)
			_:
				draw_arc(q, 5, 0, TAU, 12, col, 2.0)
		var txt: String = VehicleSim.ACT_NAMES[w.act]
		if w.act == VehicleSim.Act.BUILD and w.kit >= 0:
			txt += " " + Logi.KIND_SHORT[w.kit]
		if Sim.selected == Sim.VEH_SEL + v.id:
			draw_string(UiTheme.font, q + Vector2(9, -7), "%d %s" % [i + 1, txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		prev = q
	if v.standing and v.plan.size() > 1 and first != Vector2.INF:
		UiTheme.dashed_line(self, prev, first, Color(Pal.UI_FRIEND, col_base.a * 0.5), 1.0, 3.0)
		draw_string(UiTheme.font, prev.lerp(first, 0.5) + Vector2(4, -4), "LOOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Pal.UI_FRIEND, col_base.a))


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
	var site := Sim.site_at(w, Logi.SITE_RADIUS + m2px(1.0) * 0.0 + 120.0)
	if site and site.discovered:
		txt += "  | %s %s x%.1f" % [site.name, Logi.SITE_KIND_NAMES[site.kind], site.richness]
	var at := hover + Vector2(16, -14)
	var tw := UiTheme.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 10
	if at.x > size.x - tw:
		at.x = hover.x - tw - 10
	draw_rect(Rect2(at - Vector2(4, 18), Vector2(tw, 24)), Color(0, 0, 0, 0.7))
	draw_string(UiTheme.font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_HOT)


func _scale_bar() -> void:
	var km := m2px(1000.0)
	var o := Vector2(16, size.y - 18)
	draw_line(o, o + Vector2(km, 0), Pal.UI_TEXT, 2)
	draw_line(o, o + Vector2(0, -8), Pal.UI_TEXT, 2)
	draw_line(o + Vector2(km, 0), o + Vector2(km, -8), Pal.UI_TEXT, 2)
	draw_string(UiTheme.font, o + Vector2(km + 8, 4), "1 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Pal.UI_TEXT)
