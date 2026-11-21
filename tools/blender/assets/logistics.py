"""The supply war: hub parts, relay mast, scanner post, hauler, lifter, kit crate, and the
alien outpost that raiders plant on a site they have taken.

Human shape language (Art Profile): boxy, chamfered, bolted-on modules, bone hull with
gunmetal and orange hazard stripes, amber running lights. Moving parts are separate
objects with their origin on the axis. Variant parts (cargo pod, engineer arm, sling, gun)
are separate objects that Godot shows or hides by name.
"""
import math

from kit import Part, empty, export, reset, root


def _lattice(p, x0, y0, x1, y1, z0, z1, color="gunmetal", bars=4, w=0.12):
    """Tapered square lattice tower: four legs and alternating braces."""
    legs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in legs:
        p.hull([(sx * x0, sy * y0, z0), (sx * x0 - sx * w, sy * y0, z0), (sx * x0, sy * y0 - sy * w, z0),
                (sx * x1, sy * y1, z1), (sx * x1 - sx * w, sy * y1, z1), (sx * x1, sy * y1 - sy * w, z1)], color)
    for i in range(bars):
        t0, t1 = i / bars, (i + 1) / bars
        za, zb = z0 + (z1 - z0) * t0, z0 + (z1 - z0) * t1
        xa, xb = x0 + (x1 - x0) * t0, x0 + (x1 - x0) * t1
        ya, yb = y0 + (y1 - y0) * t0, y0 + (y1 - y0) * t1
        for k in range(4):
            sx, sy = legs[k]
            nx, ny = legs[(k + 1) % 4]
            a = (sx * xa, sy * ya, za) if i % 2 == 0 else (nx * xa, ny * ya, za)
            b = (nx * xb, ny * yb, zb) if i % 2 == 0 else (sx * xb, sy * yb, zb)
            p.hull([a, (a[0], a[1], a[2] + w), b, (b[0], b[1], b[2] + w),
                    (a[0] + 0.05, a[1] + 0.05, a[2]), (b[0] + 0.05, b[1] + 0.05, b[2])], color)


def extractor():
    """hum_str_extractor — 14 m drill rig over the site, with settling tanks."""
    reset(61)
    r = root("hum_str_extractor")
    p = Part("rig")
    p.box((10.0, 8.0, 1.0), (0, 0, 0.5), "gunmetal", chamfer=0.3)
    p.box((9.4, 7.4, 0.2), (0, 0, 1.1), "deck")
    _lattice(p, 2.2, 2.2, 0.8, 0.8, 1.2, 12.5, "bone", bars=5, w=0.22)
    p.box((2.2, 2.2, 1.4), (0, 0, 13.0), "bone", chamfer=0.2)
    p.box((2.3, 0.3, 0.3), (0, 1.15, 12.6), "orange")
    p.cyl(0.35, 12.0, (0, 0, 6.6), sides=8, color="steel")
    # engine house
    p.box((3.2, 3.0, 2.6), (-3.2, -1.8, 2.4), "bone", chamfer=0.25)
    p.box((3.3, 0.35, 0.4), (-3.2, -0.3, 3.2), "orange")
    p.cyl(0.25, 2.2, (-4.2, -2.6, 4.6), sides=8, color="charcoal")
    # settling tanks
    for i, (x, y) in enumerate(((3.0, 2.0), (3.0, -1.0), (0.4, -3.0))):
        p.cyl(1.1, 2.6, (x, y, 2.4), sides=10, color="bone_dark" if i % 2 else "bone")
        p.cyl(1.15, 0.25, (x, y, 3.0), sides=10, color="orange")
    # pipe run
    p.box((4.0, 0.3, 0.3), (1.4, 0.6, 1.5), "steel")
    p.box((0.3, 3.2, 0.3), (3.0, 0.5, 1.5), "steel")
    p.build(parent=r)
    g = Part("rig_lights")
    for (x, y, z) in ((0.9, 0.9, 13.8), (-0.9, -0.9, 13.8), (4.9, 3.9, 1.2), (-4.9, -3.9, 1.2)):
        g.box((0.2, 0.2, 0.2), (x, y, z), "amber", mat="emit")
    g.build(parent=r)
    pump = Part("pump_head")  # bobs up and down
    pump.box((1.6, 1.6, 0.8), (0, 0, 10.0), "hazard", chamfer=0.1)
    pump.build(parent=r, origin=(0, 0, 10.0))
    return export("hum_str_extractor.glb", limit=1600)


def turret():
    """hum_str_turret — hub point-defence turret. `turret_head` yaws, origin on its axis."""
    reset(62)
    r = root("hum_str_turret")
    b = Part("base")
    b.cyl(2.6, 1.2, (0, 0, 0.6), sides=8, color="gunmetal", r2=2.2)
    b.cyl(1.6, 1.6, (0, 0, 2.0), sides=8, color="bone", r2=1.4)
    b.box((3.4, 0.4, 0.3), (0, 0, 1.25), "orange")
    b.build(parent=r)
    h = Part("turret_head")
    h.box((2.6, 3.0, 1.4), (0, 0.2, 3.5), "bone", chamfer=0.3, taper=(0.85, 0.8))
    h.box((2.0, 0.5, 0.6), (0, -1.4, 3.6), "gunmetal")
    for sx in (-0.45, 0.45):
        h.cyl(0.14, 3.2, (sx, 2.8, 3.55), sides=6, color="charcoal", rot=(90, 0, 0))
    h.box((0.5, 0.3, 0.3), (1.0, 1.4, 4.3), "black")  # sight
    h.build(parent=r, origin=(0, 0, 3.0))
    g = Part("turret_light")
    g.box((0.18, 0.18, 0.18), (0, -0.6, 4.3), "amber", mat="emit")
    g.build(parent=r)
    empty("socket_muzzle_0", (0, 4.4, 3.55), r)
    return export("hum_str_turret.glb", limit=700)


def pad():
    """hum_str_pad — loading pad: landing square for lifters, ramp bay for haulers, a gantry."""
    reset(63)
    r = root("hum_str_pad")
    p = Part("pad")
    p.box((18.0, 14.0, 0.6), (0, 0, 0.3), "gunmetal", chamfer=0.2)
    p.box((10.0, 10.0, 0.1), (-3.0, 0, 0.65), "deck")
    for i in range(6):  # hazard edge on the landing square
        p.box((1.2, 0.3, 0.06), (-7.4 + i * 1.75, 4.9, 0.72), "hazard")
        p.box((1.2, 0.3, 0.06), (-7.4 + i * 1.75, -4.9, 0.72), "hazard")
    # hauler ramp bay with a loading gantry over it
    p.box((5.0, 12.0, 0.2), (6.2, 0, 0.7), "sand_dark")
    for y in (-5.5, 5.5):
        p.box((0.4, 0.4, 7.0), (4.0, y, 4.0), "bone")
        p.box((0.4, 0.4, 7.0), (8.4, y, 4.0), "bone")
    p.box((5.0, 11.8, 0.5), (6.2, 0, 7.6), "bone")
    p.box((5.2, 0.4, 0.4), (6.2, 0, 7.2), "orange")
    p.box((1.2, 1.4, 1.0), (6.2, 1.5, 6.8), "gunmetal")  # hoist trolley
    p.build(parent=r)
    g = Part("pad_lights")
    for (x, y) in ((-7.8, 4.8), (1.8, 4.8), (-7.8, -4.8), (1.8, -4.8)):
        g.box((0.25, 0.25, 0.2), (x, y, 0.8), "amber", mat="emit")
    g.build(parent=r)
    empty("socket_land_0", (-3.0, 0, 0.7), r)
    empty("socket_bay_0", (6.2, 0, 0.8), r)
    return export("hum_str_pad.glb", limit=800)


def relay():
    """hum_str_relay — 20 m lattice relay mast with a turning dish."""
    reset(64)
    r = root("hum_str_relay")
    p = Part("mast")
    p.box((5.0, 5.0, 0.8), (0, 0, 0.4), "gunmetal", chamfer=0.2)
    _lattice(p, 1.6, 1.6, 0.35, 0.35, 0.8, 19.0, "bone", bars=6, w=0.14)
    p.box((1.2, 1.2, 0.5), (0, 0, 19.2), "gunmetal")
    p.box((1.8, 1.0, 1.2), (1.8, 0.0, 1.4), "bone", chamfer=0.1)  # equipment box
    p.box((1.9, 0.2, 0.25), (1.8, 0.5, 1.6), "orange")
    p.build(parent=r)
    d = Part("dish")
    d.cyl(0.12, 2.0, (0, 0, 20.4), sides=6, color="steel")
    pts = []
    for i in range(10):
        a = 2 * math.pi * i / 10
        pts.append((math.cos(a) * 1.6, 0.6, 21.2 + math.sin(a) * 1.6))
    pts += [(0, 0.0, 21.2), (0, 1.1, 21.2)]
    d.hull(pts, "white")
    d.cyl(0.06, 1.4, (0, 1.4, 21.2), sides=5, color="steel", rot=(90, 0, 0))
    d.build(parent=r, origin=(0, 0, 20.0))
    g = Part("mast_light")
    g.box((0.3, 0.3, 0.3), (0, 0, 19.6), "red", mat="emit")
    g.build(parent=r)
    return export("hum_str_relay.glb", limit=900)


def scanner():
    """hum_str_scanner — scanner post: a squat sensor drum with a turning radar bar."""
    reset(65)
    r = root("hum_str_scanner")
    p = Part("post")
    p.cyl(2.4, 0.8, (0, 0, 0.4), sides=8, color="gunmetal")
    p.cyl(1.0, 6.0, (0, 0, 3.8), sides=8, color="bone", r2=0.7)
    p.cyl(1.05, 0.4, (0, 0, 2.2), sides=8, color="orange")
    p.box((1.6, 1.0, 1.2), (1.4, 0, 1.2), "bone", chamfer=0.1)
    p.build(parent=r)
    h = Part("scanner_head")
    h.cyl(0.9, 0.9, (0, 0, 7.3), sides=8, color="gunmetal")
    h.box((5.0, 0.5, 0.9), (0, 0, 8.2), "white", chamfer=0.1)
    h.box((0.6, 0.55, 0.3), (2.3, 0, 8.2), "orange")
    h.build(parent=r, origin=(0, 0, 7.0))
    g = Part("scanner_light")
    g.box((0.25, 0.25, 0.25), (0, 0.6, 7.0), "amber", mat="emit")
    g.build(parent=r)
    return export("hum_str_scanner.glb", limit=700)


def crate():
    """hum_kit_crate — a planted kit before it is assembled."""
    reset(66)
    r = root("hum_kit_crate")
    p = Part("crate")
    p.box((4.0, 3.0, 2.4), (0, 0, 1.2), "bone_dark", chamfer=0.15)
    p.box((4.1, 0.3, 2.5), (0, 0.8, 1.2), "orange")
    p.box((4.1, 0.3, 2.5), (0, -0.8, 1.2), "gunmetal")
    p.box((1.0, 3.1, 0.3), (0, 0, 2.45), "gunmetal")
    p.build(parent=r)
    return export("hum_kit_crate.glb", limit=120)


def hauler():
    """hum_gnd_hauler — 12 m six-wheel hauler. Variant parts: pod, engineer, gun."""
    reset(67)
    r = root("hum_gnd_hauler")
    c = Part("chassis")
    c.box((3.0, 11.0, 0.8), (0, -0.2, 1.4), "gunmetal", chamfer=0.15)
    # cab
    c.box((3.0, 3.0, 2.4), (0, 4.0, 3.0), "bone", chamfer=0.3, taper=(0.92, 0.8))
    c.hull([(-1.3, 5.4, 3.2), (1.3, 5.4, 3.2), (-1.15, 5.15, 4.1), (1.15, 5.15, 4.1), (-1.3, 5.0, 3.2), (1.3, 5.0, 3.2)], "glass", mat="glass")
    c.box((3.05, 0.3, 0.35), (0, 2.6, 2.4), "orange")
    c.box((3.2, 0.5, 0.6), (0, 5.6, 1.6), "charcoal")  # bumper
    c.cyl(0.15, 1.6, (1.3, 2.7, 4.6), sides=6, color="charcoal")  # exhaust
    # wheels (static: a hauler at 9 m/s, seen from 300 m, does not need them to turn)
    for y in (3.6, -1.6, -4.4):
        for sx in (-1, 1):
            c.cyl(0.85, 0.7, (sx * 1.65, y, 0.85), sides=10, color="rubber", rot=(0, 90, 0))
            c.cyl(0.4, 0.74, (sx * 1.65, y, 0.85), sides=6, color="steel", rot=(0, 90, 0))
    c.box((3.2, 2.0, 0.3), (0, -3.0, 1.9), "deck")  # bed floor
    c.build(parent=r)
    pod = Part("pod")
    pod.box((2.8, 6.4, 2.6), (0, -2.2, 3.35), "bone_dark", chamfer=0.2)
    for y in (-4.6, -2.2, 0.2):
        pod.box((2.9, 0.25, 2.7), (0, y, 3.35), "gunmetal")
    pod.box((2.85, 6.0, 0.25), (0, -2.2, 4.0), "orange")
    pod.build(parent=r)
    eng = Part("engineer")
    eng.box((2.6, 2.6, 1.6), (0, -4.2, 2.8), "hazard", chamfer=0.15)
    eng.cyl(0.4, 1.0, (0, -1.6, 2.6), sides=8, color="gunmetal")
    eng.hull([(-0.3, -1.6, 2.9), (0.3, -1.6, 2.9), (-0.25, -1.4, 6.5), (0.25, -1.4, 6.5), (-0.3, -1.9, 2.9), (0.3, -1.9, 2.9)], "bone")
    eng.hull([(-0.2, -1.4, 6.4), (0.2, -1.4, 6.4), (-0.15, -5.0, 5.0), (0.15, -5.0, 5.0), (-0.2, -1.6, 6.7), (0.2, -1.6, 6.7)], "bone")
    eng.box((0.5, 0.5, 1.4), (0, -5.0, 4.2), "charcoal")
    eng.build(parent=r)
    gun = Part("gun")
    gun.cyl(0.55, 0.5, (0, 3.6, 4.45), sides=8, color="gunmetal")
    gun.box((0.7, 1.2, 0.5), (0, 3.9, 4.9), "bone", chamfer=0.08)
    gun.cyl(0.08, 1.8, (0, 5.2, 4.95), sides=6, color="charcoal", rot=(90, 0, 0))
    gun.build(parent=r)
    lights = Part("hauler_lights")
    for sx in (-1, 1):
        lights.box((0.4, 0.1, 0.25), (sx * 1.1, 5.86, 2.1), "lamp", mat="emit")
        lights.box((0.3, 0.1, 0.2), (sx * 1.3, -5.7, 1.7), "red", mat="emit")
    lights.box((0.4, 0.4, 0.2), (0, 3.4, 4.3), "amber", mat="emit")
    lights.build(parent=r)
    empty("socket_dust", (0, -5.0, 0.4), r)
    return export("hum_gnd_hauler.glb", limit=1800)


def lifter():
    """hum_air_lifter — four-rotor heavy lifter. Rotors spin; variant parts: pod, sling, gun."""
    reset(68)
    r = root("hum_air_lifter")
    f = Part("frame")
    f.box((2.6, 7.0, 1.8), (0, 0, 3.0), "bone", chamfer=0.35, taper=(0.85, 0.9))
    f.hull([(-0.9, 3.4, 2.4), (0.9, 3.4, 2.4), (-0.7, 4.3, 2.9), (0.7, 4.3, 2.9), (-0.8, 3.5, 3.7), (0.8, 3.5, 3.7)], "bone")
    f.hull([(-0.7, 3.9, 3.0), (0.7, 3.9, 3.0), (-0.55, 4.25, 3.1), (0.55, 4.25, 3.1), (-0.6, 3.7, 3.55), (0.6, 3.7, 3.55)], "glass", mat="glass")
    f.box((2.65, 0.4, 1.0), (0, 1.6, 3.2), "orange")
    rotors = ((-3.6, 2.6), (3.6, 2.6), (-3.6, -2.6), (3.6, -2.6))
    for (x, y) in rotors:
        f.hull([(0, y * 0.6, 3.4), (0, y * 0.6 - 0.4, 3.4), (x, y, 3.9), (x, y - 0.4, 3.9), (0, y * 0.6, 3.7), (x, y, 4.1)], "gunmetal")
        f.cyl(0.7, 0.9, (x, y, 4.1), sides=8, color="gunmetal")
        f.cyl(1.9, 0.25, (x, y, 4.75), sides=12, color="charcoal", r2=1.95)  # duct ring
    for sx in (-1, 1):
        f.box((0.2, 4.6, 0.2), (sx * 1.1, 0, 0.9), "steel")
        f.box((0.2, 0.2, 1.4), (sx * 1.1, 1.8, 1.6), "steel")
        f.box((0.2, 0.2, 1.4), (sx * 1.1, -1.8, 1.6), "steel")
    f.build(parent=r)
    for i, (x, y) in enumerate(rotors):
        rt = Part(f"rotor_{i}")
        rt.box((3.3, 0.35, 0.06), (x, y, 4.8), "black")
        rt.box((0.35, 3.3, 0.06), (x, y, 4.8), "black")
        rt.build(parent=r, origin=(x, y, 4.8))
    pod = Part("pod")
    pod.box((2.2, 3.6, 1.6), (0, -0.2, 1.4), "bone_dark", chamfer=0.15)
    pod.box((2.25, 0.25, 1.65), (0, -0.2, 1.4), "gunmetal")
    pod.build(parent=r)
    sl = Part("sling")
    for (x, y) in ((-0.8, 1.2), (0.8, 1.2), (-0.8, -1.2), (0.8, -1.2)):
        sl.hull([(0, 0, 2.1), (0.05, 0, 2.1), (x, y, -1.6), (x + 0.05, y, -1.6)], "steel")
    sl.box((2.6, 2.0, 1.6), (0, 0, -2.4), "bone_dark", chamfer=0.12)
    sl.box((2.65, 0.3, 1.65), (0, 0.4, -2.4), "orange")
    sl.build(parent=r)
    gun = Part("gun")
    gun.cyl(0.4, 0.5, (0, 2.6, 1.9), sides=8, color="gunmetal")
    gun.cyl(0.07, 1.4, (0, 3.4, 1.8), sides=6, color="charcoal", rot=(90, 0, 0))
    gun.build(parent=r)
    lights = Part("lifter_lights")
    lights.box((0.2, 0.2, 0.2), (0, -3.5, 3.9), "red", mat="emit")
    for (x, y) in rotors:
        lights.box((0.15, 0.15, 0.15), (x * 1.5, y, 4.75), "amber", mat="emit")
    lights.build(parent=r)
    return export("hum_air_lifter.glb", limit=1400)


def outpost():
    """aln_str_outpost — the faceted cocoon raiders plant on a site they have taken."""
    reset(69)
    r = root("aln_str_outpost")
    p = Part("outpost")
    p.cyl(5.0, 1.0, (0, 0, 0.5), sides=5, color="plum", mat="alien", r2=4.5)
    # leaning cocoon: two offset hulls
    p.hull([(-2.6, -1.8, 1.0), (2.4, -2.2, 1.0), (2.8, 2.0, 1.0), (-2.2, 2.6, 1.0),
            (-1.6, -1.0, 6.0), (1.8, -1.2, 5.5), (1.4, 1.6, 6.5), (0.2, 0.4, 9.5)], "plum_light", mat="alien")
    p.hull([(1.0, -0.4, 5.0), (2.2, 0.6, 5.0), (1.6, 1.6, 5.4), (2.6, 1.4, 11.0), (2.9, 1.8, 10.6)], "verdigris", mat="alien")
    for a in (30, 150, 270):
        rad = math.radians(a)
        cx, cy = math.cos(rad), math.sin(rad)
        p.hull([(cx * 3.6, cy * 3.6, 1.0), (cx * 3.8 + cy * 0.6, cy * 3.8 - cx * 0.6, 1.0), (cx * 6.5, cy * 6.5, 0.2),
                (cx * 2.8, cy * 2.8, 4.0)], "verdigris", mat="alien")
        p.cyl(1.8, 0.3, (cx * 9.0, cy * 9.0, 0.15), sides=5, color="plum_light", mat="alien")
    p.build(parent=r)
    g = Part("outpost_glow")
    g.sphere(0.7, (0.4, 0.4, 7.2), sides=6, rings=3, color="cyan", mat="emit", scale=(1, 1, 1.5))
    for a in (30, 150, 270):
        rad = math.radians(a)
        g.cyl(1.3, 0.05, (math.cos(rad) * 9.0, math.sin(rad) * 9.0, 0.33), sides=5, color="cyan", mat="emit")
    g.build(parent=r)
    return export("aln_str_outpost.glb", limit=900)


def build():
    extractor()
    turret()
    pad()
    relay()
    scanner()
    crate()
    hauler()
    lifter()
    outpost()
