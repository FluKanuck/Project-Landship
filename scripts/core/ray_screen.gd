class_name RayScreen
## Maps a ray onto the UV of a flat screen mesh (any MeshInstance3D whose first surface is a
## quad with 0-1 UVs). Used for the projection, the settings terminal and the holo table.


static func uv_hit(mi: MeshInstance3D, origin: Vector3, dir: Vector3) -> Vector2:
	var mesh := mi.mesh
	if mesh == null:
		return Vector2(-1, -1)
	var inv := mi.global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in verts.size():
			idx.append(i)
	for t in range(0, idx.size() - 2, 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var hit = Geometry3D.ray_intersects_triangle(o, d, a, b, c)
		if hit == null:
			hit = Geometry3D.ray_intersects_triangle(o, d, a, c, b)
		if hit != null:
			var bc := _bary(hit, a, b, c)
			return uvs[idx[t]] * bc.x + uvs[idx[t + 1]] * bc.y + uvs[idx[t + 2]] * bc.z
	return Vector2(-1, -1)


static func _bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-9:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / den
	var w := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)


## Forward a mouse event into a SubViewport at a UV position.
static func push_mouse(vp: SubViewport, ev: InputEvent, uv: Vector2) -> void:
	var px := Vector2(uv.x * vp.size.x, uv.y * vp.size.y)
	var e: InputEvent = ev.duplicate()
	if e is InputEventMouse:
		(e as InputEventMouse).position = px
		(e as InputEventMouse).global_position = px
	if e is InputEventMouseMotion:
		var last: Vector2 = vp.get_meta("last_px", px)
		(e as InputEventMouseMotion).relative = px - last
		vp.set_meta("last_px", px)
	vp.push_input(e, true)
