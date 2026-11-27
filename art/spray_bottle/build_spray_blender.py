#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for a realistic Turkish Street Vendor Produce Spray Bottle (Su Fisfisi).
Preserves node names for Godot items.gd & player.gd:
  - SprayBody  (translucent contoured sky-blue plastic bottle)
  - SprayWater (vivid opaque aqua water inside — avoids Forward+ alpha-sort milkiness!)
  - Trigger    (pivoted at sprayer neck so player.gd rotation.x physically squeezes the trigger!)
Nozzle points along Godot -Z (Blender +Y) at (0, 0.095, 0.134).
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Vector


SCRIPT_DIR = Path(__file__).resolve().parent
BLEND_PATH = SCRIPT_DIR / "spray_bottle.blend"
GLB_PATH = SCRIPT_DIR / "spray_bottle.glb"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _bsdf(mat):
    if mat.node_tree is None:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def make_mat(name, color, rough=0.25, metal=0.0, coat=0.2, alpha=1.0):
    m = bpy.data.materials.new(name)
    b = _bsdf(m)
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 0.99:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
    if "Coat Weight" in b.inputs and coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = rough * 0.6
    return m


def lathe_z(name, profile, segs, mat, col):
    """Revolve [(radius, z), ...] around Z axis."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 0.0001:
            rings.append([bm.verts.new(Vector((0.0, 0.0, z)))])
        else:
            ring = []
            for k in range(segs):
                a = (k / segs) * math.tau
                ring.append(bm.verts.new(Vector((math.cos(a) * r, math.sin(a) * r, z))))
            rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        if len(r0) == 1 and len(r1) > 1:
            for k in range(segs):
                f = bm.faces.new((r0[0], r1[k], r1[(k + 1) % segs]))
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


def build_spray_bottle():
    col = bpy.data.collections.new("SprayBottle")
    bpy.context.scene.collection.children.link(col)

    m_plastic = make_mat("SprayPlastic", (0.58, 0.85, 1.0), rough=0.08, coat=0.70, alpha=0.32)
    m_water = make_mat("SprayWaterMat", (0.06, 0.44, 0.90), rough=0.05, coat=0.55)
    m_white = make_mat("SprayWhite", (0.95, 0.96, 0.98), rough=0.30, coat=0.25)
    m_blue = make_mat("SprayAccentBlue", (0.08, 0.44, 0.88), rough=0.26, coat=0.32)
    m_tube = make_mat("DipTubeMat", (0.86, 0.92, 0.96), rough=0.35, alpha=0.80)

    # 1) Smooth ergonomic pinched-waist translucent bottle body (Z: -0.075 .. +0.080)
    body_prof = [
        (0.000, -0.074),
        (0.034, -0.074),
        (0.040, -0.070),
        (0.043, -0.060),
        (0.0445, -0.044),
        (0.0435, -0.024),
        (0.040, -0.006),
        (0.0355, 0.010),
        (0.0335, 0.022),
        (0.0355, 0.036),
        (0.0365, 0.048),
        (0.033, 0.058),
        (0.026, 0.067),
        (0.0205, 0.073),
        (0.019, 0.080),
        (0.000, 0.080),
    ]
    lathe_z("SprayBody", body_prof, 36, m_plastic, col)

    # 2) Inner vivid water volume (opaque -> crisp color through translucent shell!)
    water_prof = [
        (0.000, -0.070),
        (0.033, -0.070),
        (0.0385, -0.064),
        (0.0415, -0.046),
        (0.0405, -0.024),
        (0.037, -0.006),
        (0.033, 0.010),
        (0.031, 0.022),
        (0.032, 0.028),
        (0.000, 0.027),
    ]
    lathe_z("SprayWater", water_prof, 32, m_water, col)

    # 3) Dip-tube straw inside bottle
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.0032, depth=0.148, location=(0.0, 0.003, 0.004))
    tube = bpy.context.active_object
    tube.name = "DipTube"
    tube.rotation_euler = Euler((0.06, 0.0, 0.0), "XYZ")
    tube.data.materials.append(m_tube)
    bpy.context.scene.collection.objects.unlink(tube)
    col.objects.link(tube)

    # 4) Ribbed white screw collar (Z: 0.074..0.102)
    collar_prof = [
        (0.000, 0.074),
        (0.024, 0.074),
        (0.025, 0.098),
        (0.021, 0.104),
        (0.000, 0.104),
    ]
    lathe_z("ScrewCollar", collar_prof, 24, m_white, col)

    # Subtle vertical ribs around collar
    for k in range(12):
        a = (k / 12) * math.tau
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(a) * 0.0245, math.sin(a) * 0.0245, 0.086))
        rb = bpy.context.active_object
        rb.scale = (0.003, 0.003, 0.020)
        rb.rotation_euler = Euler((0.0, 0.0, a), "XYZ")
        rb.data.materials.append(m_white)
        bpy.context.scene.collection.objects.unlink(rb)
        col.objects.link(rb)

    # 5) Sleek sculpted white spray head shroud (points forward along Blender +Y = Godot -Z!)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.012, 0.124))
    head = bpy.context.active_object
    head.name = "SprayHead"
    head.scale = (0.036, 0.076, 0.044)
    bpy.ops.object.transform_apply(scale=True)
    bev = head.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.010
    bev.segments = 3
    head.data.materials.append(m_white)
    bpy.ops.object.shade_smooth()
    bpy.context.scene.collection.objects.unlink(head)
    col.objects.link(head)

    # Rounded rear palm-rest tail of the sprayer
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=12, radius=0.022, location=(0.0, -0.022, 0.122))
    tail = bpy.context.active_object
    tail.name = "SprayTail"
    tail.scale = (0.82, 1.15, 0.96)
    tail.data.materials.append(m_white)
    bpy.ops.object.shade_smooth()
    bpy.context.scene.collection.objects.unlink(tail)
    col.objects.link(tail)

    # 6) Blue nozzle barrel + twistable spray tip (tip at Blender Y = +0.095 -> Godot Z = -0.095!)
    bpy.ops.mesh.primitive_cylinder_add(vertices=18, radius=0.0105, depth=0.036, location=(0.0, 0.062, 0.132))
    barrel = bpy.context.active_object
    barrel.name = "NozzleBarrel"
    barrel.rotation_euler = Euler((math.pi * 0.5, 0.0, 0.0), "XYZ")
    barrel.data.materials.append(m_blue)
    bpy.ops.object.shade_smooth()
    bpy.context.scene.collection.objects.unlink(barrel)
    col.objects.link(barrel)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.086, 0.132))
    cap = bpy.context.active_object
    cap.name = "NozzleTip"
    cap.scale = (0.018, 0.016, 0.018)
    bpy.ops.object.transform_apply(scale=True)
    cb = cap.modifiers.new("Bevel", "BEVEL")
    cb.width = 0.003
    cb.segments = 2
    cap.data.materials.append(m_blue)
    bpy.ops.object.shade_smooth()
    bpy.context.scene.collection.objects.unlink(cap)
    col.objects.link(cap)

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.0032, depth=0.006, location=(0.0, 0.094, 0.132))
    orifice = bpy.context.active_object
    orifice.name = "NozzleOrifice"
    orifice.rotation_euler = Euler((math.pi * 0.5, 0.0, 0.0), "XYZ")
    orifice.data.materials.append(m_white)
    bpy.context.scene.collection.objects.unlink(orifice)
    col.objects.link(orifice)

    # 7) Sculpted curved 'Trigger' pivoted at (0, 0.044, 0.114) so player.gd rotation.x squeezes cleanly!
    bm = bmesh.new()
    # Build trigger blade in local space around pivot (0,0,0), extending down (-Z) and forward (+Y)
    pts = [
        (0.0, 0.004, 0.000),
        (0.0, 0.016, -0.012),
        (0.0, 0.024, -0.028),
        (0.0, 0.028, -0.044),
        (0.0, 0.022, -0.052),
    ]
    w_half = 0.0075
    t_half = 0.0045
    rings = []
    for x0, y0, z0 in pts:
        v0 = bm.verts.new(Vector((-w_half, y0 + t_half, z0)))
        v1 = bm.verts.new(Vector((w_half, y0 + t_half, z0)))
        v2 = bm.verts.new(Vector((w_half, y0 - t_half, z0)))
        v3 = bm.verts.new(Vector((-w_half, y0 - t_half, z0)))
        rings.append((v0, v1, v2, v3))
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(4):
            kn = (k + 1) % 4
            f = bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            f.smooth = True
    bm.faces.new((rings[0][0], rings[0][3], rings[0][2], rings[0][1]))
    bm.faces.new((rings[-1][0], rings[-1][1], rings[-1][2], rings[-1][3]))
    tmesh = bpy.data.meshes.new("Trigger")
    bm.to_mesh(tmesh)
    bm.free()
    tmesh.materials.append(m_blue)
    trig = bpy.data.objects.new("Trigger", tmesh)
    trig.location = Vector((0.0, 0.040, 0.114))
    col.objects.link(trig)

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
    bg.inputs["Color"].default_value = (0.07, 0.075, 0.085, 1.0)
    bg.inputs["Strength"].default_value = 0.75

    for lname, loc, tgt, energy, color, sz in [
        ("Key", (0.32, 0.28, 0.30), (0.0, 0.02, 0.04), 14.0, (1.0, 0.97, 0.92), 0.30),
        ("Fill", (-0.34, -0.18, 0.16), (0.0, 0.02, 0.04), 7.0, (0.82, 0.92, 1.0), 0.36),
        ("Rim", (0.0, -0.32, 0.22), (0.0, 0.02, 0.04), 10.0, (0.90, 0.96, 1.0), 0.26),
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
    col = build_spray_bottle()

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
    cam.data.lens = 72.0
    cam.location = Vector((0.30, 0.22, 0.14))
    cam.rotation_euler = (Vector((0.0, 0.02, 0.04)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(PREVIEW_CLOSEUP)
    bpy.ops.render.render(write_still=True)
    print("SPRAY_BUILD_OK")


if __name__ == "__main__":
    main()
