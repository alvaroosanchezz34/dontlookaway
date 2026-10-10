"""
Review renders of the exported prop meshes (assets/props/*.obj with their
baked maps), framed to fit, plus a contact sheet of all of them.

    /home/user/.venv-blender/bin/python tools/blender/preview_assets.py [asset ...]

Writes assets/props/previews/<Asset>.png and assets/props/previews/_sheet.png.
The OBJ is in Roblox axes (Y up); the camera works in those axes too.
"""

import math
import os
import sys

import bpy  # noqa: I001
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROPS = os.path.join(ROOT, "assets", "props")


def look(eye, target):
    f = (target - eye).normalized()
    right = f.cross(Vector((0, 1, 0))).normalized()
    up = right.cross(f)
    rot = Matrix(((right.x, up.x, -f.x), (right.y, up.y, -f.y), (right.z, up.z, -f.z)))
    return Matrix.Translation(eye) @ rot.to_4x4()


def material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    folder = os.path.join(PROPS, name)
    for kind, sock, nc in (("color", "Base Color", False), ("roughness", "Roughness", True), ("metalness", "Metallic", True)):
        p = os.path.join(folder, "%s_%s.png" % (name, kind))
        if os.path.exists(p):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(p)
            if nc:
                t.image.colorspace_settings.name = "Non-Color"
            nt.links.new(t.outputs["Color"], bsdf.inputs[sock])
    p = os.path.join(folder, "%s_normal.png" % name)
    if os.path.exists(p):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(p)
        t.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def render(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.view_settings.view_transform = "AgX"
    bpy.ops.wm.obj_import(filepath=os.path.join(PROPS, name + ".obj"), forward_axis="Y", up_axis="Z")
    obj = bpy.context.selected_objects[0]
    obj.data.materials.clear()
    obj.data.materials.append(material(name))
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo + hi) / 2
    radius = (hi - lo).length / 2
    # floor under the lowest point, a back wall behind (Roblox +Z = behind the front)
    for nm, size, loc, col in (
        ("Floor", (radius * 12, 0.1, radius * 12), (c.x, lo.y - 0.05, c.z), (0.1, 0.095, 0.09)),
        ("Wall", (radius * 12, radius * 6, 0.1), (c.x, c.y, hi.z + radius * 0.4), (0.3, 0.28, 0.25)),
    ):
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object
        o.name = nm
        o.scale = size
        o.location = loc
        m = bpy.data.materials.new(nm)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
        o.data.materials.append(m)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.03, 0.035, 1)
    scene.world = world
    # front of a prop is Roblox -Z: camera in front, a little to the side and above
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 50
    co = bpy.data.objects.new("Cam", cam)
    scene.collection.objects.link(co)
    fov = 2 * math.atan(18 / cam.lens)
    dist = radius / math.sin(fov / 2) * 1.08
    eye = c + Vector((0.55, 0.38, -1.0)).normalized() * dist
    co.matrix_world = look(eye, c)
    scene.camera = co
    for nm, offs, energy, col, size in (
        ("Key", Vector((1.0, 1.2, -0.9)), 300, (1.0, 0.85, 0.7), 1.0),
        ("Fill", Vector((-1.2, 0.4, -0.6)), 80, (0.75, 0.82, 1.0), 1.5),
        ("Rim", Vector((-0.4, 1.0, 1.2)), 180, (0.8, 0.85, 1.0), 0.8),
    ):
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy = energy * radius * radius
        ld.size = radius * size
        ld.color = col
        lo_ = bpy.data.objects.new(nm, ld)
        scene.collection.objects.link(lo_)
        lo_.matrix_world = look(c + offs.normalized() * radius * 3, c)
    out = os.path.join(PROPS, "previews", name + ".png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    return out


def sheet(names):
    from PIL import Image  # noqa: PLC0415 - optional, only for the sheet

    tiles = [Image.open(os.path.join(PROPS, "previews", n + ".png")).resize((400, 300)) for n in names]
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    s = Image.new("RGB", (cols * 400, rows * 300))
    for i, t in enumerate(tiles):
        s.paste(t, ((i % cols) * 400, (i // cols) * 300))
    s.save(os.path.join(PROPS, "previews", "_sheet.png"))


def main():
    names = sys.argv[1:] or sorted(f[:-4] for f in os.listdir(PROPS) if f.endswith(".obj"))
    for n in names:
        print("preview", render(n))
    try:
        sheet(sorted(f[:-4] for f in os.listdir(PROPS) if f.endswith(".obj")))
    except ImportError:
        pass


if __name__ == "__main__":
    main()
