"""Alien forces for the wedge: light raider (wedge set item 9) and the recharge node.

Alien shape language (Art Profile): continuous faceted shells with a taper, no wheels or
tracks, asymmetry allowed, no doors or ladders. Plum hull, verdigris accents, cold cyan light.
"""
import math

from kit import Part, empty, export, reset, root


def raider():
    """aln_gnd_raider — 5.5 m hover raider. Fast, hit-and-run."""
    reset(41)
    r = root("aln_gnd_raider")
    s = Part("shell")
    s.hull([
        (0, 2.9, 1.0), (0.15, 2.7, 1.18),
        (-1.25, 0.4, 0.95), (1.35, 0.1, 0.95), (-1.1, 0.3, 1.45), (1.2, 0.0, 1.38),
        (-0.95, -2.3, 0.92), (0.85, -2.45, 0.9), (-0.7, -2.2, 1.6), (0.6, -2.4, 1.55),
        (0.25, -0.7, 1.98), (-0.2, -1.5, 1.9),
        (-0.7, 1.0, 0.78), (0.7, 0.9, 0.78), (-0.6, -1.9, 0.8), (0.6, -2.0, 0.8),
    ], "plum", mat="alien")
    # asymmetric side blade on the left
    s.hull([(-1.15, 1.2, 1.1), (-1.25, 1.0, 1.25), (-1.95, -1.4, 1.12), (-1.85, -1.8, 1.3),
            (-1.1, -1.6, 1.2), (-1.0, -1.2, 1.38)], "verdigris", mat="alien")
    # dorsal fin offset to the right
    s.hull([(0.3, -0.4, 1.9), (0.35, -2.2, 1.6), (0.38, -1.9, 2.55), (0.42, -2.5, 2.5), (0.25, -1.2, 2.1)], "plum_light", mat="alien")
    # light gun, right flank
    s.hull([(1.05, 0.9, 1.25), (1.25, 0.9, 1.25), (1.05, 0.9, 1.4), (1.25, 0.9, 1.4),
            (1.12, -0.6, 1.2), (1.32, -0.6, 1.2), (1.12, -0.6, 1.45), (1.32, -0.6, 1.45)], "plum_light", mat="alien")
    s.cyl(0.05, 1.3, (1.18, 1.5, 1.33), sides=6, color="verdigris", mat="alien", rot=(90, 0, 0))
    # hover pods
    for (x, y, rr) in ((0.0, 1.55, 0.42), (-0.85, -1.6, 0.52), (0.85, -1.75, 0.5)):
        s.cyl(rr, 0.28, (x, y, 0.86), sides=8, color="plum_light", mat="alien", r2=rr * 0.75)
    s.build(parent=r)

    g = Part("hover_glow")  # pulsed by the engine in Godot
    for (x, y, rr) in ((0.0, 1.55, 0.42), (-0.85, -1.6, 0.52), (0.85, -1.75, 0.5)):
        g.cyl(rr * 0.8, 0.04, (x, y, 0.7), sides=8, color="cyan", mat="emit")
    # sensor eye and slit lights
    g.box((0.22, 0.08, 0.05), (0.05, 2.62, 1.14), "cyan", mat="emit", rot=(0, 0, 8))
    g.hull([(-1.12, 0.35, 1.36), (-1.1, 0.25, 1.4), (-0.92, -1.9, 1.5), (-0.9, -2.0, 1.54)], "cyan", mat="emit")
    g.hull([(1.18, 0.0, 1.32), (1.16, -0.1, 1.36), (0.8, -2.2, 1.46), (0.78, -2.3, 1.5)], "cyan", mat="emit")
    g.build(parent=r)
    empty("socket_turret_s_0", (1.18, 0.2, 1.45), r)
    empty("socket_dust", (0, -0.3, 0.3), r)
    return export("aln_gnd_raider.glb", limit=800)


def recharge_node():
    """aln_str_recharge_node — 20 m energy spire. Raiders must return here (hover burns energy)."""
    reset(42)
    r = root("aln_str_recharge_node")
    p = Part("node")
    p.cyl(7.0, 1.6, (0, 0, 0.8), sides=6, color="plum", mat="alien", r2=6.2)
    p.cyl(4.0, 2.0, (0, 0, 2.6), sides=6, color="plum_light", mat="alien", r2=3.0)
    # twisted spire: stacked hulls, each rotated a little
    z = 3.6
    for i, (r0, r1, h) in enumerate(((2.4, 1.9, 4.0), (1.9, 1.3, 4.5), (1.3, 0.7, 4.5), (0.7, 0.25, 3.2))):
        rot = 15 * i
        pts = []
        for k in range(5):
            a = math.radians(72 * k + rot)
            pts.append((math.cos(a) * r0, math.sin(a) * r0, z))
            a2 = math.radians(72 * k + rot + 12)
            pts.append((math.cos(a2) * r1 + (0.4 if i == 2 else 0), math.sin(a2) * r1, z + h))
        p.hull(pts, "plum" if i % 2 == 0 else "plum_light", mat="alien")
        z += h
    # verdigris buttresses, three, uneven
    for a, L in ((20, 5.5), (150, 4.8), (265, 6.0)):
        rad = math.radians(a)
        cx, cy = math.cos(rad), math.sin(rad)
        p.hull([(cx * 2.2, cy * 2.2, 1.6), (cx * 2.2 + cy * 0.5, cy * 2.2 - cx * 0.5, 1.6),
                (cx * L, cy * L, 1.6), (cx * 2.0, cy * 2.0, 8.5), (cx * 2.4, cy * 2.4, 7.5)], "verdigris", mat="alien")
    # docking pads round the base
    for a in (60, 190, 300):
        rad = math.radians(a)
        p.cyl(2.6, 0.4, (math.cos(rad) * 11, math.sin(rad) * 11, 0.2), sides=6, color="plum_light", mat="alien")
    p.build(parent=r)

    g = Part("node_glow")
    g.sphere(0.6, (0.4, 0, z + 0.4), sides=6, rings=3, color="cyan", mat="emit", scale=(0.7, 0.7, 1.4))
    for a in (60, 190, 300):
        rad = math.radians(a)
        g.cyl(2.0, 0.06, (math.cos(rad) * 11, math.sin(rad) * 11, 0.43), sides=6, color="cyan", mat="emit")
    g.cyl(4.05, 0.12, (0, 0, 3.0), sides=6, color="cyan", mat="emit", r2=3.6)
    g.build(parent=r)

    ring = Part("ring")  # floats and turns
    for k in range(9):
        a0, a1 = math.radians(40 * k), math.radians(40 * k + 28)
        R = 4.2
        ring.hull([(math.cos(a0) * R, math.sin(a0) * R, 11.0), (math.cos(a1) * R, math.sin(a1) * R, 11.0),
                   (math.cos(a0) * (R - 0.6), math.sin(a0) * (R - 0.6), 11.4), (math.cos(a1) * (R - 0.6), math.sin(a1) * (R - 0.6), 11.4),
                   (math.cos(a0) * R, math.sin(a0) * R, 11.5), (math.cos(a1) * R, math.sin(a1) * R, 11.5)],
                  "verdigris" if k % 3 else "cyan", mat="alien" if k % 3 else "emit")
    ring.build(parent=r, origin=(0, 0, 11.2))
    for i, a in enumerate((60, 190, 300)):
        rad = math.radians(a)
        empty(f"socket_pad_{i}", (math.cos(rad) * 11, math.sin(rad) * 11, 0.4), r)
    return export("aln_str_recharge_node.glb", limit=2500)


def build():
    raider()
    recharge_node()
