"""
THE OBSERVER V2 - an organic creature, sculpted procedurally in Blender.

Not boxes, not lofted tubes: every segment of the body is a SCULPT built from
blended metaball volumes (they fuse into one continuous surface, and negative
volumes carve sockets, clefts and hollows), roughened with layered noise, then
baked onto a lighter game mesh:

  high   metaballs -> mesh (~0.02 stud resolution) -> organic noise displacement
  low    the high mesh decimated to a game budget, UV-unwrapped
  bake   high -> low: tangent normal map (OpenGL), colour and roughness;
         4096 px (Roblox's largest texture) for the head, neck, torso and
         hands, 512 px for the rest

Layers (each has a job):
  base anatomy      the silhouette: a tall, hunched, narrow body, a heavy
                    head; real volume in the chest, back, thighs and forearms
  secondary volumes tissue that breaks the skeleton look: a hunched dorsal
                    mass, sloping trapezius slopes, shoulder masses, folds of
                    dark tissue hanging down the flanks, thin membranes from
                    the neck to the shoulders and under the head, knots at
                    the elbows and knees
  surface           dead skin, never plastic: lumps and wrinkles in the
                    geometry; in the maps an ash-grey-to-black skin with real
                    value range, dark veins under it, pores and wrinkles at
                    skin scale, dry cracks over the shoulders and back, and
                    thin skin (fingers, neck, round the eyes) faking
                    scattering with a cold reddish tint; roughness in zones:
                    dry and matte almost everywhere, wet in the cleft, the
                    eye sockets, the neck and the palms (SKINS: two looks)
  focal detail      the head: long and narrow, no wings, a heavy brow
                    ridge, a cleft down the middle of a long faceless face,
                    two deep sockets (left higher) for the two small eyes,
                    which are rig parts that turn to the player

Each mesh is in its rig part's local space (Roblox axes: Y up, front -Z), so
ObserverRig.dress welds it over the Motor6D rig. Neighbouring segments
overlap at the joints so the body stays continuous when it bends. Paired
limbs share one mesh (kept nearly symmetric in X).

    ~/.venv-blender/bin/python tools/blender/build_observer.py [Segment ...]
        [--skin=B|A] [--maps=DIR] [--size=N] [--remesh=Head,...]

Writes assets/observer/<Segment>/<Segment>_{color,normal,roughness}.png (or
DIR/<Segment>/... with --maps, for proposals) and src/shared/Config/
ObserverMeshMeta.luau. The game mesh (assets/observer/<Segment>.obj) is
rebuilt only for the segments in --remesh (default: Head) or with no .obj
yet; the others are baked onto their existing .obj, so their uploaded
meshes stay valid. --size overrides every texture size (quick previews).
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

# triangles of the game mesh, texture size. 4096 is the largest texture
# Roblox takes: the head (seen under two studs in the jumpscare), neck,
# torso and hands get it; the head is the smallest of them, so it carries
# the densest texture of the body.
BUDGET = {
    "Head": (6000, 4096),
    "UpperTorso": (6000, 4096),
    "Neck": (2400, 4096),
    "LowerTorso": (2400, 512),
    "UpperArm": (2400, 512),
    "LowerArm": (2000, 512),
    "Hand": (1600, 4096),
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
    # long and narrow: a tall faceless face leaning forward a little, one
    # long skull mass behind it rising into a high crown. No wings.
    s.ell((0, 9.02, -0.04), (0.33, 0.66, 0.27), rot=(-6, 0, 3))
    s.ell((0, 9.3, 0.1), (0.36, 0.62, 0.31), rot=(6, 0, -2))
    # a heavy bulge over each socket (the right one higher), not one straight
    # ridge: from below a straight ridge reads as the peak of a cap
    s.ell((-0.17, 9.25, -0.2), (0.13, 0.08, 0.1), rot=(0, 0, 14))
    s.ell((0.19, 9.21, -0.2), (0.14, 0.085, 0.1), rot=(0, 0, -18))
    # the point under the long face, down into the neck
    s.chain([(0, 8.48, -0.08), (0.01, 8.33, -0.04)], [0.15, 0.09], flat=0.9)
    # a few irregular lumps on the skull
    s.ball((0.22, 9.52, 0.22), 0.09)
    s.ball((-0.25, 9.38, 0.28), 0.08)
    # carve: the two eye sockets (deep, the left higher) and the cleft
    for ex, ey, ez in (EYE_L, EYE_R):
        # a deep socket that opens to the front, a little hooded from above
        s.ell((hx + ex, hy + ey - 0.01, hz + ez - 0.1), (0.13, 0.11, 0.14), neg=True)
    s.ell((0.0, 8.8, -0.3), (0.025, 0.28, 0.07), neg=True)
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


# Two looks for the skin (linear RGB). Both dead, both dark but legible; they
# share the zones (veins, pores, wrinkles, cracks, thin skin, wet patches).
#   A  ash: grey ash going to black, the most value range, dry
#   B  charcoal: nearly black, more contrast in the veins, wetter (the
#      one in the game)
SKINS = {
    "A": {
        "dark": (0.040, 0.040, 0.043), "light": (0.105, 0.102, 0.100),
        "ridge": (0.030, 0.030, 0.030), "vein": (0.022, 0.020, 0.032), "veins": 0.7,
        "thin": (0.085, 0.060, 0.066), "thinAmount": 0.5,
        "crackGap": (0.012, 0.012, 0.012), "crackRim": (0.160, 0.155, 0.150),
        "dry": (0.84, 0.95), "wet": 0.32,
    },
    "B": {
        "dark": (0.016, 0.015, 0.017), "light": (0.050, 0.046, 0.046),
        "ridge": (0.018, 0.018, 0.018), "vein": (0.006, 0.004, 0.010), "veins": 0.85,
        "thin": (0.036, 0.028, 0.038), "thinAmount": 0.55,
        "crackGap": (0.004, 0.004, 0.004), "crackRim": (0.085, 0.080, 0.078),
        "dry": (0.74, 0.90), "wet": 0.22,
    },
}


class Graph:
    """Small helpers over a shader node tree: a value is a number, a tuple or
    an output socket; every helper returns an output socket."""

    def __init__(self, nt):
        self.nt = nt

    def put(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        elif isinstance(v, tuple) and len(v) == 3 and sock.type == "RGBA":
            sock.default_value = (*v, 1.0)
        else:
            sock.default_value = v

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def math(self, op, a, b=0.0, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.put(n.inputs[0], a)
        self.put(n.inputs[1], b)
        return n.outputs[0]

    def vec(self, op, a, b=(0.0, 0.0, 0.0)):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.put(n.inputs[0], a)
        self.put(n.inputs["Scale"] if op == "SCALE" else n.inputs[1], b)
        return n.outputs["Value"] if op in ("DISTANCE", "LENGTH", "DOT_PRODUCT") else n.outputs["Vector"]

    def remap(self, v, a, b, lo=0.0, hi=1.0):
        """a..b -> lo..hi, clamped (a > b runs backwards)."""
        n = self.node("ShaderNodeMapRange", clamp=True)
        if a > b:
            a, b, lo, hi = b, a, hi, lo
        self.put(n.inputs["Value"], v)
        n.inputs["From Min"].default_value = a
        n.inputs["From Max"].default_value = b
        n.inputs["To Min"].default_value = lo
        n.inputs["To Max"].default_value = hi
        return n.outputs["Result"]

    def mix(self, fac, a, b):
        n = self.node("ShaderNodeMix", data_type="RGBA")
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def noise(self, p, scale, detail=4.0):
        n = self.node("ShaderNodeTexNoise")
        self.put(n.inputs["Vector"], p)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        return n

    def voronoi(self, p, scale, feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        self.put(n.inputs["Vector"], p)
        n.inputs["Scale"].default_value = scale
        return n.outputs["Distance"]

    def xyz(self, p):
        n = self.node("ShaderNodeSeparateXYZ")
        self.put(n.inputs[0], p)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def mul(self, *vals):
        out = vals[0]
        for v in vals[1:]:
            out = self.math("MULTIPLY", out, v)
        return out


def skin_material(name, skin="B", size=1024):
    """The skin on the high mesh, in world studs (the sculpt sits at its rig
    position), for segment `name`. The bake turns it into the three maps."""
    P = SKINS[skin]
    mat = bpy.data.materials.new("ObserverSkin" + skin)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    g = Graph(nt)
    geo = g.node("ShaderNodeNewGeometry")
    pos, normal = geo.outputs["Position"], geo.outputs["Normal"]
    x, y, z = g.xyz(pos)
    nx, _, _ = g.xyz(normal)
    seed = (len(name) * 1.37, len(name) * 0.71, 0.0)
    p = g.vec("ADD", pos, seed)
    # a warped copy of the coordinates: veins and cracks wander
    warp = g.vec("ADD", p, g.vec("SCALE", g.noise(p, 2.5, 3.0).outputs["Color"], 0.18))
    ao = g.node("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.2
    cavity = g.math("SUBTRACT", 1.0, ao.outputs["AO"])

    # --- the masks of this segment
    zero = 0.0
    thin, wet, cracks = zero, zero, None
    if name == "Head":
        hx, hy, hz = PART_CENTRE["Head"]
        near_eye = zero
        for ex, ey, ez in (EYE_L, EYE_R):
            d = g.vec("DISTANCE", pos, (hx + ex, hy + ey, hz + ez))
            near_eye = g.math("MAXIMUM", near_eye, g.remap(d, 0.22, 0.1))
        thin = near_eye
        socket = zero
        for ex, ey, ez in (EYE_L, EYE_R):
            d = g.vec("DISTANCE", pos, (hx + ex, hy + ey, hz + ez - 0.04))
            socket = g.math("MAXIMUM", socket, g.remap(d, 0.19, 0.11))
        cleft = g.mul(g.remap(g.math("ABSOLUTE", x), 0.09, 0.03), g.remap(y, 8.45, 8.6), g.remap(y, 9.12, 9.02), g.remap(z, -0.14, -0.22))
        wet = g.math("MAXIMUM", g.math("MAXIMUM", socket, cleft), g.math("MULTIPLY", cavity, 0.6))
    elif name == "Neck":
        thin = 0.85
        wet = g.math("ADD", 0.35, g.math("MULTIPLY", g.remap(z, 0.02, -0.12), 0.55))
    elif name == "Hand":
        # the fingers below the palm; the palm faces the body (-X: the hand
        # mesh is the right one, at +X)
        thin = g.remap(y, 1.5, 1.25)
        wet = g.math("MAXIMUM", g.remap(nx, -0.15, -0.6), g.math("MULTIPLY", thin, 0.5))
    elif name == "UpperTorso":
        # dry cracks over the shoulders and down the back
        where = g.math("MAXIMUM", g.remap(y, 6.85, 7.3), g.remap(z, 0.1, 0.3))
        crack_zone = g.mul(where, g.remap(g.noise(p, 3.0, 2.0).outputs["Fac"], 0.42, 0.58))
        crack_edge = g.voronoi(warp, 9.0, "DISTANCE_TO_EDGE")
        cracks = g.mul(g.remap(crack_edge, 0.0, 0.022, 1.0, 0.0), crack_zone)
        wet = g.math("MULTIPLY", cavity, 0.3)
    else:
        wet = g.math("MULTIPLY", cavity, 0.3)

    # --- colour: mottled ash, veins under it, ridges catch light, cavities sink
    m1 = g.noise(p, 2.2, 4.0).outputs["Fac"]
    m2 = g.noise(p, 26.0, 3.0).outputs["Fac"]
    tone = g.remap(g.math("ADD", g.math("MULTIPLY", m1, 0.65), g.math("MULTIPLY", m2, 0.35)), 0.32, 0.68)
    col = g.mix(tone, P["dark"], P["light"])
    # veins: thin isolines of a warped noise wander and fork like vessels
    # under the skin (never closed cells, which read as scales)
    def isoline(scale, width, detail):
        n = g.noise(warp, scale, detail).outputs["Fac"]
        return g.remap(g.math("ABSOLUTE", g.math("SUBTRACT", n, 0.5)), 0.0, width, 1.0, 0.0)

    veins = g.math("MAXIMUM", isoline(3.2, 0.03, 2.0), g.math("MULTIPLY", isoline(7.5, 0.018, 3.0), 0.55))
    veins = g.math("MULTIPLY", veins, g.remap(g.noise(p, 1.4, 2.0).outputs["Fac"], 0.4, 0.6))
    col = g.mix(g.math("MULTIPLY", veins, P["veins"]), col, P["vein"])
    ridge = g.remap(geo.outputs["Pointiness"], 0.5, 0.56)
    lighten = g.node("ShaderNodeMix", data_type="RGBA", blend_type="ADD")
    g.put(lighten.inputs[0], ridge)
    g.put(lighten.inputs[6], col)
    g.put(lighten.inputs[7], P["ridge"])
    col = lighten.outputs[2]
    col = g.mix(g.math("MULTIPLY", thin, P["thinAmount"]), col, P["thin"])
    if cracks is not None:
        rim = g.mul(g.remap(crack_edge, 0.012, 0.05, 1.0, 0.0), crack_zone)
        col = g.mix(g.math("MULTIPLY", g.math("SUBTRACT", rim, cracks, True), 0.5), col, P["crackRim"])
        col = g.mix(cracks, col, P["crackGap"])
    sink = g.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    sink.inputs[0].default_value = 1.0
    g.put(sink.inputs[6], col)
    g.put(sink.inputs[7], g.remap(ao.outputs["AO"], 0.0, 1.0, 0.45, 1.0))
    g.put(bsdf.inputs["Base Color"], sink.outputs[2])

    # --- roughness: dry and matte, wet in patches, bone-dry in the cracks
    dry = g.remap(g.noise(p, 14.0, 2.0).outputs["Fac"], 0.3, 0.7, P["dry"][0], P["dry"][1])
    rough = g.math("ADD", g.math("MULTIPLY", dry, g.math("SUBTRACT", 1.0, wet, True)), g.math("MULTIPLY", wet, P["wet"]))
    if cracks is not None:
        rough = g.math("MAXIMUM", rough, g.math("MULTIPLY", cracks, 0.97))
    g.put(bsdf.inputs["Roughness"], rough)

    # --- relief for the normal map: pores, wrinkles, veins raised under the
    # skin, crack grooves. Pores only where the texture can hold them.
    pores = g.remap(g.voronoi(p, 170.0), 0.0, 0.3)
    wr_p = g.vec("MULTIPLY", p, (3.0, 0.7, 3.0))
    wrinkles = g.noise(wr_p, 22.0, 3.0).outputs["Fac"]
    height = g.math("ADD", g.math("MULTIPLY", pores, 0.3 if size >= 2048 else 0.08), g.math("MULTIPLY", wrinkles, 0.55))
    height = g.math("ADD", height, g.math("MULTIPLY", veins, 0.35))
    if cracks is not None:
        height = g.math("SUBTRACT", height, g.math("MULTIPLY", cracks, 0.9))
    bump = g.node("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.003
    g.put(bump.inputs["Height"], height)
    g.put(bsdf.inputs["Normal"], bump.outputs["Normal"])
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
    # few, large islands with room between them: no ragged island edges,
    # and the bake margin never runs into a neighbour
    bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=0.01, area_weight=1.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.01, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_maps(high, low, name, size, maps_dir, skin):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    folder = os.path.join(maps_dir, name)
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
    # a wide margin, extended from the island edges, at any texture size
    bake.margin = max(8, size // 64)
    bake.margin_type = "EXTEND"
    P = SKINS[skin]
    # the space between islands holds a neutral value, never black (black
    # roughness is a mirror and would bleed into the mips)
    fill = {
        "normal": (0.5, 0.5, 1.0, 1.0),
        "color": tuple(((P["dark"][i] + P["light"][i]) / 2) ** (1 / 2.2) for i in range(3)) + (1.0,),
        "roughness": (P["dry"][1], P["dry"][1], P["dry"][1], 1.0),
    }
    out = {}
    for kind, btype, non_color in (("normal", "NORMAL", True), ("color", "DIFFUSE", False), ("roughness", "ROUGHNESS", True)):
        img = bpy.data.images.new("%s_%s" % (name, kind), size, size, alpha=False)
        img.generated_color = fill[kind]
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


def import_low(path, centre, name):
    """The existing game mesh (its .obj, in rig-part space) back at its rig
    position, UVs and all, to bake new maps onto it unchanged."""
    bpy.ops.object.select_all(action="DESELECT")
    # forward Y / up Z: no axis conversion, the file is in the sculpt's axes
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
    low = bpy.context.selected_objects[0]
    low.name = name
    low.location = Vector(centre)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for poly in low.data.polygons:
        poly.use_smooth = True
    return low


def build(name, skin="B", maps_dir=OUT, size=None, remesh=False):
    sculpt = SEGMENTS[name]()
    high = sculpt.build(name + "_high", resolution=0.014 if name == "Head" else 0.018 if name == "Hand" else 0.024)
    roughen(high, seed=len(name), lumps=0.016 if name in ("Hand", "Foot") else 0.024)
    tris, budget_size = BUDGET[name]
    size = size or budget_size
    high.data.materials.append(skin_material(name, skin, size))
    centre = PART_CENTRE[name]
    obj_path = os.path.join(OUT, name + ".obj")
    if remesh or not os.path.exists(obj_path):
        low = high.copy()
        low.data = high.data.copy()
        low.data.materials.clear()
        low.name = name
        bpy.context.scene.collection.objects.link(low)
        decimate_to(low, tris)
        unwrap(low)
        write_obj(obj_path, low, centre, name)
    else:
        low = import_low(obj_path, centre, name)
    maps = bake_maps(high, low, name, size, maps_dir, skin)
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
    args = sys.argv[1:]
    opts = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
    names = [a for a in args if a in SEGMENTS] or list(SEGMENTS)
    skin = opts.get("skin", "B")
    maps_dir = os.path.abspath(opts.get("maps", OUT))
    size = int(opts["size"]) if "size" in opts else None
    remesh = set(filter(None, opts.get("remesh", "Head").split(",")))
    os.makedirs(OUT, exist_ok=True)
    meta = read_meta()
    for name in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        meta[name] = build(name, skin, maps_dir, size, name in remesh)
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
