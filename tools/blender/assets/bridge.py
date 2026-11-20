"""
Bridge set: room shell, command chair, preset panel, projection emitter, holo table,
settings terminal. Wedge set items 1-4 plus two bridge-roster items.

Room layout (Blender coords, +Y = front, Z up, floor top at z=0):
  room        x -9..9, y -7..7 (front wall leans out 15 deg to y 8.23 at the ceiling)
  pits        centred (-4.9, 0.6) and (4.9, 0.6), 3.4 x 6.4
  holo table  (0, 0.8)
  dais        x -2.4..2.4, y -7..-4.2, top z 0.5, chair at (0, -5.4)
Godot reads the same numbers from scripts/bridge/bridge_layout.gd.
"""
import math

from kit import Part, empty, export, reset, root, tilted_rect

LEAN = math.tan(math.radians(15))
H = 4.6


def front_y(z):
    return 7.0 + z * LEAN


def room_shell():
    reset(21)
    r = root("hum_bridge_room")

    # ---------------------------------------------------------------- floor
    fl = Part("floor-col")
    # floor holes 5 cm wider than the pits' inner faces, so the slab edges hide inside the
    # pit walls instead of being flush with them
    pits_x = (3.15, 6.65)
    pits_y = (-2.65, 3.85)
    a, b = pits_x
    pieces = [
        (-a, a, -7, 7.6),  # centre aisle
        (-9, -b, -7, 7.6), (b, 9, -7, 7.6),  # outer strips
        (-b, -a, -7, pits_y[0]), (a, b, -7, pits_y[0]),
        (-b, -a, pits_y[1], 7.6), (a, b, pits_y[1], 7.6),
    ]
    for x0, x1, y0, y1 in pieces:
        fl.box((x1 - x0, y1 - y0, 0.3), ((x0 + x1) / 2, (y0 + y1) / 2, -0.15), "deck")
    fl.build(parent=r)

    # floor plate seams, deliberately irregular
    seams = Part("floor_seams")
    for y in (-5.9, -3.1, -0.4, 2.3, 4.9, 6.6):
        seams.box((6.3, 0.05, 0.012), (0, y, 0.006), "charcoal")
    for x in (-1.6, 1.1):
        seams.box((0.05, 14.4, 0.012), (x, 0.2, 0.006), "charcoal")
    for x in (-7.8, 7.8):
        seams.box((0.05, 14.4, 0.012), (x, 0.2, 0.006), "charcoal")
    # hazard edging round the dais
    seams.box((5.0, 0.12, 0.014), (0, -3.5, 0.007), "hazard")
    seams.build(parent=r)

    # ---------------------------------------------------------------- dais + steps
    d = Part("dais-col")
    d.box((4.8, 2.8, 0.5), (0, -5.6, 0.25), "gunmetal", chamfer=0.04)
    d.box((4.0, 0.6, 0.25), (0, -3.9, 0.125), "gunmetal", chamfer=0.03)
    d.build(parent=r)
    dt = Part("dais_trim")
    dt.box((4.84, 0.06, 0.04), (0, -4.2, 0.5), "amber", mat="emit")
    dt.box((4.04, 0.06, 0.03), (0, -3.6, 0.25), "amber", mat="emit")
    for sx in (-1, 1):  # rails either side of the chair
        for y in (-6.8, -5.4, -4.3):
            dt.cyl(0.03, 1.0, (sx * 2.3, y, 1.0), sides=6, color="steel")
        dt.box((0.06, 2.6, 0.06), (sx * 2.3, -5.55, 1.5), "steel", chamfer=0.015)
    dt.build(parent=r)

    # ---------------------------------------------------------------- walls
    w = Part("walls-col")
    # back wall with a door opening x -0.9..0.9, height 2.4
    w.box((8.1, 0.3, H), (-4.95, -7.15, H / 2), "blue_steel")
    w.box((8.1, 0.3, H), (4.95, -7.15, H / 2), "blue_steel")
    w.box((1.8, 0.3, H - 2.4), (0, -7.15, 2.4 + (H - 2.4) / 2), "blue_steel")
    # side walls
    for sx in (-1, 1):
        w.hull([(sx * 9.0, -7.3, 0), (sx * 9.3, -7.3, 0), (sx * 9.0, front_y(0), 0), (sx * 9.3, front_y(0) + 0.1, 0),
                (sx * 9.0, -7.3, H), (sx * 9.3, -7.3, H), (sx * 9.0, front_y(H), H), (sx * 9.3, front_y(H) + 0.1, H)], "blue_steel")
    # front wall: lower and upper sloped slabs; the window band is open
    def slab(z0, z1, color="blue_steel"):
        pts = []
        for x in (-9.3, 9.3):
            for z in (z0, z1):
                pts += [(x, front_y(z), z), (x, front_y(z) + 0.3, z)]
        w.hull(pts, color)
    slab(0, 0.9)
    slab(3.9, H)
    w.build(parent=r)

    # door leaf (closed) + frame
    door = Part("door")
    door.box((1.8, 0.12, 2.4), (0, -7.06, 1.2), "steel", chamfer=0.03)
    door.box((0.06, 0.04, 2.0), (0, -6.99, 1.2), "black")
    door.box((2.1, 0.2, 0.15), (0, -6.95, 2.47), "hazard")
    for sx in (-1, 1):
        door.box((0.15, 0.2, 2.5), (sx * 0.98, -6.95, 1.25), "hazard")
    door.box((0.2, 0.05, 0.12), (0.6, -6.97, 1.35), "red", mat="emit")
    door.build(parent=r)

    # ---------------------------------------------------------------- window band
    mull = Part("window_frames")
    xs = [-9.0, -7.7, -6.1, -4.7, -3.3, -1.55, 0.0, 1.55, 3.3, 4.7, 6.1, 7.7, 9.0]
    for x in xs:
        pts = []
        for dx in (-0.09, 0.09):
            for z in (0.9, 3.9):
                pts += [(x + dx, front_y(z) - 0.05, z), (x + dx, front_y(z) + 0.35, z)]
        mull.hull(pts, "charcoal")
    for z, t in ((0.9, 0.2), (2.45, 0.08), (3.9, 0.2)):
        pts = []
        for x in (-9.0, 9.0):
            for dz in (-t / 2, t / 2):
                pts += [(x, front_y(z + dz) - 0.08, z + dz), (x, front_y(z + dz) + 0.35, z + dz)]
        mull.hull(pts, "charcoal")
    # sill console under the window
    mull.box((17.6, 0.55, 0.7), (0, 6.72, 0.35), "gunmetal", chamfer=0.05)
    mull.box((17.6, 0.06, 0.04), (0, 6.46, 0.66), "amber", mat="emit")
    mull.build(parent=r)
    glass = Part("bridge_glass")
    glass.quad([(-9, front_y(0.95) + 0.15, 0.95), (9, front_y(0.95) + 0.15, 0.95),
                (9, front_y(3.85) + 0.15, 3.85), (-9, front_y(3.85) + 0.15, 3.85)], "glass", mat="glass")
    glass.build(parent=r)

    # ---------------------------------------------------------------- ceiling
    c = Part("ceiling")
    c.hull([(-9.3, -7.3, H), (9.3, -7.3, H), (-9.3, front_y(H) + 0.3, H), (9.3, front_y(H) + 0.3, H),
            (-9.3, -7.3, H + 0.3), (9.3, -7.3, H + 0.3), (-9.3, front_y(H) + 0.3, H + 0.3), (9.3, front_y(H) + 0.3, H + 0.3)], "charcoal")
    for y in (-6.0, -4.1, -2.0, 0.2, 2.1, 4.3, 6.4):
        c.box((18.0, 0.32, 0.42), (0, y, H - 0.21), "gunmetal")
    # spine beam over the holo table
    c.box((0.5, 13.5, 0.3), (0, 0.4, H - 0.15), "gunmetal")
    c.build(parent=r)
    lights = Part("light_strips")
    for x in (-7.2, -2.6, 2.6, 7.2):
        for y0, y1 in ((-5.85, -4.25), (-3.95, -2.15), (-1.85, 0.05), (0.35, 1.95), (2.25, 4.15), (4.45, 6.25)):
            lights.box((0.16, (y1 - y0) - 0.2, 0.05), (x, (y0 + y1) / 2, H - 0.03), "lamp", mat="emit")
    lights.build(parent=r)

    # ---------------------------------------------------------------- side wall detail
    det = Part("wall_detail")
    rib_y = [-6.3, -5.1, -3.6, -2.4, -0.6, 0.7, 2.6, 3.5, 5.2]
    for sx in (-1, 1):
        for y in rib_y:
            det.box((0.22, 0.24, H), (sx * 8.89, y, H / 2), "charcoal")
        for z, rr in ((3.35, 0.09), (3.62, 0.06), (0.35, 0.07)):
            det.cyl(rr, 14.3, (sx * 8.82, 0.0, z), sides=8, color="steel", rot=(90, 0, 0))
        # equipment cabinets, varied heights
        for y, hh in ((-5.7, 1.9), (-1.6, 1.3), (4.4, 2.1)):
            det.box((0.5, 0.95, hh), (sx * 8.65, y, hh / 2), "gunmetal", chamfer=0.03)
            det.box((0.04, 0.7, 0.05), (sx * 8.39, y, hh - 0.15), "amber", mat="emit")
            det.box((0.04, 0.12, 0.08), (sx * 8.39, y + 0.3, hh - 0.4), "red", mat="emit")
        # status display frames
        for y in (-3.0, 1.6):
            det.box((0.12, 1.5, 0.95), (sx * 8.9, y, 2.2), "black", chamfer=0.03)
    # back wall: big plotting board frame either side of the door
    for sx in (-1, 1):
        det.box((3.2, 0.12, 1.6), (sx * 4.6, -6.95, 2.3), "black", chamfer=0.03)
        det.box((3.4, 0.16, 0.08), (sx * 4.6, -6.93, 3.2), "orange")  # stripe
    det.build(parent=r)

    # wall screens: real UVs so Godot can show live status textures
    sc = Part("wall_screens")
    for sx in (-1, 1):
        for y in (-3.0, 1.6):
            x = sx * 8.83
            corners = [(x, y + 0.68 * sx, 1.78), (x, y - 0.68 * sx, 1.78), (x, y - 0.68 * sx, 2.62), (x, y + 0.68 * sx, 2.62)]
            sc.quad(corners, "screen", mat="screen", double=False, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    sc.build(parent=r)
    boards = Part("plot_boards")
    for sx in (-1, 1):
        x0 = sx * 4.6
        boards.quad([(x0 + 1.5, -6.88, 1.58), (x0 - 1.5, -6.88, 1.58), (x0 - 1.5, -6.88, 3.02), (x0 + 1.5, -6.88, 3.02)],
                    "screen", mat="screen", double=False, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    boards.build(parent=r)

    # invisible collision for the pit floors is in the pit asset; here only walls
    empty("socket_chair", (0, -5.4, 0.5), r)
    empty("socket_holo_table", (0, 0.8, 0), r)
    empty("socket_pit_l", (-4.9, 0.6, 0), r, rot=(0, 0, 180))
    empty("socket_pit_r", (4.9, 0.6, 0), r)
    empty("socket_projection", (0, -4.0, 1.72), r)
    empty("socket_emitter", (0, -4.4, H), r)
    empty("socket_settings_terminal", (7.6, 5.2, 0), r, rot=(0, 0, -45))
    empty("socket_player_spawn", (0, -5.3, 0.5), r)
    return export("hum_bridge_room.glb", limit=40000)


def command_chair():
    reset(22)
    r = root("hum_command_chair")
    p = Part("chair")
    p.cyl(0.42, 0.06, (0, 0, 0.03), sides=8, color="gunmetal")
    p.cyl(0.11, 0.38, (0, 0, 0.25), sides=8, color="steel")
    p.box((0.62, 0.6, 0.12), (0, 0.03, 0.48), "charcoal", chamfer=0.04)
    p.box((0.58, 0.56, 0.08), (0, 0.05, 0.57), "rubber", chamfer=0.03)  # cushion
    p.box((0.6, 0.14, 0.9), (0, -0.27, 1.02), "charcoal", chamfer=0.05, rot=(-10, 0, 0), taper=(0.9, 1.0))
    p.box((0.52, 0.06, 0.7), (0, -0.19, 1.02), "rubber", chamfer=0.02, rot=(-10, 0, 0))
    p.box((0.36, 0.16, 0.26), (0, -0.38, 1.6), "charcoal", chamfer=0.05, rot=(-10, 0, 0))  # headrest
    for sx in (-1, 1):
        p.box((0.1, 0.18, 0.4), (sx * 0.22, -0.36, 1.58), "charcoal", chamfer=0.03, rot=(-10, 0, sx * 18))  # head wings
        p.box((0.12, 0.62, 0.08), (sx * 0.38, 0.08, 0.76), "gunmetal", chamfer=0.03)  # armrest
        p.box((0.06, 0.06, 0.24), (sx * 0.38, -0.15, 0.62), "steel")
        p.box((0.14, 0.2, 0.06), (sx * 0.38, 0.33, 0.79), "charcoal", chamfer=0.02)
    p.box((0.62, 0.05, 0.05), (0, -0.33, 1.42), "orange")  # stripe across the back
    p.box((0.06, 0.04, 0.03), (-0.38, 0.42, 0.82), "amber", mat="emit")
    p.build(parent=r)
    s = Part("chair_screen")  # small left armrest display
    s.quad([(-0.44, 0.24, 0.83), (-0.32, 0.24, 0.83), (-0.32, 0.42, 0.85), (-0.44, 0.42, 0.85)], "screen", mat="screen",
           double=False, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    s.build(parent=r)
    empty("socket_preset_panel", (0.38, 0.3, 0.82), r)
    empty("socket_eye", (0, 0.02, 1.22), r)
    return export("hum_command_chair.glb", limit=1200)


def preset_panel():
    """hum_preset_panel — four chunky diegetic buttons. Each button is its own object (pressable)."""
    reset(23)
    r = root("hum_preset_panel")
    p = Part("panel")
    p.box((0.16, 0.24, 0.035), (0, 0, 0.0175), "gunmetal", chamfer=0.01)
    for i in range(4):
        p.box((0.05, 0.05, 0.012), (0.035 * (1 if i % 2 else -1), -0.055 + 0.11 * (i // 2), 0.04), "black")
    p.build(parent=r)
    names = ["btn_combat", "btn_recon", "btn_transit", "btn_alert"]
    colors = ["phosphor", "phosphor", "phosphor", "red"]
    for i, (n, c) in enumerate(zip(names, colors)):
        b = Part(n)
        x, y = 0.035 * (1 if i % 2 else -1), -0.055 + 0.11 * (i // 2)
        b.box((0.042, 0.042, 0.022), (x, y, 0.055), c, mat="emit", chamfer=0.006)
        b.build(parent=r, origin=(x, y, 0.046))
    return export("hum_preset_panel.glb", limit=400)


def projection_emitter():
    """hum_projection_emitter — ceiling mounted. Origin at the ceiling mount (exception to the
    ground-origin rule: it hangs from the ceiling)."""
    reset(24)
    r = root("hum_projection_emitter")
    p = Part("emitter")
    p.box((0.3, 0.3, 0.1), (0, 0, -0.05), "gunmetal", chamfer=0.02)
    p.cyl(0.06, 1.3, (0, 0, -0.75), sides=8, color="steel")
    # arc bar
    segs = 7
    for i in range(segs):
        a0 = math.radians(-40 + 80 * i / segs)
        a1 = math.radians(-40 + 80 * (i + 1) / segs)
        R = 1.6
        pts = []
        for a in (a0, a1):
            x, y = math.sin(a) * R, -math.cos(a) * R + R
            for dz in (-1.38, -1.5):
                pts += [(x, y - 0.08, dz), (x, y + 0.08, dz)]
        p.hull(pts, "charcoal")
    p.build(parent=r)
    lens = Part("lenses")
    for a in (-30, 0, 30):
        x, y = math.sin(math.radians(a)) * 1.6, -math.cos(math.radians(a)) * 1.6 + 1.6
        lens.box((0.2, 0.2, 0.14), (x, y, -1.56), "gunmetal", chamfer=0.03)
        lens.cyl(0.06, 0.04, (x, y + 0.04, -1.64), sides=8, color="phosphor", mat="emit")
    lens.build(parent=r)
    return export("hum_projection_emitter.glb", limit=800)


def holo_table():
    reset(25)
    r = root("hum_holo_table")
    p = Part("table")
    p.cyl(1.0, 0.1, (0, 0, 0.05), sides=10, color="gunmetal")
    p.cyl(0.95, 0.72, (0, 0, 0.46), sides=10, color="charcoal", r2=0.78)
    p.cyl(1.66, 0.1, (0, 0, 0.87), sides=14, color="gunmetal", r2=1.7)  # rim underside
    p.cyl(1.7, 0.08, (0, 0, 0.96), sides=14, color="charcoal")  # rim top
    p.cyl(1.46, 0.04, (0, 0, 0.93), sides=14, color="glass")  # dark plate
    for i in range(5):  # struts, not evenly spaced
        a = math.radians(i * 72 + (8 if i % 2 else -6))
        p.box((0.12, 0.6, 0.18), (math.cos(a) * 1.1, math.sin(a) * 1.1, 0.78), "steel", rot=(0, 0, math.degrees(a) + 90))
    # operator panels on two sides
    for a in (200, 340):
        rad = math.radians(a)
        p.box((0.5, 0.26, 0.12), (math.cos(rad) * 1.78, math.sin(rad) * 1.78, 0.98), "gunmetal", chamfer=0.03,
              rot=(18, 0, a + 90))
    p.box((0.4, 0.03, 0.05), (0, -1.68, 0.9), "orange")
    p.build(parent=r)
    g = Part("emit_ring")
    g.cyl(1.47, 0.03, (0, 0, 0.965), sides=14, color="phosphor", mat="emit", r2=1.42)
    g.cyl(0.8, 0.04, (0, 0, 0.11), sides=10, color="amber", mat="emit")
    for a in (200, 340):
        rad = math.radians(a)
        for k in (-1, 0, 1):
            g.box((0.05, 0.05, 0.02), (math.cos(rad) * 1.8 + math.cos(rad + 1.57) * 0.12 * k,
                                       math.sin(rad) * 1.8 + math.sin(rad + 1.57) * 0.12 * k, 1.05),
                  "amber" if k else "red", mat="emit")
    g.build(parent=r)
    empty("socket_holo_surface", (0, 0, 0.98), r)
    return export("hum_holo_table.glb", limit=1500)


def settings_terminal():
    reset(26)
    r = root("hum_settings_terminal")
    p = Part("terminal")
    p.box((0.7, 0.5, 1.0), (0, -0.05, 0.5), "gunmetal", chamfer=0.03, taper=(1.0, 0.7))
    p.box((0.8, 0.12, 0.6), (0, 0.12, 1.35), "charcoal", chamfer=0.03, rot=(-15, 0, 0))
    p.box((0.72, 0.03, 0.04), (0, -0.28, 0.95), "hazard")
    p.box((0.06, 0.04, 0.04), (0.28, -0.2, 1.02), "amber", mat="emit")
    p.build(parent=r)
    s = Part("screen")
    s.quad(tilted_rect((0, 0.045, 1.36), 0.33, 0.24, -15), "screen", mat="screen", double=False,
           uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    s.build(parent=r)
    return export("hum_settings_terminal.glb", limit=400)


def build():
    room_shell()
    command_chair()
    preset_panel()
    projection_emitter()
    holo_table()
    settings_terminal()
