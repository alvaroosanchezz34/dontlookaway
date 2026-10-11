"""
Converts the game's .obj meshes (Roblox axes: Y up, front -Z) to .fbx for
Open Cloud uploads (it does not take .obj). Same geometry, normals and UVs.

    /home/user/.venv-blender/bin/python tools/blender/obj_to_fbx.py

Writes assets/fbx/<Name>.fbx for assets/observer/*.obj and assets/props/*.obj.
"""

import glob
import os

import bpy

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "fbx")


def main():
    os.makedirs(OUT, exist_ok=True)
    files = sorted(glob.glob(os.path.join(ROOT, "assets", "observer", "*.obj")) + glob.glob(os.path.join(ROOT, "assets", "props", "*.obj")))
    for path in files:
        name = os.path.splitext(os.path.basename(path))[0]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        # OBJ Y-up -> Blender Z-up, then FBX back to Y-up / -Z forward
        bpy.ops.wm.obj_import(filepath=path, forward_axis="NEGATIVE_Z", up_axis="Y")
        for o in bpy.context.selected_objects:
            o.name = name
            if o.data:
                o.data.name = name
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(OUT, name + ".fbx"),
            use_selection=False,
            axis_forward="-Z",
            axis_up="Y",
            apply_unit_scale=True,
            global_scale=1.0,
            mesh_smooth_type="FACE",
            path_mode="STRIP",
            embed_textures=False,
        )
        print("fbx", name)
    print("done", len(files))


if __name__ == "__main__":
    main()
