class_name CmdProjection
extends Node3D
## The configurable command display, projected in the air in front of the chair.
## Fixed in the room: it never follows the player's head.

const SIZE := Vector2(2.7, 1.3)
const RES := Vector2i(1600, 770)
## Horizontal curve: the display is an arc of a cylinder whose axis is vertical and on
## the chair side, so the edges wrap towards the commander. SIZE.x is the arc length.
## The eye sits 1.38 m behind the display centre; a larger radius is a gentler curve.
const CURVE_RADIUS := 2.0
const SEGMENTS := 48

var viewport: SubViewport
var mfd: MFD
var screen: MeshInstance3D
var mat: ShaderMaterial
var boot := 0.0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = RES
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	viewport.handle_input_locally = true
	add_child(viewport)
	mfd = MFD.new()
	viewport.add_child(mfd)

	screen = MeshInstance3D.new()
	screen.mesh = _curved_mesh()
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/projection.gdshader")
	mat.set_shader_parameter("screen_tex", viewport.get_texture())
	mat.set_shader_parameter("boot", 0.0)
	screen.material_override = mat
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.layers = WorldView.LAYER_BRIDGE
	add_child(screen)


func set_boot(v: float) -> void:
	boot = v
	mat.set_shader_parameter("boot", v)


func set_alert(on: bool) -> void:
	mat.set_shader_parameter("alert", 1.0 if on else 0.0)


## Returns the UV under a world ray, or (-1, -1).
func uv_at(origin: Vector3, dir: Vector3) -> Vector2:
	return RayScreen.uv_hit(screen, origin, dir)


func push_mouse(ev: InputEvent, uv: Vector2) -> void:
	RayScreen.push_mouse(viewport, ev, uv)


## Local position of a display UV (0,0 top left) on the curved surface. The viewer is on
## the +Z side; the centre column stays at z = 0 and the edges come forward.
static func local_at(uv: Vector2) -> Vector3:
	var a := (uv.x - 0.5) * SIZE.x / CURVE_RADIUS
	return Vector3(sin(a) * CURVE_RADIUS, (0.5 - uv.y) * SIZE.y, (1.0 - cos(a)) * CURVE_RADIUS)


## A strip of SEGMENTS columns with 0-1 UVs, normals facing the centre of the curve.
static func _curved_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var a := (u - 0.5) * SIZE.x / CURVE_RADIUS
		var n := Vector3(-sin(a), 0.0, cos(a))
		for v in [0.0, 1.0]:
			st.set_normal(n)
			st.set_uv(Vector2(u, v))
			st.add_vertex(local_at(Vector2(u, v)))
	for i in SEGMENTS:
		var t := i * 2 # top-left; +1 bottom-left, +2 top-right, +3 bottom-right
		st.add_index(t); st.add_index(t + 1); st.add_index(t + 2)
		st.add_index(t + 2); st.add_index(t + 1); st.add_index(t + 3)
	return st.commit()


## Corners in world space (for the projector beams).
func corners() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		out.append(global_transform * local_at(uv))
	return out
