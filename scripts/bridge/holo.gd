class_name Holo
extends Node3D
## The holographic map in the middle of the command room. Shows the whole theatre (or any
## part of it — it can be moved and zoomed, unlike the tactical screen), at the same
## fidelity as the tactical screen, and accepts orders too.

const PLATE := 3.0
const LIFT := 0.04

var centre := Vector2.ZERO
var span := 10000.0
var plate: MeshInstance3D
var mat: ShaderMaterial
var lines_mesh := ImmediateMesh.new()
var lines: MeshInstance3D
var markers := {} # key -> {node, label}
var font: Font
var boot := 0.0
var _t := 0.0


func _ready() -> void:
	font = load("res://assets/fonts/ShareTechMono-Regular.ttf")
	plate = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(PLATE, PLATE)
	pm.subdivide_width = 127
	pm.subdivide_depth = 127
	plate.mesh = pm
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/holo.gdshader")
	mat.set_shader_parameter("height_tex", Sim.height_tex)
	mat.set_shader_parameter("coarse_tex", Sim.coarse_tex)
	mat.set_shader_parameter("know_tex", Sim.know_tex)
	mat.set_shader_parameter("feat_tex", Sim.feature_tex)
	mat.set_shader_parameter("plate", PLATE)
	plate.material_override = mat
	plate.layers = WorldView.LAYER_BRIDGE
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position.y = LIFT
	plate.extra_cull_margin = 2.0
	add_child(plate)
	lines = MeshInstance3D.new()
	lines.mesh = lines_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lm.no_depth_test = false
	lines.material_override = lm
	lines.layers = WorldView.LAYER_BRIDGE
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)
	var glow := OmniLight3D.new()
	glow.light_color = Pal.PHOSPHOR
	glow.light_energy = 0.9
	glow.omni_range = 4.0
	glow.position = Vector3(0, 0.5, 0)
	glow.light_cull_mask = WorldView.LAYER_BRIDGE
	add_child(glow)


func hscale() -> float:
	return minf(PLATE / span * 7.0, 0.006)


func w2l(p: Vector2, h := INF) -> Vector3:
	var l := (p - centre) / span * PLATE
	if h == INF:
		h = Sim.terrain.height_at(p.x, p.y)
	return Vector3(l.x, LIFT + maxf(h + 10.0, 0.0) * hscale(), l.y)


func l2w(local: Vector3) -> Vector2:
	return centre + Vector2(local.x, local.z) / PLATE * span


func on_plate(p: Vector2) -> bool:
	return ((p - centre) / span).length() < 0.5


## Ray (world space) to theatre position; returns Vector2.INF when it misses the table.
func pick(origin: Vector3, dir: Vector3) -> Vector2:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	if absf(d.y) < 1e-4:
		return Vector2.INF
	# iterate a little so the hit sits on the raised relief, not the flat plate
	var y := LIFT + 0.05
	var hit := Vector3.ZERO
	for i in 3:
		var t := (y - o.y) / d.y
		if t < 0.0:
			return Vector2.INF
		hit = o + d * t
		var w := l2w(hit)
		y = w2l(w).y
	var wp := l2w(hit)
	if not on_plate(wp):
		return Vector2.INF
	return wp


func zoom_by(f: float, about := Vector2.INF) -> void:
	var ns := clampf(span * f, 1500.0, 10000.0)
	if about != Vector2.INF:
		centre = about + (centre - about) * (ns / span)
	span = ns
	_clamp()


func pan_by(px_delta: Vector2) -> void:
	centre -= px_delta * span * 0.0012
	_clamp()


func _clamp() -> void:
	var lim := maxf(0.0, Terrain.HALF - span * 0.25)
	centre = centre.clamp(Vector2(-lim, -lim), Vector2(lim, lim))


func _process(delta: float) -> void:
	_t += delta
	mat.set_shader_parameter("centre", centre)
	mat.set_shader_parameter("span", span)
	mat.set_shader_parameter("hscale", hscale())
	mat.set_shader_parameter("alert", 1.0 if Sim.alert else 0.0)
	mat.set_shader_parameter("boot", boot)
	plate.visible = boot > 0.01
	_update_markers()
	_draw_lines()


# ------------------------------------------------------------------ markers

func _marker(key: String, shape: String, col: Color) -> Dictionary:
	if markers.has(key):
		return markers[key]
	var n := Node3D.new()
	add_child(n)
	var mi := MeshInstance3D.new()
	var m: Mesh
	match shape:
		"ship":
			var b := PrismMesh.new()
			b.size = Vector3(0.06, 0.03, 0.14)
			m = b
			mi.rotation_degrees = Vector3(-90, 0, 0)
		"drone":
			var p := PrismMesh.new()
			p.size = Vector3(0.05, 0.02, 0.06)
			m = p
			mi.rotation_degrees = Vector3(-90, 0, 0)
		"node":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.03
			c.height = 0.07
			c.radial_segments = 3
			m = c
		_:
			var s := SphereMesh.new()
			s.radius = 0.016
			s.height = 0.032
			s.radial_segments = 4
			s.rings = 2
			m = s
	mi.mesh = m
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = col * 1.6
	mi.material_override = mm
	mi.layers = WorldView.LAYER_BRIDGE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var l := Label3D.new()
	l.font = font
	l.font_size = 40
	l.pixel_size = 0.0011
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = col
	l.outline_size = 0
	l.position = Vector3(0, 0.06, 0)
	l.layers = WorldView.LAYER_BRIDGE
	n.add_child(l)
	var rec := {"node": n, "mesh": mi, "label": l, "mat": mm, "col": col}
	markers[key] = rec
	return rec


func _place(rec: Dictionary, p: Vector2, float_h: float, text: String, alpha := 1.0, heading := INF) -> void:
	var n: Node3D = rec.node
	var vis := on_plate(p) and boot > 0.5
	n.visible = vis
	if not vis:
		return
	var base := w2l(p)
	n.position = base + Vector3(0, float_h, 0)
	if heading != INF:
		n.rotation = Vector3(0, -heading, 0)
		(rec.label as Label3D).rotation = Vector3.ZERO
	(rec.label as Label3D).text = text
	var c: Color = rec.col
	(rec.label as Label3D).modulate = Color(c, c.a * alpha)
	(rec.mat as StandardMaterial3D).albedo_color = Color(c * 1.6, alpha)


func _update_markers() -> void:
	var c := Sim.carrier
	_place(_marker("carrier", "ship", Pal.UI_HOT), c.pos2(), 0.06, "LANDSHIP", 1.0, c.heading)
	for d in Sim.drones:
		var rec := _marker("d%d" % d.id, "drone", Pal.UI_FRIEND)
		var lost := d.airborne() and d.link == DroneSim.Link.LOST
		var src: DroneSim = Sim.shadows.get(d.id, d) if lost else d
		var show := d.airborne() or d.state == DroneSim.State.DESTROYED
		if not show:
			(rec.node as Node3D).visible = false
			continue
		var txt := d.callsign + (" PRED" if lost else "")
		_place(rec, src.pos2(), 0.14, txt, 0.5 if lost else 1.0, src.heading)
	var seen := {}
	for ct in Sim.contacts.values():
		var key := "c%d" % ct.id
		seen[key] = true
		var rec := _marker(key, "contact", Pal.UI_ENEMY)
		var age: float = Sim.game_time - ct.last
		var a := 1.0 if ct.live else clampf(1.0 - age / Sim.GHOST_FADE, 0.15, 0.7)
		var name := ("R-%d" if ct["class"] == "RAIDER" else "H-%d") % (ct.id + 1)
		var txt := name if ct.live else "%s +%s" % [name, Sim.age_text(age)]
		var pulse := 1.0 + (0.3 * sin(_t * 8.0) if ct.live else 0.0)
		(rec.mesh as MeshInstance3D).scale = Vector3.ONE * pulse
		_place(rec, Vector2(ct.pos.x, ct.pos.z), 0.05, txt, a)
	for key in markers.keys():
		if key.begins_with("c") and not seen.has(key):
			(markers[key].node as Node3D).visible = false
	if Sim.node_found:
		_place(_marker("node", "node", Pal.UI_ENEMY), Terrain.CAMP, 0.04, "RECHARGE NODE")


# ------------------------------------------------------------------ lines: coverage, plans, stalks

func _draw_lines() -> void:
	lines_mesh.clear_surfaces()
	if boot < 0.5:
		return
	lines_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := Sim.carrier
	_ring(c.pos2(), CarrierSim.SENSOR_RANGE, Color(Pal.UI_TEXT, 0.35))
	_ring(c.pos2(), Sim.LINK_MAX, Color(Pal.UI_FRIEND, 0.18), true)
	var prev := c.pos2()
	for p in c.course:
		_seg(prev, p, Color(Pal.UI_TEXT, 0.7), 0.03)
		prev = p
	for d in Sim.drones:
		var lost := d.airborne() and d.link == DroneSim.Link.LOST
		var src: DroneSim = Sim.shadows.get(d.id, d) if lost else d
		if d.airborne() and not lost:
			_ring(d.pos2(), d.sensor_range(), Color(Pal.UI_FRIEND, 0.3))
		if d.airborne():
			_stalk(src.pos2(), 0.14, Color(Pal.UI_FRIEND, 0.5))
		var from := src.pos2() if d.airborne() else c.pos2()
		var start := src.wp if d.airborne() else 0
		for i in range(start, src.plan.size()):
			var w: Dictionary = src.plan[i]
			var col: Color = Pal.ROE_COLORS[w.roe]
			col.a = 0.4 if lost else 0.85
			_seg(from, w.pos, col, 0.1)
			_cross(w.pos, col)
			from = w.pos
	for ct in Sim.contacts.values():
		var a := 0.7 if ct.live else 0.25
		_stalk(Vector2(ct.pos.x, ct.pos.z), 0.05, Color(Pal.UI_ENEMY, a))
	lines_mesh.surface_end()


func _v(col: Color, p: Vector3) -> void:
	lines_mesh.surface_set_color(col)
	lines_mesh.surface_add_vertex(p)


func _seg(a: Vector2, b: Vector2, col: Color, lift: float) -> void:
	var n := maxi(2, int(a.distance_to(b) / span * 40.0))
	for i in n:
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		if not (on_plate(p0) and on_plate(p1)):
			continue
		_v(col, w2l(p0) + Vector3(0, lift, 0))
		_v(col, w2l(p1) + Vector3(0, lift, 0))


func _ring(p: Vector2, r: float, col: Color, dashed := false) -> void:
	var n := 64
	for i in n:
		if dashed and i % 2 == 1:
			continue
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var q0 := p + Vector2(cos(a0), sin(a0)) * r
		var q1 := p + Vector2(cos(a1), sin(a1)) * r
		if on_plate(q0) and on_plate(q1):
			_v(col, w2l(q0) + Vector3(0, 0.012, 0))
			_v(col, w2l(q1) + Vector3(0, 0.012, 0))


func _stalk(p: Vector2, h: float, col: Color) -> void:
	if not on_plate(p):
		return
	var b := w2l(p)
	_v(col, b)
	_v(col, b + Vector3(0, h, 0))


func _cross(p: Vector2, col: Color) -> void:
	if not on_plate(p):
		return
	var b := w2l(p) + Vector3(0, 0.1, 0)
	var s := 0.025
	_v(col, b + Vector3(-s, 0, -s)); _v(col, b + Vector3(s, 0, s))
	_v(col, b + Vector3(-s, 0, s)); _v(col, b + Vector3(s, 0, -s))
