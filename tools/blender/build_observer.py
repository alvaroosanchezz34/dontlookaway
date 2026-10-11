"""
THE OBSERVER V2 - an organic creature, sculpted procedurally in Blender.

Not boxes, not lofted tubes: every segment of the body is a SCULPT built from
blended metaball volumes (they fuse into one continuous surface, and negative
volumes carve sockets, clefts and hollows), roughened with layered noise, then
baked onto a lighter game mesh:

  high   metaballs -> mesh (~0.02 stud resolution) -> organic noise displacement
  low    the high mesh decimated to a game budget, UV-unwrapped
  bake   high -> low: tangent normal map (OpenGL), colour (with cavity
         darkening) and roughness, 1024 px for the head and torso, 512 px for
         the limbs

Layers (each has a job):
  base anatomy      the silhouette: a tall, hunched, narrow body, a heavy
                    head; real volume in the chest, back, thighs and forearms
  secondary volumes tissue that breaks the skeleton look: a hunched dorsal
                    mass, sloping trapezius slopes, shoulder masses, folds of
                    dark tissue hanging down the flanks, thin membranes from
                    the neck to the shoulders and under the head, knots at
                    the elbows and knees
  surface           irregular, matte, never plastic: low lumps and fine
                    wrinkles in the geometry; mottled near-black skin with
                    darker cavities and slightly lighter ridges in the maps;
                    roughness 0.75-0.95, a little lower in the deepest folds
  focal detail      the head: a wide, drooping, asymmetric crescent (the
                    left side longer, the right side lower), a heavy brow
                    ridge, a cleft down the middle of a long faceless face,
                    two deep sockets (left higher) for the two small eyes,
                    which are rig parts that turn to the player

Each mesh is in its rig part's local space (Roblox axes: Y up, front -Z), so
ObserverRig.dress welds it over the Motor6D rig. Neighbouring segments
overlap at the joints so the body stays continuous when it bends. Paired
limbs share one mesh (kept nearly symmetric in X).

    /home/user/.venv-blender/bin/python tools/blender/build_observer.py [Segment ...]

Writes assets/observer/<Segment>.obj, assets/observer/<Segment>/<Segment>_
{color,normal,roughness}.png and src/shared/Config/ObserverMeshMeta.luau.
"""

import math
import os
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Vector, noise

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "observer")
META = os.path.join(ROOT, "src", "shared", "Config", "ObserverMeshMeta.luau")
K = 0.575  # metaball surface extent per unit of radius x size (threshold 0.6, stiffness 2)

# Eyes (ObserverRig): head-local centres. The sockets are carved around them.
EYE_L = (-0.19, 0.12, -0.23)
EYE_R = (0.21, 0.05, -0.22)

# Rig part centres at rest (ObserverRig.build, base = identity).
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

# triangles of the game mesh, texture size
BUDGET = {
    "Head": (6000, 1024),
    "UpperTorso": (6000, 1024),
    "Neck": (2400, 512),
    "LowerTorso": (2400, 512),
    "UpperArm": (2400, 512),
    "LowerArm": (2000, 512),
    "Hand": (1600, 512),
    "UpperLeg": (2400, 512),
    "LowerLeg": (2000, 512),
    "Foot": (1400, 512),
}


# ---------------------------------------------------------------------------
# sculpting with metaballs
# ---------------------------------------------------------------------------


class Sculpt:
    def __init__(self):
        self.items = []

    def ell(self, c, h, rot=None, neg=False, stiff=2.0):
        """Ellipsoid with half extents h=(x, y, z); rot=(rx, ry, rz) degrees."""
        self.items.append(("ELLIPSOID", Vector(c), h, rot, neg, stiff))

    def ball(self, c, r, neg=False, stiff=2.0):
        self.items.append(("BALL", Vector(c), (r, r, r), None, neg, stiff))

    def cap(self, a, b, r, neg=False, stiff=2.0):
        """Capsule from a to b with radius r."""
        a, b = Vector(a), Vector(b)
        self.items.append(("CAPSULE", (a + b) / 2, (b - a), r, neg, stiff))

    def chain(self, points, radii, flat=1.0):
        """Overlapping ellipsoids along a polyline, radius tapering; `flat`
        squashes them front-to-back (a blade rather than a horn)."""
        for i in range(len(points) - 1):
            a, b = Vector(points[i]), Vector(points[i + 1])
            r = (radii[i] + radii[i + 1]) / 2
            d = b - a
            yaw = 0.0
            roll = math.degrees(math.atan2(d.y, d.x))
            yaw = -math.degrees(math.atan2(d.z, math.hypot(d.x, d.y)))
            self.ell((a + b) / 2, (d.length / 2 + r * 0.6, r, r * flat), rot=(0, yaw, roll))

    def build(self, name, resolution=0.02):
        mb = bpy.data.metaballs.new(name)
        mb.resolution = resolution
        mb.render_resolution = resolution
        mb.threshold = 0.6
        obj = bpy.data.objects.new(name + "_mb", mb)
        bpy.context.scene.collection.objects.link(obj)
        for kind, c, h, extra, neg, stiff in self.items:
            e = mb.elements.new()
            e.stiffness = stiff
            e.use_negative = neg
            e.co = c
            if kind == "BALL":
                e.type = "BALL"
                e.radius = h[0] / K
            elif kind == "ELLIPSOID":
                e.type = "ELLIPSOID"
                e.radius = 1.0
                e.size_x, e.size_y, e.size_z = (h[0] / K, h[1] / K, h[2] / K)
                if extra:
                    rx, ry, rz = (math.radians(v) for v in extra)
                    from mathutils import Euler  # noqa: PLC0415

                    e.rotation = Euler((rx, ry, rz), "XYZ").to_quaternion()
            else:  # capsule: local X along the segment
                d, r = h, extra
                e.type = "CAPSULE"
                e.radius = r / K
                e.size_x = d.length / 2
                e.rotation = Vector((1, 0, 0)).rotation_difference(d.normalized())
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        bpy.data.objects.remove(obj)
        out = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(out)
        return out


def fbm(p, octaves, base_freq, seed):
    total, amp, freq, norm = 0.0, 1.0, base_freq, 0.0
    for o in range(octaves):
        total += amp * noise.noise(p * freq + Vector((seed * 7.1 + o * 3.3, seed * 1.7, -seed * 4.9)))
        norm += amp
        amp *= 0.5
        freq *= 2.1
    return total / norm


def roughen(obj, seed, lumps=0.022, wrinkles=0.006):
    """Organic surface: soft lumps plus fine stretched wrinkles, along normals,
    then a light smoothing so nothing looks faceted."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    for v in bm.verts:
        p = v.co
        n = v.normal
        lump = fbm(p, 3, 1.6, seed) * lumps
        # wrinkles stretched along Y (they follow the body's length)
        wr = fbm(Vector((p.x * 3.0, p.y * 0.8, p.z * 3.0)), 3, 5.0, seed + 11) * wrinkles
        v.co = p + n * (lump + wr)
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(obj.data)
    bm.free()
    for poly in obj.data.polygons:
        poly.use_smooth = True


# ---------------------------------------------------------------------------
# the anatomy (Roblox coordinates, feet at y = 0, front -Z)
# ---------------------------------------------------------------------------


def head():
    s = Sculpt()
    hx, hy, hz = PART_CENTRE["Head"]
    # face: long, faceless, leaning forward a little; skull mass behind
    s.ell((0, 9.0, -0.03), (0.4, 0.46, 0.28), rot=(-6, 0, 0))
    s.ell((0, 9.1, 0.14), (0.48, 0.4, 0.3))
    # heavy brow ridge, higher on the right
    s.ell((-0.17, 9.27, -0.22), (0.24, 0.08, 0.12), rot=(0, 0, 8))
    s.ell((0.19, 9.22, -0.22), (0.25, 0.09, 0.12), rot=(0, 0, -12))
    # the crescent: drooping wings, swept back. Left longer, right lower.
    left = [(-0.3, 9.12, 0.02), (-0.8, 9.12, 0.06), (-1.35, 9.06, 0.12), (-1.85, 8.94, 0.2), (-2.3, 8.78, 0.28)]
    right = [(0.3, 9.1, 0.02), (0.78, 9.06, 0.06), (1.28, 8.95, 0.13), (1.72, 8.8, 0.2), (2.05, 8.62, 0.27)]
    s.chain(left, [0.27, 0.22, 0.15, 0.09, 0.035], flat=0.62)
    s.chain(right, [0.27, 0.22, 0.15, 0.09, 0.035], flat=0.62)
    # a fold along the top of each wing (a second, thinner layer)
    s.chain([(-0.35, 9.3, 0.08), (-0.95, 9.27, 0.12), (-1.6, 9.17, 0.18)], [0.08, 0.06, 0.03], flat=0.8)
    s.chain([(0.35, 9.28, 0.08), (0.9, 9.22, 0.12), (1.45, 9.1, 0.18)], [0.08, 0.06, 0.03], flat=0.8)
    # membranes under the wings, joining them to the face (no hard joint)
    for sx in (-1, 1):
        s.ell((sx * 0.55, 8.84, 0.04), (0.38, 0.16, 0.06), rot=(0, 0, sx * 14))
    # the point under the face, down into the neck
    s.chain([(0, 8.72, -0.06), (0.02, 8.45, -0.04), (0.0, 8.22, 0.0)], [0.2, 0.12, 0.08], flat=0.9)
    # a few irregular lumps on the skull
    s.ball((0.28, 9.32, 0.22), 0.1)
    s.ball((-0.33, 9.28, 0.3), 0.08)
    # carve: the two eye sockets (deep, the left higher) and the cleft
    for ex, ey, ez in (EYE_L, EYE_R):
        # a deep socket that opens to the front, a little hooded from above
        s.ell((hx + ex, hy + ey - 0.01, hz + ez - 0.1), (0.13, 0.11, 0.14), neg=True)
    s.ell((0.0, 8.85, -0.3), (0.025, 0.2, 0.06), neg=True)
    return s


def neck():
    s = Sculpt()
    s.cap((0, 7.42, 0.04), (0, 8.6, -0.02), 0.17)
    # two tendons down the front, a heavy nape behind
    for sx in (-1, 1):
        s.cap((sx * 0.07, 8.45, -0.1), (sx * 0.24, 7.55, -0.08), 0.06)
    s.ell((0, 7.9, 0.13), (0.2, 0.42, 0.14))
    # membranes flaring to the shoulders
    for sx in (-1, 1):
        s.ell((sx * 0.34, 7.62, 0.04), (0.3, 0.16, 0.07), rot=(0, 0, sx * -26))
    return s


def upper_torso():
    s = Sculpt()
    s.ell((0, 6.72, -0.02), (0.6, 0.74, 0.36))  # ribcage
    s.ell((0, 7.12, 0.0), (0.74, 0.32, 0.32))  # upper chest
    s.ell((0, 5.55, 0.0), (0.4, 0.5, 0.25))  # waist
    s.ell((0, 5.0, 0.02), (0.37, 0.36, 0.23))  # running down over the pelvis: no seam at the waist
    s.ell((0, 7.02, 0.33), (0.5, 0.58, 0.22))  # hunched dorsal mass
    s.ell((0, 6.35, 0.3), (0.36, 0.5, 0.14))  # lower back
    # a mantle of tissue rising up the back of the neck: the head sits down
    # into the shoulders instead of on a stalk
    s.ell((0, 7.62, 0.2), (0.5, 0.36, 0.26))
    for sx in (-1, 1):
        s.ell((sx * 0.36, 7.55, 0.1), (0.28, 0.26, 0.24), rot=(0, 0, sx * -22))
    for sx in (-1, 1):
        s.ell((sx * 0.9, 7.28, 0.0), (0.32, 0.22, 0.26), rot=(0, 0, sx * -18))  # shoulder masses
        s.cap((sx * 0.22, 7.66, 0.08), (sx * 0.98, 7.38, 0.05), 0.15)  # trapezius slopes
        s.ell((sx * 0.5, 6.95, 0.22), (0.24, 0.42, 0.12), rot=(0, 0, sx * 12))  # shoulder blades under the skin
        # folds of dark tissue hanging down the flanks (three layers)
        for k, z in enumerate((-0.16, 0.0, 0.17)):
            s.ell((sx * (0.6 + 0.03 * k), 6.35 - 0.1 * k, z), (0.09, 0.5 - 0.06 * k, 0.13), rot=(0, 0, sx * (6 + 3 * k)))
        # a soft fold of tissue under the shoulder, against the ribs
        s.ell((sx * 0.62, 6.75, 0.14), (0.14, 0.55, 0.2), rot=(0, 0, sx * 10))
    # a faint ridge of spine bumps under the skin
    for i in range(6):
        s.ball((0, 7.25 - i * 0.28, 0.4 - 0.02 * i), 0.06)
    return s


def lower_torso():
    s = Sculpt()
    s.ell((0, 4.85, 0.0), (0.38, 0.3, 0.24))
    s.ell((0, 5.25, -0.01), (0.35, 0.32, 0.22))
    for sx in (-1, 1):
        s.ball((sx * 0.26, 4.62, 0.0), 0.2)
    return s


def upper_arm():
    s = Sculpt()
    # runs on into the forearm, hidden inside it: no doll joint at the elbow
    s.cap((1.1, 4.15, 0), (1.1, 7.3, 0), 0.115)
    s.ell((1.1, 4.7, 0.02), (0.13, 0.4, 0.13))  # tapering down over the elbow
    s.ball((1.1, 7.22, 0.0), 0.2)  # the shoulder cap
    s.ell((1.1, 6.3, -0.04), (0.14, 0.62, 0.13))  # a lean mass in front
    s.ell((1.1, 5.5, 0.05), (0.12, 0.55, 0.12))  # and behind
    return s


def lower_arm():
    s = Sculpt()
    s.cap((1.13, 1.72, 0), (1.13, 4.48, 0), 0.09)
    s.ell((1.13, 3.9, 0.0), (0.15, 0.55, 0.13))  # forearm near the elbow
    s.ell((1.13, 4.4, 0.03), (0.135, 0.3, 0.135))  # the elbow, long and smooth
    return s


def hand():
    s = Sculpt()
    s.ball((1.14, 1.88, 0.0), 0.07)
    s.ell((1.14, 1.68, 0.0), (0.1, 0.18, 0.05))  # the palm
    for dx, length in ((-0.055, 0.52), (0.0, 0.62), (0.055, 0.5)):
        s.cap((1.14 + dx * 0.6, 1.6, 0.0), (1.14 + dx * 1.4, 1.6 - length, -0.02), 0.028)
    return s


def upper_leg():
    s = Sculpt()
    s.cap((0.27, 2.0, 0), (0.27, 4.62, 0), 0.13)
    s.ell((0.27, 3.85, -0.03), (0.22, 0.68, 0.22))  # the thigh
    s.ell((0.25, 4.6, 0.0), (0.25, 0.38, 0.25))  # up into the hip: no stick in a socket
    s.ell((0.27, 2.55, -0.01), (0.15, 0.4, 0.15))  # tapering down over the knee
    return s


def lower_leg():
    s = Sculpt()
    s.cap((0.27, 0.1, 0), (0.27, 2.3, 0), 0.095)
    s.ell((0.27, 1.75, 0.06), (0.15, 0.5, 0.15))  # the calf
    s.ell((0.27, 2.2, -0.03), (0.15, 0.32, 0.15))  # the knee, long and smooth
    return s


def foot():
    s = Sculpt()
    s.ell((0.27, 0.1, -0.22), (0.095, 0.08, 0.36))
    s.ball((0.27, 0.13, 0.08), 0.1)
    s.ball((0.27, 0.22, 0.0), 0.08)
    return s


SEGMENTS = {
    "Head": head,
    "Neck": neck,
    "UpperTorso": upper_torso,
    "LowerTorso": lower_torso,
    "UpperArm": upper_arm,
    "LowerArm": lower_arm,
    "Hand": hand,
    "UpperLeg": upper_leg,
    "LowerLeg": lower_leg,
    "Foot": foot,
}


# ---------------------------------------------------------------------------
# skin material (on the high mesh) and the bake
# ---------------------------------------------------------------------------


def skin_material():
    mat = bpy.data.materials.new("ObserverSkin")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    # mottling: two scales of noise between near-blacks (cool / faintly warm)
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 3.0
    n1.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], n1.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.008, 0.0075, 0.008, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (0.021, 0.017, 0.016, 1)
    nt.links.new(n1.outputs["Fac"], ramp.inputs["Fac"])
    # cavities darker, ridges a touch lighter: ambient occlusion and pointiness
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.25
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ridge = nt.nodes.new("ShaderNodeMapRange")
    ridge.inputs["From Min"].default_value = 0.5
    ridge.inputs["From Max"].default_value = 0.56
    ridge.inputs["To Min"].default_value = 0.0
    ridge.inputs["To Max"].default_value = 1.0
    nt.links.new(geo.outputs["Pointiness"], ridge.inputs["Value"])
    lighten = nt.nodes.new("ShaderNodeMix")
    lighten.data_type = "RGBA"
    lighten.blend_type = "ADD"
    nt.links.new(ridge.outputs["Result"], lighten.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], lighten.inputs[6])
    lighten.inputs[7].default_value = (0.008, 0.0075, 0.0075, 1)
    cav = nt.nodes.new("ShaderNodeMapRange")
    cav.inputs["To Min"].default_value = 0.35
    cav.inputs["To Max"].default_value = 1.0
    nt.links.new(ao.outputs["AO"], cav.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(lighten.outputs[2], mul.inputs[6])
    nt.links.new(cav.outputs["Result"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    # roughness: matte, a little less in the deepest folds
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = 0.68
    rr.inputs["To Max"].default_value = 0.94
    nt.links.new(ao.outputs["AO"], rr.inputs["Value"])
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 14.0
    rmix = nt.nodes.new("ShaderNodeMath")
    rmix.operation = "MULTIPLY_ADD"
    nt.links.new(n2.outputs["Fac"], rmix.inputs[0])
    rmix.inputs[1].default_value = 0.08
    nt.links.new(rr.outputs["Result"], rmix.inputs[2])
    nt.links.new(rmix.outputs["Value"], bsdf.inputs["Roughness"])
    # fine skin: pores and creases as bump (baked into the normal map)
    n3 = nt.nodes.new("ShaderNodeTexVoronoi")
    n3.inputs["Scale"].default_value = 60.0
    n4 = nt.nodes.new("ShaderNodeTexWave")
    n4.wave_type = "BANDS"
    n4.inputs["Scale"].default_value = 9.0
    n4.inputs["Distortion"].default_value = 8.0
    n4.inputs["Detail"].default_value = 4.0
    nt.links.new(coord.outputs["Object"], n4.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(n3.outputs["Distance"], add.inputs[0])
    nt.links.new(n4.outputs["Fac"], add.inputs[1])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.18
    bump.inputs["Distance"].default_value = 0.004
    nt.links.new(add.outputs["Value"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def decimate_to(obj, tris):
    current = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if current > tris:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = tris / current
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=tri.name)
    for poly in obj.data.polygons:
        poly.use_smooth = True


def unwrap(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.006, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_maps(high, low, name, size):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    low.data.materials.clear()
    target = bpy.data.materials.new(name + "_target")
    target.use_nodes = True
    low.data.materials.append(target)
    tex = target.node_tree.nodes.new("ShaderNodeTexImage")
    target.node_tree.nodes.active = tex
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = 0.04
    bake.max_ray_distance = 0.12
    bake.margin = 8
    out = {}
    for kind, btype, non_color in (("normal", "NORMAL", True), ("color", "DIFFUSE", False), ("roughness", "ROUGHNESS", True)):
        img = bpy.data.images.new("%s_%s" % (name, kind), size, size, alpha=False)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        tex.image = img
        kwargs = {"type": btype}
        if btype == "NORMAL":
            bake.normal_space = "TANGENT"
            bake.normal_r, bake.normal_g, bake.normal_b = "POS_X", "POS_Y", "POS_Z"
        if btype == "DIFFUSE":
            bake.use_pass_direct = False
            bake.use_pass_indirect = False
            bake.use_pass_color = True
        bpy.ops.object.bake(**kwargs)
        path = os.path.join(folder, "%s_%s.png" % (name, kind))
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        out[kind] = path
    return out


def write_obj(path, obj, centre, name):
    me = obj.data
    uv = me.uv_layers.active.data
    cx, cy, cz = centre
    with open(path, "w") as fh:
        fh.write("# DON'T LOOK AWAY - The Observer V2 (tools/blender/build_observer.py)\n")
        fh.write("o Observer%s\n" % name)
        for v in me.vertices:
            fh.write("v %.5f %.5f %.5f\n" % (v.co.x - cx, v.co.y - cy, v.co.z - cz))
        me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
        loops = me.loops
        normals = [tuple(l.normal) for l in loops]
        for l in loops:
            fh.write("vt %.5f %.5f\n" % tuple(uv[l.index].uv))
        for n in normals:
            fh.write("vn %.5f %.5f %.5f\n" % n)
        for p in me.polygons:
            idx = ["%d/%d/%d" % (loops[i].vertex_index + 1, i + 1, i + 1) for i in p.loop_indices]
            fh.write("f " + " ".join(idx) + "\n")


def build(name):
    sculpt = SEGMENTS[name]()
    high = sculpt.build(name + "_high", resolution=0.018 if name in ("Head", "Hand") else 0.024)
    roughen(high, seed=len(name), lumps=0.016 if name in ("Hand", "Foot") else 0.024)
    high.data.materials.append(skin_material())
    low = high.copy()
    low.data = high.data.copy()
    low.name = name
    bpy.context.scene.collection.objects.link(low)
    tris, size = BUDGET[name]
    decimate_to(low, tris)
    unwrap(low)
    maps = bake_maps(high, low, name, size)
    centre = PART_CENTRE[name]
    write_obj(os.path.join(OUT, name + ".obj"), low, centre, name)
    xs = [v.co.x - centre[0] for v in low.data.vertices]
    ys = [v.co.y - centre[1] for v in low.data.vertices]
    zs = [v.co.z - centre[2] for v in low.data.vertices]
    lo, hi = (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))
    size3 = [hi[i] - lo[i] for i in range(3)]
    off = [(hi[i] + lo[i]) / 2 for i in range(3)]
    count = len(low.data.polygons)
    print("%-11s %5d triangles  size %.2f x %.2f x %.2f  maps %s" % (name, count, *size3, ", ".join(sorted(maps))))
    return size3, off, count


def read_meta():
    meta = {}
    if os.path.exists(META):
        import re  # noqa: PLC0415

        pat = re.compile(r"\t(\w+) = \{ size = Vector3.new\(([^)]*)\), offset = Vector3.new\(([^)]*)\), triangles = (\d+) \}")
        for line in open(META):
            m = pat.match(line)
            if m:
                meta[m.group(1)] = ([float(x) for x in m.group(2).split(",")], [float(x) for x in m.group(3).split(",")], int(m.group(4)))
    return meta


def main():
    names = [a for a in sys.argv[1:] if a in SEGMENTS] or list(SEGMENTS)
    os.makedirs(OUT, exist_ok=True)
    meta = read_meta()
    for name in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        meta[name] = build(name)
    meta = {k: v for k, v in meta.items() if k in SEGMENTS}
    with open(META, "w") as fh:
        fh.write("--[[\n\tObserverMeshMeta (generated by tools/blender/build_observer.py - do not edit)\n")
        fh.write("\tBounding box of every Observer mesh in its rig part's local space: the\n")
        fh.write("\tgame sizes each MeshPart to `size` and places it at `offset` from the part.\n]]\n\nreturn {\n")
        for name in SEGMENTS:
            if name in meta:
                size, off, tris = meta[name]
                fh.write(
                    "\t%s = { size = Vector3.new(%.4f, %.4f, %.4f), offset = Vector3.new(%.4f, %.4f, %.4f), triangles = %d },\n"
                    % (name, *size, *off, tris)
                )
        fh.write("}\n")
    print("done")


if __name__ == "__main__":
    main()
