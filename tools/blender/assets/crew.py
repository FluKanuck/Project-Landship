"""Bridge crew: seated figure, console, crew pit. Wedge set items 5, 6, 7."""
from kit import Part, empty, export, reset, root, tilted_rect


def crew_figure():
    """hum_crew_figure — seated, helmeted, faceless. Head and arms move (idle animation)."""
    reset(11)
    r = root("hum_crew_figure")
    body = Part("body")
    # legs: thighs forward, shins down to the floor
    for sx in (-1, 1):
        x = 0.11 * sx
        body.box((0.16, 0.48, 0.16), (x, 0.22, 0.55), "olive", chamfer=0.03)
        body.box((0.14, 0.15, 0.52), (x, 0.47, 0.28), "olive", chamfer=0.03)
        body.box((0.14, 0.26, 0.09), (x, 0.52, 0.045), "rubber", chamfer=0.02)  # boots
    body.box((0.38, 0.28, 0.2), (0, 0.0, 0.56), "olive", chamfer=0.04)  # pelvis
    body.box((0.42, 0.26, 0.52), (0, -0.02, 0.9), "olive", chamfer=0.05, taper=(1.12, 1.0))  # torso
    body.box((0.44, 0.06, 0.3), (0, 0.12, 0.98), "charcoal", chamfer=0.02)  # chest rig
    body.box((0.3, 0.12, 0.34), (0, -0.19, 0.92), "charcoal", chamfer=0.03)  # back pack / life support
    body.box((0.08, 0.04, 0.06), (0.12, 0.155, 1.05), "orange", mat="emit")  # status lamp
    body.cyl(0.07, 0.08, (0, 0, 1.19), sides=8, color="olive")  # neck
    body.build(parent=r)

    head = Part("head")  # origin on the neck pivot
    head.sphere(0.155, (0, 0.02, 1.36), sides=10, rings=5, color="bone", scale=(1.0, 1.1, 1.05))
    head.box((0.26, 0.08, 0.1), (0, 0.15, 1.36), "visor", chamfer=0.025)  # visor, faceless
    head.box((0.33, 0.06, 0.035), (0, 0.035, 1.47), "orange")  # helmet stripe
    head.box((0.05, 0.05, 0.16), (-0.165, 0.0, 1.36), "steel")  # comms pod
    head.cyl(0.006, 0.18, (-0.17, -0.02, 1.5), sides=6, color="black")  # antenna stub
    head.build(parent=r, origin=(0, 0.02, 1.22))

    for side, sx in (("l", -1), ("r", 1)):
        arm = Part(f"arm_{side}")  # origin at the shoulder
        sh = (0.245 * sx, 0.0, 1.12)
        arm.box((0.12, 0.12, 0.3), (0.255 * sx, 0.06, 0.98), "olive", chamfer=0.03, rot=(-35, 0, 0))
        arm.box((0.1, 0.3, 0.1), (0.25 * sx, 0.3, 0.86), "olive", chamfer=0.025)
        arm.box((0.09, 0.11, 0.07), (0.24 * sx, 0.5, 0.86), "charcoal", chamfer=0.02)  # glove
        arm.build(parent=r, origin=sh)
    return export("hum_crew_figure.glb", limit=1000)


def crew_console():
    """hum_crew_console — angled operator desk. Screen is its own object for a runtime texture."""
    reset(12)
    r = root("hum_crew_console")
    p = Part("console")
    p.box((1.2, 0.5, 0.72), (0, 0.15, 0.36), "charcoal", chamfer=0.03)  # desk body
    p.box((1.24, 0.62, 0.05), (0, 0.06, 0.745), "gunmetal", chamfer=0.015)  # desk top
    p.box((1.2, 0.12, 0.62), (0, 0.42, 1.08), "charcoal", chamfer=0.03, rot=(-18, 0, 0))  # screen housing
    p.box((0.4, 0.2, 0.03), (0, -0.08, 0.785), "black", chamfer=0.01)  # keyboard
    for i, x in enumerate((-0.42, -0.3, 0.32, 0.44)):
        p.box((0.05, 0.05, 0.02), (x, -0.12, 0.78), ("amber", "red", "amber", "amber")[i], mat="emit")
    p.box((1.0, 0.04, 0.06), (0, 0.39, 0.42), "amber", mat="emit")  # kick light
    # stool
    p.cyl(0.04, 0.42, (0, -0.55, 0.21), sides=8, color="steel")
    p.cyl(0.22, 0.03, (0, -0.55, 0.015), sides=8, color="gunmetal")
    p.box((0.42, 0.42, 0.08), (0, -0.55, 0.46), "rubber", chamfer=0.03)
    p.build(parent=r)
    s = Part("screen")
    # one quad on the housing face that looks at the operator (-Y), tilted back with it
    s.quad(tilted_rect((0, 0.345, 1.1), 0.52, 0.27, -18), "screen", mat="screen", double=False,
           uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    s.build(parent=r)
    empty("socket_operator", (0, -0.55, 0.0), r)
    return export("hum_crew_console.glb", limit=600)


def crew_pit():
    """hum_crew_pit — sunken trench; origin on the rim (room floor level)."""
    reset(13)
    r = root("hum_crew_pit")
    W, L, D = 3.4, 6.4, 1.2
    p = Part("pit")
    p.box((W, L, 0.1), (0, 0, -D - 0.05), "deck")  # floor
    p.box((W + 0.2, 0.1, D), (0, L / 2 + 0.05, -D / 2), "gunmetal")
    p.box((W + 0.2, 0.1, D), (0, -L / 2 - 0.05, -D / 2), "gunmetal")
    p.box((0.1, L, D), (W / 2 + 0.05, 0, -D / 2), "gunmetal")
    p.box((0.1, L, D), (-W / 2 - 0.05, 0, -D / 2), "gunmetal")
    # wall ribs, uneven spacing so the detail does not repeat
    for y in (-2.7, -1.5, -0.6, 0.9, 1.7, 2.8):
        p.box((0.08, 0.14, D - 0.1), (W / 2 - 0.02, y, -D / 2), "charcoal")
    p.box((0.06, L - 0.3, 0.04), (W / 2 - 0.06, 0, -0.35), "amber", mat="emit")  # light strip
    p.box((0.06, L - 0.3, 0.04), (-W / 2 + 0.06, 0, -0.95), "amber", mat="emit")
    # steps down at the back end
    for i in range(3):
        p.box((1.0, 0.32, 0.4 * (i + 1)), (-W / 2 + 0.6, -L / 2 + 0.16 + 0.32 * (2 - i), -D + 0.2 * (i + 1)), "steel", chamfer=0.02)
    # rim coping and handrails
    for sy in (-1, 1):
        p.box((W + 0.4, 0.2, 0.06), (0, sy * (L / 2 + 0.1), -0.03), "hazard")
    for sx in (-1, 1):
        p.box((0.2, L + 0.4, 0.06), (sx * (W / 2 + 0.1), 0, -0.03), "hazard")
        for y in (-2.9, -1.0, 1.0, 2.9):
            p.cyl(0.025, 0.95, (sx * (W / 2 + 0.12), y, 0.475), sides=6, color="steel")
        p.box((0.06, L - 0.1, 0.06), (sx * (W / 2 + 0.12), 0, 0.96), "steel", chamfer=0.015)
    p.build(parent=r)
    p2 = Part("pit-colonly")
    p2.box((W, L, 0.1), (0, 0, -D - 0.05), "deck")
    p2.build(parent=r)
    for i, y in enumerate((-1.6, 0.2, 2.0)):
        empty(f"socket_console_{i}", (W / 2 - 0.55, y, -D), r, rot=(0, 0, -90))
    return export("hum_crew_pit.glb", limit=1500)


def build():
    crew_figure()
    crew_console()
    crew_pit()
