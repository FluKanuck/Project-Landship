"""
Carrier landship exterior (roster: carrier exterior, first pass for the wedge).

360 m long, 110 m wide, deck at 50 m. The bridge room sits inside the tower at
socket_bridge_room; the tower front leaves the room's window band open so the
player can see the deck and the desert from the bridge.
"""
import math

from kit import Part, empty, export, reset, root

L, W = 360.0, 110.0
DECK = 50.0
ROOM = (0.0, -95.0, 78.0)  # bridge room floor centre (Blender coords)
LEAN = math.tan(math.radians(15))


def room_front_y(z_local):
    return ROOM[1] + 7.0 + z_local * LEAN


def carrier():
    reset(51)
    r = root("hum_carrier")

    hull = Part("hull")
    # main hull with a raked prow and a squared stern
    hull.hull([
        (-W / 2, -L / 2, 24), (W / 2, -L / 2, 24), (-W / 2, -L / 2, DECK), (W / 2, -L / 2, DECK),
        (-W / 2, L / 2 - 40, 24), (W / 2, L / 2 - 40, 24),
        (-W / 2 + 6, L / 2, DECK), (W / 2 - 6, L / 2, DECK),
        (-W / 2 + 14, L / 2 - 10, 30), (W / 2 - 14, L / 2 - 10, 30),
    ], "bone_dark")
    # side armour belts (gunmetal) and the orange stripe along both flanks
    for sx in (-1, 1):
        hull.box((3.0, L - 50, 12), (sx * (W / 2 + 1.0), -15, 31), "gunmetal", chamfer=0.8)
        hull.box((1.2, L - 70, 2.2), (sx * (W / 2 + 0.4), -20, 44), "orange")
    # deck plate
    hull.box((W - 2, L - 8, 1.0), (0, 0, DECK + 0.5), "deck")
    # runway markings: centreline dashes and edge lines, irregular gaps near the tower
    for y in range(-50, 170, 14):
        hull.box((1.2, 7.0, 0.2), (8, y, DECK + 1.1), "white")
    for sx in (-1, 1):
        hull.box((0.8, 220, 0.2), (8 + sx * 14, 60, DECK + 1.1), "white")
    hull.box((30, 3.0, 0.2), (8, 172, DECK + 1.1), "hazard")
    hull.box((30, 1.2, 0.2), (8, -55, DECK + 1.1), "hazard")
    hull.box((4.0, 40, 0.6), (8, 140, DECK + 1.2), "steel")  # launch rail
    # hangar elevator plates and hatches
    for (x, y, sw, sl) in ((-30, 40, 24, 30), (-30, 100, 24, 24), (36, -20, 20, 28)):
        hull.box((sw, sl, 0.4), (x, y, DECK + 1.05), "charcoal")
        hull.box((sw + 1.0, 0.8, 0.45), (x, y - sl / 2, DECK + 1.08), "hazard")
    hull.build(parent=r)

    # ---------------------------------------------------------------- tracks
    tr = Part("tracks")
    for x in (-40, 0, 40):
        for y in (-140, -62, 18, 96):
            yy = y + (6 if x == 0 else 0)
            tr.box((22, 62, 22), (x, yy, 12), "charcoal", chamfer=3.0)
            tr.box((24, 64, 2.5), (x, yy, 23.5), "gunmetal", chamfer=0.6)  # track guard
            if abs(x) == 40:
                sx = 1 if x > 0 else -1
                for k in range(6):
                    tr.cyl(7.5, 1.0, (x + sx * 11.2, yy - 25 + k * 10, 10), sides=10, color="steel", rot=(0, 90, 0))
                tr.box((1.0, 64, 3.0), (x + sx * 11.4, yy, 20.5), "hazard")
    tr.build(parent=r)

    # ---------------------------------------------------------------- tower
    tw = Part("tower")
    rz = ROOM[2]
    # lower tower, deck to below the crew pits (1.3 m under the bridge floor), so no
    # tower surface shows inside the room or z-fights with its floor.
    tz = rz - 1.4
    tw.box((30, 44, tz - DECK), (0, -106, DECK + (tz - DECK) / 2), "bone", chamfer=1.5, taper=(0.9, 0.92))
    # lid closing the tower top for the exterior cameras (the room is bridge-layer only),
    # under the 0.3 m floor slab, with holes where the crew pits drop through it
    lid_x, lid_y = (-13.5, 13.5), (-126.0, -86.0)
    hole_x, hole_y = (3.0, 6.8), (ROOM[1] - 2.8, ROOM[1] + 4.0)
    lid = [
        (lid_x[0], lid_x[1], lid_y[0], hole_y[0]), (lid_x[0], lid_x[1], hole_y[1], lid_y[1]),
        (lid_x[0], -hole_x[1], hole_y[0], hole_y[1]), (-hole_x[0], hole_x[0], hole_y[0], hole_y[1]),
        (hole_x[1], lid_x[1], hole_y[0], hole_y[1]),
    ]
    for x0, x1, y0, y1 in lid:
        tw.box((x1 - x0, y1 - y0, 1.0), ((x0 + x1) / 2, (y0 + y1) / 2, rz - 0.9), "bone")
    # bridge level: back + sides as solid blocks round the room
    tw.box((28, 6, 6.0), (0, -105.5, rz + 3.0), "bone")
    for sx in (-1, 1):
        tw.hull([(sx * 9.4, -103, rz), (sx * 14, -103, rz), (sx * 9.4, room_front_y(0) + 0.4, rz),
                 (sx * 14, room_front_y(0) + 0.4, rz), (sx * 9.4, -103, rz + 5.0), (sx * 14, -103, rz + 5.0),
                 (sx * 9.4, room_front_y(5.0) + 0.4, rz + 5.0), (sx * 14, room_front_y(5.0) + 0.4, rz + 5.0)], "bone")

    # front face below and above the window band (same 15 deg lean as the room's wall)
    def slab(z0, z1, x0=-14, x1=14):
        pts = []
        for x in (x0, x1):
            for z in (z0, z1):
                pts += [(x, room_front_y(z) + 0.32, rz + z), (x, room_front_y(z) + 0.7, rz + z)]
        tw.hull(pts, "bone")
    slab(0, 0.85)
    slab(3.95, 5.0)
    # roof and visor over the windows
    tw.box((28.5, 20, 1.2), (0, -95, rz + 5.6), "gunmetal")
    tw.hull([(-14, room_front_y(5.0) + 0.4, rz + 5.0), (14, room_front_y(5.0) + 0.4, rz + 5.0),
             (-14, room_front_y(5.0) + 3.0, rz + 4.6), (14, room_front_y(5.0) + 3.0, rz + 4.6),
             (-14, room_front_y(5.0) + 0.4, rz + 5.4), (14, room_front_y(5.0) + 0.4, rz + 5.4)], "gunmetal")
    tw.box((28.6, 1.0, 1.0), (0, -114, rz + 3.0), "orange")
    # mast
    tw.box((3, 3, 14), (0, -100, rz + 13), "gunmetal")
    tw.box((10, 1.2, 1.2), (0, -100, rz + 16), "steel")
    tw.box((6, 1.0, 1.0), (0, -100, rz + 11), "steel")
    tw.box((0.6, 0.6, 0.6), (5, -100, rz + 16.6), "red", mat="emit")
    tw.box((0.6, 0.6, 0.6), (-5, -100, rz + 16.6), "red", mat="emit")
    tw.build(parent=r)
    glow = Part("tower_lights")
    for sx in (-1, 1):
        glow.box((0.5, 8, 0.4), (sx * 14.1, -100, rz + 1.0), "amber", mat="emit")
    glow.box((26, 0.4, 0.4), (0, room_front_y(5.2) + 0.5, rz + 5.15), "amber", mat="emit")
    glow.build(parent=r)

    radar = Part("radar")  # turns about Z on top of the mast
    radar.box((12, 1.2, 3.0), (0, -100, rz + 21.5), "steel", chamfer=0.3)
    radar.box((12.4, 0.4, 0.4), (0, -99.3, rz + 21.5), "gunmetal")
    radar.cyl(0.6, 1.4, (0, -100, rz + 20.3), sides=8, color="gunmetal")
    radar.build(parent=r, origin=(0, -100, rz + 20.0))

    # ---------------------------------------------------------------- deck structures
    st = Part("structures")
    # construction platform gantry
    for sx in (-1, 1):
        st.box((4, 6, 34), (sx * 46, 30, DECK + 17), "gunmetal", chamfer=0.6)
        st.box((5, 7, 2), (sx * 46, 30, DECK + 1), "hazard")
    st.box((96, 5, 4), (0, 30, DECK + 35), "gunmetal", chamfer=0.6)
    st.box((8, 7, 5), (-12, 30, DECK + 31.5), "bone")  # crane trolley
    st.cyl(0.25, 18, (-12, 30, DECK + 20), sides=6, color="black")
    st.box((10, 8, 3), (-12, 30, DECK + 10), "hazard")  # hook block
    # point-defence turrets on the corners
    for (x, y) in ((-48, 150), (48, 150), (-48, -150), (48, -150), (-48, 60)):
        st.cyl(4.0, 3.0, (x, y, DECK + 1.5), sides=8, color="gunmetal")
        st.box((5, 5, 3.5), (x, y, DECK + 4.5), "bone", chamfer=0.6)
        st.box((0.6, 6, 0.6), (x - 1.0, y + 4.5, DECK + 5.2), "steel")
        st.box((0.6, 6, 0.6), (x + 1.0, y + 4.5, DECK + 5.2), "steel")
    # main gun forward on the port side
    st.cyl(9.0, 3.0, (-34, 128, DECK + 1.5), sides=10, color="gunmetal")
    st.box((14, 16, 6), (-34, 126, DECK + 6), "bone", chamfer=1.5, taper=(0.8, 0.8))
    for dx in (-2.2, 2.2):
        st.box((1.4, 22, 1.4), (-34 + dx, 145, DECK + 6.5), "steel")
    # stern ramp folded up
    st.hull([(-20, -L / 2, 24), (20, -L / 2, 24), (-20, -L / 2 - 4, 26), (20, -L / 2 - 4, 26),
             (-20, -L / 2, 44), (20, -L / 2, 44), (-20, -L / 2 - 3, 44), (20, -L / 2 - 3, 44)], "gunmetal")
    st.box((40, 1.0, 2.0), (0, -L / 2 - 3.6, 40), "hazard")
    # deck edge rails, broken into runs
    for sx in (-1, 1):
        for y0, y1 in ((-176, -130), (-120, -40), (-30, 80), (90, 168)):
            st.box((0.5, y1 - y0, 1.4), (sx * (W / 2 - 1.5), (y0 + y1) / 2, DECK + 1.7), "steel")
    # satellite launch rail (future) forward of the tower, port side
    st.box((6, 40, 3), (-36, -60, DECK + 2.5), "gunmetal", chamfer=0.5)
    st.build(parent=r)

    empty("socket_bridge_room", ROOM, r)
    empty("socket_launch", (8, 120, DECK + 2.5), r)
    empty("socket_recover", (8, -30, DECK + 2.5), r)
    empty("socket_cam_fwd", (0, room_front_y(3.0) + 3.0, ROOM[2] + 3.0), r)
    return export("hum_carrier.glb", limit=30000)


def build():
    carrier()
