class_name WorldView
extends Node3D
## Everything outside the bridge: sky, sun, haze, dunes, props, the carrier, drones,
## raiders and their effects. Visuals only — positions come from Sim.

const LAYER_WORLD := 1
const LAYER_BRIDGE := 2

var env: Environment
var sun: DirectionalLight3D
var carrier_node: Node3D
var radar: Node3D
var drone_vis: Array[Dictionary] = []
var raider_vis: Array[Dictionary] = []
var node_ring: Node3D
var tracers: MeshInstance3D
var tracer_mesh := ImmediateMesh.new()
var _prev := {}
var _cur := {}
var _tracer_list: Array = []
var track_dust: Array[CPUParticles3D] = []
var node_root: Node3D
var struct_vis := {} # structure id -> {root, model, crate, kind, smoke}
var veh_vis := {} # vehicle id -> {root, rotors, parts, dust}
const STRUCT_ASSET := {Logi.Kind.EXTRACTOR: "hum_str_extractor", Logi.Kind.TURRET: "hum_str_turret", Logi.Kind.PAD: "hum_str_pad",
	Logi.Kind.RELAY: "hum_str_relay", Logi.Kind.SCANNER: "hum_str_scanner", Logi.Kind.ALIEN_OUTPOST: "aln_str_outpost"}


func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_props()
	_build_carrier()
	_build_units()
	_build_effects()
	_build_storm()
	Prefs.changed.connect(_apply_quality)
	_apply_quality()


# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.27, 0.38, 0.52)
	sm.sky_horizon_color = Color(0.84, 0.69, 0.53)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.45, 0.36, 0.27)
	sm.ground_horizon_color = Color(0.84, 0.72, 0.58)
	sm.sun_angle_max = 18.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.7)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.88, 0.7, 0.5)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.00009
	env.fog_aerial_perspective = 0.12
	env.fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.14
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.82, 0.6)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 700.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	sun.light_volumetric_fog_energy = 2.5
	# late afternoon, sun in the west-south-west, 24 degrees up
	sun.rotation = Vector3(deg_to_rad(-19.0), deg_to_rad(-112.0), 0.0)
	add_child(sun)


func _apply_quality() -> void:
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	var hi := Prefs.quality >= 1
	env.volumetric_fog_enabled = forward_plus and hi
	env.volumetric_fog_density = 0.0009
	env.volumetric_fog_albedo = Color(0.95, 0.85, 0.7)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.15
	env.ssao_enabled = forward_plus and hi
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 700.0 if hi else 300.0


# ------------------------------------------------------------------ terrain + props

func _build_terrain() -> void:
	var t := Sim.terrain
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Dunes"
	mi.mesh = t.build_mesh()
	mi.material_override = mat
	mi.layers = LAYER_WORLD
	add_child(mi)
	var sk := MeshInstance3D.new()
	sk.name = "FarDunes"
	sk.mesh = t.build_skirt_mesh()
	sk.material_override = mat
	sk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sk)
	# oasis water
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	w.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.42, 0.44)
	wm.roughness = 0.05
	wm.metallic = 0.2
	wm.metallic_specular = 0.9
	w.material_override = wm
	w.position = Vector3(Terrain.OASIS.x, t.water_level, Terrain.OASIS.y)
	add_child(w)


func _build_props() -> void:
	var t := Sim.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var rocks := ["env_rock_a", "env_rock_b", "env_rock_c"]
	var placed := 0
	var tries := 0
	while placed < 150 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(-4700, 4700), rng.randf_range(-4700, 4700))
		var fx := clampi(int((p.x + Terrain.HALF) / Terrain.CELL), 0, Terrain.N)
		var fz := clampi(int((p.y + Terrain.HALF) / Terrain.CELL), 0, Terrain.N)
		var m := t.mesa_mask[fz * (Terrain.N + 1) + fx]
		var mine := p.distance_to(Terrain.MINE) < 600.0
		if not ((m > 0.08 and m < 0.85) or mine or rng.randf() < 0.012):
			continue
		if p.distance_to(Sim.carrier.pos2()) < 400.0:
			continue
		var r := Assets.spawn(rocks[rng.randi() % 3], "exterior")
		r.position = Vector3(p.x, t.height_at(p.x, p.y) - 0.5, p.y)
		r.rotation.y = rng.randf() * TAU
		r.scale = Vector3.ONE * rng.randf_range(0.8, 2.6) * (1.6 if m > 0.08 else 1.0)
		add_child(r)
		placed += 1
	for wp in Terrain.WRECKS:
		var wr := Assets.spawn("env_wreck_a")
		wr.position = Vector3(wp.x, t.height_at(wp.x, wp.y), wp.y)
		wr.rotation.y = rng.randf() * TAU
		add_child(wr)
	# oasis scrub
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.5
	cone.height = 5.0
	cone.radial_segments = 6
	cone.rings = 1
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("5E7F52")
	cm.roughness = 0.9
	cone.material = cm
	mm.mesh = cone
	var spots: Array[Transform3D] = []
	for i in 260:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(180.0, 420.0)
		var q := Terrain.OASIS + Vector2(cos(a), sin(a)) * rr
		var h := t.height_at(q.x, q.y)
		if h < t.water_level + 0.3 or h > t.water_level + 9.0:
			continue
		var s := rng.randf_range(0.6, 1.8)
		spots.append(Transform3D(Basis().scaled(Vector3(s, s * rng.randf_range(0.8, 1.6), s)), Vector3(q.x, h + 2.0 * s, q.y)))
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# the alien recharge node
	var node := Assets.spawn("aln_str_recharge_node")
	var cp := Terrain.CAMP
	node.position = Vector3(cp.x, t.height_at(cp.x, cp.y) - 0.3, cp.y)
	add_child(node)
	node_root = node
	node_ring = Assets.find(node, "ring") as Node3D
	var glow := OmniLight3D.new()
	glow.light_color = Pal.CYAN
	glow.light_energy = 6.0
	glow.omni_range = 60.0
	glow.position = Vector3(0, 18, 0)
	node.add_child(glow)


# ------------------------------------------------------------------ carrier

func _build_carrier() -> void:
	carrier_node = Assets.spawn("hum_carrier")
	carrier_node.name = "Carrier"
	add_child(carrier_node)
	radar = Assets.find(carrier_node, "radar") as Node3D
	# sand thrown up by the tracks (Kharak: "the splash the carrier makes when it crests a dune")
	for p in [Vector3(-40, 4, 150), Vector3(40, 4, 150), Vector3(0, 4, 156), Vector3(-40, 4, -110), Vector3(40, 4, -110)]:
		var d := _make_dust()
		d.amount = 70
		d.lifetime = 7.0
		d.emission_sphere_radius = 14.0
		d.scale_amount_min = 25.0
		d.scale_amount_max = 60.0
		d.initial_velocity_min = 3.0
		d.initial_velocity_max = 9.0
		d.direction = Vector3(0, 0.5, 1)
		d.position = p
		d.emitting = false
		carrier_node.add_child(d)
		track_dust.append(d)
	# deck and tower lights so the ship reads at dusk
	for p in [Vector3(-50, 55, -150), Vector3(50, 55, -150), Vector3(-50, 55, 150), Vector3(50, 55, 150)]:
		var l := OmniLight3D.new()
		l.light_color = Pal.AMBER
		l.light_energy = 3.0
		l.omni_range = 40.0
		l.position = p
		l.layers = LAYER_WORLD
		carrier_node.add_child(l)


func carrier_xform() -> Transform3D:
	return carrier_node.global_transform


# ------------------------------------------------------------------ units

func _build_units() -> void:
	for d in Sim.drones:
		var root := Assets.spawn("hum_air_swift")
		var cam := Assets.attach(root, "socket_camera_0", "mod_sen_gimbal_cam")
		add_child(root)
		var gimbal := Assets.find(cam, "gimbal_ball") as Node3D
		var camera := Camera3D.new()
		camera.name = "FeedCam"
		camera.fov = 38.0
		camera.near = 1.0
		camera.far = 20000.0
		camera.cull_mask = LAYER_WORLD
		camera.position = Vector3(0, 0, -0.25)
		gimbal.add_child(camera)
		var trail := _make_smoke()
		root.add_child(trail)
		drone_vis.append({"root": root, "prop": Assets.find(root, "rotor_main"), "gimbal": gimbal, "cam": camera,
			"smoke": trail, "look": Vector3.ZERO})
	for r in Sim.raiders:
		var root := Assets.spawn("aln_gnd_raider")
		add_child(root)
		var dust := _make_dust()
		dust.position = Vector3(0, 0.3, 1.6)
		root.add_child(dust)
		var glow := Assets.find(root, "hover_glow") as Node3D
		var light := OmniLight3D.new()
		light.light_color = Pal.CYAN
		light.light_energy = 2.0
		light.omni_range = 9.0
		light.position = Vector3(0, 0.3, 0)
		root.add_child(light)
		raider_vis.append({"root": root, "dust": dust, "glow": glow, "light": light})


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2
	p.direction = Vector3(0, 0.6, 1)
	p.spread = 35.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -0.4, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.72, 0.52, 0.55))
	grad.set_color(1, Color(0.85, 0.72, 0.52, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_dot()
	q.material = m
	p.mesh = q
	return p


func _make_smoke() -> CPUParticles3D:
	var p := _make_dust()
	p.emitting = false
	p.amount = 60
	p.lifetime = 9.0
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0.6, 1.2, 0)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 10.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.13, 0.12, 0.8))
	grad.set_color(1, Color(0.35, 0.3, 0.27, 0.0))
	p.color_ramp = grad
	return p


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	_dot = gt
	return _dot


func _build_effects() -> void:
	tracers = MeshInstance3D.new()
	tracers.mesh = tracer_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1)
	m.vertex_color_use_as_albedo = true
	tracers.material_override = m
	tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracers)


## Distant storm front: an arc of billboard wall far to the west.
func _build_storm() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := 13000.0
	var H := 4600.0
	var a0 := deg_to_rad(150.0)
	var a1 := deg_to_rad(250.0)
	var n := 48
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var p0 := Vector3(cos(lerpf(a0, a1, t0)) * R, 0, sin(lerpf(a0, a1, t0)) * R)
		var p1 := Vector3(cos(lerpf(a0, a1, t1)) * R, 0, sin(lerpf(a0, a1, t1)) * R)
		var quad := [[p0, Vector2(t0, 1)], [p1, Vector2(t1, 1)], [p1 + Vector3(0, H, 0), Vector2(t1, 0)],
			[p0, Vector2(t0, 1)], [p1 + Vector3(0, H, 0), Vector2(t1, 0)], [p0 + Vector3(0, H, 0), Vector2(t0, 0)]]
		for q in quad:
			st.set_uv(q[1])
			st.add_vertex(q[0] + Vector3(0, -120, 0))
	var mi := MeshInstance3D.new()
	mi.name = "StormFront"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/storm.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 5000.0
	add_child(mi)


# ------------------------------------------------------------------ per frame

func _physics_process(_d: float) -> void:
	# keep the previous sim state so _process can interpolate between ticks
	_prev = _cur
	_cur = {"carrier": Sim.carrier.xform()}
	for d in Sim.drones:
		_cur["d%d" % d.id] = [d.pos, d.heading, d.bank]
	for r in Sim.raiders:
		_cur["r%d" % r.id] = [r.pos, r.heading]
	for v in Sim.vehicles:
		_cur["v%d" % v.id] = [v.pos, v.heading]


func _process(delta: float) -> void:
	if _cur.is_empty():
		_physics_process(0.0)
	var f := Engine.get_physics_interpolation_fraction()
	var ts := float(Sim.time_scale())
	# carrier
	var ct: Transform3D = _cur.carrier
	if _prev.has("carrier"):
		ct = (_prev.carrier as Transform3D).interpolate_with(_cur.carrier, f)
	carrier_node.global_transform = ct
	var carrier_moving := Sim.carrier.speed > 0.6
	for d in track_dust:
		d.emitting = carrier_moving
		d.speed_scale = clampf(Sim.carrier.speed / 6.0, 0.5, 1.5)
	if radar:
		radar.rotate_object_local(Vector3.UP, delta * 1.2 * minf(ts, 4.0))
	if node_ring:
		node_ring.rotate_object_local(Vector3.UP, delta * 0.3 * minf(ts, 4.0))
	# drones
	for i in Sim.drones.size():
		var d := Sim.drones[i]
		var v: Dictionary = drone_vis[i]
		var root: Node3D = v.root
		var visible_now := d.state != DroneSim.State.REBUILD
		root.visible = visible_now
		var k := "d%d" % d.id
		var cur: Array = _cur[k]
		var p: Vector3 = cur[0]
		var h: float = cur[1]
		var b: float = cur[2]
		if _prev.has(k) and d.airborne():
			var pv: Array = _prev[k]
			p = (pv[0] as Vector3).lerp(cur[0], f)
			h = lerp_angle(pv[1], cur[1], f)
		var basis := Basis(Vector3.UP, -h) * Basis(Vector3.BACK, -b) * Basis(Vector3.RIGHT, clampf(d.vspeed * 0.01, -0.25, 0.25))
		root.global_transform = Transform3D(basis, p)
		var prop: Node3D = v.prop
		if prop and d.airborne():
			prop.rotate_object_local(Vector3.BACK, delta * 60.0)
		var smoke: CPUParticles3D = v.smoke
		smoke.emitting = d.state == DroneSim.State.DESTROYED or (d.airborne() and d.hp < 3)
		_aim_gimbal(d, v, delta)
	# raiders
	for i in Sim.raiders.size():
		var r := Sim.raiders[i]
		var v: Dictionary = raider_vis[i]
		var k := "r%d" % r.id
		var cur: Array = _cur[k]
		var p: Vector3 = cur[0]
		var h: float = cur[1]
		if _prev.has(k):
			var pv: Array = _prev[k]
			p = (pv[0] as Vector3).lerp(cur[0], f)
			h = lerp_angle(pv[1], cur[1], f)
		var hover := sin(Time.get_ticks_msec() * 0.003 + i) * 0.15
		(v.root as Node3D).global_transform = Transform3D(Basis(Vector3.UP, -h), p + Vector3(0, hover, 0))
		var moving := r.vel.length() > 3.0
		(v.dust as CPUParticles3D).emitting = moving
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012 + i * 2.0)
		(v.light as OmniLight3D).light_energy = 1.2 + pulse * 1.5 if r.alive() else 0.0
		if not r.alive():
			(v.root as Node3D).rotation.z = 0.35
			(v.dust as CPUParticles3D).emitting = false
	_update_structures(delta, ts)
	_update_vehicles(delta, f)
	_draw_tracers(delta)


# ------------------------------------------------------------------ the supply war

func _update_structures(delta: float, ts: float) -> void:
	var t := Sim.terrain
	for s in Sim.structures:
		if s.kind == Logi.Kind.ALIEN_NODE:
			if s.dead and node_root and node_root.rotation.z < 0.25:
				node_root.rotation.z = minf(0.25, node_root.rotation.z + delta * 0.1)
				node_root.position.y -= delta * 1.5
			continue
		var vis: Dictionary = struct_vis.get(s.id, {})
		if vis.is_empty():
			var root := Node3D.new()
			root.position = Vector3(s.pos.x, t.height_at(s.pos.x, s.pos.y) - 0.2, s.pos.y)
			root.rotation.y = fposmod(s.id * 1.7, TAU)
			add_child(root)
			var model := Assets.spawn(STRUCT_ASSET[s.kind])
			root.add_child(model)
			var crate: Node3D = null
			if s.owner == Logi.Owner.PLAYER:
				crate = Assets.spawn("hum_kit_crate")
				root.add_child(crate)
			var smoke := _make_smoke()
			smoke.position = Vector3(0, 3, 0)
			root.add_child(smoke)
			vis = {"root": root, "model": model, "crate": crate, "smoke": smoke,
				"head": Assets.find(model, "turret_head"), "dish": Assets.find(model, "dish"),
				"scan": Assets.find(model, "scanner_head"), "pump": Assets.find(model, "pump_head")}
			struct_vis[s.id] = vis
		var model: Node3D = vis.model
		var built := s.build >= 1.0
		if vis.crate:
			(vis.crate as Node3D).visible = not built and not s.dead
		model.visible = built or s.is_alien() or s.dead
		var full := 1.7 if s.is_alien() else 1.0
		if s.is_alien() and not built:
			model.scale = Vector3.ONE * lerpf(0.2, full, s.build)
		elif built:
			model.scale = Vector3.ONE * full
		(vis.smoke as CPUParticles3D).emitting = s.dead and Sim.game_time - s.died_at < 1800.0 or (not s.dead and s.hp < s.max_hp * 0.5)
		if s.dead:
			model.visible = true
			if model.rotation.x < 0.3:
				model.rotation.x = minf(0.3, model.rotation.x + delta * 0.5)
				model.position.y = maxf(-3.0, model.position.y - delta * 2.0)
			continue
		if not built:
			continue
		if vis.head:
			var best := Vector3.INF
			var bd := 1200.0
			for r in Sim.raiders:
				if r.alive() and r.pos2().distance_to(s.pos) < bd:
					bd = r.pos2().distance_to(s.pos)
					best = r.pos
			if best != Vector3.INF:
				var head: Node3D = vis.head
				var to := best - head.global_position
				var want := atan2(-to.x, -to.z)
				head.global_rotation.y = lerp_angle(head.global_rotation.y, want, clampf(delta * 3.0, 0.0, 1.0))
		if vis.dish:
			(vis.dish as Node3D).rotate_object_local(Vector3.UP, delta * 0.2 * minf(ts, 4.0))
		if vis.scan:
			(vis.scan as Node3D).rotate_object_local(Vector3.UP, delta * 1.6 * minf(ts, 4.0))
		if vis.pump:
			(vis.pump as Node3D).position.y = 10.0 + sin(Time.get_ticks_msec() * 0.002 * minf(ts, 4.0)) * 0.8


func _update_vehicles(delta: float, f: float) -> void:
	var t := Sim.terrain
	for v in Sim.vehicles:
		var vis: Dictionary = veh_vis.get(v.id, {})
		if vis.is_empty():
			var root := Assets.spawn("hum_gnd_hauler" if v.is_hauler() else "hum_air_lifter")
			add_child(root)
			var rotors: Array = []
			for i in 4:
				var rt := Assets.find(root, "rotor_%d" % i)
				if rt:
					rotors.append(rt)
			var dust := _make_dust()
			dust.position = Vector3(0, 0.4, 5.0)
			dust.scale_amount_min = 6.0
			dust.scale_amount_max = 14.0
			root.add_child(dust)
			var smoke := _make_smoke()
			root.add_child(smoke)
			vis = {"root": root, "rotors": rotors, "dust": dust, "smoke": smoke, "parts": {}}
			for part in ["pod", "engineer", "sling", "gun"]:
				var n := Assets.find(root, part)
				if n:
					vis.parts[part] = n
			veh_vis[v.id] = vis
		var root: Node3D = vis.root
		root.visible = v.is_out() or v.state == VehicleSim.State.DESTROYED
		if not root.visible:
			continue
		for part in vis.parts:
			var n: Node3D = vis.parts[part]
			n.visible = (part == "gun" and v.gun) or part == v.utility
		if vis.parts.has("pod") and v.utility == "pod" and v.is_hauler():
			(vis.parts.pod as Node3D).visible = true
		var k := "v%d" % v.id
		var cur: Array = _cur.get(k, [v.pos, v.heading])
		var p: Vector3 = cur[0]
		var h: float = cur[1]
		if _prev.has(k):
			var pv: Array = _prev[k]
			if (pv[0] as Vector3).distance_to(cur[0]) < 200.0:
				p = (pv[0] as Vector3).lerp(cur[0], f)
				h = lerp_angle(pv[1], cur[1], f)
		var basis := Basis(Vector3.UP, -h)
		if v.is_hauler() and v.state != VehicleSim.State.BOARDING:
			var fw := Vector2(sin(h), -cos(h))
			var hf := t.height_at(p.x + fw.x * 5.0, p.z + fw.y * 5.0)
			var hb := t.height_at(p.x - fw.x * 5.0, p.z - fw.y * 5.0)
			basis = basis * Basis(Vector3.RIGHT, atan2(hf - hb, 10.0))
		if v.state == VehicleSim.State.DESTROYED:
			basis = basis * Basis(Vector3.BACK, 0.4)
		root.global_transform = Transform3D(basis, p)
		var moving := v.speed > 1.0 and v.state != VehicleSim.State.DESTROYED
		(vis.dust as CPUParticles3D).emitting = v.is_hauler() and moving
		(vis.smoke as CPUParticles3D).emitting = v.state == VehicleSim.State.DESTROYED or v.hp < v.max_hp * 0.5
		for rt in vis.rotors:
			if v.airborne() or v.state == VehicleSim.State.BOARDING:
				(rt as Node3D).rotate_object_local(Vector3.UP, delta * 40.0)


func _aim_gimbal(d: DroneSim, v: Dictionary, delta: float) -> void:
	var gimbal: Node3D = v.gimbal
	var target: Vector3
	var t := Sim.terrain
	if d.mode in ["loiter", "scan", "hold"]:
		target = Vector3(d.orbit_center.x, t.height_at(d.orbit_center.x, d.orbit_center.y), d.orbit_center.y)
	elif d.state == DroneSim.State.ACTIVE and d.wp < d.plan.size():
		var f := Vector2(sin(d.heading), -cos(d.heading))
		var a := d.pos2() + f * 650.0
		target = Vector3(a.x, t.height_at(a.x, a.y), a.y)
	else:
		var f := Vector2(sin(d.heading), -cos(d.heading))
		var a := d.pos2() + f * 900.0
		target = Vector3(a.x, t.height_at(a.x, a.y) + 40.0, a.y)
	# lock on to the nearest live contact in view, if any
	for c in Sim.contacts.values():
		if c.live and Vector2(c.pos.x, c.pos.z).distance_to(d.pos2()) < 900.0:
			target = c.pos
			break
	var cur: Vector3 = v.look
	if cur == Vector3.ZERO:
		cur = target
	cur = cur.lerp(target, clampf(delta * 1.5, 0.0, 1.0))
	v.look = cur
	# the lens faces Blender +Y, which is Godot -Z, so look_at aims lens and camera together
	if gimbal.global_position.distance_to(cur) > 1.0:
		gimbal.look_at(cur, Vector3.UP)


func _draw_tracers(delta: float) -> void:
	for r in Sim.raiders:
		for s in r.shots:
			_tracer_list.append({"from": s.from, "to": s.to, "t": 0.0, "c": Color(0.24, 2.4, 2.1)})
		r.shots.clear()
	var ours := Color(2.2, 1.3, 0.4)
	for s in Sim.structures:
		for sh in s.shots:
			_tracer_list.append({"from": sh.from, "to": sh.to, "t": 0.0, "c": ours})
		s.shots.clear()
	for v in Sim.vehicles:
		for sh in v.shots:
			_tracer_list.append({"from": sh.from, "to": sh.to, "t": 0.0, "c": ours})
		v.shots.clear()
	for sh in Sim.pd_shots:
		_tracer_list.append({"from": sh.from, "to": sh.to, "t": 0.0, "c": ours})
	Sim.pd_shots.clear()
	if _tracer_list.size() > 200:
		_tracer_list = _tracer_list.slice(_tracer_list.size() - 200)
	tracer_mesh.clear_surfaces()
	if _tracer_list.is_empty():
		return
	tracer_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for tr in _tracer_list:
		tr.t += delta
		var a: Vector3 = tr.from
		var b: Vector3 = tr.to
		var k := clampf(tr.t / 0.35, 0.0, 1.0)
		var p0 := a.lerp(b, maxf(0.0, k - 0.15))
		var p1 := a.lerp(b, k)
		tracer_mesh.surface_set_color(tr.get("c", Color(0.24, 2.4, 2.1)))
		tracer_mesh.surface_add_vertex(p0)
		tracer_mesh.surface_add_vertex(p1)
	tracer_mesh.surface_end()
	_tracer_list = _tracer_list.filter(func(x): return x.t < 0.4)


func feed_camera(i: int) -> Camera3D:
	return drone_vis[i].cam


func drone_root(i: int) -> Node3D:
	return drone_vis[i].root
