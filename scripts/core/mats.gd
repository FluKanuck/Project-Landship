class_name Mats
## Shared materials. Every imported asset has its glTF materials swapped for these by name
## (Art Profile: one material per side, one palette texture, dust from a shader).

static var _cache := {}
static var palette_tex: Texture2D


static func _palette() -> Texture2D:
	if palette_tex == null:
		palette_tex = load("res://assets/textures/palette.png")
	return palette_tex


static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: Material
	match name:
		"hull":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/hull.gdshader")
			s.set_shader_parameter("palette", _palette())
			m = s
		"hull_clean":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/hull.gdshader")
			s.set_shader_parameter("palette", _palette())
			s.set_shader_parameter("dust_amount", 0.08)
			s.set_shader_parameter("grime", 0.1)
			m = s
		"rock":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/hull.gdshader")
			s.set_shader_parameter("palette", _palette())
			s.set_shader_parameter("dust_amount", 0.75)
			s.set_shader_parameter("roughness_base", 0.95)
			s.set_shader_parameter("metallic_base", 0.0)
			m = s
		"interior":
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = _palette()
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sm.roughness = 0.85
			sm.metallic = 0.05
			sm.metallic_specular = 0.12
			m = sm
		"alien":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/alien.gdshader")
			s.set_shader_parameter("palette", _palette())
			m = s
		"emit":
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.albedo_texture = _palette()
			sm.albedo_color = Color(1.3, 1.3, 1.3)
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m = sm
		"glass":
			var sm := StandardMaterial3D.new()
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.albedo_color = Color(0.16, 0.22, 0.22, 0.22)
			sm.roughness = 0.06
			sm.metallic = 0.7
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = sm
		"glass_solid":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.09, 0.13, 0.14)
			sm.roughness = 0.08
			sm.metallic = 0.6
			m = sm
		"screen":
			m = screen_material(randf() * 100.0)
		_:
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = _palette()
			m = sm
	_cache[name] = m
	return m


static func screen_material(seed: float, tint := Pal.PHOSPHOR) -> ShaderMaterial:
	var s := ShaderMaterial.new()
	s.shader = load("res://shaders/screen.gdshader")
	s.set_shader_parameter("seed", seed)
	s.set_shader_parameter("tint", tint)
	return s


## Swap the glTF materials of every mesh under `node`.
## `context` picks the hull variant: "exterior", "interior" or "clean".
static func apply(node: Node, context := "exterior") -> void:
	for mi in _meshes(node):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var n := src.resource_name if src else "hull"
			var key := n
			if n == "hull":
				key = {"exterior": "hull", "interior": "interior", "clean": "hull_clean"}.get(context, "hull")
			elif n == "glass" and context == "exterior_solid_glass":
				key = "glass_solid"
			elif n == "screen":
				mi.set_surface_override_material(i, screen_material(randf() * 100.0))
				continue
			mi.set_surface_override_material(i, get_mat(key))


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
