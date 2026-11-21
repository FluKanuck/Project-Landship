class_name Terrain
extends RefCounted
## The 10 km x 10 km desert. Heights, colours, the dune mesh, and the textures the
## holo table and tactical map sample. North is -Z, east is +X.

const SIZE := 10000.0
const N := 200 # cells per side (50 m)
const CELL := SIZE / N
const HALF := SIZE * 0.5

# Named places (world X, Z)
const CARRIER_START := Vector2(0.0, 3600.0)
const CAMP := Vector2(2700.0, -3100.0) # alien recharge node, on a mesa
const OASIS := Vector2(-2500.0, -900.0)
const MINE := Vector2(1900.0, 1100.0)
const WRECKS := [Vector2(-700.0, 1600.0), Vector2(1200.0, -400.0), Vector2(-1800.0, -2600.0), Vector2(400.0, -1900.0)]

var heights := PackedFloat32Array()
var colors := PackedColorArray()
var mesa_mask := PackedFloat32Array()
var water_level := 0.0

var _n_base := FastNoiseLite.new()
var _n_warp := FastNoiseLite.new()
var _n_warp2 := FastNoiseLite.new()
var _n_mask := FastNoiseLite.new()
var _n_mesa := FastNoiseLite.new()
var _n_rough := FastNoiseLite.new()


func _init() -> void:
	_setup_noise(_n_base, 11, 1.0 / 3200.0, 3)
	_setup_noise(_n_warp, 12, 1.0 / 1100.0, 2)
	_setup_noise(_n_warp2, 13, 1.0 / 2600.0, 1)
	_setup_noise(_n_mask, 14, 1.0 / 1500.0, 2)
	_setup_noise(_n_mesa, 15, 1.0 / 1400.0, 2)
	_setup_noise(_n_rough, 16, 1.0 / 140.0, 2)
	_generate()


func _setup_noise(n: FastNoiseLite, s: int, f: float, oct: int) -> void:
	n.seed = s
	n.frequency = f
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct


## Raw height function (also used for the far skirt).
func raw_height(x: float, z: float, with_features := true) -> Vector2:
	var base := _n_base.get_noise_2d(x, z) * 28.0
	if not with_features:
		return Vector2(base, 0.0)
	var edge: float = 1.0 - smoothstep(4100.0, 4950.0, maxf(absf(x), absf(z)))
	# dunes: asymmetric ridges across a west-south-west wind, warped so they wander
	var ang := deg_to_rad(18.0)
	var s := x * cos(ang) + z * sin(ang)
	var w := _n_warp.get_noise_2d(x, z) * 220.0
	var period := 430.0 + _n_warp2.get_noise_2d(x, z) * 140.0
	var t := fposmod((s + w) / period, 1.0)
	var p := t / 0.8 if t < 0.8 else (1.0 - t) / 0.2
	p = p * p * (3.0 - 2.0 * p)
	var mask := clampf(_n_mask.get_noise_2d(x, z) * 0.9 + 0.62, 0.12, 1.0)
	var dune := p * 28.0 * mask
	# oasis basin: no dunes, a dip
	var d_oasis := Vector2(x, z).distance_to(OASIS)
	var basin := 1.0 - smoothstep(160.0, 520.0, d_oasis)
	dune *= 1.0 - basin
	var h := base + dune * edge - basin * 16.0
	# mineral field: rough broken ground
	var d_mine := Vector2(x, z).distance_to(MINE)
	var mine := 1.0 - smoothstep(250.0, 650.0, d_mine)
	h += _n_rough.get_noise_2d(x, z) * 9.0 * mine
	# mesas (hard ground)
	var m := _n_mesa.get_noise_2d(x, z)
	var d_camp := Vector2(x, z).distance_to(CAMP)
	m = maxf(m, 0.75 * (1.0 - smoothstep(380.0, 520.0, d_camp)))
	var d_start := Vector2(x, z).distance_to(CARRIER_START)
	m = minf(m, lerpf(-1.0, 1.0, smoothstep(700.0, 1300.0, d_start)))
	m = minf(m, lerpf(-1.0, 1.0, smoothstep(600.0, 900.0, d_oasis)))
	var plateau := smoothstep(0.43, 0.49, m) * edge
	var top := base + 46.0 + _n_rough.get_noise_2d(x * 0.5, z * 0.5) * 3.0
	h = lerpf(h, top, plateau)
	return Vector2(h, plateau)


func _generate() -> void:
	var count := (N + 1) * (N + 1)
	heights.resize(count)
	mesa_mask.resize(count)
	colors.resize(count)
	for j in N + 1:
		for i in N + 1:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var r := raw_height(x, z)
			heights[j * (N + 1) + i] = r.x
			mesa_mask[j * (N + 1) + i] = r.y
	water_level = height_at(OASIS.x, OASIS.y) + 2.5
	# colours from slope, mask and named places
	var sand := Color("C99F69")
	var sand_hi := Color("D8B47E")
	var lee := Color("94633E")
	var rock := Pal.UMBER
	var rock_top := Color("8E6E55")
	for j in N + 1:
		for i in N + 1:
			var k := j * (N + 1) + i
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var hx := _h(i + 1, j) - _h(i - 1, j)
			var hz := _h(i, j + 1) - _h(i, j - 1)
			var slope := Vector2(hx, hz).length() / (2.0 * CELL)
			var c := sand.lerp(sand_hi, clampf(0.5 + hx * 0.02, 0.0, 1.0))
			c = c.lerp(lee, smoothstep(0.08, 0.3, slope) * (0.85 if hx < 0.0 else 0.3))
			var m := mesa_mask[k]
			c = c.lerp(rock_top, smoothstep(0.6, 1.0, m))
			c = c.lerp(rock, smoothstep(0.3, 0.7, slope) * smoothstep(0.05, 0.4, m + slope * 0.5))
			var d_mine := Vector2(x, z).distance_to(MINE)
			c = c.lerp(Color("6B4A36"), (1.0 - smoothstep(200.0, 640.0, d_mine)) * 0.75)
			var d_oasis := Vector2(x, z).distance_to(OASIS)
			var hrel := heights[k] - water_level
			if d_oasis < 600.0:
				c = c.lerp(Pal.GREEN, (1.0 - smoothstep(0.0, 9.0, hrel)) * (1.0 - smoothstep(250.0, 560.0, d_oasis)))
				c = c.lerp(Color("7A6A48"), (1.0 - smoothstep(-2.0, 1.0, hrel)) * 0.8)
			colors[k] = c


func _h(i: int, j: int) -> float:
	i = clampi(i, 0, N)
	j = clampi(j, 0, N)
	return heights[j * (N + 1) + i]


func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / CELL
	var fz := (z + HALF) / CELL
	fx = clampf(fx, 0.0, N - 0.0001)
	fz = clampf(fz, 0.0, N - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := _h(i, j)
	var b := _h(i + 1, j)
	var c := _h(i, j + 1)
	var d := _h(i + 1, j + 1)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func is_hard_ground(x: float, z: float) -> bool:
	var fx := clampi(int((x + HALF) / CELL), 0, N)
	var fz := clampi(int((z + HALF) / CELL), 0, N)
	return mesa_mask[fz * (N + 1) + fx] > 0.6


## Steepest rise over a 50 m step, as rise/run.
func slope_at(x: float, z: float) -> float:
	var hx := height_at(x + CELL * 0.5, z) - height_at(x - CELL * 0.5, z)
	var hz := height_at(x, z + CELL * 0.5) - height_at(x, z - CELL * 0.5)
	return Vector2(hx, hz).length() / CELL


## Firm, level enough for a hauler to drive up a ramp onto a moving landship.
func good_ground(x: float, z: float) -> bool:
	return slope_at(x, z) < 0.09 or is_hard_ground(x, z)


## Height of a point above the average ground in a ring around it (for relays and scanners).
func relief_at(p: Vector2, r := 700.0) -> float:
	var sum := 0.0
	for i in 8:
		var a := TAU * i / 8.0
		var q := p + Vector2(cos(a), sin(a)) * r
		sum += height_at(q.x, q.y)
	return height_at(p.x, p.y) - sum / 8.0


func in_bounds(p: Vector2, margin := 200.0) -> bool:
	return absf(p.x) < HALF - margin and absf(p.y) < HALF - margin


# ------------------------------------------------------------------ meshes

func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var count := (N + 1) * (N + 1)
	verts.resize(count)
	cols.resize(count)
	for j in N + 1:
		for i in N + 1:
			var k := j * (N + 1) + i
			verts[k] = Vector3(-HALF + i * CELL, heights[k], -HALF + j * CELL)
			cols[k] = colors[k]
	idx.resize(N * N * 6)
	var w := 0
	for j in N:
		for i in N:
			var a := j * (N + 1) + i
			var b := a + 1
			var c := a + (N + 1)
			var d := c + 1
			if (i + j) % 2 == 0:
				idx[w] = a; idx[w + 1] = b; idx[w + 2] = d
				idx[w + 3] = a; idx[w + 4] = d; idx[w + 5] = c
			else:
				idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
				idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(count)
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Low-detail ring of dunes past the play area so the horizon is not a cliff.
func build_skirt_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ext := 40000.0
	var n := 48
	var step := ext * 2.0 / n
	for j in n:
		for i in n:
			var x0 := -ext + i * step
			var z0 := -ext + j * step
			# skip cells fully inside the play area
			if absf(x0 + step * 0.5) < HALF - step * 0.5 and absf(z0 + step * 0.5) < HALF - step * 0.5:
				continue
			var q := [Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step)]
			var p3 := []
			for v in q:
				var hh := raw_height(v.x, v.y, false).x
				var far := smoothstep(6000.0, 30000.0, v.length())
				hh += sin(v.x * 0.0011 + v.y * 0.0004) * 24.0 * far + far * 30.0
				p3.append(Vector3(v.x, hh - 1.5, v.y))
			var c := Pal.OCHRE.darkened(0.04)
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for t in tri:
					st.set_color(c)
					st.add_vertex(p3[t])
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ textures for maps

## Height as a float texture. `res` pixels across the whole map.
func height_texture(res: int) -> ImageTexture:
	var img := Image.create(res, res, false, Image.FORMAT_RF)
	for y in res:
		for x in res:
			var wx := -HALF + (x + 0.5) / res * SIZE
			var wz := -HALF + (y + 0.5) / res * SIZE
			img.set_pixel(x, y, Color(height_at(wx, wz), 0, 0))
	return ImageTexture.create_from_image(img)


## Feature mask texture: R mesa, G oasis/water, B mineral.
func feature_texture(res: int) -> ImageTexture:
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	for y in res:
		for x in res:
			var wx := -HALF + (x + 0.5) / res * SIZE
			var wz := -HALF + (y + 0.5) / res * SIZE
			var fx := clampi(int((wx + HALF) / CELL), 0, N)
			var fz := clampi(int((wz + HALF) / CELL), 0, N)
			var m := mesa_mask[fz * (N + 1) + fx]
			var wat := 1.0 if height_at(wx, wz) < water_level and Vector2(wx, wz).distance_to(OASIS) < 650.0 else 0.0
			var mine := 1.0 - smoothstep(250.0, 650.0, Vector2(wx, wz).distance_to(MINE))
			img.set_pixel(x, y, Color(m, wat, mine))
	return ImageTexture.create_from_image(img)


static func world_to_uv(p: Vector2) -> Vector2:
	return (p + Vector2(HALF, HALF)) / SIZE


static func bearing_deg(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
