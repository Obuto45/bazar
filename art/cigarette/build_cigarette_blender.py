#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for a realistic burning Turkish cigarette with
authentic layered cylindrical flaky ash that grows dynamically as you smoke.

Orientation matches Godot items.gd natively (export_yup=True maps Blender +Y -> Godot -Z):
  - CigFilter:   Blender y = -0.036 .. 0.000  (Godot z = +0.036 .. 0.000, cork filter + cotton butt)
  - CigPaper:    Blender y =  0.000 .. +0.088 (Godot z =  0.000 .. -0.088, ribbed paper, scales on burn)
  - CigTipGroup: Blender y = +0.088           (slides back as paper burns!)
      - Ember:   Glowing cracked red-orange tobacco burn collar right at the paper-to-ash line!
      - AshBody: Cylindrical rough flaky layered grey-charcoal ash pivoted at y=0 (scales cleanly as ash grows!)
"""

import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TEX_DIR = SCRIPT_DIR / "textures"
BLEND_PATH = SCRIPT_DIR / "cigarette.blend"
GLB_PATH = SCRIPT_DIR / "cigarette.glb"
PREVIEW_4ANGLE = SCRIPT_DIR / "preview_4angle.png"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"

R = 0.0072  # 14.4 mm diameter (~1.65x real scale for crisp 1st-person FPS readability)
FILTER_LEN = 0.036
PAPER_LEN = 0.088
BASE_ASH_LEN = 0.015  # default ash length at scale 1.0 (scales 0.28..2.2 in Godot!)


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


def build_uv_cylinder_y(name: str, y0: float, y1: float, radius: float, segs: int = 36, cap_start: bool = False, cap_end: bool = False) -> bpy.types.Object:
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    v_steps = 8
    grid = []
    for iv in range(v_steps + 1):
        vt = iv / v_steps
        y = y0 + (y1 - y0) * vt
        row = []
        for iu in range(segs + 1):
            a = (iu / segs) * math.tau
            row.append(bm.verts.new((math.cos(a) * radius, y, math.sin(a) * radius)))
        grid.append(row)

    for iv in range(v_steps):
        v0 = iv / v_steps
        v1 = (iv + 1) / v_steps
        for iu in range(segs):
            u0 = iu / segs
            u1 = (iu + 1) / segs
            f = bm.faces.new((grid[iv][iu], grid[iv][iu + 1], grid[iv + 1][iu + 1], grid[iv + 1][iu]))
            for loop, t_uv in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                loop[uv].uv = t_uv

    if cap_start:
        # Subtle recessed porous cotton butt ring
        vc = bm.verts.new((0.0, y0 + 0.0008, 0.0))
        for iu in range(segs):
            f = bm.faces.new((grid[0][iu + 1], grid[0][iu], vc))
            for loop in f.loops:
                loop[uv].uv = (0.5, 0.12)
    if cap_end:
        vc = bm.verts.new((0.0, y1, 0.0))
        for iu in range(segs):
            f = bm.faces.new((grid[-1][iu], grid[-1][iu + 1], vc))
            for loop in f.loops:
                loop[uv].uv = (0.5, 0.95)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    set_smooth(obj)
    return obj


def build_ember_collar() -> bpy.types.Object:
    """Glowing uneven red-orange tobacco ember collar right where paper burns into ash."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rng = random.Random(303)
    segs = 36
    v_steps = 5
    grid = []
    for iv in range(v_steps + 1):
        vt = iv / v_steps
        y = -0.0010 + vt * 0.0055
        # Slight bulge right at burn line, narrowing slightly into ash
        r_base = R * (0.995 - 0.03 * vt)
        row = []
        for iu in range(segs + 1):
            a = (iu / segs) * math.tau
            # Organic jagged burn wave around circumference
            wave = math.sin(a * 5.0 + 0.4) * 0.0006 + math.cos(a * 9.0) * 0.00035
            rj = r_base + (rng.uniform(-0.00022, 0.00022) if iu < segs else 0.0)
            row.append(bm.verts.new((math.cos(a) * rj, y + wave * (1.0 - vt * 0.4), math.sin(a) * rj)))
        # Stitch seam identically
        row[-1].co = row[0].co.copy()
        grid.append(row)

    for iv in range(v_steps):
        v0 = iv / v_steps
        v1 = (iv + 1) / v_steps
        for iu in range(segs):
            u0 = iu / segs
            u1 = (iu + 1) / segs
            f = bm.faces.new((grid[iv][iu], grid[iv][iu + 1], grid[iv + 1][iu + 1], grid[iv + 1][iu]))
            for loop, t_uv in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                loop[uv].uv = t_uv

    # Close both ends so manifold normals point cleanly outward
    vb = bm.verts.new((0.0, -0.0010, 0.0))
    vt_c = bm.verts.new((0.0, 0.0052, 0.0))
    for iu in range(segs):
        f0 = bm.faces.new((grid[0][iu + 1], grid[0][iu], vb))
        f1 = bm.faces.new((grid[-1][iu], grid[-1][iu + 1], vt_c))
        for f in (f0, f1):
            for loop in f.loops:
                loop[uv].uv = (0.5, 0.5)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Ember")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Ember", mesh)
    set_smooth(obj)
    return obj


def build_realistic_flaky_ash() -> bpy.types.Object:
    """
    Authentic cylindrical rough, flaky, ring-layered cigarette ash column!
    Pivoted at y = 0.0 (just past ember collar) so scaling along Y (Godot Z)
    grows the ash naturally as you take puffs!
    """
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rng = random.Random(1969)
    segs = 36
    v_steps = 12

    grid = []
    for iv in range(v_steps + 1):
        vt = iv / v_steps
        y = 0.0022 + vt * BASE_ASH_LEN
        # Real cigarette ash stays nearly cylindrical (~92-95% of paper radius) with subtle flaky ripples and blunt rounded-flat tip!
        if vt < 0.86:
            # Stratified horizontal ash ridges + tiny organic droop as ash gets longer
            ridge = 0.00028 * math.sin(vt * math.tau * 4.5)
            r_base = R * (0.945 - 0.025 * vt) + ridge
            droop_z = -0.00055 * (vt * vt)
        else:
            # Blunt rough flaky tip closure
            k = (vt - 0.86) / 0.14
            r_base = R * (0.92 * (1.0 - 0.42 * k * k))
            droop_z = -0.00055 * (vt * vt)

        row = []
        for iu in range(segs + 1):
            a = (iu / segs) * math.tau
            jitter = rng.uniform(-0.00032, 0.00032) if (0 < iv < v_steps and iu < segs) else 0.0
            rj = max(0.001, r_base + jitter)
            yj = y + (rng.uniform(-0.00025, 0.00025) if (0 < iv < v_steps and iu < segs) else 0.0)
            row.append(bm.verts.new((math.cos(a) * rj, yj, math.sin(a) * rj + droop_z)))
        row[-1].co = row[0].co.copy()
        grid.append(row)

    for iv in range(v_steps):
        v0 = iv / v_steps
        v1 = (iv + 1) / v_steps
        for iu in range(segs):
            u0 = iu / segs
            u1 = (iu + 1) / segs
            f = bm.faces.new((grid[iv][iu], grid[iv][iu + 1], grid[iv + 1][iu + 1], grid[iv + 1][iu]))
            for loop, t_uv in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                loop[uv].uv = t_uv

    # Watertight back & uneven blunt front ash cap
    v_back = bm.verts.new((0.0, 0.0022, 0.0))
    v_tip = bm.verts.new((0.0, 0.0022 + BASE_ASH_LEN + 0.0008, -0.00055))
    for iu in range(segs):
        f0 = bm.faces.new((grid[0][iu + 1], grid[0][iu], v_back))
        f1 = bm.faces.new((grid[-1][iu], grid[-1][iu + 1], v_tip))
        for loop in f0.loops:
            loop[uv].uv = (0.5, 0.05)
        for loop in f1.loops:
            loop[uv].uv = (0.5, 0.92)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("AshBody")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("AshBody", mesh)
    # Keep flat-ish micro-facets on ash so it looks dry, rough and powdery!
    return obj


def make_img_mat(name: str, tex_path: Path, roughness: float = 0.78, emit_strength: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    bs = _bsdf(mat)
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(tex_path))
    img.pack()
    tex.image = img
    nt.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = roughness
    if emit_strength > 0.0 and "Emission Color" in bs.inputs:
        nt.links.new(tex.outputs["Color"], bs.inputs["Emission Color"])
        bs.inputs["Emission Strength"].default_value = emit_strength
    return mat


def build_cigarette():
    col = ensure_collection("Cigarette")
    root = bpy.data.objects.new("CigaretteRoot", None)
    link_obj(root, col)

    m_filter = make_img_mat("CigFilterMat", TEX_DIR / "filter_tex.png", roughness=0.68)
    m_paper = make_img_mat("CigPaperMat", TEX_DIR / "paper_tex.png", roughness=0.84)
    m_ash = make_img_mat("CigAshMat", TEX_DIR / "ash_tex.png", roughness=0.98)
    m_ember = make_img_mat("CigEmberMat", TEX_DIR / "ember_tex.png", roughness=0.88, emit_strength=3.4)

    # 1. Cork Filter (y = -FILTER_LEN .. 0)
    flt = build_uv_cylinder_y("CigFilter", -FILTER_LEN, 0.0, R * 1.012, segs=36, cap_start=True)
    flt.data.materials.append(m_filter)
    flt.parent = root
    link_obj(flt, col)

    # 2. Ribbed White Paper (y = 0 .. PAPER_LEN)
    pap = build_uv_cylinder_y("CigPaper", 0.0, PAPER_LEN, R, segs=36, cap_end=False)
    pap.data.materials.append(m_paper)
    pap.parent = root
    link_obj(pap, col)

    # 3. Tip Group (Ember collar at burn line + Cylindrical Flaky AshBody extending forward)
    tip_grp = bpy.data.objects.new("CigTipGroup", None)
    tip_grp.location = (0.0, PAPER_LEN, 0.0)
    tip_grp.parent = root
    link_obj(tip_grp, col)

    emb = build_ember_collar()
    emb.data.materials.append(m_ember)
    emb.parent = tip_grp
    link_obj(emb, col)

    ash = build_realistic_flaky_ash()
    ash.data.materials.append(m_ash)
    ash.parent = tip_grp
    link_obj(ash, col)

    return root, col, ash


def setup_studio():
    col = ensure_collection("Studio")
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.05

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.035, 0.038, 0.048, 1.0)
    bg.inputs["Strength"].default_value = 0.50

    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.22, depth=0.01, location=(0.0, 0.03, -R - 0.0055))
    floor = bpy.context.active_object
    fmat = bpy.data.materials.new("SlateFloor")
    fb = _bsdf(fmat)
    fb.inputs["Base Color"].default_value = (0.065, 0.068, 0.082, 1.0)
    fb.inputs["Roughness"].default_value = 0.45
    floor.data.materials.append(fmat)
    link_obj(floor, col)

    lights = [
        ("Key", "AREA", (0.18, -0.10, 0.22), (0.0, 0.04, 0.0), 4.0, (1.0, 0.96, 0.90), 0.22),
        ("Fill", "AREA", (-0.22, 0.14, 0.16), (0.0, 0.04, 0.0), 2.2, (0.80, 0.88, 1.0), 0.26),
        ("Rim", "AREA", (0.04, 0.22, 0.10), (0.0, 0.09, 0.0), 2.8, (1.0, 0.58, 0.24), 0.14),
    ]
    for lname, ltype, loc, tgt, energy, color, sz in lights:
        ld = bpy.data.lights.new(lname, type=ltype)
        ld.energy = energy; ld.color = color; ld.size = sz
        lo = bpy.data.objects.new(lname, ld)
        lo.location = Vector(loc)
        lo.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        link_obj(lo, col)

    cd = bpy.data.cameras.new("Cam")
    cd.clip_start = 0.004
    cam = bpy.data.objects.new("Cam", cd)
    link_obj(cam, col)
    scene.camera = cam
    return cam


def render_view(cam, loc, tgt, out_path: Path, rx: int, ry: int, lens: float = 82.0):
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
    _, col, ash = build_cigarette()

    # Export clean GLB at default scale (1.0)
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
    # 4 angles: full side, hero 3/4, close-up of short ash, close-up of LONG grown ash (scale.y = 1.9)!
    paths = []
    p0 = tmp / "side.png"
    render_view(cam, (0.31, 0.036, 0.042), (0.0, 0.036, 0.0), p0, 640, 480, 74.0)
    paths.append(p0)

    p1 = tmp / "hero34.png"
    render_view(cam, (0.20, 0.16, 0.075), (0.0, 0.042, 0.0), p1, 640, 480, 74.0)
    paths.append(p1)

    p2 = tmp / "ash_short.png"
    ash.scale.y = 0.65
    render_view(cam, (0.068, 0.135, 0.028), (0.0, 0.092, 0.0), p2, 640, 480, 82.0)
    paths.append(p2)

    p3 = tmp / "ash_long.png"
    ash.scale.y = 1.95
    render_view(cam, (0.088, 0.165, 0.034), (0.0, 0.102, 0.0), p3, 640, 480, 82.0)
    paths.append(p3)

    stitch_2x2(paths, PREVIEW_4ANGLE)

    ash.scale.y = 1.35
    render_view(cam, (0.145, 0.165, 0.056), (0.0, 0.072, 0.0), PREVIEW_CLOSEUP, 1024, 768, 78.0)

    for p in paths:
        p.unlink(missing_ok=True)
    tmp.rmdir()
    print("REALISTIC_CIG_BUILD_OK")


if __name__ == "__main__":
    main()
