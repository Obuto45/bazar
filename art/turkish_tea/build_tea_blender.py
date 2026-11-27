#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for an authentic Turkish Ince Belli Tea Glass
(glass, ruby tea liquid, patterned porcelain saucer, sculpted stainless spoon, 2 sugar cubes).

Node names preserved for Godot player.gd:
  - TeaLiquid  (pivoted at glass bottom so scale.y lowers smoothly per sip)
  - SpoonPivot (centered inside glass so rotation.y stirs the spoon on right-click)
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TEX_DIR = SCRIPT_DIR / "textures"
BLEND_PATH = SCRIPT_DIR / "turkish_tea.blend"
GLB_PATH = SCRIPT_DIR / "turkish_tea.glb"
PREVIEW_4ANGLE = SCRIPT_DIR / "preview_4angle.png"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"

# Classic Pasabahce-style Ince Belli outer + inner wall profile (height ~9.6 cm, sits on saucer at z=0.011)
GLASS_PROFILE = [
    # Bottom contact on saucer
    (0.0000, 0.0112),
    (0.0190, 0.0112),
    (0.0235, 0.0124),
    (0.0262, 0.0155),
    # Plump lower belly
    (0.0298, 0.0230),
    (0.0322, 0.0320),
    (0.0328, 0.0410),
    (0.0314, 0.0500),
    # Iconic pinched "ince bel" waist!
    (0.0282, 0.0595),
    (0.0264, 0.0680),
    (0.0268, 0.0755),
    # Graceful flared drinking lip
    (0.0292, 0.0845),
    (0.0324, 0.0940),
    (0.0346, 0.1025),
    (0.0354, 0.1065),
    # Smooth rounded glass lip thickness
    (0.0346, 0.1076),
    (0.0332, 0.1072),
    # Inner wall descending back down to thick crystal glass base
    (0.0312, 0.0970),
    (0.0278, 0.0850),
    (0.0246, 0.0720),
    (0.0248, 0.0610),
    (0.0298, 0.0440),
    (0.0290, 0.0300),
    (0.0245, 0.0210),
    (0.0170, 0.0195),
    (0.0000, 0.0195),
]

# Tea liquid pivoted at z = 0.020 (local coords relative to TeaLiquid origin!)
LIQUID_LOCAL_PROFILE = [
    (0.0000, 0.0000),
    (0.0165, 0.0000),
    (0.0238, 0.0020),
    (0.0284, 0.0110),
    (0.0292, 0.0240),
    (0.0242, 0.0410),
    (0.0240, 0.0520),
    (0.0270, 0.0640),
    (0.0298, 0.0735),
    (0.0292, 0.0748),
    (0.0000, 0.0742),
]

# Traditional porcelain tea saucer (diameter 13.4 cm, concave center well)
SAUCER_PROFILE = [
    (0.0000, 0.0022),
    (0.0280, 0.0022),
    (0.0310, 0.0000),
    (0.0355, 0.0000),
    (0.0390, 0.0022),
    (0.0520, 0.0072),
    (0.0635, 0.0138),
    (0.0672, 0.0170),
    (0.0666, 0.0188),
    (0.0635, 0.0185),
    (0.0520, 0.0124),
    (0.0380, 0.0086),
    (0.0315, 0.0108),
    (0.0278, 0.0102),
    (0.0000, 0.0100),
]


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def ensure_collection(name: str, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        if parent is None:
            bpy.context.scene.collection.children.link(col)
        else:
            parent.children.link(col)
    return col


def link_obj(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)


def set_smooth(obj):
    if obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True


def _bsdf(mat: bpy.types.Material):
    if not mat.node_tree:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def build_lathe(name: str, profile, segs: int = 64, planar_uv_r: float = 0.0) -> bpy.types.Object:
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap") if planar_uv_r > 0.0 else None
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            ring = []
            for i in range(segs):
                a = (i / segs) * math.tau
                ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
            rings.append(ring)

    for k in range(len(rings) - 1):
        r0, r1 = rings[k], rings[k + 1]
        if len(r0) == 1 and len(r1) > 1:
            for i in range(segs):
                bm.faces.new((r0[0], r1[(i + 1) % segs], r1[i]))
        elif len(r0) > 1 and len(r1) == 1:
            for i in range(segs):
                bm.faces.new((r0[i], r0[(i + 1) % segs], r1[0]))
        elif len(r0) > 1 and len(r1) > 1:
            for i in range(segs):
                ni = (i + 1) % segs
                bm.faces.new((r0[i], r0[ni], r1[ni], r1[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if uv_layer is not None:
        for f in bm.faces:
            for loop in f.loops:
                co = loop.vert.co
                u = 0.5 + co.x / (planar_uv_r * 2.02)
                v = 0.5 + co.y / (planar_uv_r * 2.02)
                loop[uv_layer].uv = (u, v)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    set_smooth(obj)
    return obj


def build_spoon() -> bpy.types.Object:
    """Sculpted stainless-steel Turkish teaspoon (concave oval bowl + slim tapered handle)."""
    bm = bmesh.new()
    # Bowl (ellipsoid indented slightly)
    mat_bowl = Matrix.Translation((0.0, 0.0, 0.008)) @ Matrix.Diagonal((0.0068, 0.0030, 0.0125, 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=10, radius=1.0, matrix=mat_bowl)
    # Tapered slim neck + decorative flattened handle end
    sections = [
        (0.019, 0.0020, 0.0011),
        (0.045, 0.0018, 0.0010),
        (0.075, 0.0024, 0.0011),
        (0.102, 0.0044, 0.0013),
        (0.114, 0.0052, 0.0013),
        (0.120, 0.0032, 0.0011),
    ]
    rings = []
    segs = 10
    for z, rx, ry in sections:
        ring = []
        bend_y = 0.0035 * math.sin(max(0.0, (z - 0.02) / 0.10) * math.pi)
        for i in range(segs):
            a = (i / segs) * math.tau
            ring.append(bm.verts.new((math.cos(a) * rx, math.sin(a) * ry + bend_y, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segs):
            ni = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][ni], rings[k + 1][ni], rings[k + 1][i]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("TeaSpoon")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("TeaSpoon", mesh)
    set_smooth(obj)
    return obj


def build_sugar_cubes() -> bpy.types.Object:
    """Two classic white Turkish sugar cubes resting on the saucer edge."""
    bm = bmesh.new()
    specs = [
        ((0.041, -0.022, 0.0175), Euler((0.12, -0.14, 0.35), "XYZ")),
        ((0.045, -0.004, 0.0185), Euler((0.05, -0.16, -0.25), "XYZ")),
    ]
    for pos, rot in specs:
        mat = Matrix.Translation(pos) @ rot.to_matrix().to_4x4() @ Matrix.Diagonal((0.0125, 0.0125, 0.0095, 1.0))
        res = bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
        bmesh.ops.bevel(bm, geom=res["verts"], offset=0.0012, segments=2, affect="EDGES")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("SugarCubes")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("SugarCubes", mesh)
    return obj


def build_tea_assembly():
    col = ensure_collection("TurkishTea")
    root = bpy.data.objects.new("TurkishTeaSet", None)
    link_obj(root, col)

    # Materials
    m_saucer = bpy.data.materials.new("PorcelainSaucerMat")
    bs = _bsdf(m_saucer)
    tex = m_saucer.node_tree.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(TEX_DIR / "saucer_tex.png"))
    img.pack()
    tex.image = img
    m_saucer.node_tree.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.14
    if "Coat Weight" in bs.inputs:
        bs.inputs["Coat Weight"].default_value = 0.85

    m_glass = bpy.data.materials.new("InceBelliGlassMat")
    bg = _bsdf(m_glass)
    bg.inputs["Base Color"].default_value = (0.94, 0.98, 1.0, 1.0)
    bg.inputs["Roughness"].default_value = 0.04
    if "IOR" in bg.inputs:
        bg.inputs["IOR"].default_value = 1.51
    if "Transmission Weight" in bg.inputs:
        bg.inputs["Transmission Weight"].default_value = 0.85
    if "Coat Weight" in bg.inputs:
        bg.inputs["Coat Weight"].default_value = 1.0
    bg.inputs["Alpha"].default_value = 0.28
    if hasattr(m_glass, "blend_method"):
        m_glass.blend_method = "BLEND"

    m_gold = bpy.data.materials.new("GoldRimMat")
    bgo = _bsdf(m_gold)
    bgo.inputs["Base Color"].default_value = (0.92, 0.74, 0.24, 1.0)
    bgo.inputs["Metallic"].default_value = 0.92
    bgo.inputs["Roughness"].default_value = 0.18

    m_tea = bpy.data.materials.new("RubyTeaMat")
    bt = _bsdf(m_tea)
    # Iconic deep dark ruby-crimson "tavsan kani" tea
    bt.inputs["Base Color"].default_value = (0.16, 0.008, 0.0015, 1.0)
    bt.inputs["Roughness"].default_value = 0.04
    if "Coat Weight" in bt.inputs:
        bt.inputs["Coat Weight"].default_value = 1.0
    if "Emission Color" in bt.inputs:
        bt.inputs["Emission Color"].default_value = (0.28, 0.014, 0.002, 1.0)
        bt.inputs["Emission Strength"].default_value = 0.07
    bt.inputs["Alpha"].default_value = 0.86
    if hasattr(m_tea, "blend_method"):
        m_tea.blend_method = "BLEND"

    m_steel = bpy.data.materials.new("StainlessSpoonMat")
    bst = _bsdf(m_steel)
    bst.inputs["Base Color"].default_value = (0.86, 0.89, 0.92, 1.0)
    bst.inputs["Metallic"].default_value = 0.96
    bst.inputs["Roughness"].default_value = 0.12

    m_sugar = bpy.data.materials.new("SugarCubeMat")
    bsu = _bsdf(m_sugar)
    bsu.inputs["Base Color"].default_value = (0.97, 0.96, 0.94, 1.0)
    bsu.inputs["Roughness"].default_value = 0.82

    # 1. Saucer
    saucer = build_lathe("Saucer", SAUCER_PROFILE, segs=64, planar_uv_r=0.0672)
    saucer.data.materials.append(m_saucer)
    saucer.parent = root
    link_obj(saucer, col)

    # 2. Ince Belli Glass
    glass = build_lathe("TeaGlass", GLASS_PROFILE, segs=64)
    glass.data.materials.append(m_glass)
    glass.parent = root
    link_obj(glass, col)

    # Delicate gold lip band
    bpy.ops.mesh.primitive_torus_add(
        major_segments=64, minor_segments=12, major_radius=0.0348, minor_radius=0.0010, location=(0.0, 0.0, 0.1066)
    )
    rim = bpy.context.active_object
    rim.name = "GoldRim"
    set_smooth(rim)
    rim.data.materials.append(m_gold)
    rim.parent = root
    link_obj(rim, col)

    # 3. TeaLiquid (origin at glass bottom z=0.020 so Godot scale.y lowers level!)
    liq = build_lathe("TeaLiquid", LIQUID_LOCAL_PROFILE, segs=48)
    liq.location = (0.0, 0.0, 0.020)
    liq.data.materials.append(m_tea)
    liq.parent = root
    link_obj(liq, col)

    # 4. SpoonPivot + sculpted TeaSpoon resting diagonally inside glass
    sp_piv = bpy.data.objects.new("SpoonPivot", None)
    sp_piv.location = (0.0, 0.0, 0.022)
    sp_piv.parent = root
    link_obj(sp_piv, col)

    spoon = build_spoon()
    spoon.location = (0.006, 0.0, 0.002)
    spoon.rotation_euler = Euler((0.0, math.radians(17.0), math.radians(-22.0)), "XYZ")
    spoon.data.materials.append(m_steel)
    spoon.parent = sp_piv
    link_obj(spoon, col)

    # 5. Two Sugar Cubes on saucer
    sugar = build_sugar_cubes()
    sugar.data.materials.append(m_sugar)
    sugar.parent = root
    link_obj(sugar, col)

    return root, col


def setup_studio():
    col = ensure_collection("Studio")
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.05

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.06, 0.055, 0.05, 1.0)
    bg.inputs["Strength"].default_value = 0.65

    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.35, depth=0.012, location=(0.0, 0.0, -0.006))
    floor = bpy.context.active_object
    fmat = bpy.data.materials.new("WoodTable")
    fb = _bsdf(fmat)
    fb.inputs["Base Color"].default_value = (0.14, 0.085, 0.045, 1.0)
    fb.inputs["Roughness"].default_value = 0.36
    floor.data.materials.append(fmat)
    link_obj(floor, col)

    lights = [
        ("Key", "AREA", (0.28, -0.32, 0.28), (0.0, 0.0, 0.06), 10.0, (1.0, 0.95, 0.88), 0.28),
        ("Fill", "AREA", (-0.32, -0.22, 0.20), (0.0, 0.0, 0.06), 4.5, (0.85, 0.92, 1.0), 0.36),
        ("RubyBack", "AREA", (0.0, 0.26, 0.09), (0.0, 0.0, 0.055), 14.0, (1.0, 0.72, 0.38), 0.16),
    ]
    for lname, ltype, loc, tgt, energy, color, sz in lights:
        ld = bpy.data.lights.new(lname, type=ltype)
        ld.energy = energy; ld.color = color; ld.size = sz
        lo = bpy.data.objects.new(lname, ld)
        lo.location = Vector(loc)
        lo.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        link_obj(lo, col)

    cd = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cd)
    link_obj(cam, col)
    scene.camera = cam
    return cam


def render_view(cam, loc, tgt, out_path: Path, rx: int, ry: int, lens: float = 76.0):
    scene = bpy.context.scene
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    cam.data.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(out_path)
    bpy.ops.render.render(write_still=True)


def stitch_2x2(paths, out_path: Path):
    imgs = []
    for p in paths:
        im = bpy.data.images.load(str(p))
        w, h = im.size
        imgs.append(np.array(im.pixels[:], dtype=np.float32).reshape((h, w, 4)))
        bpy.data.images.remove(im)
    h, w, _ = imgs[0].shape
    grid = np.zeros((h * 2, w * 2, 4), dtype=np.float32)
    grid[h:h * 2, 0:w, :] = imgs[0]
    grid[h:h * 2, w:w * 2, :] = imgs[1]
    grid[0:h, 0:w, :] = imgs[2]
    grid[0:h, w:w * 2, :] = imgs[3]
    out_im = bpy.data.images.new("Sheet", width=w * 2, height=h * 2, alpha=True)
    out_im.pixels[:] = grid.ravel()
    out_im.filepath_raw = str(out_path)
    out_im.file_format = "PNG"
    out_im.save()
    bpy.data.images.remove(out_im)


def main():
    clear_scene()
    _, col = build_tea_assembly()

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

    tmp = SCRIPT_DIR / "_tmp_renders"
    tmp.mkdir(exist_ok=True)
    views = [
        ("front", (0.0, -0.34, 0.095), (0.0, 0.0, 0.056), 76.0),
        ("hero34", (0.22, -0.26, 0.165), (0.0, 0.0, 0.056), 74.0),
        ("top34", (0.14, -0.18, 0.265), (0.0, 0.0, 0.045), 72.0),
        ("side", (-0.34, 0.0, 0.095), (0.0, 0.0, 0.056), 76.0),
    ]
    paths = []
    for tag, loc, tgt, lens in views:
        p = tmp / f"{tag}.png"
        render_view(cam, loc, tgt, p, 640, 640, lens)
        paths.append(p)
    stitch_2x2(paths, PREVIEW_4ANGLE)
    render_view(cam, (0.16, -0.21, 0.135), (0.0, 0.0, 0.058), PREVIEW_CLOSEUP, 1024, 1024, 78.0)

    for p in paths:
        p.unlink(missing_ok=True)
    tmp.rmdir()
    print("TURKISH_TEA_BUILD_OK")


if __name__ == "__main__":
    main()
