class_name ExtCamPanel
extends Control
## Forward camera on the bridge tower: the view over the bow, for long crossings.

var world: WorldView
var vp: SubViewport
var cam: Camera3D
var active := false


func _init(w: WorldView) -> void:
	world = w


func _ready() -> void:
	clip_contents = true
	vp = SubViewport.new()
	vp.size = Vector2i(640, 640)
	vp.world_3d = world.get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	cam = Camera3D.new()
	cam.cull_mask = WorldView.LAYER_WORLD
	cam.fov = 55.0
	cam.far = 16000.0
	cam.current = true
	vp.add_child(cam)
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/feed.gdshader")
	m.set_shader_parameter("feed", vp.get_texture())
	m.set_shader_parameter("link", 1.0)
	tr.material = m
	add_child(tr)


func set_active(on: bool) -> void:
	active = on
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func frame_subtitle() -> String:
	return "BOW  HDG %03d" % int(fposmod(rad_to_deg(Sim.carrier.heading), 360.0))


func _process(_d: float) -> void:
	if not active:
		return
	if size.x > 10:
		var want := Vector2i(640, int(640.0 * size.y / size.x))
		if want != vp.size:
			vp.size = want
	var x := world.carrier_xform()
	cam.global_transform = x * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(0, 86.0, 85.0))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.85, 1.0, 0.9, 0.7)
	draw_line(c + Vector2(-60, 0), c + Vector2(-20, 0), col, 2)
	draw_line(c + Vector2(20, 0), c + Vector2(60, 0), col, 2)
	draw_line(c + Vector2(0, -20), c + Vector2(0, -8), col, 2)
