class_name FeedPanel
extends Control
## Live camera feed from a Swift's gimbal camera, with a flight HUD. The picture degrades as
## the data link weakens and is lost completely beyond link range.

var world: WorldView
var vp: SubViewport
var cam: Camera3D
var tex: TextureRect
var mat: ShaderMaterial
var hud: Control
var which := 0
var fov := 38.0
var thermal := 0 # 0 off, 1 white hot, 2 ironbow
const THERMAL_NAMES := ["THERMAL", "TH WHOT", "TH IRON"]
var hvp: SubViewport # heat picture: LAYER_HEAT only, rendered while thermal is on
var hcam: Camera3D
var _hit := 0.0
var _last_hp := {}
var active := true
var btns: Array[Button] = []
var th_btn: Button
var auto_btn: Button
var _press_pos = null # left button down on the picture (null when not)
var _dragging := false
const DRAG_PX := 6.0


func _init(w: WorldView) -> void:
	world = w


func _ready() -> void:
	clip_contents = true
	vp = SubViewport.new()
	vp.size = Vector2i(800, 450)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = world.get_viewport().world_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	cam = Camera3D.new()
	cam.cull_mask = WorldView.LAYER_WORLD
	cam.far = 16000.0
	cam.near = 1.0
	cam.current = true
	vp.add_child(cam)
	# heat camera: same pose and lens, sees only the heat stand-ins, with a plain
	# environment so fog, glow and tonemapping leave the heat values alone
	hvp = SubViewport.new()
	hvp.size = vp.size
	hvp.transparent_bg = true # sky stays empty (cold)
	hvp.world_3d = vp.world_3d
	hvp.msaa_3d = Viewport.MSAA_DISABLED
	hvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(hvp)
	hcam = Camera3D.new()
	hcam.cull_mask = WorldView.LAYER_HEAT
	hcam.far = 16000.0
	hcam.near = 1.0
	hcam.current = true
	var henv := Environment.new()
	henv.background_mode = Environment.BG_CLEAR_COLOR
	henv.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	henv.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	hcam.environment = henv
	hvp.add_child(hcam)
	tex = TextureRect.new()
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/feed.gdshader")
	mat.set_shader_parameter("feed", vp.get_texture())
	mat.set_shader_parameter("heat", hvp.get_texture())
	tex.material = mat
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	add_child(hud)
	var bar := HBoxContainer.new()
	bar.position = Vector2(10, 8)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	for i in Sim.drones.size():
		var b := UiTheme.button("CAM %d" % (i + 1), true, 84)
		b.pressed.connect(func(): which = i)
		bar.add_child(b)
		btns.append(b)
	th_btn = UiTheme.button("THERMAL", true, 110)
	th_btn.tooltip_text = "Thermal camera: off / white hot / ironbow"
	th_btn.pressed.connect(func(): thermal = (thermal + 1) % 3)
	bar.add_child(th_btn)
	auto_btn = UiTheme.button("AUTO", true, 84)
	auto_btn.pressed.connect(func(): world.gimbal_auto(which))
	bar.add_child(auto_btn)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_active(on: bool) -> void:
	active = on
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_update_heat_vp()


func _update_heat_vp() -> void:
	var want := SubViewport.UPDATE_ALWAYS if (active and thermal > 0) else SubViewport.UPDATE_DISABLED
	if hvp.render_target_update_mode != want:
		hvp.render_target_update_mode = want


func frame_subtitle() -> String:
	var d := Sim.drones[which]
	return "%s  GIMBAL %s  FOV %d" % [d.callsign, _mode_text(), int(fov)]


func _mode_text() -> String:
	match world.gimbal_mode(which):
		"manual": return "MAN"
		"point": return "LOCK PT"
		"contact":
			var c = Sim.contacts.get(world.gimbal_contact(which))
			return "LOCK %s" % _contact_tag(c) if c != null else "LOCK PT"
	return "AUTO"


func _contact_tag(ct: Dictionary) -> String:
	return ("R-%d" if ct["class"] == "RAIDER" else "H-%d") % (ct.id + 1)


## Gimbal control: drag to slew, click a contact box to track it, click the ground to lock
## that point, right click to hand the gimbal back to AUTO. Wheel zooms.
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov = clampf(fov * 0.85, 6.0, 60.0)
			accept_event()
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov = clampf(fov / 0.85, 6.0, 60.0)
			accept_event()
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			world.gimbal_auto(which)
			Sfx.ui("button")
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_pos = ev.position
				_dragging = false
			else:
				if _press_pos != null and not _dragging and _feed_live():
					_click_lock(ev.position)
				_press_pos = null
				_dragging = false
			accept_event()
	elif ev is InputEventMouseMotion and _press_pos != null and _feed_live():
		if not _dragging and ev.position.distance_to(_press_pos) > DRAG_PX:
			_dragging = true
		if _dragging:
			# degrees per pixel from the current field of view, so a drag tracks the picture
			var k := deg_to_rad(cam.fov) / maxf(size.y, 1.0)
			world.gimbal_slew(which, ev.relative.x * k, -ev.relative.y * k)
		accept_event()


func _feed_live() -> bool:
	return get_meta("link", 1.0) > 0.01 and Sim.drones[which].airborne()


func _click_lock(pos: Vector2) -> void:
	# a contact box under the click first
	var best = null
	var best_d := 1e9
	for rid in Sim.contacts:
		var ct: Dictionary = Sim.contacts[rid]
		var r = _contact_box(ct)
		if r == null:
			continue
		var dd: float = pos.distance_to(r[0])
		if dd < r[1] + 10.0 and dd < best_d:
			best = rid
			best_d = dd
	if best != null:
		world.gimbal_lock_contact(which, best)
		Sfx.ui("button")
		return
	# otherwise the ground under the click
	var vpos := pos / size * Vector2(vp.size)
	var hit = WorldView.ground_hit(cam.project_ray_origin(vpos), cam.project_ray_normal(vpos))
	if hit != null:
		world.gimbal_lock_point(which, hit)
		Sfx.ui("button")


## Screen centre and half size of a live contact's box in the feed, or null.
func _contact_box(ct: Dictionary):
	if not ct.live:
		return null
	var p: Vector3 = ct.pos
	if cam.is_position_behind(p):
		return null
	var dist := cam.global_position.distance_to(p)
	if dist > 3000.0:
		return null
	return [cam.unproject_position(p) / Vector2(vp.size) * size, clampf(4000.0 / dist, 10.0, 40.0), dist]


func _process(delta: float) -> void:
	if not active:
		return
	# follow the selected drone when the commander changes selection
	if Sim.selected >= 0 and Sim.selected != which and not has_meta("pinned"):
		which = Sim.selected
	for i in btns.size():
		btns[i].set_pressed_no_signal(i == which)
	th_btn.set_pressed_no_signal(thermal > 0)
	th_btn.text = "%s %s" % [Prefs.key_name("thermal"), THERMAL_NAMES[thermal]]
	auto_btn.text = "%s AUTO" % Prefs.key_name("gimbal_auto")
	_update_heat_vp()
	auto_btn.set_pressed_no_signal(world.gimbal_mode(which) == "auto")
	if size.x > 10 and size.y > 10:
		var want := Vector2i(800, int(800.0 * size.y / size.x))
		if want != vp.size:
			vp.size = want
			hvp.size = want
	var d := Sim.drones[which]
	var src := world.feed_camera(which)
	cam.global_transform = src.global_transform
	cam.fov = lerpf(cam.fov, fov, clampf(delta * 6.0, 0.0, 1.0))
	hcam.global_transform = cam.global_transform
	hcam.fov = cam.fov
	var link := 1.0
	if not d.airborne():
		link = 1.0 if d.state in [DroneSim.State.READY, DroneSim.State.REFUEL] else 0.0
	else:
		var dist := d.pos2().distance_to(Sim.carrier.pos2())
		link = clampf(1.0 - (dist - Sim.LINK_OK) / (Sim.LINK_MAX - Sim.LINK_OK), 0.0, 1.0)
		if d.link == DroneSim.Link.LOST:
			link = 0.0
	if d.state == DroneSim.State.DESTROYED or d.state == DroneSim.State.REBUILD:
		link = 0.0
	if _last_hp.get(which, d.hp) > d.hp:
		_hit = 1.0
	_last_hp[which] = d.hp
	_hit = maxf(0.0, _hit - delta * 2.0)
	mat.set_shader_parameter("link", link)
	mat.set_shader_parameter("thermal", thermal)
	mat.set_shader_parameter("hit", _hit)
	set_meta("link", link)
	hud.queue_redraw()


func _draw_hud() -> void:
	var d := Sim.drones[which]
	var s := hud.size
	var f := UiTheme.font
	var c := Color(0.85, 1.0, 0.9, 0.9)
	var link: float = get_meta("link", 1.0)
	if link <= 0.01:
		var msg := "NO SIGNAL"
		if d.state == DroneSim.State.DESTROYED:
			msg = "SIGNAL TERMINATED"
		elif d.state == DroneSim.State.REBUILD:
			msg = "AIRFRAME IN FABRICATION"
		elif d.link == DroneSim.Link.LOST:
			msg = "NO SIGNAL  /  OUT OF LINK RANGE"
		var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		hud.draw_rect(Rect2(s * 0.5 - Vector2(w * 0.5 + 20, 34), Vector2(w + 40, 54)), Color(0, 0, 0, 0.7))
		hud.draw_string(f, s * 0.5 + Vector2(-w * 0.5, 6), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Pal.UI_ENEMY)
		return
	# reticle
	var m := s * 0.5
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		hud.draw_line(m + dir * 14, m + dir * 46, c, 2)
	hud.draw_rect(Rect2(m - Vector2(4, 4), Vector2(8, 8)), c, false, 1.5)
	# compass tape: the camera's bearing (where the picture looks), scrolling smoothly.
	# Marks sit on whole 5-degree bearings and slide with the fractional heading.
	var look := -cam.global_basis.z
	var hdg := fposmod(rad_to_deg(atan2(look.x, -look.z)), 360.0)
	var tape_y := 66.0
	var px_per_deg := 6.0
	var first := int(floor((hdg - 40.0) / 5.0)) * 5
	for deg in range(first, int(hdg + 40.0) + 1, 5):
		var off := deg - hdg
		if absf(off) > 40.0:
			continue
		var x := m.x + off * px_per_deg
		var b := posmod(deg, 360)
		var fade := 1.0 - smoothstep(30.0, 40.0, absf(off)) # soft ends instead of popping
		hud.draw_line(Vector2(x, tape_y), Vector2(x, tape_y + (12 if b % 10 == 0 else 6)), Color(c, 0.7 * fade), 1.5)
		if b % 30 == 0:
			hud.draw_string(f, Vector2(x - 14, tape_y + 30), "%03d" % b, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(c, fade))
	hud.draw_line(Vector2(m.x, tape_y - 4), Vector2(m.x, tape_y + 16), Pal.UI_HOT, 2.0)
	hud.draw_string(f, Vector2(m.x - 18, tape_y - 6), "%03d" % (int(round(hdg)) % 360), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Pal.UI_HOT)
	# left block
	var agl := d.pos.y - Sim.terrain.height_at(d.pos.x, d.pos.z)
	var lines := [
		"%s  %s" % [d.callsign, d.status_text()],
		"ALT %4d M AGL" % int(agl),
		"SPD %3d KM/H" % int(d.speed * 3.6),
		"FUEL %3d MIN" % int(d.fuel / 60.0),
		"HULL %d/3" % d.hp,
	]
	for i in lines.size():
		hud.draw_string(f, Vector2(16, s.y - 120 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, c)
	# right block: link, ROE, grid ref
	var rc := Sim.carrier.pos2()
	var right := [
		"LINK %3d%%" % int(link * 100.0),
		"ROE %s" % (Pal.ROE_LONG[d.current_roe()] if d.airborne() else "-"),
		"BRG %03d FROM SHIP" % int(Terrain.bearing_deg(rc, d.pos2())),
		"RNG %.1f KM" % (rc.distance_to(d.pos2()) / 1000.0),
		Sim.clock_text(),
	]
	for i in right.size():
		var t: String = right[i]
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var col := c
		if i == 0 and link < 0.6:
			col = Pal.UI_WARN
		hud.draw_string(f, Vector2(s.x - w - 16, s.y - 120 + i * 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
	if d.under_fire > 0.0 and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0:
		hud.draw_string(f, Vector2(m.x - 80, m.y + 90), "UNDER FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Pal.UI_ENEMY)
	# gimbal mode, top right under the toolbar
	var gm := world.gimbal_mode(which)
	var gt := "GIMBAL " + _mode_text()
	var gw := f.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	hud.draw_string(f, Vector2(s.x - gw - 16, 30), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Pal.UI_HOT if gm != "auto" else c)
	# boxes round live contacts in view; the tracked one gets corner brackets
	var locked = world.gimbal_contact(which) if gm == "contact" else null
	for rid in Sim.contacts:
		var ct: Dictionary = Sim.contacts[rid]
		var box = _contact_box(ct)
		if box == null:
			continue
		var sp: Vector2 = box[0]
		var r: float = box[1]
		hud.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2), Pal.UI_ENEMY, false, 2.0)
		hud.draw_string(f, sp + Vector2(r + 4, -r), "%s %dM" % [_contact_tag(ct), int(box[2])], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_ENEMY)
		if rid == locked:
			_brackets(sp, r + 8.0, Pal.UI_HOT)
			hud.draw_string(f, sp + Vector2(-r, r + 22), "TRACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_HOT)
	# a locked ground point: a small diamond on the spot
	if gm == "point":
		var gp := world.gimbal_point(which)
		if not cam.is_position_behind(gp):
			var q := cam.unproject_position(gp) / Vector2(vp.size) * s
			var pts := PackedVector2Array([q + Vector2(0, -9), q + Vector2(9, 0), q + Vector2(0, 9), q + Vector2(-9, 0), q + Vector2(0, -9)])
			hud.draw_polyline(pts, Pal.UI_HOT, 2.0)
			hud.draw_string(f, q + Vector2(14, 5), "PT %dM" % int(cam.global_position.distance_to(gp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_HOT)


func _brackets(c: Vector2, r: float, col: Color) -> void:
	var l := r * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * r, sy * r)
			hud.draw_line(p, p - Vector2(sx * l, 0), col, 2.0)
			hud.draw_line(p, p - Vector2(0, sy * l), col, 2.0)
