"""
THE OBSERVER, as smooth flowing meshes (replaces tools/gen_observer.py's
ribbed sculpt). One mesh per rig segment, so the Motor6D rig in
src/shared/ObserverRig.luau keeps animating it: each mesh is welded to its
(hidden) rig part by ObserverRig.dress.

Every segment is a loft of rounded cross-sections smoothed with a
subdivision surface: no hard edges, no separate pieces. Segments overlap at
the joints with rounded, tapering ends, so the body reads as one continuous
shape when it bends:
  Head        the wide horizontal blade and the point under it that runs
              into the neck, one piece: top edge almost straight, lower edge
              rising to the tips
  Neck        long and thin, flaring into the chin and the shoulders
  UpperTorso  narrow waist widening into sloped shoulders that reach the arms
  LowerTorso, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot

Coordinates are Roblox's (Y up, front -Z), each mesh in its rig part's local
space. The rest pose matches ObserverRig.build (feet at y = 0).

    /home/user/.venv-blender/bin/python tools/blender/build_observer.py

Writes assets/observer/<Segment>.obj and src/shared/Config/ObserverMeshMeta.luau.
"""

import math
import os

import bpy  # noqa: I001
import bmesh

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "observer")
META = os.path.join(ROOT, "src", "shared", "Config", "ObserverMeshMeta.luau")
RING = 14  # points per cross-section


# Rig part centres at rest (ObserverRig.build, base = identity). Paired
# segments are modelled once, centred on the right-hand part.
PART_CENTRE = {
    "Head": (0, 9.0, 0),
    "Neck": (0, 8.05, 0),
    "UpperTorso": (0, 6.45, 0),
    "LowerTorso": (0, 4.9, 0),
    "UpperArm": (1.1, 5.9, 0),
    "LowerArm": (1.13, 3.15, 0),
    "Hand": (1.14, 1.55, 0),
    "UpperLeg": (0.27, 3.45, 0),
    "LowerLeg": (0.27, 1.25, 0),
    "Foot": (0.27, 0.1, -0.15),
}


def ring_x(x, cy, top, bottom, depth, front=None):
    """A section across the X axis (the head's blade): above the centre line
    it reaches `top`, below `bottom`; `depth` front/back (front may differ)."""
    pts = []
    for i in range(RING):
        a = 2 * math.pi * i / RING
        s, c = math.sin(a), math.cos(a)
        y = cy + (top if s > 0 else bottom) * s
        z = (front if (front is not None and c < 0) else depth) * c
        pts.append((x, y, z))
    return pts


def ring_y(y, cx, wl, wr, depth_front, depth_back):
    """A section across the Y axis (torso, limbs): width to the left / right
    of `cx`, depth to the front (-Z) / back (+Z)."""
    pts = []
    for i in range(RING):
        a = 2 * math.pi * i / RING
        s, c = math.sin(a), math.cos(a)
        x = cx + (wr if c > 0 else wl) * c
        z = (depth_back if s > 0 else depth_front) * s
        pts.append((x, y, z))
    return pts


def ring_z(z, cx, cy, w, up, down):
    """A section across the Z axis (the foot)."""
    pts = []
    for i in range(RING):
        a = 2 * math.pi * i / RING
        s, c = math.sin(a), math.cos(a)
        pts.append((cx + w * c, cy + (up if s > 0 else down) * s, z))
    return pts


def loft(rings, cap_a, cap_b):
    """A closed tube through the rings, capped with a point at each end."""
    verts, faces = [], []
    for r in rings:
        verts.extend(r)
    n = len(rings)
    for j in range(n - 1):
        for i in range(RING):
            a = j * RING + i
            b = j * RING + (i + 1) % RING
            faces.append((a, b, b + RING, a + RING))
    ia = len(verts)
    verts.append(cap_a)
    ib = len(verts)
    verts.append(cap_b)
    for i in range(RING):
        faces.append((ia, (i + 1) % RING, i))
        last = (n - 1) * RING
        faces.append((ib, last + i, last + (i + 1) % RING))
    return verts, faces


def head():
    # the blade: sections from the middle out to each tip (symmetric)
    prof = [  # x, centre y, top, bottom, depth
        (0.0, 9.05, 0.29, 0.78, 0.25),
        (0.32, 9.05, 0.28, 0.46, 0.24),
        (0.75, 9.05, 0.25, 0.27, 0.21),
        (1.3, 9.06, 0.2, 0.13, 0.16),
        (1.85, 9.07, 0.13, 0.05, 0.1),
    ]
    rings = []
    for x, cy, top, bottom, depth in reversed(prof[1:]):
        rings.append(ring_x(-x, cy, top, bottom, depth))
    for x, cy, top, bottom, depth in prof:
        rings.append(ring_x(x, cy, top, bottom, depth))
    return loft(rings, (-2.35, 9.08, 0), (2.35, 9.08, 0))


def along_y(sections, cap_low, cap_high, cx=0.0):
    """sections: (y, half width, half depth) from low to high."""
    rings = [ring_y(y, cx, w, w, d, d) for y, w, d in sections]
    return loft(rings, cap_low, cap_high)


def limb(cx, rings, cap):
    """A round limb: rings are (y, radius) from low to high; the caps sit a
    little beyond the end rings so the ends are rounded, not pointed, and two
    limbs meeting at a joint overlap with the same thickness (no pinch)."""
    lo_y, lo_r = rings[0]
    hi_y, hi_r = rings[-1]
    return along_y([(y, r, r) for y, r in rings], (cx, lo_y - cap * lo_r, 0), (cx, hi_y + cap * hi_r, 0), cx=cx)


# Joints at rest: shoulder y 7.35, elbow 4.45, wrist 1.85, hip 4.6, knee 2.3,
# ankle 0.2, waist ~5.3, neck base 7.6, head joint 8.55. Both segments at a
# joint carry a ring of the same radius across it.
SEGMENTS = {
    "Head": head,
    "Neck": lambda: along_y([(7.45, 0.36, 0.2), (7.7, 0.2, 0.16), (8.15, 0.15, 0.14), (8.55, 0.2, 0.17)], (0, 7.3, 0), (0, 8.75, 0)),
    # narrow waist widening into sloped shoulders that reach the arms
    "UpperTorso": lambda: along_y(
        [(5.15, 0.38, 0.22), (5.45, 0.4, 0.22), (6.35, 0.54, 0.25), (6.9, 0.78, 0.25), (7.22, 1.22, 0.21), (7.48, 0.74, 0.19)],
        (0, 5.02, 0),
        (0, 7.72, 0),
    ),
    "LowerTorso": lambda: along_y([(4.35, 0.34, 0.21), (4.6, 0.44, 0.23), (5.0, 0.42, 0.23), (5.45, 0.38, 0.22)], (0, 4.2, 0), (0, 5.58, 0)),
    "UpperArm": lambda: limb(1.1, [(4.38, 0.105), (4.6, 0.105), (5.9, 0.12), (7.2, 0.13), (7.42, 0.12)], 0.8),
    "LowerArm": lambda: limb(1.13, [(1.8, 0.075), (1.95, 0.075), (3.15, 0.095), (4.35, 0.105), (4.55, 0.105)], 0.8),
    "Hand": lambda: along_y([(1.25, 0.05, 0.03), (1.5, 0.095, 0.05), (1.75, 0.085, 0.055), (1.92, 0.075, 0.075)], (1.14, 1.1, 0), (1.14, 1.98, 0), cx=1.14),
    "UpperLeg": lambda: limb(0.27, [(2.2, 0.125), (2.45, 0.125), (3.45, 0.15), (4.45, 0.18), (4.75, 0.17)], 0.8),
    "LowerLeg": lambda: limb(0.27, [(0.15, 0.085), (0.3, 0.085), (1.25, 0.115), (2.2, 0.125), (2.4, 0.125)], 0.8),
    "Foot": lambda: loft(
        [ring_z(0.18, 0.27, 0.1, 0.1, 0.09, 0.09), ring_z(-0.05, 0.27, 0.09, 0.11, 0.08, 0.08), ring_z(-0.35, 0.27, 0.07, 0.07, 0.05, 0.06)],
        (0.27, 0.12, 0.26),
        (0.27, 0.05, -0.55),
    ),
}


def smooth(name, verts, faces, levels=2):
    """Subdivision surface, triangulated: (verts, normals, tris)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    me.validate()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    m = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(m)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.normal_update()
    out_v = [tuple(v.co) for v in bm.verts]
    out_n = [tuple(v.normal) for v in bm.verts]
    out_f = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    ev.to_mesh_clear()
    return out_v, out_n, out_f


def write_obj(path, verts, normals, tris, name):
    with open(path, "w") as fh:
        fh.write("# DON'T LOOK AWAY - The Observer (tools/blender/build_observer.py)\n")
        # the object name: Studio names the imported mesh after it
        fh.write("o Observer%s\n" % name)
        for v in verts:
            fh.write("v %.5f %.5f %.5f\n" % v)
        fh.write("vt 0.5 0.5\n")
        for n in normals:
            fh.write("vn %.5f %.5f %.5f\n" % n)
        for a, b, c in tris:
            fh.write("f %d/1/%d %d/1/%d %d/1/%d\n" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    meta = []
    for name, make in SEGMENTS.items():
        verts, faces = make()
        v, n, f = smooth(name, verts, faces)
        cx, cy, cz = PART_CENTRE[name]
        local = [(x - cx, y - cy, z - cz) for x, y, z in v]
        write_obj(os.path.join(OUT, name + ".obj"), local, n, f, name)
        lo = [min(p[i] for p in local) for i in range(3)]
        hi = [max(p[i] for p in local) for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        off = [(hi[i] + lo[i]) / 2 for i in range(3)]
        meta.append((name, size, off, len(f)))
        print("%-11s %5d triangles  size %.2f x %.2f x %.2f" % (name, len(f), *size))
    # the old face halves are gone from the design
    for stale in ("FaceL.obj", "FaceR.obj"):
        p = os.path.join(OUT, stale)
        if os.path.exists(p):
            os.remove(p)
    with open(META, "w") as fh:
        fh.write("--[[\n\tObserverMeshMeta (generated by tools/blender/build_observer.py - do not edit)\n")
        fh.write("\tBounding box of every Observer mesh in its rig part's local space: the\n")
        fh.write("\tgame sizes each MeshPart to `size` and places it at `offset` from the part.\n]]\n\nreturn {\n")
        for name, size, off, tris in meta:
            fh.write(
                "\t%s = { size = Vector3.new(%.4f, %.4f, %.4f), offset = Vector3.new(%.4f, %.4f, %.4f), triangles = %d },\n"
                % (name, *size, *off, tris)
            )
        fh.write("}\n")
    print("done")


if __name__ == "__main__":
    main()
