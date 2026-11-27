#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for a classic Turkish Street Vendor Megaphone (El Megafonu).
Horn points forward along Godot -Z (Blender +Y) so it drops directly into items.gd.
Includes smooth exponential flare horn, red rubber bumper rim, inner acoustic phase plug,
rear mic housing & perforated grille, pistol grip with red talk trigger, and siren switch.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector


SCRIPT_DIR = Path(__file__).resolve().parent
BLEND_PATH = SCRIPT_DIR / "megaphone.blend"
GLB_PATH = SCRIPT_DIR / "megaphone.glb"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"

# Blender Y -> Godot -Z! So horn extends from y=-0.06 (rear mic) to y=+0.22 (bell mouth), centered at z=+0.04 (Godot y=+0.04)
HORN_Z = 0.040


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _bsdf(mat):
    if mat.node_tree is None:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def make_mat(name, color, rough=0.35, metal=0.0, coat=0.15):
    m = bpy.data.materials.new(name)
    b = _bsdf(m)
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Coat Weight" in b.inputs and coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = rough * 0.7
    return m


def lathe_y(name, profile, segs, mat, col, z_off=HORN_Z):
    """Revolve profile [(y, radius), ...] around the Y axis centered at (0, y, z_off)."""
    bm = bmesh.new()
    rings = []
    for y, r in profile:
        if r <= 0.0001:
            v = bm.verts.new(Vector((0.0, y, z_off)))
            rings.append([v])
        else:
            ring = []
            for k in range(segs):
                a = (k / segs) * math.tau
                ring.append(bm.verts.new(Vector((math.cos(a) * r, y, z_off + math.sin(a) * r))))
            rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        if len(r0) == 1 and len(r1) > 1:
            for k in range(segs):
                f = bm.faces.new((r0[0], r1[(k + 1) % segs], r1[k]))
                f.smooth = True
        elif len(r0) > 1 and len(r1) == 1:
            for k in range(segs):
                f = bm.faces.new((r0[k], r0[(k + 1) % segs], r1[0]))
                f.smooth = True
        elif len(r0) > 1 and len(r1) > 1:
            for k in range(segs):
                kn = (k + 1) % segs
                f = bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
                f.smooth = True

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    return obj


def build_megaphone():
    col = bpy.data.collections.new("Megaphone")
    bpy.context.scene.collection.children.link(col)

    m_white = make_mat("MegaWhiteABS", (0.94, 0.92, 0.87), rough=0.28, metal=0.0, coat=0.35)
    m_red = make_mat("MegaCrimson", (0.72, 0.06, 0.05), rough=0.30, metal=0.0, coat=0.32)
    m_rubber = make_mat("MegaRubber", (0.08, 0.08, 0.10), rough=0.78, metal=0.0, coat=0.0)
    m_dark = make_mat("MegaDarkPlastic", (0.12, 0.13, 0.15), rough=0.44, metal=0.05, coat=0.12)
    m_chrome = make_mat("MegaChrome", (0.85, 0.87, 0.90), rough=0.18, metal=0.92, coat=0.0)

    # 1) Main flared cream-white horn (outer + inner wall!)
    horn_prof = [
        (-0.015, 0.038),
        (0.015, 0.041),
        (0.055, 0.047),
        (0.095, 0.058),
        (0.135, 0.074),
        (0.175, 0.094),
        (0.205, 0.112),
        (0.220, 0.119),
        # Inner curved lip & acoustic throat
        (0.220, 0.112),
        (0.202, 0.105),
        (0.165, 0.084),
        (0.115, 0.058),
        (0.065, 0.036),
        (0.045, 0.028),
        (0.045, 0.000),
    ]
    lathe_y("HornBody", horn_prof, 36, m_white, col)

    # 2) Thick red rubber bumper lip around front bell mouth
    rim_prof = [
        (0.214, 0.116),
        (0.223, 0.124),
        (0.231, 0.124),
        (0.234, 0.117),
        (0.229, 0.110),
        (0.216, 0.109),
        (0.214, 0.116),
    ]
    lathe_y("RedRim", rim_prof, 36, m_red, col)

    # 3) Inner acoustic compression dome (classic megaphone center cone!)
    cone_prof = [
        (0.060, 0.000),
        (0.062, 0.032),
        (0.105, 0.038),
        (0.148, 0.032),
        (0.162, 0.020),
        (0.166, 0.000),
    ]
    lathe_y("AcousticPlug", cone_prof, 24, m_red, col)

    # 4) Rear crimson battery compartment & collar + chrome accent ring
    rear_prof = [
        (-0.082, 0.000),
        (-0.082, 0.031),
        (-0.075, 0.037),
        (-0.025, 0.040),
        (-0.012, 0.042),
        (-0.012, 0.036),
    ]
    lathe_y("RearHousing", rear_prof, 32, m_red, col)

    chrome_ring = [
        (-0.016, 0.039),
        (-0.014, 0.0435),
        (-0.006, 0.0435),
        (-0.004, 0.0395),
    ]
    lathe_y("CollarChrome", chrome_ring, 32, m_chrome, col)

    # 5) Perforated mic cap on rear face
    mic_prof = [
        (-0.090, 0.000),
        (-0.090, 0.024),
        (-0.084, 0.027),
        (-0.079, 0.027),
    ]
    lathe_y("MicGrille", mic_prof, 24, m_dark, col)

    # 6) Ergonomic sculpted pistol grip (angled downward/back)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, -0.022, -0.046))
    grip = bpy.context.active_object
    grip.name = "PistolGrip"
    grip.scale = (0.028, 0.040, 0.115)
    grip.rotation_euler = Euler((-0.24, 0.0, 0.0), "XYZ")
    bpy.ops.object.transform_apply(scale=True)
    bev = grip.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.007
    bev.segments = 3
    grip.data.materials.append(m_dark)
    bpy.ops.object.shade_smooth()
    bpy.context.scene.collection.objects.unlink(grip)
    col.objects.link(grip)

    # Rubber grip ribs aligned flush along the pistol grip axis (Rx(-0.24) maps +Z -> (0, +sin, +cos))
    for d_off in [-0.028, -0.010, 0.008, 0.026]:
        ry = -0.022 + d_off * math.sin(0.24)
        rz = -0.046 + d_off * math.cos(0.24)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, ry, rz))
        rib = bpy.context.active_object
        rib.scale = (0.031, 0.043, 0.0055)
        rib.rotation_euler = Euler((-0.24, 0.0, 0.0), "XYZ")
        rib.data.materials.append(m_rubber)
        bpy.context.scene.collection.objects.unlink(rib)
        col.objects.link(rib)

    # 7) Red push-to-talk trigger + top siren button + chrome volume wheel
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.002, -0.018))
    trig = bpy.context.active_object
    trig.name = "TalkTrigger"
    trig.scale = (0.016, 0.018, 0.036)
    trig.rotation_euler = Euler((0.25, 0.0, 0.0), "XYZ")
    trig.data.materials.append(m_red)
    bpy.context.scene.collection.objects.unlink(trig)
    col.objects.link(trig)

    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.009, depth=0.012, location=(0.0, -0.046, 0.082))
    siren_btn = bpy.context.active_object
    siren_btn.name = "SirenButton"
    siren_btn.data.materials.append(m_chrome)
    bpy.context.scene.collection.objects.unlink(siren_btn)
    col.objects.link(siren_btn)

    # Side volume dial
    bpy.ops.mesh.primitive_cylinder_add(vertices=18, radius=0.011, depth=0.010, location=(0.040, -0.046, 0.042))
    vol = bpy.context.active_object
    vol.name = "VolDial"
    vol.rotation_euler = Euler((0.0, math.pi * 0.5, 0.0), "XYZ")
    vol.data.materials.append(m_chrome)
    bpy.context.scene.collection.objects.unlink(vol)
    col.objects.link(vol)

    # 8) Rear wrist-strap loop
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.014, minor_radius=0.003, location=(0.0, -0.038, -0.104),
        rotation=Euler((0.0, math.pi * 0.5, 0.0), "XYZ"),
    )
    loop = bpy.context.active_object
    loop.name = "StrapLoop"
    loop.data.materials.append(m_chrome)
    bpy.context.scene.collection.objects.unlink(loop)
    col.objects.link(loop)

    return col


def setup_studio():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 48
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"

    col = bpy.data.collections.new("Studio")
    scene.collection.children.link(col)
    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.07, 0.07, 0.08, 1.0)
    bg.inputs["Strength"].default_value = 0.75

    for lname, loc, tgt, energy, color, sz in [
        ("Key", (0.38, 0.36, 0.32), (0.0, 0.06, 0.02), 16.0, (1.0, 0.96, 0.90), 0.35),
        ("Fill", (-0.36, -0.24, 0.18), (0.0, 0.06, 0.02), 7.0, (0.85, 0.92, 1.0), 0.40),
        ("Rim", (0.0, -0.36, 0.25), (0.0, 0.06, 0.02), 10.0, (1.0, 0.92, 0.80), 0.28),
    ]:
        ld = bpy.data.lights.new(lname, type="AREA")
        ld.energy = energy
        ld.color = color
        ld.size = sz
        lo = bpy.data.objects.new(lname, ld)
        lo.location = Vector(loc)
        lo.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        col.objects.link(lo)

    cd = bpy.data.cameras.new("Cam")
    cd.clip_start = 0.004
    cam = bpy.data.objects.new("Cam", cd)
    col.objects.link(cam)
    scene.camera = cam
    return cam


def main():
    clear_scene()
    col = build_megaphone()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in col.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )

    cam = setup_studio()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    scene = bpy.context.scene
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    cam.data.lens = 68.0
    cam.location = Vector((0.36, 0.34, 0.16))
    cam.rotation_euler = (Vector((0.0, 0.07, 0.02)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(PREVIEW_CLOSEUP)
    bpy.ops.render.render(write_still=True)
    print("MEGAPHONE_BUILD_OK")


if __name__ == "__main__":
    main()
