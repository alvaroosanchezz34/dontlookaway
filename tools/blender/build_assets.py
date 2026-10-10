"""
Builds DON'T LOOK AWAY's hero props in Blender, bakes their PBR maps and
exports them for Roblox.

    /home/user/.venv-blender/bin/python tools/blender/build_assets.py [asset ...]

For every asset writes
    assets/props/<Asset>.obj                       mesh (studs, Roblox axes)
    assets/props/<Asset>/<Asset>_{color,normal,roughness,metalness}.png
    assets/props/previews/<Asset>.png              Cycles review render
and finally src/shared/Config/PropMeshMeta.luau (size and pivot offset of
every mesh, used by the game to size and place the MeshParts).

All geometry and materials are authored here: original, no external assets.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import dla_blender as B  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "props")
META = os.path.join(ROOT, "src", "shared", "Config", "PropMeshMeta.luau")


# ---------------------------------------------------------------------------
# assets: each returns (list of objects, preview options)
# Front faces +Y; origin = centre of the footprint on the floor.
# ---------------------------------------------------------------------------


def reception_desk():
    """Matches Props.receptionDesk's footprint: 12.4 wide, counter top at 4.5,
    public face at y = +1.8 (Roblox z = -1.8)."""
    wood = B.wood("DeskWood", base=(0.045, 0.02, 0.01), light=(0.16, 0.075, 0.035))
    frame = B.wood("DeskFrame", base=(0.03, 0.014, 0.008), light=(0.11, 0.05, 0.025), gloss=0.26)
    woodX = B.wood("DeskWoodX", base=(0.045, 0.02, 0.01), light=(0.16, 0.075, 0.035), axis="X")
    frameX = B.wood("DeskFrameX", base=(0.03, 0.014, 0.008), light=(0.11, 0.05, 0.025), gloss=0.26, axis="X")
    stone = B.stone("DeskStone", base=(0.42, 0.4, 0.36), vein=(0.2, 0.19, 0.17))
    objs = []
    # carcass and recessed plinth
    objs.append(B.box("Carcass", (12.0, 0.6, 3.9), (0, 1.5, 2.25), wood, bev=0.015))
    objs.append(B.box("Plinth", (11.7, 0.5, 0.3), (0, 1.42, 0.15), frameX, bev=0.01))
    # frame-and-panel front: stiles, rails and four fielded panels
    for i in range(5):
        objs.append(B.box("Stile%d" % i, (0.34, 0.1, 3.3), (-5.83 + i * 2.915, 1.85, 2.1), frame, bev=0.02))
    # rails sit between the stiles and a little behind them (real joinery),
    # so no two faces share a plane
    for i in range(4):
        x = -4.37 + i * 2.915
        objs.append(B.box("TopRail", (2.6, 0.08, 0.32), (x, 1.84, 3.72), frameX, bev=0.015))
        objs.append(B.box("BottomRail", (2.6, 0.08, 0.36), (x, 1.84, 0.48), frameX, bev=0.015))
    for i in range(4):
        objs.append(B.fielded_panel("Panel%d" % i, 2.5, 2.8, 0.09, 0.32, (-4.37 + i * 2.915, 1.8, 2.1), wood))
    # counter: stone slab with a rounded nose, ogee moulding under it, corbels
    slab = [(0.5, 4.2), (1.95, 4.2)] + [(1.95 + 0.15 * math.cos(-math.pi / 2 + math.pi * k / 8), 4.35 + 0.15 * math.sin(-math.pi / 2 + math.pi * k / 8)) for k in range(9)] + [(0.5, 4.5)]
    objs.append(B.extrude_profile("Counter", slab, 12.4, "X", mat=stone))
    og = [(1.8, 4.2)] + [(1.8 + u, 4.2 - 0.22 + v) for u, v in B.ogee(0.14, 0.22)[1:-1]] + [(1.8, 4.2 - 0.22)]
    objs.append(B.extrude_profile("CounterMould", og, 12.0, "X", mat=frameX))
    # corbel: square top under the overhang, concave quarter-ellipse below
    corbel = [(1.8, 3.62), (1.8, 4.2), (2.05, 4.2)] + [(2.05 + 0.25 * math.cos(t), 3.62 + 0.58 * math.sin(t)) for t in [math.pi / 2 + i * math.pi / 16 for i in range(1, 8)]]
    for x in (-5.4, -1.8, 1.8, 5.4):
        objs.append(B.extrude_profile("Corbel", corbel, 0.26, "X", loc=(x, 0, 0), mat=frame))
    # side returns with a fielded panel each, capped
    for sx in (-1, 1):
        objs.append(B.box("Side", (0.6, 3.5, 4.2), (sx * 6.0, -0.05, 2.1), wood, bev=0.02))
        objs.append(B.box("SideCap", (0.72, 3.72, 0.1), (sx * 6.0, 0, 4.25), frame, bev=0.015))
        p = B.fielded_panel("SidePanel", 2.6, 2.7, 0.07, 0.28, (0, 0, 0), wood)
        p.rotation_euler = (0, 0, math.radians(-90 * sx))
        p.location = (sx * 6.3, 0.1, 2.1)
        objs.append(p)
    # the working side
    objs.append(B.box("WorkTop", (11.4, 2.2, 0.25), (0, 0, 3.0), woodX, bev=0.02))
    objs.append(B.box("WorkEdge", (11.4, 0.08, 0.3), (0, -1.14, 2.99), frameX, bev=0.01))
    objs.append(B.box("Shelf", (11.0, 1.5, 0.12), (0, -0.1, 1.2), frameX, bev=0.01))
    return objs, {}


def door_leaf():
    """Four-panel door leaf, 3.3 x 9.6 x 0.3, centred on the origin (it hangs
    on the door panel, not on the floor). Stiles and rails proud of fielded
    panels, a bolection moulding round each panel, on both faces. The lock
    rail is at the lever height (-0.6)."""
    wood = B.wood("DoorWood", base=(0.06, 0.03, 0.015), light=(0.2, 0.1, 0.05))
    trim = B.wood("DoorTrim", base=(0.04, 0.02, 0.01), light=(0.14, 0.07, 0.035), gloss=0.28)
    woodX = B.wood("DoorWoodX", base=(0.06, 0.03, 0.015), light=(0.2, 0.1, 0.05), axis="X")
    W, H, T = 3.3, 9.6, 0.3
    objs = [B.box("Core", (W - 0.02, T - 0.06, H - 0.02), (0, 0, 0), wood, bev=0.02)]
    st = 0.55
    for face in (-1, 1):
        y = face * (T / 2 - 0.02)
        for sx in (-1, 1):
            objs.append(B.box("Stile", (st, 0.06, H), (sx * (W / 2 - st / 2), y, 0), wood, bev=0.015))
        rails = ((H / 2 - 0.275, 0.55), (-0.6, 0.8), (-H / 2 + 0.5, 1.0))
        for zc, h in rails:
            objs.append(B.box("Rail", (W - 2 * st, 0.05, h), (0, y, zc), woodX, bev=0.012))
        objs.append(B.box("MuntinUp", (0.36, 0.05, 4.45), (0, y, 2.025), wood, bev=0.012))
        objs.append(B.box("MuntinLow", (0.36, 0.05, 2.8), (0, y, -2.4), wood, bev=0.012))
        for zc, ph in ((2.025, 4.45), (-2.4, 2.8)):
            for sx in (-1, 1):
                px = sx * (0.18 + 0.46)
                p = B.fielded_panel("Panel", 0.9, ph, 0.06, 0.16, (0, 0, 0), wood)
                if face < 0:
                    p.rotation_euler = (0, 0, math.radians(180))
                p.location = (px, face * (T / 2 - 0.05), zc)
                objs.append(p)
                # bolection moulding: four mitre-less strips round the panel
                for (sz, ox, oz) in (((0.98, 0.06, 0.07), 0, ph / 2 + 0.02), ((0.98, 0.06, 0.07), 0, -ph / 2 - 0.02), ((0.07, 0.06, ph + 0.11), 0.47, 0), ((0.07, 0.06, ph + 0.11), -0.47, 0)):
                    objs.append(B.box("Mould", sz, (px + ox, face * (T / 2 + 0.005), zc + oz), trim, bev=0.02, seg=3))
    return objs, {"cam": 9.5}


def door_casing():
    """One face of a door surround: moulded legs, a head, rosette corner blocks.
    Origin = door centre on the floor; the back sits on the wall plane (y = 0),
    the moulding faces +Y (into the room)."""
    trim = B.wood("CasingWood", base=(0.05, 0.025, 0.012), light=(0.16, 0.08, 0.04), gloss=0.3)
    trimX = B.wood("CasingWoodX", base=(0.05, 0.025, 0.012), light=(0.16, 0.08, 0.04), gloss=0.3, axis="X")
    objs = []
    # leg profile across its width (u = x offset from leg centre, v = depth): two beads and a flat
    prof = [(-0.225, -0.03), (0.225, -0.03), (0.225, 0.14), (0.17, 0.2), (0.1, 0.2), (0.06, 0.24), (-0.02, 0.24), (-0.06, 0.2), (-0.16, 0.2), (-0.225, 0.27)]
    legH = 9.95
    for sx in (-1, 1):
        pts = [(u * sx, v) for u, v in prof] if sx > 0 else [(-u, v) for u, v in reversed(prof)]
        leg = B.extrude_profile("Leg", [(u, v) for u, v in pts], legH, "Z", loc=(sx * 2.1, 0, legH / 2), mat=trim)
        objs.append(leg)
        objs.append(B.box("CornerBlock", (0.56, 0.32, 0.56), (sx * 2.1, 0.13, legH + 0.28), trim, bev=0.025))
        ros = B.lathe("Rosette", [(0.0, 0.0), (0.2, 0.0), (0.21, 0.03), (0.15, 0.07), (0.07, 0.09), (0.0, 0.1)], 24, mat=trim)
        ros.rotation_euler = (math.radians(-90), 0, 0)
        ros.location = (sx * 2.1, 0.29, legH + 0.28)
        objs.append(ros)
    head = [(u, v) for u, v in prof]
    objs.append(B.extrude_profile("Head", [(v, -u) for u, v in head], 3.64, "X", loc=(0, 0, legH + 0.28), mat=trimX))
    return objs, {"cam": 9}


def pendant_lamp():
    """Enamel school-house pendant, origin at the ceiling point, hanging -Z.
    Canopy and cord grip in brass; the bulb is NOT in the mesh (the game keeps
    its own glowing bulb part)."""
    brass = B.metal("LampBrass", base=(0.5, 0.36, 0.16), rough=0.3)
    enamel = B.paint("LampEnamel", (0.06, 0.1, 0.075), rough=0.35, under=(0.05, 0.045, 0.04), chip=0.45, metallic_under=0.8)
    white = B.paint("LampReflector", (0.75, 0.73, 0.68), rough=0.3, under=(0.3, 0.28, 0.25), chip=0.2)
    cord = B.fabric("LampCord", (0.02, 0.02, 0.02))
    objs = []
    objs.append(B.lathe("Canopy", [(0.0, -0.22), (0.3, -0.22), (0.375, -0.12), (0.375, 0.0), (0.0, 0.0)], 32, mat=brass))
    objs.append(B.cylinder("Cord", 0.04, 2.45, (0, 0, -1.42), "Z", cord, 10))
    objs.append(B.lathe("Grip", [(0.0, -2.92), (0.09, -2.9), (0.08, -2.6), (0.0, -2.6)], 16, mat=brass))
    outer = [(0.0, -2.86), (0.28, -2.88), (0.36, -3.08), (0.6, -3.3), (0.85, -3.5), (1.02, -3.68), (1.08, -3.75), (1.06, -3.8)]
    inner = [(1.0, -3.76), (0.95, -3.68), (0.8, -3.52), (0.56, -3.33), (0.33, -3.12), (0.25, -2.95), (0.0, -2.94)]
    objs.append(B.lathe("ShadeOuter", outer + [(1.0, -3.76)], 40, mat=enamel))
    objs.append(B.lathe("ShadeInner", [(1.0, -3.765)] + inner[1:], 40, mat=white))
    return objs, {"cam": 6.5}


def wall_sconce():
    """Brass wall sconce: back plate on the wall (y = 0), a curved arm out to
    +Y and up to a cup; the glass tulip and bulb stay parts in the game."""
    brass = B.metal("SconceBrass", base=(0.5, 0.36, 0.16), rough=0.28)
    objs = []
    plate = B.lathe("Plate", [(0.0, 0.0), (0.33, 0.0), (0.35, 0.03), (0.3, 0.07), (0.15, 0.09), (0.0, 0.09)], 32, mat=brass)
    plate.rotation_euler = (math.radians(-90), 0, 0)
    objs.append(plate)
    # the arm: a quarter bend made of short tube segments
    pts = [(0.0, 0.08 + 0.6 * math.sin(t), -0.05 + 0.4 * (1 - math.cos(t))) for t in [i * (math.pi / 2) / 8 for i in range(9)]]
    for a, b in zip(pts, pts[1:]):
        mid = [(a[k] + b[k]) / 2 for k in range(3)]
        dy, dz = b[1] - a[1], b[2] - a[2]
        seg = B.cylinder("Arm", 0.045, math.hypot(dy, dz) + 0.02, (0, 0, 0), "Z", brass, 12)
        seg.rotation_euler = (-math.atan2(dy, dz), 0, 0)
        seg.location = mid
        objs.append(seg)
    objs.append(B.lathe("Cup", [(0.0, 0.3), (0.08, 0.3), (0.16, 0.36), (0.17, 0.42), (0.14, 0.44), (0.0, 0.44)], 24, loc=(0, 0.68, 0), mat=brass))
    return objs, {"cam": 3.2}


def radiator():
    """Cast-iron column radiator, 8 sections, on two feet, with a valve on the
    left inlet, all within the 3.3 studs of the part-built radiator. Painted cream, chipped to
    iron on the edges."""
    iron = B.paint("RadiatorPaint", (0.62, 0.58, 0.5), rough=0.5, under=(0.09, 0.08, 0.075), chip=0.45, metallic_under=0.6)
    brass = B.metal("ValveBrass", base=(0.45, 0.32, 0.14), rough=0.35)
    objs = []
    for i in range(8):
        x = (i - 3.5) * 0.38
        for y in (-0.16, 0.16):
            objs.append(B.cylinder("Column", 0.1, 2.2, (x, y, 1.6), "Z", iron, 14))
        objs.append(B.box("HubTop", (0.3, 0.52, 0.2), (x, 0, 2.72), iron, bev=0.06, seg=3))
        objs.append(B.box("HubBottom", (0.3, 0.52, 0.2), (x, 0, 0.5), iron, bev=0.06, seg=3))
    for sx in (-1, 1):
        objs.append(B.box("Foot", (0.28, 0.6, 0.42), (sx * 1.14, 0, 0.21), iron, bev=0.05, seg=2))
    objs.append(B.cylinder("Inlet", 0.07, 0.14, (-1.42, 0, 0.5), "X", brass, 12))
    objs.append(B.lathe("ValveBody", [(0.0, -0.12), (0.11, -0.1), (0.12, 0.0), (0.11, 0.1), (0.0, 0.12)], 16, loc=(-1.48, 0, 0.5), mat=brass))
    objs.append(B.cylinder("ValveStem", 0.03, 0.3, (-1.48, 0, 0.72), "Z", brass, 8))
    objs.append(B.lathe("ValveWheel", [(0.0, -0.025), (0.16, -0.025), (0.17, 0.0), (0.16, 0.025), (0.0, 0.025)], 20, loc=(-1.48, 0, 0.88), mat=brass))
    return objs, {"cam": 6}


def wood_chair():
    """Turned bentwood-style side chair (1.8 x 4 x 1.8): dished seat, turned
    legs, back posts, a curved crest rail and spindles; back at y = -0.8."""
    wood = B.wood("ChairWood", base=(0.07, 0.035, 0.018), light=(0.22, 0.11, 0.055), scale=4)
    objs = []
    seat = B.box("Seat", (1.8, 1.8, 0.2), (0, 0, 1.9), B.wood("ChairSeat", base=(0.07, 0.035, 0.018), light=(0.22, 0.11, 0.055), scale=4, axis="X"), bev=0.08, seg=3)
    objs.append(seat)
    leg = [(0.0, 0.0), (0.07, 0.0), (0.09, 0.15), (0.075, 0.5), (0.1, 0.9), (0.08, 1.2), (0.1, 1.6), (0.11, 1.8), (0.0, 1.8)]
    for x, y in ((-0.72, 0.72), (0.72, 0.72), (-0.72, -0.72), (0.72, -0.72)):
        objs.append(B.lathe("Leg", leg, 14, loc=(x, y, 0), mat=wood))
    for x in (-0.72, 0.72):
        objs.append(B.lathe("BackPost", [(0.0, 1.95), (0.085, 1.95), (0.07, 2.6), (0.085, 3.3), (0.07, 3.9), (0.0, 3.95)], 14, loc=(x, -0.76, 0), mat=wood))
    for x in (-0.36, 0.0, 0.36):
        objs.append(B.cylinder("Spindle", 0.04, 1.45, (x, -0.76, 2.75), "Z", wood, 10))
    crest = [(-0.08 + 0.06 * math.sin(k * math.pi / 8), 3.45 + 0.16 * k / 8) for k in range(9)] + [(0.08, 3.61), (0.1, 3.45)]
    objs.append(B.extrude_profile("Crest", crest, 1.62, "X", loc=(0, -0.76, 0), mat=wood, bev=0.02))
    for y in (-0.72, 0.72):
        objs.append(B.cylinder("Stretcher", 0.045, 1.3, (0, y, 0.55), "X", wood, 10))
    for x in (-0.72, 0.72):
        objs.append(B.cylinder("Stretcher", 0.045, 1.3, (x, 0, 0.75), "Y", wood, 10))
    return objs, {"cam": 6}


def table():
    """Turned-leg table 5 x 3 (the default Props.table size), top 3.12 high
    with a rounded edge, aprons, turned legs."""
    wood = B.wood("TableWood", base=(0.07, 0.035, 0.018), light=(0.22, 0.11, 0.055), scale=3)
    objs = []
    edge = [(-1.5 + 0.0, 2.875), (1.5, 2.875)] + [(1.5 + 0.0, 3.0)] + [(-1.5, 3.12)]
    woodX = B.wood("TableTop", base=(0.07, 0.035, 0.018), light=(0.22, 0.11, 0.055), scale=3, axis="X")
    objs.append(B.box("Top", (5.0, 3.0, 0.25), (0, 0, 3.0), woodX, bev=0.07, seg=3))
    for sz, loc in (((4.12, 0.1, 0.42), (0, 1.2, 2.66)), ((4.12, 0.1, 0.42), (0, -1.2, 2.66)), ((0.1, 2.12, 0.42), (2.2, 0, 2.66)), ((0.1, 2.12, 0.42), (-2.2, 0, 2.66))):
        objs.append(B.box("Apron", sz, loc, wood, bev=0.02))
    leg = [(0.0, 0.0), (0.08, 0.0), (0.1, 0.12), (0.08, 0.6), (0.12, 1.3), (0.09, 1.8), (0.13, 2.3), (0.14, 2.4), (0.14, 2.87), (0.0, 2.87)]
    for x, y in ((-2.2, 1.2), (2.2, 1.2), (-2.2, -1.2), (2.2, -1.2)):
        objs.append(B.lathe("Leg", leg, 16, loc=(x, y, 0), mat=wood))
    _ = edge
    return objs, {"cam": 8}


def sofa():
    """Buttoned chesterfield sofa 6 x 2.6: rolled arms, deep buttoned back,
    two seat cushions, turned feet. Worn upholstery."""
    leather = B.fabric("SofaFabric", (0.12, 0.05, 0.035), rough=0.75)
    wood = B.wood("SofaFeet", base=(0.05, 0.025, 0.012), light=(0.15, 0.075, 0.035))
    objs = []
    objs.append(B.box("Base", (6.0, 2.5, 0.9), (0, 0.0, 0.85), leather, bev=0.18, seg=4))
    objs.append(B.box("Back", (6.0, 0.6, 1.9), (0, -1.0, 1.95), leather, bev=0.25, seg=5))
    for sx in (-1, 1):
        objs.append(B.box("Arm", (0.6, 2.5, 1.3), (sx * 2.7, 0, 1.6), leather, bev=0.22, seg=5))
        objs.append(B.cylinder("Roll", 0.36, 2.5, (sx * 2.78, 0, 2.25), "Y", leather, 20))
    for sx in (-1, 1):
        objs.append(B.box("Cushion", (2.55, 2.0, 0.42), (sx * 1.28, 0.1, 1.5), leather, bev=0.16, seg=4))
    # tufting: shallow buttons in a grid on the back
    for row in range(2):
        for col in range(7):
            # built at the origin, turned to face +Y, then moved onto the back
            btn = B.lathe("Button", [(0.0, 0.0), (0.05, 0.0), (0.05, 0.03), (0.0, 0.04)], 10, mat=leather)
            btn.rotation_euler = (math.radians(-90), 0, 0)
            btn.location = (-2.25 + col * 0.75 + (row % 2) * 0.375, -0.69, 2.1 + row * 0.5)
            objs.append(btn)
    for x, y in ((-2.7, 1.0), (2.7, 1.0), (-2.7, -1.0), (2.7, -1.0)):
        objs.append(B.lathe("Foot", [(0.0, 0.0), (0.08, 0.0), (0.12, 0.2), (0.1, 0.4), (0.0, 0.4)], 12, loc=(x, y, 0), mat=wood))
    return objs, {"cam": 9}


def filing_cabinet():
    """Steel 3-drawer filing cabinet 1.8 x 4.4 x 2.2: pressed drawer fronts
    with a recess, label holders, pull handles, a toe kick, painted green-grey
    chipped to bare steel."""
    steel = B.paint("CabinetPaint", (0.16, 0.19, 0.17), rough=0.45, under=(0.25, 0.25, 0.25), chip=0.5, metallic_under=0.9)
    chrome = B.metal("CabinetChrome", base=(0.6, 0.6, 0.58), rough=0.25, tarnish=(0.2, 0.19, 0.17))
    objs = [B.box("Body", (1.8, 2.2, 4.3), (0, 0, 2.25), steel, bev=0.03)]
    objs.append(B.box("Kick", (1.6, 2.0, 0.12), (0, -0.02, 0.06), steel, bev=0.01))
    for i in range(3):
        z = 0.8 + i * 1.4
        objs.append(B.box("Front", (1.62, 0.08, 1.28), (0, 1.12, z), steel, bev=0.04, seg=3))
        objs.append(B.box("Recess", (1.3, 0.04, 0.9), (0, 1.16, z - 0.05), steel, bev=0.02))
        objs.append(B.box("LabelHolder", (0.5, 0.05, 0.25), (0, 1.19, z + 0.43), chrome, bev=0.01))
        objs.append(B.box("Pull", (0.6, 0.12, 0.08), (0, 1.24, z + 0.15), chrome, bev=0.03, seg=3))
    objs.append(B.cylinder("Lock", 0.07, 0.06, (0.62, 1.13, 4.25), "Y", chrome, 12))
    return objs, {"cam": 6.5}


def _trim_run(name, profile, mat):
    """A 4-stud straight run of a moulding profile (u = out from the wall =
    +Y, v = up). Origin: back-bottom centre (on the wall, at the run's foot).
    The game stretches it along X to each wall run (the profile does not
    change along X, so stretching never distorts it)."""
    return [B.extrude_profile(name, profile, 4.0, "X", mat=mat)], {"cam": 3.5, "tex": 512}


def baseboard():
    """Moulded skirting 0.5 high, 0.35 deep: a flat board with an ogee cap
    and a small bead at the floor."""
    wood = B.wood("SkirtingWood", base=(0.04, 0.02, 0.01), light=(0.13, 0.065, 0.032), gloss=0.3, axis="X")
    prof = [(0.0, 0.0), (0.33, 0.0), (0.35, 0.025), (0.33, 0.05), (0.3, 0.06), (0.3, 0.36)]
    prof += [(0.3 - 0.12 * (1 - math.cos(math.pi * t)) / 2, 0.36 + 0.14 * t) for t in (0.2, 0.4, 0.6, 0.8, 1.0)]
    prof += [(0.0, 0.5)]
    return _trim_run("Baseboard", prof, wood)


def dado_rail():
    """Chair rail 0.2 high, 0.32 deep: a rounded nosing over a small cove."""
    wood = B.wood("RailWood", base=(0.04, 0.02, 0.01), light=(0.13, 0.065, 0.032), gloss=0.3, axis="X")
    prof = [(0.0, 0.0), (0.12, 0.0), (0.16, 0.04)]
    prof += [(0.22 + 0.1 * math.cos(a), 0.1 + 0.1 * math.sin(a)) for a in [(-90 + k * 22.5) * math.pi / 180 for k in range(9)]]
    prof += [(0.0, 0.2)]
    return _trim_run("DadoRail", prof, wood)


def cornice():
    """Plaster crown moulding 0.32 high, 0.24 out: a cove between two fillets.
    Origin at the back-bottom (on the wall, at the cove's foot)."""
    plaster = B.paint("CornicePlaster", (0.62, 0.6, 0.55), rough=0.8, under=(0.4, 0.38, 0.34), chip=0.25)
    prof = [(0.0, 0.0), (0.04, 0.0), (0.04, 0.03)]
    prof += [(0.04 + 0.17 * (1 - math.cos(a)), 0.03 + 0.22 * math.sin(a)) for a in [k * (math.pi / 2) / 8 for k in range(1, 9)]]
    prof += [(0.24, 0.27), (0.24, 0.32), (0.0, 0.32)]
    return _trim_run("Cornice", prof, plaster)


def office_desk():
    """Pedestal office desk 6 x 3 (Props.desk): moulded top, a three-drawer
    pedestal on the right with brass cup pulls, a side panel on the left and a
    modesty panel at the back. Front = +Y."""
    wood = B.wood("OfficeDeskWood", base=(0.06, 0.03, 0.015), light=(0.19, 0.095, 0.045))
    woodX = B.wood("OfficeDeskTop", base=(0.06, 0.03, 0.015), light=(0.19, 0.095, 0.045), axis="X")
    brass = B.metal("OfficeDeskBrass", base=(0.5, 0.36, 0.16), rough=0.3)
    objs = [B.box("Top", (6.0, 3.0, 0.3), (0, 0, 3.15), woodX, bev=0.06, seg=3)]
    objs.append(B.box("SidePanel", (0.25, 2.8, 2.86), (-2.85, 0, 1.57), wood, bev=0.02))
    objs.append(B.box("Pedestal", (1.8, 2.8, 2.86), (1.95, 0, 1.57), wood, bev=0.02))
    objs.append(B.box("Plinth", (1.6, 2.5, 0.14), (1.95, -0.05, 0.07), wood, bev=0.01))
    objs.append(B.box("Modesty", (5.6, 0.15, 1.8), (0, -1.3, 2.1), wood, bev=0.015))
    for i in range(3):
        z = 0.62 + i * 0.95
        p = B.fielded_panel("DrawerFront", 1.6, 0.85, 0.06, 0.1, (0, 0, 0), wood)
        p.location = (1.95, 1.4, z)
        objs.append(p)
        objs.append(B.lathe("PullBack", [(0.0, 0.0), (0.12, 0.0), (0.12, 0.02), (0.0, 0.02)], 16, mat=brass))
        cup = objs[-1]
        cup.rotation_euler = (math.radians(-90), 0, 0)
        cup.location = (1.95, 1.47, z + 0.18)
        objs.append(B.box("Pull", (0.5, 0.06, 0.1), (1.95, 1.52, z + 0.18), brass, bev=0.03, seg=3))
    return objs, {"cam": 8}


def locker():
    """Steel locker 2 x 6.6 x 1.8 (Props.locker): pressed door with louvres,
    a lift handle, a number plate, hinges, a dark plinth. Painted, chipped."""
    steel = B.paint("LockerPaint", (0.18, 0.24, 0.28), rough=0.45, under=(0.3, 0.3, 0.3), chip=0.5, metallic_under=0.9)
    chrome = B.metal("LockerChrome", base=(0.6, 0.6, 0.58), rough=0.25, tarnish=(0.2, 0.19, 0.17))
    objs = [B.box("Body", (2.0, 1.8, 6.4), (0, 0, 3.4), steel, bev=0.03)]
    objs.append(B.box("Plinth", (1.9, 1.7, 0.2), (0, -0.02, 0.1), steel, bev=0.01))
    objs.append(B.box("Door", (1.8, 0.06, 6.1), (0, 0.92, 3.45), steel, bev=0.03, seg=2))
    for i in range(5):
        objs.append(B.box("Louvre", (1.0, 0.08, 0.07), (0, 0.97, 5.5 + i * 0.2), steel, bev=0.02))
    objs.append(B.box("Handle", (0.12, 0.12, 0.6), (0.65, 1.0, 3.2), chrome, bev=0.04, seg=3))
    objs.append(B.box("NumberPlate", (0.5, 0.04, 0.3), (0, 0.97, 4.7), chrome, bev=0.01))
    for z in (1.2, 5.6):
        objs.append(B.cylinder("Hinge", 0.05, 0.5, (-0.92, 0.95, z), "Z", chrome, 10))
    return objs, {"cam": 8}


def metal_shelf():
    """Bolted steel shelving 6 wide (Props.metalShelf default): angle-iron
    posts, four shelves with folded lips, X-bracing at the back, foot plates."""
    steel = B.paint("ShelfPaint", (0.32, 0.33, 0.32), rough=0.5, under=(0.1, 0.09, 0.08), chip=0.4, metallic_under=0.8)
    objs = []
    for x in (-2.9, 2.9):
        for y in (-0.85, 0.85):
            # angle-iron post: an L section
            objs.append(B.box("PostA", (0.2, 0.04, 7.0), (x, y + (0.08 if y < 0 else -0.08), 3.5), steel, bev=0.008))
            objs.append(B.box("PostB", (0.04, 0.2, 7.0), (x + (0.08 if x < 0 else -0.08), y, 3.5), steel, bev=0.008))
            objs.append(B.box("FootPlate", (0.34, 0.34, 0.04), (x, y, 0.02), steel, bev=0.01))
    for i in range(4):
        z = 0.5 + i * 2.1
        objs.append(B.box("Shelf", (6.0, 2.0, 0.06), (0, 0, z), steel, bev=0.01))
        objs.append(B.box("Lip", (5.6, 0.04, 0.3), (0, 1.02, z - 0.1), steel, bev=0.01))
        objs.append(B.box("LipBack", (5.6, 0.04, 0.3), (0, -1.02, z - 0.1), steel, bev=0.01))
    span, rise = 5.6, 6.3
    ang = math.atan2(rise, span)
    for sgn in (-1, 1):
        br = B.box("Brace", (math.hypot(span, rise), 0.03, 0.08), (0, 0, 0), steel, bev=0.0)
        br.rotation_euler = (0, -sgn * ang, 0)
        br.location = (0, -0.95, 3.65)
        objs.append(br)
    return objs, {"cam": 9}


def picture_frame():
    """Gilt picture frame, 4.5 x 3.5 outside (a 4 x 3 painting), stretched by
    the game to each painting's size. Origin on the wall, centre of the
    picture; the moulding stands out to +Y and keeps a 0.03 lip over the
    canvas edge. Gold leaf worn through to red bole on the high edges."""
    gilt = B.paint("FrameGilt", (0.55, 0.4, 0.15), rough=0.35, under=(0.35, 0.09, 0.05), chip=0.6, metallic_under=0.0)
    objs = []
    W, H, b = 4.5, 3.5, 0.28
    prof = [(0.0, 0.0), (b, 0.0), (b, 0.18), (b - 0.05, 0.3), (b - 0.12, 0.33), (b - 0.2, 0.3), (b - 0.25, 0.27), (0.0, 0.27)]
    # four bars, each a profile extruded along its edge (u across the bar from the opening, v = depth)
    # top / bottom bars run the full width; the side bars butt between them
    # (no overlapping volumes, so no coplanar faces at the corners)
    for side in ("top", "bottom", "left", "right"):
        if side in ("top", "bottom"):
            # extruded along X: profile points are (Y = depth, Z = height)
            pts = [(v, (H / 2 - b + u) if side == "top" else -(H / 2 - b + u)) for u, v in prof]
            o = B.extrude_profile("Bar", pts, W, "X", mat=gilt)
        else:
            # extruded along Z: profile points are (X, Y = depth)
            pts = [((W / 2 - b + u) if side == "right" else -(W / 2 - b + u), v) for u, v in prof]
            o = B.extrude_profile("Bar", pts, H - 2 * b, "Z", mat=gilt)
        objs.append(o)
    return objs, {"cam": 6}


ASSETS = {
    "ReceptionDesk": reception_desk,
    "DoorLeaf": door_leaf,
    "DoorCasing": door_casing,
    "PendantLamp": pendant_lamp,
    "WallSconce": wall_sconce,
    "Radiator": radiator,
    "WoodChair": wood_chair,
    "Table": table,
    "Sofa": sofa,
    "FilingCabinet": filing_cabinet,
    "Baseboard": baseboard,
    "DadoRail": dado_rail,
    "Cornice": cornice,
    "OfficeDesk": office_desk,
    "Locker": locker,
    "MetalShelf": metal_shelf,
    "PictureFrame": picture_frame,
}


def build(name):
    B.reset()
    objs, opts = ASSETS[name]()
    obj = B.join(objs, name)
    B.unwrap(obj)
    tris = B.triangle_count(obj)
    tex_dir = os.path.join(OUT, name)
    maps = B.bake(obj, tex_dir, name, size=opts.get("tex", 1024))
    size, centre = B.export_obj(obj, os.path.join(OUT, name + ".obj"))
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
    B.preview(obj, os.path.join(OUT, "previews", name + ".png"), maps, cam_dist=opts.get("cam"))
    print("%s: %d triangles, size %.2f x %.2f x %.2f" % (name, tris, *size))
    return {"size": size, "centre": centre, "tris": tris}


def write_meta(meta):
    old = {}
    if os.path.exists(META):
        # keep entries of assets not rebuilt this run
        import re

        src = open(META).read()
        for m in re.finditer(r"\t(\w+) = \{ size = Vector3\.new\(([^)]*)\), offset = Vector3\.new\(([^)]*)\), triangles = (\d+) \}", src):
            old[m.group(1)] = m.group(0)
    lines = [
        "--[[",
        "\tPropMeshMeta (generated by tools/blender/build_assets.py - do not edit)",
        "\tBounds of every prop mesh in studs (Roblox axes) and the offset of its",
        "\tbounding-box centre from the prop's origin (centre of the footprint on the",
        "\tfloor), so MeshPart.Size and its CFrame can be set exactly.",
        "]]",
        "",
        "return {",
    ]
    names = sorted(set(old) | set(meta))
    for n in names:
        if n in meta:
            s, c = meta[n]["size"], meta[n]["centre"]
            lines.append("\t%s = { size = Vector3.new(%.4f, %.4f, %.4f), offset = Vector3.new(%.4f, %.4f, %.4f), triangles = %d }," % (n, *s, *c, meta[n]["tris"]))
        else:
            lines.append(old[n] + ",")
    lines.append("}")
    open(META, "w").write("\n".join(lines) + "\n")


def main():
    names = [a for a in sys.argv[1:] if a in ASSETS] or list(ASSETS)
    meta = {}
    for n in names:
        meta[n] = build(n)
    write_meta(meta)


if __name__ == "__main__":
    main()
