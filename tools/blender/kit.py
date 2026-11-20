"""
Landship asset kit — shared helpers for every Blender asset script.

Follows the Art Profile tab of the design doc:
  * 1 Blender unit = 1 metre, origin on the ground at the asset centre.
  * Blender +Y is the front of every asset (exports to Godot -Z).
  * Flat shading only, faceted shapes (boxes, wedges, convex hulls, 8-12 sided cylinders).
  * One shared palette texture; every face samples one swatch.
  * Sockets are Empties named socket_<type>_<n>; moving parts are separate objects
    with their origin on the axis of rotation.

Run any asset script with:  python3 tools/blender/build_all.py
"""
import math
import os
import random

import bpy  # must load before bmesh
import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE_PNG = os.path.join(ROOT, "assets", "textures", "palette.png")
OUT_DIR = os.path.join(ROOT, "assets", "models")

# 8 x 4 swatches. Order is the contract with Godot (scripts/core/palette.gd mirrors it).
PALETTE = [
    ("bone", "#D9D2C0"), ("gunmetal", "#4A4E52"), ("orange", "#E0762A"), ("amber", "#FFB347"),
    ("plum", "#2B2230"), ("verdigris", "#7FD1B9"), ("cyan", "#5FF2E0"), ("ochre", "#D8B581"),
    ("rust", "#A9744A"), ("umber", "#6E5444"), ("green", "#5E7F52"), ("teal", "#3F7C84"),
    ("charcoal", "#2E3236"), ("phosphor", "#FFB000"), ("black", "#15171A"), ("grey", "#7A7E80"),
    ("bone_dark", "#A8A190"), ("glass", "#1E2A2E"), ("red", "#C0392B"), ("olive", "#4F5442"),
    ("helmet", "#8C9090"), ("visor", "#0E1214"), ("rubber", "#262626"), ("white", "#ECECEC"),
    ("steel", "#5C6166"), ("plum_light", "#4A3B52"), ("deck", "#3B3F42"), ("hazard", "#D9A300"),
    ("screen", "#7CFFB2"), ("blue_steel", "#39454E"), ("sand_dark", "#8A6A48"), ("lamp", "#FFF1D0"),
]
SW = {name: i for i, (name, _) in enumerate(PALETTE)}
COLS, ROWS = 8, 4

# Material slots. Godot swaps these for its shared materials by name.
MATERIALS = ["hull", "interior", "alien", "emit", "glass", "screen", "rock"]


def swatch_uv(name):
    i = SW[name]
    c, r = i % COLS, i // COLS
    return Vector(((c + 0.5) / COLS, 1.0 - (r + 0.5) / ROWS))


# ----------------------------------------------------------------------------- scene

def reset(seed=1):
    random.seed(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mat_cache.clear()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


_mat_cache = {}


def material(name):
    if name in _mat_cache:
        return _mat_cache[name]
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    img = bpy.data.images.get("palette.png") or bpy.data.images.load(PALETTE_PNG)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    if name == "emit":
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0
    if name == "glass":
        bsdf.inputs["Alpha"].default_value = 0.35
        bsdf.inputs["Roughness"].default_value = 0.1
    _mat_cache[name] = m
    return m


# ----------------------------------------------------------------------------- mesh building

class Part:
    """Accumulates faceted geometry into one bmesh; finished into one object."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []  # material names in slot order

    def _slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _paint(self, faces, color, mat):
        uv = swatch_uv(color)
        slot = self._slot(mat)
        for f in faces:
            f.material_index = slot
            f.smooth = False
            for l in f.loops:
                l[self.uv].uv = uv

    # -- primitives -------------------------------------------------------
    def hull(self, points, color="bone", mat="hull", m=None):
        """Convex hull of points: the workhorse for chamfered, faceted shapes."""
        m = m or Matrix()
        uniq = []
        for p in points:
            v = m @ Vector(p)
            if all((v - u).length > 1e-6 for u in uniq):
                uniq.append(v)
        verts = [self.bm.verts.new(v) for v in uniq]
        res = bmesh.ops.convex_hull(self.bm, input=verts)
        # drop points that ended up inside the hull
        loose = list({v for v in res.get("geom_interior", []) + res.get("geom_unused", []) if isinstance(v, bmesh.types.BMVert) and v.is_valid})
        if loose:
            bmesh.ops.delete(self.bm, geom=loose, context="VERTS")
        faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace) and g.is_valid]
        # merge coplanar triangles into clean facets
        edges = list({e for f in faces for e in f.edges})
        bmesh.ops.dissolve_limit(self.bm, angle_limit=math.radians(1.0), use_dissolve_boundaries=False, verts=[], edges=edges)
        self._paint_unpainted(color, mat)
        return self

    def _paint_unpainted(self, color, mat):
        # Faces with a zero UV have not been painted yet.
        uv = swatch_uv(color)
        slot = self._slot(mat)
        for f in self.bm.faces:
            if f.loops[0][self.uv].uv.length == 0.0:
                f.material_index = slot
                f.smooth = False
                for l in f.loops:
                    l[self.uv].uv = uv

    def box(self, size, loc=(0, 0, 0), color="bone", mat="hull", rot=(0, 0, 0), chamfer=0.0, taper=None):
        """Box with optional chamfer (real geometry) and top taper (x,y scale of top face)."""
        sx, sy, sz = (s / 2 for s in size)
        tx, ty = taper or (1.0, 1.0)
        pts = []
        c = min(chamfer, sx * 0.9, sy * 0.9, sz * 0.9)
        for zs, (kx, ky) in ((-1, (1, 1)), (1, (tx, ty))):
            for xs in (-1, 1):
                for ys in (-1, 1):
                    x, y, z = xs * sx * kx, ys * sy * ky, zs * sz
                    if c > 0:
                        pts += [(x - xs * c, y, z), (x, y - ys * c, z), (x, y, z - zs * c)]
                    else:
                        pts.append((x, y, z))
        mtx = Matrix.Translation(loc) @ euler(rot)
        return self.hull(pts, color, mat, mtx)

    def cyl(self, r, h, loc=(0, 0, 0), sides=10, color="gunmetal", mat="hull", rot=(0, 0, 0), r2=None):
        """Cylinder along local Z, base at -h/2. r2 makes a cone/frustum."""
        r2 = r if r2 is None else r2
        pts = []
        for i in range(sides):
            a = 2 * math.pi * (i + 0.5) / sides
            pts.append((math.cos(a) * r, math.sin(a) * r, -h / 2))
            pts.append((math.cos(a) * r2, math.sin(a) * r2, h / 2))
        mtx = Matrix.Translation(loc) @ euler(rot)
        return self.hull(pts, color, mat, mtx)

    def sphere(self, r, loc=(0, 0, 0), sides=10, rings=5, color="gunmetal", mat="hull", scale=(1, 1, 1)):
        pts = []
        for j in range(rings + 1):
            t = math.pi * j / rings
            for i in range(sides):
                a = 2 * math.pi * (i + 0.5 * (j % 2)) / sides
                pts.append((math.sin(t) * math.cos(a) * r * scale[0], math.sin(t) * math.sin(a) * r * scale[1], math.cos(t) * r * scale[2]))
        return self.hull(pts, color, mat, Matrix.Translation(loc))

    def quad(self, corners, color="glass", mat="glass", double=True, uvs=None):
        """Single flat polygon (glass panes, screens). `uvs` gives real 0-1 UVs for runtime textures."""
        vs = [self.bm.verts.new(Vector(c)) for c in corners]
        f = self.bm.faces.new(vs)
        fs = [f]
        if double:
            vs2 = [self.bm.verts.new(Vector(c)) for c in reversed(corners)]
            fs.append(self.bm.faces.new(vs2))
        self._paint(fs, color, mat)
        if uvs:
            for l, uv in zip(f.loops, uvs):
                l[self.uv].uv = Vector(uv)
        self.keep_open = True
        return self

    # -- finish ---------------------------------------------------------------
    def build(self, parent=None, loc=(0, 0, 0), origin=None):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        if not getattr(self, "keep_open", False):
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        for f in me.polygons:
            f.use_smooth = False
        for m in self.mats:
            me.materials.append(material(m))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if origin is not None:
            # move geometry so the object origin sits at `origin` (local coords of the part)
            me.transform(Matrix.Translation(-Vector(origin)))
            ob.location = Vector(origin)
        if parent is not None:
            ob.parent = parent
        ob.location = ob.location + Vector(loc)
        return ob


def tilted_rect(center, hw, hh, tilt_deg):
    """Corners of a rectangle in the XZ plane, tilted about X by tilt_deg, centred on `center`."""
    m = Matrix.Translation(center) @ euler((tilt_deg, 0, 0))
    return [tuple(m @ Vector(p)) for p in ((-hw, 0, -hh), (hw, 0, -hh), (hw, 0, hh), (-hw, 0, hh))]


def euler(rot):
    from mathutils import Euler
    return Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0), size=0.25):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    e.location = loc
    e.rotation_euler = [math.radians(a) for a in rot]
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def root(name):
    return empty(name, size=1.0)


# ----------------------------------------------------------------------------- checks + export

def tri_count():
    n = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH" and not ob.name.endswith("-colonly"):
            for p in ob.data.polygons:
                n += len(p.vertices) - 2
    return n


def export(filename, limit=None):
    os.makedirs(OUT_DIR, exist_ok=True)
    tris = tri_count()
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_extras=True,
    )
    status = "OK" if (limit is None or tris <= limit) else "OVER LIMIT"
    print(f"[kit] {filename}: {tris} tris (limit {limit}) {status}")
    if limit is not None and tris > limit:
        raise SystemExit(f"{filename} is over its triangle limit")
    return tris


def mirror_x(points):
    return points + [(-x, y, z) for (x, y, z) in points]
