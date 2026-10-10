"""
Renders a room of the real, procedurally built map in Blender Cycles, with the
game's own texture files and the Blender prop meshes, to review the art in
context. NOT Roblox's renderer: an approximation built to resemble it.

    lune run tools/light_study.luau build/test.rbxlx G_r 8919 build/light_G_r.json
    /home/user/.venv-blender/bin/python tools/blender/render_room.py build/light_G_r.json out.png [parts|meshes] [NORMAL|EMERGENCY|BLACKOUT]

How it approximates Roblox (Future lighting):
  * every part is a box / cylinder / ball in Roblox coordinates (Y up)
  * its MaterialVariant / material picks the texture set in assets/textures,
    box-projected at the variant's StudsPerTile, multiplied by Part.Color
  * lights: same falloff window as the game (energy chosen so a light gives
    its Roblox brightness at half its Range), shadows only where Shadows=true
    (a Roblox light without shadows goes through walls, and so does this one)
  * no diffuse bounce (Roblox has none): the world colour is the preset's
    Ambient, the exposure is the preset's ExposureCompensation
  * "meshes": parts flagged MeshHide are dropped and the OBJ meshes with their
    baked maps are placed at their MeshOrigin
  * decals and SurfaceGuis are not rendered
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402,I001
from mathutils import Matrix, Vector  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import sync_assets  # noqa: E402

REPLACES = {
    "Plaster": "plaster_aged", "Carpet": "carpet_worn", "CeramicTiles": "tiles_worn", "Concrete": "concrete_grimy",
    "WoodPlanks": "wood_planks_worn", "Brick": "brick_grimy", "Marble": "marble_stained", "Metal": "metal_worn",
    "Wood": "wood_aged", "Fabric": "fabric_worn", "CorrodedMetal": "metal_rusted",
}
VARIANT_KEY = {v[0]: k for k, v in sync_assets.DEFS.items()}
STUDS = {k: v[2] for k, v in sync_assets.DEFS.items()}
EMERGENCY_COLOR = (255, 176, 120)
ALARM_COLOR = (255, 64, 52)


def lin(c):
    out = []
    for x in c:
        x /= 255.0
        out.append(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4)
    return out


_mats = {}


def texture_material(key, color, rough_default=0.7):
    name = "%s|%d,%d,%d" % (key, *color)
    if name in _mats:
        return _mats[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tint = (*lin(color), 1)
    folder = os.path.join(ROOT, "assets", "textures", key) if key else None
    if folder and os.path.exists(os.path.join(folder, key + "_color.png")):
        # world-space tiling, StudsPerTile studs per repeat (as Roblox tiles
        # a MaterialVariant across parts)
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mapping = nt.nodes.new("ShaderNodeMapping")
        s = 1.0 / STUDS.get(key, 8)
        mapping.inputs["Scale"].default_value = (s, s, s)
        nt.links.new(geo.outputs["Position"], mapping.inputs["Vector"])

        def tex(kind, non_color):
            path = os.path.join(folder, "%s_%s.png" % (key, kind))
            if not os.path.exists(path):
                return None
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(path, check_existing=True)
            if non_color:
                t.image.colorspace_settings.name = "Non-Color"
            t.projection = "BOX"
            t.projection_blend = 0.15
            nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
            return t

        c = tex("color", False)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(c.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = tint
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        r = tex("roughness", True)
        if r:
            nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
        m = tex("metalness", True)
        if m:
            nt.links.new(m.outputs["Color"], bsdf.inputs["Metallic"])
        n = tex("normal", True)
        if n:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.8
            nt.links.new(n.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        bsdf.inputs["Base Color"].default_value = tint
        bsdf.inputs["Roughness"].default_value = rough_default
    _mats[name] = mat
    return mat


def special_material(kind, color, transparency):
    name = "%s|%d,%d,%d|%.2f" % (kind, *color, transparency)
    if name in _mats:
        return _mats[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    c = (*lin(color), 1)
    if kind == "Neon":
        bsdf.inputs["Emission Color"].default_value = c
        bsdf.inputs["Emission Strength"].default_value = 6.0
        bsdf.inputs["Base Color"].default_value = c
    else:  # glass / translucent
        bsdf.inputs["Base Color"].default_value = c
        bsdf.inputs["Transmission Weight"].default_value = 0.9
        bsdf.inputs["Roughness"].default_value = 0.1
        bsdf.inputs["Alpha"].default_value = max(0.15, 1 - transparency)
    _mats[name] = mat
    return mat


LAMP_OFF = (38, 38, 36)  # LightController's DARK


def lamp_lit(lamp, state):
    # mirrors state_lights: which fixtures still glow in this state
    if lamp.get("mode") == "dead":
        return False
    return state == "NORMAL" or lamp.get("circuit") == "EMERGENCY"


def part_material(p, state="NORMAL"):
    if p.get("lamp") and not lamp_lit(p["lamp"], state):
        return special_material("Glass", LAMP_OFF, 0)
    if p["material"] == "Neon":
        return special_material("Neon", p["color"], 0)
    if p["material"] == "Glass" or p["transparency"] > 0.3:
        return special_material("Glass", p["color"], p["transparency"])
    key = VARIANT_KEY.get(p["variant"]) if p["variant"] else None
    key = key or REPLACES.get(p["material"])
    return texture_material(key, p["color"])


def cframe_matrix(pos, rx, ry, rz):
    return Matrix((
        (rx[0], ry[0], rz[0], pos[0]),
        (rx[1], ry[1], rz[1], pos[1]),
        (rx[2], ry[2], rz[2], pos[2]),
        (0, 0, 0, 1),
    ))


_proto = {}


def proto(shape):
    if shape in _proto:
        return _proto[shape]
    if shape == "ball":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=32, ring_count=16)
        bpy.ops.object.shade_smooth()  # Roblox draws a Ball smooth
    elif shape == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.0, vertices=16, rotation=(0, math.radians(90), 0))
        bpy.ops.object.transform_apply(rotation=True)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    me = o.data
    bpy.data.objects.remove(o)
    _proto[shape] = me
    return me


def add_part(p, coll, state="NORMAL"):
    me = proto(p["shape"]).copy()
    o = bpy.data.objects.new(p["name"], me)
    coll.objects.link(o)
    o.matrix_world = cframe_matrix(p["pos"], p["rx"], p["ry"], p["rz"]) @ Matrix.Diagonal((*p["size"], 1))
    me.materials.append(part_material(p, state))


def add_mesh(m, coll):
    path = os.path.join(ROOT, "assets", "props", m["name"] + ".obj")
    if not os.path.exists(path):
        return False
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
    o = bpy.context.selected_objects[0]
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
    o.matrix_world = cframe_matrix(m["pos"], m["rx"], m["ry"], m["rz"])
    if m.get("stretch"):
        # straight runs: the 4-stud mesh stretched along X to the run's length
        o.matrix_world = o.matrix_world @ Matrix.Diagonal((m["stretch"] / 4.0, 1, 1, 1))
    name = m["name"]
    key = "mesh|" + name
    if key not in _mats:
        mat = bpy.data.materials.new(key)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        folder = os.path.join(ROOT, "assets", "props", name)
        for kind, sock, nc in (("color", "Base Color", False), ("roughness", "Roughness", True), ("metalness", "Metallic", True)):
            pth = os.path.join(folder, "%s_%s.png" % (name, kind))
            if os.path.exists(pth):
                t = nt.nodes.new("ShaderNodeTexImage")
                t.image = bpy.data.images.load(pth, check_existing=True)
                if nc:
                    t.image.colorspace_settings.name = "Non-Color"
                nt.links.new(t.outputs["Color"], bsdf.inputs[sock])
        pth = os.path.join(folder, "%s_normal.png" % name)
        if os.path.exists(pth):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(pth, check_existing=True)
            t.image.colorspace_settings.name = "Non-Color"
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(t.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        _mats[key] = mat
    o.data.materials.clear()
    o.data.materials.append(_mats[key])
    return True


def state_lights(data, state):
    out = []
    for L in data["lights"]:
        col, b = L["color"], L["brightness"]
        if L["tag"] == "fixture":
            if L["mode"] == "dead":
                continue
            emergency = L["circuit"] == "EMERGENCY"
            if state == "EMERGENCY":
                if not emergency:
                    continue
                col, b = EMERGENCY_COLOR, b * 0.55
            elif state == "BLACKOUT":
                if not emergency:
                    continue
                col, b = ALARM_COLOR, b * 0.21
        elif L["tag"] == "off":
            continue
        elif L["powered"] and state != "NORMAL":
            continue
        out.append(dict(L, color=col, brightness=b))
    return out


def add_light(L, coll, k):
    # the energy that gives `brightness` at half the range under inverse square
    d = L["range"] / 2
    if L["class"] == "PointLight":
        ld = bpy.data.lights.new("L", "POINT")
        ld.energy = L["brightness"] * 0.5625 * 4 * math.pi * d * d * k
        ld.shadow_soft_size = 0.25
    elif L["class"] == "SpotLight":
        ld = bpy.data.lights.new("L", "SPOT")
        ld.energy = L["brightness"] * 0.5625 * 4 * math.pi * d * d * k
        ld.spot_size = math.radians(min(L["angle"], 179))
        ld.spot_blend = 0.35
        ld.shadow_soft_size = 0.3
    else:
        ld = bpy.data.lights.new("L", "AREA")
        ld.energy = L["brightness"] * 0.5625 * 2 * math.pi * d * d * k
        ld.size = 1.2
        ld.spread = math.radians(min(L["angle"], 180))
    ld.color = lin(L["color"])
    ld.use_shadow = bool(L["shadows"])
    o = bpy.data.objects.new("L", ld)
    coll.objects.link(o)
    pos = Vector(L["pos"])
    o.location = pos
    if L["class"] != "PointLight":
        o.rotation_euler = Vector(L["dir"]).to_track_quat("-Z", "Y").to_euler()


def camera_for(data):
    lo, hi = data["min"], data["max"]
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    sx, sz = hi[0] - lo[0], hi[2] - lo[2]
    y = lo[1]
    if sx > sz * 2:
        return (lo[0] + 3, y + 5.4, c[2]), (hi[0], y + 4.2, c[2])
    if sz > sx * 2:
        return (c[0], y + 5.4, hi[2] - 3), (c[0], y + 4.2, lo[2])
    return (c[0] - sx * 0.1, y + 5.4, hi[2] - 2.5), (c[0], y + 4.2, lo[2] + 4)


def main():
    path, out = sys.argv[1], sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "meshes"
    state = sys.argv[4] if len(sys.argv) > 4 else "NORMAL"
    data = json.load(open(path))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.cycles.diffuse_bounces = 0  # Roblox has no bounce light
    scene.cycles.glossy_bounces = 1
    scene.cycles.transmission_bounces = 2
    scene.render.resolution_x, scene.render.resolution_y = 960, 540
    scene.view_settings.view_transform = "AgX"
    presets = data["presets"]
    preset = presets.get(state) or presets[{"NORMAL": "POWERED", "EMERGENCY": "DARK"}.get(state, state)]
    scene.view_settings.exposure = preset["exposure"]
    coll = scene.collection
    have = {f[:-4] for f in os.listdir(os.path.join(ROOT, "assets", "props")) if f.endswith(".obj")}
    for p in data["parts"]:
        # a part a mesh replaces is dropped only when that mesh exists
        if mode == "meshes" and p.get("meshHide") and p.get("meshOf") in have:
            continue
        add_part(p, coll, state)
    placed = 0
    if mode == "meshes":
        for m in data.get("meshes", []):
            placed += 1 if add_mesh(m, coll) else 0
    lights = state_lights(data, state)
    for L in lights:
        add_light(L, coll, 1.0)
    world = bpy.data.worlds.new("Ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*lin(preset["ambient"]), 1)
    scene.world = world
    eye, target = camera_for(data)
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 18
    co = bpy.data.objects.new("Cam", cam)
    coll.objects.link(co)
    # Roblox axes: Y is up. Build the camera basis by hand (to_track_quat
    # assumes Blender's Z-up world and would roll the picture).
    f = (Vector(target) - Vector(eye)).normalized()
    right = f.cross(Vector((0, 1, 0))).normalized()
    up = right.cross(f)
    rot = Matrix((
        (right.x, up.x, -f.x),
        (right.y, up.y, -f.y),
        (right.z, up.z, -f.z),
    ))
    co.matrix_world = Matrix.Translation(Vector(eye)) @ rot.to_4x4()
    scene.camera = co
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("%s %s %s: %d parts, %d meshes, %d lights -> %s" % (data["room"], mode, state, len(data["parts"]), placed, len(lights), out))


if __name__ == "__main__":
    main()
