"""
DON'T LOOK AWAY - Blender asset library (runs with the `bpy` module).

Builds original hero props as real meshes, bakes their PBR maps and exports
them for Roblox:

    geometry   bevelled boxes, extruded profiles (mouldings, counter noses),
               lathed solids (lamp shades), all in studs (1 BU = 1 stud)
    materials  procedural node materials (varnished wood, stone, brass, enamel,
               cast iron, fabric, paint) with edge wear (Bevel-node normal
               difference) and cavity dirt (AO node), so every asset gets wear
               where it physically happens on *its* geometry
    bake       one UV atlas per asset; Cycles bakes albedo, tangent-space
               normal (OpenGL / Y+, what SurfaceAppearance expects), roughness
               and metalness to 1024 px PNGs
    export     OBJ, Y up, Roblox axes (front of a prop = -Z in Roblox), plus
               the bounds the game needs to size and place the MeshPart
    preview    a Cycles render of the asset for review

Coordinates while modelling: Blender Z up, the prop's FRONT faces +Y, origin
at the centre of its footprint on the floor. On export (x, y, z) -> (x, z, -y),
so +Y (front) becomes Roblox -Z = LookVector.
"""

import math
import os

import bpy  # noqa: I001 - bpy must be imported first: it provides bmesh and mathutils
import bmesh
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# scene
# ---------------------------------------------------------------------------


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.unit_settings.system = "NONE"
    return scene


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me))


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def bevel(obj, width, segments=2, angle=40):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.harden_normals = False
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------


def box(name, size, loc, mat=None, bev=0.02, seg=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(loc)
    obj = mesh_object(name, bm)
    if bev and bev > 0:
        bevel(obj, min(bev, min(size) * 0.45), seg)
    if mat:
        assign(obj, mat)
    return obj


def extrude_profile(name, points, length, axis="X", loc=(0, 0, 0), mat=None, bev=0.0):
    """points: closed 2D profile (u, v) in the plane perpendicular to `axis`;
    for axis X, u = Y and v = Z. Extruded symmetrically by `length`."""
    bm = bmesh.new()
    half = length / 2
    ring_a, ring_b = [], []
    for u, v in points:
        if axis == "X":
            a, b = Vector((-half, u, v)), Vector((half, u, v))
        elif axis == "Y":
            a, b = Vector((u, -half, v)), Vector((u, half, v))
        else:
            a, b = Vector((u, v, -half)), Vector((u, v, half))
        ring_a.append(bm.verts.new(a + Vector(loc)))
        ring_b.append(bm.verts.new(b + Vector(loc)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ring_a[i], ring_a[j], ring_b[j], ring_b[i]))
    bm.faces.new(list(reversed(ring_a)))
    bm.faces.new(ring_b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm)
    if bev:
        bevel(obj, bev, 1)
    if mat:
        assign(obj, mat)
    return obj


def lathe(name, profile, segments=32, loc=(0, 0, 0), mat=None):
    """profile: [(radius, z)] from bottom to top; revolved around Z."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for k in range(segments):
            a = 2 * math.pi * k / segments
            ring.append(bm.verts.new(Vector((r * math.cos(a), r * math.sin(a), z)) + Vector(loc)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segments):
            k2 = (k + 1) % segments
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    # caps where the radius is not ~0
    if profile[0][0] > 1e-3:
        bm.faces.new(list(reversed(rings[0])))
    if profile[-1][0] > 1e-3:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm)
    if mat:
        assign(obj, mat)
    return obj


def cylinder(name, radius, depth, loc, axis="Z", mat=None, segments=24, bev=0.0):
    obj = lathe(name, [(radius, -depth / 2), (radius, depth / 2)], segments, (0, 0, 0), mat)
    if axis == "X":
        obj.rotation_euler = (0, math.radians(90), 0)
    elif axis == "Y":
        obj.rotation_euler = (math.radians(90), 0, 0)
    obj.location = loc
    if bev:
        bevel(obj, bev, 2)
    return obj


def fielded_panel(name, w, h, depth, raise_w, loc, mat):
    """A raised-and-fielded panel: a flat field in the middle and bevelled
    raise round it, as one solid (front faces +Y)."""
    bm = bmesh.new()
    x0, x1 = -w / 2, w / 2
    z0, z1 = -h / 2, h / 2
    fx0, fx1 = x0 + raise_w, x1 - raise_w
    fz0, fz1 = z0 + raise_w, z1 - raise_w
    back = [bm.verts.new((x, 0, z)) for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
    edge = [bm.verts.new((x, depth * 0.35, z)) for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
    field = [bm.verts.new((x, depth, z)) for x, z in ((fx0, fz0), (fx1, fz0), (fx1, fz1), (fx0, fz1))]
    bm.faces.new(list(reversed(back)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((back[i], back[j], edge[j], edge[i]))
        bm.faces.new((edge[i], edge[j], field[j], field[i]))
    bm.faces.new(field)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm)
    obj.location = loc
    assign(obj, mat)
    return obj


def ogee(depth, height, steps=6):
    """Ogee moulding profile (u = out from the wall, v = up), closed."""
    pts = [(0.0, 0.0)]
    for i in range(steps + 1):
        t = i / steps
        # S-curve: concave then convex
        u = depth * (0.5 - 0.5 * math.cos(math.pi * t))
        v = height * t
        pts.append((u * (1 if t > 0 else 0), v))
    pts.append((0.0, height))
    return pts


# ---------------------------------------------------------------------------
# materials (procedural, baked later)
# ---------------------------------------------------------------------------


def _nodes(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nt, bsdf


def _ramp(nt, fac, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    cr = r.color_ramp
    cr.elements[0].position, cr.elements[0].color = stops[0][0], (*stops[0][1], 1)
    cr.elements[1].position, cr.elements[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, col in stops[1:-1]:
        e = cr.elements.new(pos)
        e.color = (*col, 1)
    nt.links.new(fac, r.inputs["Fac"])
    return r


def _math(nt, op, a, b=None, clamp=True):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = op
    m.use_clamp = clamp
    if isinstance(a, (int, float)):
        m.inputs[0].default_value = a
    else:
        nt.links.new(a, m.inputs[0])
    if b is not None:
        if isinstance(b, (int, float)):
            m.inputs[1].default_value = b
        else:
            nt.links.new(b, m.inputs[1])
    return m.outputs[0]


def _mix_rgb(nt, fac, a, b, blend="MIX"):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = blend
    if isinstance(fac, (int, float)):
        m.inputs["Factor"].default_value = fac
    else:
        nt.links.new(fac, m.inputs["Factor"])
    for sock, val in ((m.inputs[6], a), (m.inputs[7], b)):
        if isinstance(val, tuple):
            sock.default_value = (*val, 1)
        else:
            nt.links.new(val, sock)
    return m.outputs[2]


def _wear_masks(nt, edge_width=0.012, cavity_dist=0.25):
    """edge: 1 on exposed edges (bevel-node normal differs from the true
    normal); cavity: 1 in creases and corners (ambient occlusion)."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = edge_width
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    edge = _math(nt, "SUBTRACT", 1.0, dot.outputs["Value"])
    edge = _math(nt, "MULTIPLY", edge, 14.0)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 18
    noise.inputs["Detail"].default_value = 6
    edge = _math(nt, "MULTIPLY", edge, noise.outputs["Fac"])
    edge = _math(nt, "MULTIPLY", edge, 2.0)
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.inputs["Distance"].default_value = cavity_dist
    cavity = _math(nt, "SUBTRACT", 1.0, ao.outputs["AO"])
    cavity = _math(nt, "POWER", cavity, 0.8)
    return edge, cavity


def wood(name, base=(0.16, 0.085, 0.045), light=(0.32, 0.18, 0.09), scale=2.2, gloss=0.32, axis="Z"):
    """Varnished hardwood: flowing figure from a distorted wave texture, pores,
    darker varnish build-up in cavities, varnish worn pale on edges."""
    mat, nt, bsdf = _nodes(name)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    # grain runs along `axis` (the length of the board this material is on):
    # that axis is stretched (small scale) and the two across it compressed,
    # so every face of the board shows long lines along it (verified with a
    # render test: the opposite gives cross grain or a zebra figure)
    along, across = scale * 0.35, scale * 3.0
    mapping.inputs["Scale"].default_value = {"X": (along, across, across), "Y": (across, along, across), "Z": (across, across, along)}[axis]
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 1.4
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    wave.inputs["Detail Scale"].default_value = 1.6
    nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    pores = nt.nodes.new("ShaderNodeTexNoise")
    pores.inputs["Scale"].default_value = 180
    pores.inputs["Detail"].default_value = 2
    nt.links.new(mapping.outputs["Vector"], pores.inputs["Vector"])
    streak = nt.nodes.new("ShaderNodeTexNoise")
    streak.inputs["Scale"].default_value = 3.0
    streak.inputs["Detail"].default_value = 10
    streak.inputs["Roughness"].default_value = 0.7
    nt.links.new(mapping.outputs["Vector"], streak.inputs["Vector"])
    figure = _math(nt, "ADD", _math(nt, "MULTIPLY", wave.outputs["Fac"], 0.75), _math(nt, "MULTIPLY", streak.outputs["Fac"], 0.35), clamp=True)
    grain = _ramp(nt, figure, [(0.0, base), (0.35, (base[0] * 1.6, base[1] * 1.6, base[2] * 1.6)), (0.6, light), (0.8, (base[0] * 1.3, base[1] * 1.3, base[2] * 1.3)), (1.0, base)])
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", pores.outputs["Fac"], 0.25), grain.outputs["Color"], (0.05, 0.03, 0.02), "MULTIPLY")
    edge, cavity = _wear_masks(nt)
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", cavity, 0.7), col, (0.03, 0.02, 0.015))
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", edge, 0.6), col, (light[0] * 1.5, light[1] * 1.4, light[2] * 1.3))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = _math(nt, "ADD", gloss, _math(nt, "MULTIPLY", edge, 0.35))
    rough = _math(nt, "ADD", rough, _math(nt, "MULTIPLY", cavity, 0.25))
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(_math(nt, "ADD", wave.outputs["Fac"], _math(nt, "MULTIPLY", pores.outputs["Fac"], 0.5)), bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def stone(name, base=(0.62, 0.6, 0.55), vein=(0.42, 0.4, 0.37)):
    """Honed stone / marble counter: soft clouds, thin veins, dull where used."""
    mat, nt, bsdf = _nodes(name)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.2
    noise.inputs["Detail"].default_value = 8
    noise.inputs["Distortion"].default_value = 2.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 0.6
    wave.inputs["Distortion"].default_value = 14
    wave.inputs["Detail"].default_value = 6
    nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
    veins = _ramp(nt, wave.outputs["Fac"], [(0.0, (1, 1, 1)), (0.48, (1, 1, 1)), (0.5, (0, 0, 0)), (0.52, (1, 1, 1)), (1.0, (1, 1, 1))])
    cloud = _ramp(nt, noise.outputs["Fac"], [(0.2, (base[0] * 0.9, base[1] * 0.9, base[2] * 0.9)), (0.8, base)])
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", _math(nt, "SUBTRACT", 1.0, veins.outputs["Color"]), 0.6), cloud.outputs["Color"], vein)
    edge, cavity = _wear_masks(nt, 0.01, 0.2)
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", cavity, 0.5), col, (0.2, 0.19, 0.17))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(_math(nt, "ADD", 0.22, _math(nt, "MULTIPLY", noise.outputs["Fac"], 0.2)), bsdf.inputs["Roughness"])
    return mat


def metal(name, base=(0.55, 0.42, 0.2), rough=0.35, tarnish=(0.18, 0.15, 0.1), metallic=0.55):
    """Brass / steel: polished where touched (edges), tarnished in cavities.
    Metalness stays partial on purpose: a fully metallic surface shows only
    reflections, and Roblox's night-time environment would turn it black."""
    mat, nt, bsdf = _nodes(name)
    bsdf.inputs["Metallic"].default_value = metallic
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9
    noise.inputs["Detail"].default_value = 6
    edge, cavity = _wear_masks(nt, 0.008, 0.15)
    col = _mix_rgb(nt, _math(nt, "ADD", _math(nt, "MULTIPLY", cavity, 0.9), _math(nt, "MULTIPLY", noise.outputs["Fac"], 0.25)), base, tarnish)
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", edge, 0.6), col, (min(1, base[0] * 1.3), min(1, base[1] * 1.3), min(1, base[2] * 1.3)))
    nt.links.new(col, bsdf.inputs["Base Color"])
    r = _math(nt, "ADD", rough, _math(nt, "MULTIPLY", cavity, 0.4))
    r = _math(nt, "SUBTRACT", r, _math(nt, "MULTIPLY", edge, 0.2))
    nt.links.new(r, bsdf.inputs["Roughness"])
    return mat


def paint(name, base, rough=0.55, under=(0.35, 0.33, 0.3), chip=0.5, metallic_under=0.0):
    """Painted surface (enamel, painted iron, painted wood): chipped on edges
    showing what is under it, dirt in cavities."""
    mat, nt, bsdf = _nodes(name)
    edge, cavity = _wear_masks(nt, 0.01, 0.2)
    chipm = _math(nt, "GREATER_THAN", _math(nt, "MULTIPLY", edge, chip * 2), 0.5)
    col = _mix_rgb(nt, chipm, base, under)
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", cavity, 0.6), col, (base[0] * 0.25, base[1] * 0.25, base[2] * 0.25))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(_math(nt, "ADD", rough, _math(nt, "MULTIPLY", cavity, 0.3)), bsdf.inputs["Roughness"])
    if metallic_under > 0:
        nt.links.new(_math(nt, "MULTIPLY", chipm, metallic_under), bsdf.inputs["Metallic"])
    return mat


def fabric(name, base, rough=0.92):
    mat, nt, bsdf = _nodes(name)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    weave = nt.nodes.new("ShaderNodeTexWave")
    weave.wave_type = "BANDS"
    weave.inputs["Scale"].default_value = 120
    nt.links.new(coord.outputs["Object"], weave.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6
    edge, cavity = _wear_masks(nt, 0.02, 0.3)
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", weave.outputs["Fac"], 0.12), base, (base[0] * 0.7, base[1] * 0.7, base[2] * 0.7))
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", noise.outputs["Fac"], 0.15), col, (base[0] * 1.2, base[1] * 1.15, base[2] * 1.1))
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", edge, 0.35), col, (base[0] * 1.35, base[1] * 1.3, base[2] * 1.25))
    col = _mix_rgb(nt, _math(nt, "MULTIPLY", cavity, 0.6), col, (base[0] * 0.35, base[1] * 0.35, base[2] * 0.35))
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    nt.links.new(weave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ---------------------------------------------------------------------------
# bake + export
# ---------------------------------------------------------------------------


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        apply_modifiers(o)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    # smooth shading with sharp edges above 35 degrees: turned and bevelled
    # parts read round, box edges stay crisp (the exported normals carry it)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.set_sharp_from_angle(angle=math.radians(35))
    return obj


def unwrap(obj, margin=0.004):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def _image(name, size, non_color):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def bake(obj, out_dir, asset, size=1024, samples=16):
    """Bakes albedo, normal (OpenGL), roughness and metalness of every material
    on `obj` into one texture set via its UVs."""
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.render.bake.margin = 8
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    maps = {}
    os.makedirs(out_dir, exist_ok=True)

    def target(img):
        for mat in obj.data.materials:
            nt = mat.node_tree
            node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
            node.name = "BakeTarget"
            node.image = img
            nt.nodes.active = node

    def save(img, key):
        path = os.path.join(out_dir, "%s_%s.png" % (asset, key))
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        maps[key] = path

    # albedo: diffuse colour only
    img = _image(asset + "_color", size, False)
    target(img)
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
    save(img, "color")
    # normal, tangent space, OpenGL (+Y)
    img = _image(asset + "_normal", size, True)
    target(img)
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.normal_g = "POS_Y"
    bpy.ops.object.bake(type="NORMAL", use_clear=True)
    save(img, "normal")
    # roughness
    img = _image(asset + "_roughness", size, True)
    target(img)
    bpy.ops.object.bake(type="ROUGHNESS", use_clear=True)
    save(img, "roughness")
    # metalness: route Metallic into an emission and bake EMIT
    img = _image(asset + "_metalness", size, True)
    target(img)
    restore = []
    for mat in obj.data.materials:
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        em = nt.nodes.new("ShaderNodeEmission")
        src = bsdf.inputs["Metallic"]
        if src.is_linked:
            nt.links.new(src.links[0].from_socket, em.inputs["Color"])
        else:
            v = src.default_value
            em.inputs["Color"].default_value = (v, v, v, 1)
        old = out.inputs["Surface"].links[0].from_socket
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        restore.append((nt, old, out, em))
    bpy.ops.object.bake(type="EMIT", use_clear=True)
    save(img, "metalness")
    for nt, old, out, em in restore:
        nt.links.new(old, out.inputs["Surface"])
        nt.nodes.remove(em)
    return maps


def export_obj(obj, path):
    """Rotates into Roblox axes (Y up, front = -Z), exports, rotates back.
    Returns (size, centre) of the exported bounds in studs."""
    rot = Matrix.Rotation(math.radians(-90), 4, "X")  # (x, y, z) -> (x, z, -y)
    obj.data.transform(rot)
    obj.data.update()
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    centre = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(
        filepath=path,
        export_selected_objects=True,
        forward_axis="Y",
        up_axis="Z",
        export_materials=False,
        export_triangulated_mesh=True,
        export_normals=True,
        export_uv=True,
        apply_modifiers=True,
    )
    obj.data.transform(rot.inverted())
    obj.data.update()
    return size, centre


def preview(obj, path, maps=None, res=(900, 600), samples=48, cam_dist=None, cam_height=None):
    """Cycles render of the asset (with its baked maps if given) on a dark
    floor, warm key + cool rim: for reviewing shape and materials."""
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    if maps:
        mat = bpy.data.materials.new("Baked")
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        for key, sock, nc in (("color", "Base Color", False), ("roughness", "Roughness", True), ("metalness", "Metallic", True)):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(maps[key], check_existing=False)
            if nc:
                t.image.colorspace_settings.name = "Non-Color"
            nt.links.new(t.outputs["Color"], bsdf.inputs[sock])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(maps["normal"], check_existing=False)
        t.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    xs = [(obj.matrix_world @ v.co) for v in obj.data.vertices]
    lo = Vector((min(p.x for p in xs), min(p.y for p in xs), min(p.z for p in xs)))
    hi = Vector((max(p.x for p in xs), max(p.y for p in xs), max(p.z for p in xs)))
    c = (lo + hi) / 2
    ext = (hi - lo).length
    floor = box("PreviewFloor", (ext * 6, ext * 6, 0.1), (c.x, c.y, lo.z - 0.05), paint("PreviewFloorMat", (0.12, 0.115, 0.11), 0.7), bev=0)
    wall = box("PreviewWall", (ext * 6, 0.2, ext * 3), (c.x, lo.y - ext * 0.6, c.z), paint("PreviewWallMat", (0.32, 0.3, 0.27), 0.85), bev=0)
    _ = (floor, wall)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.01, 0.01, 0.012, 1)
    scene.world = world
    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 60 * ext * ext
    key.size = ext
    key.color = (1.0, 0.86, 0.7)
    ko = link(bpy.data.objects.new("Key", key))
    ko.location = c + Vector((ext * 0.9, ext * 1.1, ext * 0.9))
    ko.rotation_euler = (c - ko.location).to_track_quat("-Z", "Y").to_euler()
    rim = bpy.data.lights.new("Rim", "AREA")
    rim.energy = 25 * ext * ext
    rim.size = ext * 0.6
    rim.color = (0.7, 0.8, 1.0)
    ro = link(bpy.data.objects.new("Rim", rim))
    ro.location = c + Vector((-ext * 1.1, -ext * 0.3, ext * 0.8))
    ro.rotation_euler = (c - ro.location).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 45
    co = link(bpy.data.objects.new("Cam", cam))
    d = cam_dist or ext * 1.25
    co.location = c + Vector((d * 0.55, d * 0.95, cam_height if cam_height is not None else ext * 0.35))
    co.rotation_euler = (c - co.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = co
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
