class_name CmdProjection
extends Node3D
## The configurable command display, projected in the air in front of the chair.
## Fixed in the room: it never follows the player's head.

const SIZE := Vector2(2.7, 1.3)
const RES := Vector2i(1600, 770)

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
	var q := QuadMesh.new()
	q.size = SIZE
	screen.mesh = q
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


## Corners in world space (for the projector beams).
func corners() -> Array[Vector3]:
	var h := SIZE * 0.5
	var out: Array[Vector3] = []
	for p in [Vector3(-h.x, h.y, 0), Vector3(h.x, h.y, 0), Vector3(h.x, -h.y, 0), Vector3(-h.x, -h.y, 0)]:
		out.append(global_transform * p)
	return out
