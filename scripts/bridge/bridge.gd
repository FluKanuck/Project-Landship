class_name Bridge
extends Node3D
## The command room: chair, projection, preset buttons, holo table, crew pits with their
## faceless crew, settings terminal, lights. Rides inside the carrier's tower.

var room: Node3D
var chair: Node3D
var panel: Node3D
var buttons := {} # name -> {node, rest}
var holo: Holo
var projection: CmdProjection
var terminal: Node3D
var terminal_screen: MeshInstance3D
var settings: SettingsUI
var crew: Array[Dictionary] = []
var lights: Array[Light3D] = []
var light_base := {}
var screens: Array[ShaderMaterial] = []
var beams: Array[MeshInstance3D] = []
var power := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	room = Assets.spawn("hum_bridge_room", "interior")
	add_child(room)
	Assets.set_layer(room, WorldView.LAYER_BRIDGE)
	_collect_screens(room)
	var boards := Assets.find(room, "plot_boards") as MeshInstance3D
	if boards:
		var sb := StatusBoard.new()
		add_child(sb)
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_texture = sb.viewport.get_texture()
		bm.albedo_color = Color(1.25, 1.25, 1.25)
		boards.set_surface_override_material(0, bm)

	chair = Assets.spawn("hum_command_chair", "interior")
	chair.transform = _socket("socket_chair")
	add_child(chair)
	Assets.set_layer(chair, WorldView.LAYER_BRIDGE)
	panel = Assets.attach(chair, "socket_preset_panel", "hum_preset_panel", "interior")
	Assets.set_layer(panel, WorldView.LAYER_BRIDGE)
	var names := {"btn_combat": "CMBT", "btn_recon": "RECN", "btn_transit": "TRNS", "btn_alert": "ALRT"}
	var acts := {"btn_combat": "preset_1", "btn_recon": "preset_2", "btn_transit": "preset_3", "btn_alert": "preset_4"}
	for n in names:
		var b := Assets.find(panel, n) as Node3D
		buttons[n] = {"node": b, "rest": b.position, "down": 0.0}
		var l := Label3D.new()
		# name plus its hotkey, kept current when keys are rebound
		var set_text := func(): l.text = "%s [%s]" % [names[n], Prefs.key_name(acts[n])]
		set_text.call()
		Prefs.keys_changed.connect(set_text)
		l.font = load("res://assets/fonts/ShareTechMono-Regular.ttf")
		l.font_size = 19 # smaller than before: the label now carries the key too
		l.pixel_size = 0.0007
		l.modulate = Pal.PHOSPHOR if n != "btn_alert" else Pal.RED
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.position = b.position + Vector3(0, 0.002, 0.034)
		l.layers = WorldView.LAYER_BRIDGE
		panel.add_child(l)
	_collect_screens(chair)

	var em := Assets.spawn("hum_projection_emitter", "interior")
	em.transform = _socket("socket_emitter")
	add_child(em)
	Assets.set_layer(em, WorldView.LAYER_BRIDGE)

	var table := Assets.spawn("hum_holo_table", "interior")
	table.transform = _socket("socket_holo_table")
	add_child(table)
	Assets.set_layer(table, WorldView.LAYER_BRIDGE)
	holo = Holo.new()
	holo.position = (Assets.find(table, "socket_holo_surface") as Node3D).position
	table.add_child(holo)

	for side in ["socket_pit_l", "socket_pit_r"]:
		var pit := Assets.spawn("hum_crew_pit", "interior")
		pit.transform = _socket(side)
		add_child(pit)
		Assets.set_layer(pit, WorldView.LAYER_BRIDGE)
		for i in 3:
			var s := Assets.find(pit, "socket_console_%d" % i) as Node3D
			var con := Assets.spawn("hum_crew_console", "interior")
			con.transform = s.transform
			pit.add_child(con)
			Assets.set_layer(con, WorldView.LAYER_BRIDGE)
			_collect_screens(con)
			var fig := Assets.spawn("hum_crew_figure", "interior")
			fig.transform = con.transform * (Assets.find(con, "socket_operator") as Node3D).transform
			pit.add_child(fig)
			Assets.set_layer(fig, WorldView.LAYER_BRIDGE)
			crew.append({"head": Assets.find(fig, "head"), "arm_l": Assets.find(fig, "arm_l"), "arm_r": Assets.find(fig, "arm_r"),
				"phase": _rng.randf() * 10.0, "look": 0.0, "look_t": 0.0, "next": _rng.randf_range(1.0, 6.0)})
			if i == 1:
				Sfx.register_chatter_point(fig)
		var pl := OmniLight3D.new()
		pl.light_color = Pal.AMBER
		pl.light_energy = 0.7
		pl.omni_range = 4.5
		pl.position = Vector3(0, -0.4, 0)
		pl.light_cull_mask = WorldView.LAYER_BRIDGE
		pit.add_child(pl)
		lights.append(pl)

	terminal = Assets.spawn("hum_settings_terminal", "interior")
	terminal.transform = _socket("socket_settings_terminal")
	add_child(terminal)
	Assets.set_layer(terminal, WorldView.LAYER_BRIDGE)
	terminal_screen = Assets.find(terminal, "screen") as MeshInstance3D
	settings = SettingsUI.new()
	terminal.add_child(settings)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_texture = settings.viewport.get_texture()
	tm.albedo_color = Color(1.4, 1.4, 1.4)
	terminal_screen.set_surface_override_material(0, tm)

	projection = CmdProjection.new()
	projection.transform = _socket("socket_projection")
	add_child(projection)
	_build_beams(em)
	_build_lights()


func _socket(name: String) -> Transform3D:
	var s := Assets.find(room, name) as Node3D
	return s.transform if s else Transform3D()


func _collect_screens(n: Node) -> void:
	for mi in Mats._meshes(n):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("screen.gdshader"):
				screens.append(m)


func _build_beams(em: Node3D) -> void:
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/beam.gdshader")
	var lenses := []
	for mi in Mats._meshes(em):
		if mi.name == "lenses":
			lenses.append(mi)
	var corners := projection.corners()
	var src := []
	for a in [-30.0, 0.0, 30.0]:
		var x := sin(deg_to_rad(a)) * 1.6
		var y := -cos(deg_to_rad(a)) * 1.6 + 1.6
		src.append(em.global_transform * Vector3(x, -1.62, -y))
	# one thin pyramid per lens towards the projection corners
	for s in src:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			st.set_uv(Vector2(0, 0)); st.add_vertex(to_local(s))
			st.set_uv(Vector2(0, 1)); st.add_vertex(to_local(a))
			st.set_uv(Vector2(1, 1)); st.add_vertex(to_local(b))
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = bm
		mi.layers = WorldView.LAYER_BRIDGE
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		beams.append(mi)


func _build_lights() -> void:
	# warm pools under the ceiling strips; dim, the sun through the windows does the rest
	for p in [Vector3(-7.2, 4.2, -3.0), Vector3(7.2, 4.2, -3.0), Vector3(-7.2, 4.2, 3.4), Vector3(7.2, 4.2, 3.4),
			Vector3(-2.6, 4.2, 4.6), Vector3(2.6, 4.2, 4.6), Vector3(0, 4.2, -5.2), Vector3(-5.5, 3.2, -5.6), Vector3(5.5, 3.2, -5.6), Vector3(-4.6, 3.6, 5.6), Vector3(4.6, 3.6, 5.6)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.62)
		l.light_energy = 0.85
		l.omni_range = 7.0
		l.omni_attenuation = 1.4
		l.position = p
		l.light_cull_mask = WorldView.LAYER_BRIDGE
		l.shadow_enabled = false
		add_child(l)
		lights.append(l)
	var spot := SpotLight3D.new()
	spot.light_color = Pal.PHOSPHOR
	spot.light_energy = 2.0
	spot.spot_range = 6.0
	spot.spot_angle = 28.0
	spot.position = Vector3(0, 4.3, -0.8)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_cull_mask = WorldView.LAYER_BRIDGE
	add_child(spot)
	lights.append(spot)
	var chair_l := OmniLight3D.new()
	chair_l.light_color = Pal.PHOSPHOR
	chair_l.light_energy = 0.6
	chair_l.omni_range = 2.5
	chair_l.position = Vector3(0, 1.7, 4.2)
	chair_l.light_cull_mask = WorldView.LAYER_BRIDGE
	add_child(chair_l)
	lights.append(chair_l)
	# the Compatibility renderer (web) has no SSAO or volumetric light: lift the interior a little
	var compat := RenderingServer.get_current_rendering_method() != "forward_plus"
	for l in lights:
		light_base[l] = l.light_energy * (1.9 if compat else 1.0)
		l.light_energy = 0.0
	# keep the sky's ambient light from flattening the interior
	var probe := ReflectionProbe.new()
	probe.size = Vector3(19, 5.4, 15.5)
	probe.position = Vector3(0, 2.3, -0.4)
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.32, 0.27, 0.22)
	probe.ambient_color_energy = 1.2 if compat else 0.8
	probe.interior = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = WorldView.LAYER_BRIDGE
	add_child(probe)


func set_power(v: float) -> void:
	power = v
	for l in lights:
		var on := clampf(v * lights.size() - lights.find(l), 0.0, 1.0)
		l.light_energy = light_base[l] * on
	for i in screens.size():
		screens[i].set_shader_parameter("brightness", 1.4 * clampf(v * 2.0 - float(i) / screens.size(), 0.0, 1.0))


func set_alert(on: bool) -> void:
	for l in lights:
		if not l.has_meta("base_col"):
			l.set_meta("base_col", l.light_color)
		l.light_color = Color(1.0, 0.22, 0.15) if on else l.get_meta("base_col")
	for s in screens:
		s.set_shader_parameter("alert", 1.0 if on else 0.0)
	projection.set_alert(on)


func press(name: String) -> void:
	if buttons.has(name):
		buttons[name].down = 1.0
		Sfx.ui("button")


func button_at(origin: Vector3, dir: Vector3) -> String:
	var best := ""
	var bd := 1e9
	for n in buttons:
		var b: Node3D = buttons[n].node
		var c := b.global_position + b.global_transform.basis.y * 0.01
		var t := (c - origin).dot(dir)
		if t < 0.0:
			continue
		var d := (origin + dir * t).distance_to(c)
		if d < 0.026 and t < bd:
			bd = t
			best = n
	return best


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for n in buttons:
		var b: Dictionary = buttons[n]
		b.down = maxf(0.0, b.down - delta * 4.0)
		(b.node as Node3D).position = b.rest - Vector3(0, 0.008 * b.down, 0)
	# crew idle: glance around now and then, hands busy on the consoles
	for c in crew:
		c.next -= delta
		if c.next <= 0.0:
			c.next = _rng.randf_range(2.0, 9.0)
			c.look_t = _rng.randf_range(-0.9, 0.9) if _rng.randf() < 0.6 else 0.0
		c.look = lerpf(c.look, c.look_t, clampf(delta * 2.5, 0.0, 1.0))
		var head: Node3D = c.head
		if head:
			head.rotation = Vector3(sin(t * 0.7 + c.phase) * 0.05 - 0.1, c.look, 0)
		var typing := 0.5 + 0.5 * sin(t * 9.0 + c.phase * 3.0)
		if c.arm_l:
			(c.arm_l as Node3D).rotation = Vector3(sin(t * 7.3 + c.phase) * 0.04 * typing, 0, 0)
		if c.arm_r:
			(c.arm_r as Node3D).rotation = Vector3(sin(t * 8.1 + c.phase * 2.0) * 0.05 * (1.0 - typing), 0, 0)
