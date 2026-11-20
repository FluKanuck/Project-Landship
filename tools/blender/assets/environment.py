"""Environment props for the wedge: rock outcrops, wreck. (Dunes are made in Godot.)"""
import math
import random

from kit import Part, export, reset, root


def outcrop(name, seed, size, n_lumps):
    reset(seed)
    r = root(name)
    p = Part("rock-col")
    for i in range(n_lumps):
        cx = random.uniform(-size * 0.5, size * 0.5)
        cy = random.uniform(-size * 0.4, size * 0.4)
        rad = random.uniform(size * 0.25, size * 0.5)
        h = random.uniform(size * 0.25, size * 0.7)
        pts = []
        for k in range(7):
            a = 2 * math.pi * k / 7 + random.uniform(-0.3, 0.3)
            rr = rad * random.uniform(0.7, 1.1)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr, -size * 0.1))
            pts.append((cx + math.cos(a) * rr * 0.6, cy + math.sin(a) * rr * 0.6, h * random.uniform(0.6, 1.0)))
        pts.append((cx + random.uniform(-0.2, 0.2) * rad, cy, h * 1.1))
        p.hull(pts, random.choice(["umber", "rust", "umber", "sand_dark"]), mat="rock")
    p.build(parent=r)
    return export(f"{name}.glb", limit=800)


def wreck():
    """env_wreck_a — old tracked hauler, half buried and tilted."""
    reset(62)
    r = root("env_wreck_a")
    p = Part("wreck-col")
    p.box((4.2, 9.0, 2.6), (0, 0, 1.3), "rust", chamfer=0.3)
    p.box((3.4, 3.0, 2.0), (0, 3.4, 3.2), "rust", chamfer=0.3, taper=(0.9, 0.8))
    p.box((0.9, 9.4, 1.4), (-2.4, 0, 0.7), "charcoal", chamfer=0.2)
    p.box((0.9, 9.4, 1.4), (2.4, 0, 0.7), "charcoal", chamfer=0.2)
    p.box((4.0, 0.3, 0.5), (0, -4.5, 2.5), "orange")  # faded stripe
    p.box((3.0, 0.1, 0.9), (0, 4.95, 3.3), "glass")
    p.cyl(0.18, 2.4, (1.2, -2.8, 3.4), sides=6, color="black")  # exhaust stack
    p.build(parent=r)
    r.rotation_euler = (math.radians(9), math.radians(-6), math.radians(23))
    r.location.z = -0.9
    return export("env_wreck_a.glb", limit=600)


def build():
    outcrop("env_rock_a", 61, 9.0, 4)
    outcrop("env_rock_b", 63, 16.0, 6)
    outcrop("env_rock_c", 64, 5.0, 2)
    wreck()
