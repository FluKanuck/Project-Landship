"""Swift light fixed-wing scout drone + gimbal camera module. Wedge set item 8."""
import math

from kit import Part, empty, export, reset, root


def section(y, w, z0, z1, n=8):
    """Octagonal-ish fuselage cross-section at station y."""
    pts = []
    cz, hz = (z0 + z1) / 2, (z1 - z0) / 2
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        pts.append((math.cos(a) * w / 2, y, cz + math.sin(a) * hz))
    return pts


def swift():
    """hum_air_swift — 6 m scout. High straight wing, V-tail, pusher prop."""
    reset(31)
    r = root("hum_air_swift")
    f = Part("airframe")
    # fuselage: one convex hull through a few stations
    pts = [(0, 3.15, 0.92)]
    pts += section(2.6, 0.5, 0.66, 1.18)
    pts += section(1.6, 0.78, 0.56, 1.32)
    pts += section(0.2, 0.82, 0.56, 1.34)
    pts += section(-1.4, 0.6, 0.72, 1.3)
    pts += section(-2.55, 0.32, 0.92, 1.22)
    f.hull(pts, "bone")
    # belly plate in gunmetal
    f.hull([(x * 0.33, y, z) for (x, y, z) in section(1.4, 1.0, 0.53, 0.6, 6) + section(-1.2, 0.8, 0.68, 0.74, 6)], "gunmetal")
    # orange stripe band behind the nose
    f.hull(section(2.1, 0.68, 0.6, 1.26) + section(1.85, 0.74, 0.58, 1.29), "orange")
    # sensor window band (dark), unmanned so no canopy
    f.hull([(-0.22, 2.55, 1.12), (0.22, 2.55, 1.12), (-0.3, 2.0, 1.25), (0.3, 2.0, 1.25), (0, 2.25, 1.23), (0, 2.6, 1.15)], "glass")
    # wing: two tapered halves with 3 deg dihedral and a little sweep
    for sx in (-1, 1):
        tip_z = 1.36 + 3.6 * math.tan(math.radians(3))
        w = [
            (sx * 0.2, 0.95, 1.36), (sx * 0.2, 0.0, 1.36), (sx * 0.2, 0.95, 1.46), (sx * 0.2, 0.0, 1.44),
            (sx * 3.6, 0.72, tip_z), (sx * 3.6, 0.15, tip_z), (sx * 3.6, 0.72, tip_z + 0.05), (sx * 3.6, 0.15, tip_z + 0.05),
        ]
        f.hull(w, "bone")
        f.box((0.1, 0.12, 0.06), (sx * 3.62, 0.5, tip_z + 0.02), "amber", mat="emit")  # wingtip light
        f.box((0.6, 0.08, 0.03), (sx * 2.6, 0.2, tip_z - 0.04), "gunmetal")  # aileron hinge line
    f.box((0.5, 1.1, 0.12), (0, 0.48, 1.42), "gunmetal", chamfer=0.03)  # wing root fairing
    # engine intake on top behind the wing
    f.hull([(-0.2, -0.3, 1.33), (0.2, -0.3, 1.33), (-0.14, -0.3, 1.5), (0.14, -0.3, 1.5),
            (-0.18, -1.6, 1.3), (0.18, -1.6, 1.3), (-0.1, -1.4, 1.42), (0.1, -1.4, 1.42)], "gunmetal")
    f.box((0.28, 0.04, 0.14), (0, -0.3, 1.42), "black")
    # V-tail
    for sx in (-1, 1):
        a = math.radians(35)
        base = (sx * 0.08, -2.0, 1.2)
        tip = (sx * (0.08 + math.sin(a) * 1.1), -2.5, 1.2 + math.cos(a) * 1.1)
        f.hull([base, (base[0], -2.6, 1.2), (base[0], -2.0, 1.25), (base[0], -2.6, 1.25),
                tip, (tip[0], -2.85, tip[2]), (tip[0] + sx * 0.04, -2.5, tip[2]), (tip[0] + sx * 0.04, -2.85, tip[2])], "bone")
    f.box((0.06, 0.08, 0.06), (0, -2.62, 1.3), "red", mat="emit")  # tail strobe
    # landing gear
    f.cyl(0.035, 0.45, (0, 2.0, 0.3), sides=6, color="steel")
    f.cyl(0.11, 0.07, (0, 2.0, 0.11), sides=8, color="rubber", rot=(0, 90, 0))
    for sx in (-1, 1):
        f.hull([(sx * 0.3, -0.4, 0.62), (sx * 0.3, -0.7, 0.62), (sx * 0.75, -0.5, 0.14), (sx * 0.75, -0.6, 0.14)], "steel")
        f.cyl(0.13, 0.08, (sx * 0.78, -0.55, 0.13), sides=8, color="rubber", rot=(0, 90, 0))
    f.cyl(0.012, 0.35, (0.1, 0.9, 1.6), sides=6, color="black")  # whip antenna
    f.build(parent=r)

    prop = Part("rotor_main")  # pusher prop, spins about +Y
    c = (0, -2.78, 1.07)
    prop.cyl(0.11, 0.22, (0, -2.8, 1.07), sides=8, color="gunmetal", rot=(90, 0, 0), r2=0.03)
    for i in range(3):
        a = math.radians(i * 120 + 10)
        tip = (math.cos(a) * 0.62, -2.8, 1.07 + math.sin(a) * 0.62)
        n = (math.cos(a + 1.57) * 0.06, 0, math.sin(a + 1.57) * 0.06)
        prop.hull([(c[0] + n[0], -2.77, c[2] + n[2]), (c[0] - n[0], -2.83, c[2] - n[2]),
                   (tip[0] + n[0] * 0.6, -2.79, tip[2] + n[2] * 0.6), (tip[0] - n[0] * 0.6, -2.81, tip[2] - n[2] * 0.6)], "charcoal")
    prop.build(parent=r, origin=c)

    empty("socket_camera_0", (0, 2.15, 0.6), r)
    empty("socket_pylon_s_0", (-1.8, 0.55, 1.38), r)
    empty("socket_pylon_s_1", (1.8, 0.55, 1.38), r)
    empty("socket_utility_0", (0, -1.0, 1.36), r)
    return export("hum_air_swift.glb", limit=800)


def gimbal_camera():
    """mod_sen_gimbal_cam — fits socket_camera. Origin at the mount; it hangs down."""
    reset(32)
    r = root("mod_sen_gimbal_cam")
    m = Part("mount")
    m.cyl(0.08, 0.06, (0, 0, -0.03), sides=8, color="gunmetal")
    m.box((0.05, 0.05, 0.12), (0, 0, -0.1), "steel")
    m.build(parent=r)
    b = Part("gimbal_ball")  # yaws and pitches about its centre
    b.sphere(0.15, (0, 0, -0.25), sides=10, rings=5, color="gunmetal")
    b.box((0.18, 0.08, 0.12), (0, 0.12, -0.25), "black", chamfer=0.02)
    b.cyl(0.035, 0.03, (0, 0.165, -0.25), sides=8, color="lamp", mat="emit", rot=(90, 0, 0))
    b.box((0.04, 0.02, 0.03), (0.06, 0.16, -0.21), "red", mat="emit")
    b.build(parent=r, origin=(0, 0, -0.25))
    return export("mod_sen_gimbal_cam.glb", limit=300)


def build():
    swift()
    gimbal_camera()
