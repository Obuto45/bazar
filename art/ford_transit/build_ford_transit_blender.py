#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for a detailed, game-ready
Ford Transit MK7 (2006-2013) 350L Single-Cab Flatbed Kamyonet
("GARDASLAR SEBZE MEYVE") for Godot 4.7.

Run headless:
    blender --background --python art/ford_transit/build_ford_transit_blender.py

Outputs:
  - art/ford_transit/ford_transit.blend             (editable multi-collection Blender project)
  - art/ford_transit/preview_renders.png            (4-angle EEVEE studio turntable sheet)
  - art/ford_transit/preview_front_closeup.png      (hero front 3/4 closeup)
  - models/ford_transit/ford_transit_complete.glb   (FordTransitBody + Wheel_FL/FR/RL/RR)
  - models/ford_transit/ford_transit_chassis.glb    (body only for VehicleBody3D)
  - models/ford_transit/wheel_front.glb             (single front commercial wheel)
  - models/ford_transit/wheel_rear.glb              (heavy dually rear wheel)
"""

import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector
import numpy as np


# =============================================================================
# PATHS & VEHICLE DIMENSIONS (Ford Transit MK7 350L Long-Wheelbase Single Cab)
# =============================================================================
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
MODELS_DIR = REPO_ROOT / "models" / "ford_transit"
BANNER_PATH = SCRIPT_DIR / "rear_banner.png"
BLEND_PATH = SCRIPT_DIR / "ford_transit.blend"
PREVIEW_SHEET_PATH = SCRIPT_DIR / "preview_renders.png"
PREVIEW_HERO_PATH = SCRIPT_DIR / "preview_front_closeup.png"
TEX_DIR = SCRIPT_DIR / "textures"

WHEEL_RADIUS = 0.37
FRONT_Z = 1.82
REAR_Z = -1.78
FRONT_X = 0.86
REAR_X = 0.82


def G(x: float, y: float, z: float) -> Vector:
    """Convert Godot vehicle coords (x=Left, y=Up, z=Forward) -> Blender Z-up (x, -z, y)."""
    return Vector((x, -z, y))


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


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# =============================================================================
# ANTI-ALIASED PROCEDURAL TEXTURES (Ford Blue Oval Badge + Turkish 34 GRD 45 Plate)
# =============================================================================
def draw_thick_segment(arr, x0, y0, x1, y1, radius, color):
    """Draw anti-aliased rounded capsule segment into RGBA float32 numpy array."""
    h, w, _ = arr.shape
    minx = max(0, int(math.floor(min(x0, x1) - radius - 2)))
    maxx = min(w - 1, int(math.ceil(max(x0, x1) + radius + 2)))
    miny = max(0, int(math.floor(min(y0, y1) - radius - 2)))
    maxy = min(h - 1, int(math.ceil(max(y0, y1) + radius + 2)))
    if minx > maxx or miny > maxy:
        return
    yy, xx = np.mgrid[miny:maxy + 1, minx:maxx + 1].astype(np.float32)
    dx = x1 - x0
    dy = y1 - y0
    l2 = dx * dx + dy * dy
    if l2 < 1e-6:
        dist = np.sqrt((xx - x0) ** 2 + (yy - y0) ** 2)
    else:
        t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / l2, 0.0, 1.0)
        px = x0 + t * dx
        py = y0 + t * dy
        dist = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
    alpha = np.clip(radius + 0.8 - dist, 0.0, 1.0)
    sub = arr[miny:maxy + 1, minx:maxx + 1]
    col = np.array(color, dtype=np.float32)
    for c in range(3):
        sub[:, :, c] = sub[:, :, c] * (1.0 - alpha) + col[c] * alpha


# Crisp vector stroke glyphs in normalized (0..1, 0..1) box (Y=0 bottom, Y=1 top)
VECTOR_GLYPHS = {
    "3": [((0.1, 0.9), (0.85, 0.9)), ((0.85, 0.9), (0.85, 0.52)), ((0.25, 0.52), (0.85, 0.52)),
          ((0.85, 0.52), (0.85, 0.1)), ((0.1, 0.1), (0.85, 0.1))],
    "4": [((0.72, 0.08), (0.72, 0.92)), ((0.72, 0.92), (0.10, 0.36)), ((0.10, 0.36), (0.92, 0.36))],
    "5": [((0.85, 0.9), (0.15, 0.9)), ((0.15, 0.9), (0.15, 0.52)), ((0.15, 0.52), (0.80, 0.52)),
          ((0.80, 0.52), (0.88, 0.40)), ((0.88, 0.40), (0.88, 0.18)), ((0.88, 0.18), (0.75, 0.08)),
          ((0.75, 0.08), (0.12, 0.08))],
    "G": [((0.85, 0.82), (0.72, 0.92)), ((0.72, 0.92), (0.26, 0.92)), ((0.26, 0.92), (0.12, 0.76)),
          ((0.12, 0.76), (0.12, 0.24)), ((0.12, 0.24), (0.26, 0.08)), ((0.26, 0.08), (0.76, 0.08)),
          ((0.76, 0.08), (0.88, 0.22)), ((0.88, 0.22), (0.88, 0.48)), ((0.50, 0.48), (0.88, 0.48))],
    "R": [((0.15, 0.08), (0.15, 0.92)), ((0.15, 0.92), (0.72, 0.92)), ((0.72, 0.92), (0.86, 0.78)),
          ((0.86, 0.78), (0.86, 0.60)), ((0.86, 0.60), (0.72, 0.48)), ((0.72, 0.48), (0.15, 0.48)),
          ((0.52, 0.48), (0.88, 0.08))],
    "D": [((0.15, 0.08), (0.15, 0.92)), ((0.15, 0.92), (0.64, 0.92)), ((0.64, 0.92), (0.86, 0.74)),
          ((0.86, 0.74), (0.86, 0.26)), ((0.86, 0.26), (0.64, 0.08)), ((0.64, 0.08), (0.15, 0.08))],
    "T": [((0.08, 0.90), (0.92, 0.90)), ((0.50, 0.90), (0.50, 0.08))],
    "F": [((0.16, 0.10), (0.34, 0.92)), ((0.22, 0.92), (0.94, 0.92)), ((0.24, 0.52), (0.74, 0.52))],
    "o": [((0.35, 0.58), (0.70, 0.58)), ((0.70, 0.58), (0.82, 0.42)), ((0.82, 0.42), (0.72, 0.14)),
          ((0.72, 0.14), (0.32, 0.14)), ((0.32, 0.14), (0.20, 0.32)), ((0.20, 0.32), (0.35, 0.58))],
    "r": [((0.20, 0.12), (0.32, 0.58)), ((0.32, 0.46), (0.56, 0.58)), ((0.56, 0.58), (0.82, 0.52))],
    "d": [((0.72, 0.12), (0.88, 0.94)), ((0.74, 0.52), (0.42, 0.56)), ((0.42, 0.56), (0.20, 0.36)),
          ((0.20, 0.36), (0.26, 0.14)), ((0.26, 0.14), (0.64, 0.14)), ((0.64, 0.14), (0.74, 0.26))],
    " ": [],
}


def draw_vector_text(arr, text, x0, y0, cw, ch, stroke_r, color, gap=0.22):
    cx = float(x0)
    for ch_sym in text:
        segs = VECTOR_GLYPHS.get(ch_sym, [])
        for (a, b) in segs:
            draw_thick_segment(arr, cx + a[0] * cw, y0 + a[1] * ch, cx + b[0] * cw, y0 + b[1] * ch, stroke_r, color)
        cx += cw * (0.55 if ch_sym == " " else (1.0 + gap))


def save_np_image(name: str, arr_rgba: np.ndarray, filepath: Path):
    h, w, _ = arr_rgba.shape
    img = bpy.data.images.new(name=name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(arr_rgba.astype(np.float32).ravel())
    img.filepath_raw = str(filepath)
    img.file_format = "PNG"
    filepath.parent.mkdir(parents=True, exist_ok=True)
    img.save()
    img.pack()
    return img


def make_plate_texture():
    w, h = 640, 144
    arr = np.ones((h, w, 4), dtype=np.float32)
    arr[:, :, 0:3] = [0.95, 0.96, 0.97]
    # Crisp embossed black outer border
    arr[0:7, :, 0:3] = 0.05
    arr[h - 7:h, :, 0:3] = 0.05
    arr[:, 0:7, 0:3] = 0.05
    arr[:, w - 7:w, 0:3] = 0.05
    # Authentic Turkish Blue TR band on left
    arr[7:h - 7, 7:82, 0:3] = [0.03, 0.16, 0.56]
    draw_vector_text(arr, "TR", 18, 22, 22, 46, 3.6, [0.97, 0.98, 0.99], gap=0.25)
    # Crisp anti-aliased FE-Schrift-style Turkish plate lettering "34 GRD 45"
    draw_vector_text(arr, "34 GRD 45", 104, 24, 48, 96, 6.2, [0.04, 0.04, 0.05], gap=0.24)
    return save_np_image("TRPlateTex", arr, TEX_DIR / "plate_tr.png")


# =============================================================================
# PBR MATERIALS CATALOG (Blender 5.3 native node_tree without deprecated use_nodes)
# =============================================================================
def build_materials():
    mats = {}

    def make_pbr(name, color, metallic=0.0, roughness=0.5, coat=0.0, coat_rough=0.1,
                 emission=None, emission_strength=0.0, alpha=1.0, ior=1.45, tex_img=None):
        mat = bpy.data.materials.new(name=name)
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["IOR"].default_value = ior
        if "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = coat
            bsdf.inputs["Coat Roughness"].default_value = coat_rough
        if emission is not None and emission_strength > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        if alpha < 1.0:
            bsdf.inputs["Alpha"].default_value = alpha
            if hasattr(mat, "blend_method"):
                mat.blend_method = "BLEND"
        if tex_img is not None:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = tex_img
            tex.extension = "CLIP"
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        mats[name] = mat
        return mat

    # Classic Turkish Ford Transit Frozen White gloss clearcoat paint
    make_pbr("TransitWhite", (0.93, 0.935, 0.945), metallic=0.03, roughness=0.20, coat=0.88, coat_rough=0.07)
    # Recessed dark panel shut lines
    make_pbr("PanelSeam", (0.06, 0.065, 0.075), metallic=0.0, roughness=0.85)
    # Textured satin-matte charcoal ABS plastic (MK7 bumper, wheel arch flares, rub strips, mirrors)
    make_pbr("BumperPlastic", (0.088, 0.095, 0.105), metallic=0.02, roughness=0.68)
    # Titanium-graphite satin plastic for MK7 twin grille crossbars
    make_pbr("GrilleBarGrey", (0.21, 0.225, 0.248), metallic=0.22, roughness=0.40)
    # Deep matte-black honeycomb backing behind grille
    make_pbr("GrilleMeshDark", (0.028, 0.030, 0.035), metallic=0.06, roughness=0.82)
    # Heavy chassis ladder frame & axles
    make_pbr("ChassisSteel", (0.070, 0.075, 0.082), metallic=0.45, roughness=0.60)
    # Exhaust pipe aluminized steel
    make_pbr("ExhaustSteel", (0.48, 0.45, 0.41), metallic=0.78, roughness=0.46)
    # Galvanized steel (cargo posts, latches, hinges, side cyclist bars, rear banner frame)
    make_pbr("GalvSteel", (0.64, 0.67, 0.70), metallic=0.64, roughness=0.36)
    # Industrial dark steel-grey painted cargo cage tubing
    make_pbr("CageSteel", (0.24, 0.28, 0.33), metallic=0.52, roughness=0.40)
    # Ribbed aluminum/silver-white drop-side boards
    make_pbr("AluminumDropside", (0.83, 0.85, 0.87), metallic=0.38, roughness=0.30, coat=0.25, coat_rough=0.20)
    # Anti-slip phenolic deck floor
    make_pbr("BedDeckFloor", (0.18, 0.15, 0.13), metallic=0.08, roughness=0.85)
    # Mirror-bright chrome (headlight parabolic reflectors, Ford badge ring, fog bezels, lug nuts)
    make_pbr("Chrome", (0.90, 0.92, 0.95), metallic=0.98, roughness=0.07)
    # Mirror glass
    make_pbr("MirrorGlass", (0.78, 0.83, 0.87), metallic=0.96, roughness=0.04)
    # Dark-tinted automotive cab glass — rich dark automotive tint while interior seats & wheel stay readable!
    make_pbr("CabGlass", (0.018, 0.040, 0.058), metallic=0.08, roughness=0.04, coat=1.0, coat_rough=0.02, alpha=0.58, ior=1.52)
    # Black rubber seals, wipers, mudflaps
    make_pbr("RubberBlack", (0.040, 0.042, 0.046), metallic=0.0, roughness=0.86)
    # Dark charcoal interior headliner, dash, A/B pillars, floor
    make_pbr("InteriorDark", (0.055, 0.058, 0.065), metallic=0.0, roughness=0.88)
    make_pbr("SeatFabric", (0.17, 0.195, 0.23), metallic=0.0, roughness=0.92)
    # Rolled cobalt-blue tarpaulin strapped on cab-over rack
    make_pbr("TarpBlue", (0.06, 0.27, 0.64), metallic=0.0, roughness=0.56)

    # IMPORTANT: Exact material names expected by wholesaler.gd!
    # `HeadlightGlass` goes on the glowing H4/fog emitter bulbs inside the chrome reflector bowls;
    # `HeadlightLensClear` is the crystal-clear outer curved polycarbonate lens covering the cluster!
    make_pbr("HeadlightGlass", (1.0, 0.96, 0.84), metallic=0.10, roughness=0.12,
             emission=(1.0, 0.95, 0.78), emission_strength=2.0)
    hl_clear = make_pbr("HeadlightLensClear", (0.98, 0.99, 1.0), metallic=0.0, roughness=0.03,
                        coat=0.25, coat_rough=0.03, alpha=0.07, ior=1.15)
    bsdf_hl = hl_clear.node_tree.nodes.get("Principled BSDF")
    if "Specular IOR Level" in bsdf_hl.inputs:
        bsdf_hl.inputs["Specular IOR Level"].default_value = 0.22
    make_pbr("AmberIndicator", (0.95, 0.26, 0.002), metallic=0.04, roughness=0.20, coat=0.80,
             emission=(0.95, 0.26, 0.002), emission_strength=0.10)
    make_pbr("TailLightRed", (0.85, 0.03, 0.03), metallic=0.05, roughness=0.15, coat=0.85,
             emission=(0.75, 0.02, 0.02), emission_strength=0.55)
    make_pbr("ReverseWhite", (0.94, 0.95, 0.96), metallic=0.05, roughness=0.16, coat=0.7)

    # Commercial Tires & Ford Transit 6-Lug Steel Wheels
    make_pbr("TireRubber", (0.050, 0.053, 0.058), metallic=0.0, roughness=0.84)
    make_pbr("RimSilver", (0.74, 0.76, 0.79), metallic=0.78, roughness=0.26)
    make_pbr("WheelHubDark", (0.09, 0.10, 0.11), metallic=0.35, roughness=0.56)

    # Pure matte-black signboard backing seamlessly matching rear_banner.png black backdrop
    make_pbr("BannerBackingBlack", (0.004, 0.004, 0.005), metallic=0.0, roughness=0.65, coat=0.02)

    plate_img = make_plate_texture()
    make_pbr("LicensePlateTR", (1.0, 1.0, 1.0), metallic=0.12, roughness=0.36, tex_img=plate_img)

    banner_img = None
    if BANNER_PATH.exists():
        banner_img = bpy.data.images.load(str(BANNER_PATH))
        banner_img.pack()
    make_pbr("RearBannerDecal", (1.0, 1.0, 1.0), metallic=0.0, roughness=0.65, coat=0.02, tex_img=banner_img)

    # Classic Turkish windshield top sunstrip ("MASALLAH" + twin Nazar Boncugu!)
    masallah_path = TEX_DIR / "masallah_strip.png"
    masallah_img = None
    if masallah_path.exists():
        masallah_img = bpy.data.images.load(str(masallah_path))
        masallah_img.pack()
    make_pbr("WindshieldMasallah", (1.0, 1.0, 1.0), metallic=0.05, roughness=0.22, coat=0.65, tex_img=masallah_img)

    # Colorful Turkish Hal Plastic Crates & Produce Mounds
    make_pbr("CrateRed", (0.82, 0.11, 0.10), roughness=0.46)
    make_pbr("CrateGreen", (0.10, 0.56, 0.20), roughness=0.46)
    make_pbr("CrateBlue", (0.09, 0.36, 0.78), roughness=0.46)
    make_pbr("CrateYellow", (0.92, 0.72, 0.08), roughness=0.46)
    make_pbr("CrateOrange", (0.92, 0.42, 0.06), roughness=0.46)

    make_pbr("FruitTomato", (0.86, 0.10, 0.07), roughness=0.26, coat=0.4)
    make_pbr("FruitWatermelon", (0.10, 0.38, 0.12), roughness=0.34, coat=0.3)
    make_pbr("FruitOrange", (0.95, 0.44, 0.04), roughness=0.44)
    make_pbr("FruitLemon", (0.96, 0.84, 0.08), roughness=0.38)
    make_pbr("FruitEggplant", (0.24, 0.05, 0.30), roughness=0.22, coat=0.65)
    make_pbr("FruitApple", (0.74, 0.08, 0.09), roughness=0.28, coat=0.45)
    make_pbr("FruitOnion", (0.76, 0.54, 0.24), roughness=0.58)

    return mats


# =============================================================================
# GEOMETRY UTILITIES
# =============================================================================
def finalize_mesh_obj(name: str, bm: bmesh.types.BMesh, mat, col, smooth=True,
                      edge_split_deg=None, bevel_width=0.0, bevel_segs=2, subsurf=0, mirror_x=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    link_obj(obj, col)

    if isinstance(mat, list):
        for m in mat:
            mesh.materials.append(m)
    elif mat is not None:
        mesh.materials.append(mat)

    mesh.polygons.foreach_set("use_smooth", [bool(smooth)] * len(mesh.polygons))

    if mirror_x:
        mod = obj.modifiers.new("Mirror", "MIRROR")
        mod.use_axis = (True, False, False)
        mod.use_clip = True
        mod.merge_threshold = 0.002

    if bevel_width > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel_width
        mod.segments = bevel_segs
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(32.0)

    if subsurf > 0:
        mod = obj.modifiers.new("Subsurf", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf

    if edge_split_deg is not None and smooth:
        mod = obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
        mod.use_edge_angle = True
        mod.split_angle = math.radians(edge_split_deg)
        mod.use_edge_sharp = True

    mesh.update()
    return obj


def bm_add_box_g(bm: bmesh.types.BMesh, x0, x1, y0, y1, z0, z1, mat_idx=0):
    if x0 > x1:
        x0, x1 = x1, x0
    if y0 > y1:
        y0, y1 = y1, y0
    if z0 > z1:
        z0, z1 = z1, z0
    cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
    mat_t = Matrix.Translation(G(cx, cy, cz)) @ Matrix.Diagonal((sx, sz, sy, 1.0))
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=mat_t)
    verts = set(ret["verts"])
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx
    return ret["verts"]


def bm_add_cyl_x_g(bm, x0, x1, y, z, r, segs=24, mat_idx=0, cap=True):
    cx = (x0 + x1) * 0.5
    length = abs(x1 - x0)
    rot = Matrix.Rotation(math.pi * 0.5, 4, "Y")
    mat_t = Matrix.Translation(G(cx, y, z)) @ rot
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False, segments=segs,
        radius1=r, radius2=r, depth=length, matrix=mat_t
    )
    verts = set(ret["verts"])
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx
    return ret["verts"]


def bm_add_cyl_y_g(bm, x, y0, y1, z, r, segs=16, mat_idx=0, cap=True):
    cy = (y0 + y1) * 0.5
    length = abs(y1 - y0)
    mat_t = Matrix.Translation(G(x, cy, z))
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False, segments=segs,
        radius1=r, radius2=r, depth=length, matrix=mat_t
    )
    verts = set(ret["verts"])
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx
    return ret["verts"]


def bm_add_cyl_z_g(bm, x, y, z0, z1, r, segs=16, mat_idx=0, cap=True):
    cz = (z0 + z1) * 0.5
    length = abs(z1 - z0)
    rot = Matrix.Rotation(math.pi * 0.5, 4, "X")
    mat_t = Matrix.Translation(G(x, y, cz)) @ rot
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False, segments=segs,
        radius1=r, radius2=r, depth=length, matrix=mat_t
    )
    verts = set(ret["verts"])
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx
    return ret["verts"]


def bm_add_cone_z_g(bm, x, y, z0, z1, r0, r1, segs=20, mat_idx=0, cap=True):
    """Tapered frustum/parabolic cone along Godot +Z (great for headlight reflectors!)."""
    cz = (z0 + z1) * 0.5
    length = abs(z1 - z0)
    rot = Matrix.Rotation(math.pi * 0.5, 4, "X")
    mat_t = Matrix.Translation(G(x, y, cz)) @ rot
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False, segments=segs,
        radius1=r1, radius2=r0, depth=length, matrix=mat_t
    )
    verts = set(ret["verts"])
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx
    return ret["verts"]


def bm_add_tube_g(bm, p0, p1, r, segs=12, mat_idx=0, cap=True):
    b0 = G(*p0)
    b1 = G(*p1)
    dv = b1 - b0
    length = dv.length
    if length < 1e-6:
        return []
    mid = (b0 + b1) * 0.5
    quat = Vector((0, 0, 1)).rotation_difference(dv.normalized())
    mat_t = Matrix.Translation(mid) @ quat.to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False, segments=segs,
        radius1=r, radius2=r, depth=length, matrix=mat_t
    )
    verts = set(ret["verts"])
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx
    return ret["verts"]


def bm_add_prism_x_g(bm, x0, x1, yz_loop, mat_idx=0):
    """Extrude 2D (y, z) polygon along X from x0 to x1 (for boolean window cutters, etc.)."""
    if x0 > x1:
        x0, x1 = x1, x0
    v0s = [bm.verts.new(G(x0, y, z)) for (y, z) in yz_loop]
    v1s = [bm.verts.new(G(x1, y, z)) for (y, z) in yz_loop]
    n = len(yz_loop)
    for i in range(n):
        in_ = (i + 1) % n
        f = bm.faces.new((v0s[i], v1s[i], v1s[in_], v0s[in_]))
        f.material_index = mat_idx
    f0 = bm.faces.new(list(reversed(v0s)))
    f0.material_index = mat_idx
    f1 = bm.faces.new(v1s)
    f1.material_index = mat_idx


def bm_add_lathe_x_g(bm, profile_xr, y_center, z_center, segs=32, mat_idx=0, closed_profile=False):
    rings = []
    for x_val, rad in profile_xr:
        ring = []
        for i in range(segs):
            ang = 2.0 * math.pi * i / segs
            y = y_center + rad * math.sin(ang)
            z = z_center + rad * math.cos(ang)
            ring.append(bm.verts.new(G(x_val, y, z)))
        rings.append(ring)

    n_rings = len(rings)
    end = n_rings if closed_profile else n_rings - 1
    for r_i in range(end):
        r0 = rings[r_i]
        r1 = rings[(r_i + 1) % n_rings]
        for i in range(segs):
            i_next = (i + 1) % segs
            try:
                f = bm.faces.new((r0[i], r1[i], r1[i_next], r0[i_next]))
                f.material_index = mat_idx
            except ValueError:
                pass
    return rings


def make_uv_quad_obj(name, p0, p1, p2, p3, mat, col, uvs=None):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    vs = [bm.verts.new(G(*p)) for p in (p0, p1, p2, p3)]
    f = bm.faces.new(vs)
    if uvs is None:
        uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    for loop, uv in zip(f.loops, uvs):
        loop[uv_layer].uv = uv
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link_obj(obj, col)
    mesh.materials.append(mat)
    mesh.update()
    return obj


# =============================================================================
# 1. FORD TRANSIT MK7 SCULPTED CAB SHELL (Smooth Oval Nose + Hollowed Windows!)
# =============================================================================
def cab_nose_z_offset(x_norm: float) -> float:
    """Smooth elliptical/oval plan-view nose sweep (rounded center bulge & graceful cheeks)."""
    return -0.105 * (x_norm ** 2) - 0.145 * (x_norm ** 4)


def cab_half_width(y: float, z: float) -> float:
    """Authentic Transit MK7 cab cross-section width with smooth oval nose taper & tumblehome."""
    if y <= 0.48:
        w = 0.920
    elif y <= 0.78:
        t = (y - 0.48) / 0.30
        w = 0.920 + 0.065 * math.sin(t * math.pi * 0.5)
    elif y <= 1.28:
        t = (y - 0.78) / 0.50
        w = 0.985 - 0.022 * t
    elif y <= 1.42:
        t = (y - 1.28) / 0.14
        w = 0.963 - 0.028 * t
    elif y <= 2.04:
        t = (y - 1.42) / 0.62
        w = 0.935 - 0.140 * (t ** 1.12)
    else:
        t = min(1.0, (y - 2.04) / 0.12)
        w = 0.795 - 0.060 * t

    # Stronger smooth oval plan-view width taper toward the rounded front nose!
    if z > 2.05:
        tz = min(1.0, (z - 2.05) / 0.92)
        w -= 0.090 * (tz ** 1.6)
    return w


def build_mk7_cab(mats, cols):
    col_cab = cols["01_Cab"]
    col_fascia = cols["02_FrontFascia"]
    col_glass = cols["03_Windows_Interior"]

    # -------------------------------------------------------------------------
    # A. MAIN SCULPTED CAB BODY SHELL (Oval Rounded Front + Level-2 Subsurf!)
    # -------------------------------------------------------------------------
    u_steps = [-1.0, -0.97, -0.91, -0.82, -0.70, -0.55, -0.38, -0.20, 0.0, 0.20, 0.38, 0.55, 0.70, 0.82, 0.91, 0.97, 1.0]
    profile = [
        # (y,     z,     nose_w, crown_w, hood_w)
        (0.44,  0.76,  0.00,   0.00,    0.00),  # 0  Rear bottom corner
        (0.84,  0.76,  0.00,   0.00,    0.00),  # 1  Rear mid lower
        (1.30,  0.77,  0.00,   0.00,    0.00),  # 2  Rear beltline
        (1.76,  0.80,  0.00,   0.00,    0.00),  # 3  Rear upper cab
        (2.03,  0.85,  0.00,   0.85,    0.00),  # 4  Rear roof header
        (2.08,  1.06,  0.05,   1.00,    0.00),  # 5  Roof mid-rear
        (2.07,  1.34,  0.18,   1.00,    0.00),  # 6  Roof mid-front
        (2.00,  1.58,  0.42,   0.72,    0.00),  # 7  Rounded windshield header brow
        (1.72,  1.88,  0.52,   0.18,    0.00),  # 8  Curved panoramic windshield mid
        (1.42,  2.17,  0.58,   0.00,    0.00),  # 9  Windshield cowl base
        (1.37,  2.32,  0.68,   0.00,    0.85),  # 10 Rounded hood rear
        (1.30,  2.58,  0.84,   0.00,    1.00),  # 11 Rounded arched hood mid
        (1.23,  2.80,  0.96,   0.00,    0.72),  # 12 Soft rounded hood-to-nose roll top
        (1.16,  2.89,  1.00,   0.00,    0.25),  # 13 Smooth oval nose shoulder!
        (0.98,  2.93,  1.00,   0.00,    0.00),  # 14 Upper oval grille/headlight fascia center
        (0.78,  2.92,  1.00,   0.00,    0.00),  # 15 Bumper top shelf seam
        (0.46,  2.76,  0.85,   0.00,    0.00),  # 16 Lower nose behind bumper
        (0.44,  2.30,  0.10,   0.00,    0.00),  # 17 Underbody front
        (0.44,  1.50,  0.00,   0.00,    0.00),  # 18 Underbody mid
    ]

    bm_cab = bmesh.new()
    grid = []
    for u in u_steps:
        au = abs(u)
        ring = []
        for (yb, zb, nw, cw, hw) in profile:
            hw_max = cab_half_width(yb, zb)
            x = hw_max * u
            # Smooth rounded roof crown + smooth arched bonnet
            y = yb + cw * 0.092 * (1.0 - au ** 2.0)
            if hw > 0.0:
                bonnet_arch = 0.044 * (1.0 - au ** 1.85)
                crease = 0.010 * math.exp(-((au - 0.56) / 0.13) ** 2)
                y += hw * (bonnet_arch + crease)
            if au > 0.85 and yb > 1.15:
                edge_t = (au - 0.85) / 0.15
                y -= 0.024 * (edge_t ** 2) * max(cw, hw, 0.35)
            z = zb + nw * cab_nose_z_offset(au)
            ring.append(bm_cab.verts.new(G(x, y, z)))
        grid.append(ring)

    n_u, n_p = len(u_steps), len(profile)
    for ui in range(n_u - 1):
        for pi in range(n_p):
            pi_n = (pi + 1) % n_p
            bm_cab.faces.new((grid[ui][pi], grid[ui + 1][pi], grid[ui + 1][pi_n], grid[ui][pi_n]))

    cy_s, cz_s = 1.18, 1.62
    for (ring_end, sx) in [(grid[0], -1.0), (grid[-1], +1.0)]:
        mid_ring = []
        for (yb, zb, nw, cw, hw) in profile:
            ym = yb * 0.55 + cy_s * 0.45
            zm = (zb + nw * cab_nose_z_offset(1.0)) * 0.55 + cz_s * 0.45
            xm = sx * (cab_half_width(ym, zm) + 0.016)
            mid_ring.append(bm_cab.verts.new(G(xm, ym, zm)))
        center_v = bm_cab.verts.new(G(sx * (cab_half_width(cy_s, cz_s) + 0.020), cy_s, cz_s))
        for pi in range(n_p):
            pi_n = (pi + 1) % n_p
            if sx > 0:
                bm_cab.faces.new((ring_end[pi], mid_ring[pi], mid_ring[pi_n], ring_end[pi_n]))
                bm_cab.faces.new((mid_ring[pi], center_v, mid_ring[pi_n]))
            else:
                bm_cab.faces.new((ring_end[pi_n], mid_ring[pi_n], mid_ring[pi], ring_end[pi]))
                bm_cab.faces.new((mid_ring[pi_n], center_v, mid_ring[pi]))

    bmesh.ops.remove_doubles(bm_cab, verts=bm_cab.verts, dist=0.001)
    bmesh.ops.recalc_face_normals(bm_cab, faces=bm_cab.faces)

    cab_obj = finalize_mesh_obj(
        "MK7_CabShell", bm_cab, [mats["TransitWhite"], mats["InteriorDark"]], col_cab,
        smooth=True, subsurf=2, mirror_x=False
    )

    bpy.context.view_layer.objects.active = cab_obj
    for mod in list(cab_obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"CAB_BASE_POLYS={len(cab_obj.data.polygons)}")

    # Side dipping window polygon (cleanly behind the solid white A-pillar all the way to roof!)
    side_win_poly = [
        (1.33, 1.03),
        (1.85, 1.03),
        (1.86, 1.43),
        (1.50, 1.86),
        (1.27, 1.86),
        (1.28, 1.54),
    ]

    # -------------------------------------------------------------------------
    # EXACT SURFACE RAYCAST SAMPLER ON SUBSURF-2 CAB SHELL (BEFORE BOOLEAN CUTS!)
    # Guarantees 0.0mm gaps between cutout, recessed glass, MAŞALLAH strip & gasket!
    # -------------------------------------------------------------------------
    def sample_ws_surface(u: float, v: float):
        """
        Sample exact point & outward normal on the un-cut Subsurf-2 cab windshield!
        u in [-1.05..+1.05] (left-to-right inside A-pillars), v in [-0.10..+1.05] (cowl to roof brow).
        Returns (point_godot: Vector, normal_godot: Vector).
        """
        y_bot = 1.440 + 0.008 * (1.0 - min(1.0, u * u))
        y_top = 1.910 + 0.048 * (1.0 - min(1.0, u * u))  # Smoothly arches with oval roof crown!
        y = y_bot + v * (y_top - y_bot)
        # Wide panoramic MK7 windshield leaving crisp uniform ~10.5cm solid white A-pillars!
        half_w = 0.770 - 0.130 * max(0.0, min(1.0, v))
        x = u * half_w
        origin_b = G(x, y, 3.60)
        dir_b = (G(0.0, 0.0, -1.0) - G(0.0, 0.0, 0.0)).normalized()
        hit, loc_b, norm_b, _ = cab_obj.ray_cast(origin_b, dir_b)
        if not hit:
            # Safe fallback matching nominal windshield slope
            z_fb = 2.14 + v * (1.63 - 2.14) + 0.50 * cab_nose_z_offset(min(1.0, abs(u)))
            return Vector((x, y, z_fb)), Vector((0.0, 0.70, 0.71)).normalized()
        # Convert Blender Z-up back to Godot coords: (bx, bz, -by)
        p_g = Vector((loc_b.x, loc_b.z, -loc_b.y))
        n_g = Vector((norm_b.x, norm_b.z, -norm_b.y)).normalized()
        return p_g, n_g

    def sample_side_surface(sx: float, y: float, z: float):
        """Raycast from outside +/-X straight onto the curved cab door skin."""
        origin_b = G(sx * 2.40, y, z)
        dir_b = Vector((-sx, 0.0, 0.0))
        hit, loc_b, norm_b, _ = cab_obj.ray_cast(origin_b, dir_b)
        if not hit:
            return Vector((sx * cab_half_width(y, z), y, z)), Vector((sx, 0.0, 0.0))
        return Vector((loc_b.x, loc_b.z, -loc_b.y)), Vector((norm_b.x, norm_b.z, -norm_b.y)).normalized()

    # Pre-sample exact windshield & side-door surface meshes BEFORE boolean cuts modify cab_obj!
    ws_nu, ws_nv = 13, 7
    ws_u_cut = [-0.985 + 1.970 * i / (ws_nu - 1) for i in range(ws_nu)]
    ws_v_cut = [0.015 + 0.970 * j / (ws_nv - 1) for j in range(ws_nv)]
    ws_cut_samples = [[sample_ws_surface(u, v) for u in ws_u_cut] for v in ws_v_cut]

    ws_u_glass = [-1.035 + 2.070 * i / (ws_nu - 1) for i in range(ws_nu)]
    ws_v_glass = [-0.035 + 1.070 * j / (ws_nv - 1) for j in range(ws_nv)]
    ws_glass_samples = [[sample_ws_surface(u, v) for u in ws_u_glass] for v in ws_v_glass]

    ms_nu, ms_nv = 15, 3
    ms_u_vals = [-1.015 + 2.030 * i / (ms_nu - 1) for i in range(ms_nu)]
    ms_v_vals = [0.765, 0.890, 1.015]
    ms_samples = [[sample_ws_surface(u, v) for u in ms_u_vals] for v in ms_v_vals]

    # Pre-sample windshield rubber perimeter & wiper cowl panel directly on cab_obj!
    perim_pts = []
    # Bottom edge (left->right)
    for i in range(ws_nu):
        perim_pts.append(sample_ws_surface(-0.990 + 1.980 * i / (ws_nu - 1), 0.012))
    # Right edge (bottom->top)
    for j in range(1, ws_nv):
        perim_pts.append(sample_ws_surface(0.990, 0.012 + 0.976 * j / (ws_nv - 1)))
    # Top arched edge (right->left)
    for i in range(1, ws_nu):
        perim_pts.append(sample_ws_surface(0.990 - 1.980 * i / (ws_nu - 1), 0.988))
    # Left edge (top->bottom)
    for j in range(1, ws_nv - 1):
        perim_pts.append(sample_ws_surface(-0.990, 0.988 - 0.976 * j / (ws_nv - 1)))

    cowl_u = [-1.04 + 2.08 * i / (ws_nu - 1) for i in range(ws_nu)]
    cowl_bot = [sample_ws_surface(u, -0.105) for u in cowl_u]
    cowl_top = [sample_ws_surface(u, 0.018) for u in cowl_u]

    # Pre-sample wipers directly on the exact windshield surface!
    wiper_samples = []
    for (u0, v0, u1, v1, bl_u0, bl_v0, bl_u1, bl_v1) in [
        (0.68, -0.01, 0.08, 0.20, -0.18, 0.13, 0.36, 0.25),
        (-0.04, -0.01, -0.60, 0.18, -0.84, 0.12, -0.34, 0.23),
    ]:
        wiper_samples.append((
            sample_ws_surface(u0, v0),
            sample_ws_surface(u1, v1),
            sample_ws_surface(bl_u0, bl_v0),
            sample_ws_surface(bl_u1, bl_v1),
        ))

    # Pre-sample side door window perimeters directly on the curved cab flanks!
    side_trim_samples = {}
    side_div_samples = {}
    for sx in (-1.0, 1.0):
        side_trim_samples[sx] = [sample_side_surface(sx, wy, wz) for (wy, wz) in side_win_poly]
        side_div_samples[sx] = (sample_side_surface(sx, 1.275, 1.63), sample_side_surface(sx, 1.710, 1.63))

    def apply_cab_cut(cut_name: str, bm_c: bmesh.types.BMesh):
        bmesh.ops.recalc_face_normals(bm_c, faces=bm_c.faces)
        c_obj = finalize_mesh_obj(cut_name, bm_c, [mats["TransitWhite"], mats["InteriorDark"]], col_cab, smooth=False)
        bm_mod = cab_obj.modifiers.new(cut_name, "BOOLEAN")
        bm_mod.operation = "DIFFERENCE"
        bm_mod.solver = "FLOAT"
        bm_mod.object = c_obj
        bpy.context.view_layer.objects.active = cab_obj
        bpy.ops.object.modifier_apply(modifier=bm_mod.name)
        bpy.data.objects.remove(c_obj, do_unlink=True)
        print(f"AFTER_{cut_name}_POLYS={len(cab_obj.data.polygons)}")

    # 1. Cut front wheel arches
    for sx, tag in [(-1.0, "R"), (1.0, "L")]:
        bm_c = bmesh.new()
        bm_add_cyl_x_g(bm_c, sx * 0.56, sx * 1.24, WHEEL_RADIUS + 0.015, FRONT_Z, 0.445, segs=32, mat_idx=1)
        apply_cab_cut(f"CutWheelArch_{tag}", bm_c)

    # 2. Hollow sloped interior cabin room (strictly INSIDE roof & A-pillars — NEVER clips exterior!)
    bm_c = bmesh.new()
    cabin_yz = [
        (0.88, 0.88),
        (1.88, 0.90),
        (1.88, 1.38),
        (1.42, 1.84),
        (0.88, 1.84),
    ]
    bm_add_prism_x_g(bm_c, -0.68, 0.68, cabin_yz, mat_idx=1)
    apply_cab_cut("CutCabinRoom", bm_c)

    # 3. Cut EXACT arched panoramic windshield opening from pre-sampled cab surface!
    bm_c = bmesh.new()
    outer_g = []
    inner_g = []
    for j in range(ws_nv):
        ro, ri = [], []
        for i in range(ws_nu):
            p, n = ws_cut_samples[j][i]
            po = p + n * 0.24
            pi = p - n * 0.48
            ro.append(bm_c.verts.new(G(po.x, po.y, po.z)))
            ri.append(bm_c.verts.new(G(pi.x, pi.y, pi.z)))
        outer_g.append(ro)
        inner_g.append(ri)
    for j in range(ws_nv - 1):
        for i in range(ws_nu - 1):
            bm_c.faces.new((outer_g[j][i], outer_g[j][i + 1], outer_g[j + 1][i + 1], outer_g[j + 1][i])).material_index = 1
            bm_c.faces.new((inner_g[j][i], inner_g[j + 1][i], inner_g[j + 1][i + 1], inner_g[j][i + 1])).material_index = 1
    for i in range(ws_nu - 1):
        bm_c.faces.new((outer_g[0][i], inner_g[0][i], inner_g[0][i + 1], outer_g[0][i + 1])).material_index = 1
        bm_c.faces.new((outer_g[-1][i + 1], inner_g[-1][i + 1], inner_g[-1][i], outer_g[-1][i])).material_index = 1
    for j in range(ws_nv - 1):
        bm_c.faces.new((outer_g[j + 1][0], inner_g[j + 1][0], inner_g[j][0], outer_g[j][0])).material_index = 1
        bm_c.faces.new((outer_g[j][-1], inner_g[j][-1], inner_g[j + 1][-1], outer_g[j + 1][-1])).material_index = 1
    apply_cab_cut("CutWindshield", bm_c)

    # 4. Cut dipping side door windows ONLY on outer left/right door skins (preserves solid A-pillars!)
    for (x0_s, x1_s, tag) in [(0.58, 1.25, "L"), (-1.25, -0.58, "R")]:
        bm_c = bmesh.new()
        bm_add_prism_x_g(bm_c, x0_s, x1_s, side_win_poly, mat_idx=1)
        apply_cab_cut(f"CutSideWindow_{tag}", bm_c)

    # 5. Cut rear cab window
    bm_c = bmesh.new()
    bm_add_box_g(bm_c, -0.56, 0.56, 1.43, 1.84, 0.60, 0.96, mat_idx=1)
    apply_cab_cut("CutRearWindow", bm_c)

    # 6. Cut contoured MK7 corner headlight pockets (clean flush contour under smooth oval fender!)
    hl_cut_pts = [
        (0.515, 2.882, 0.805, 1.142),
        (0.620, 2.842, 0.804, 1.145),
        (0.735, 2.770, 0.810, 1.143),
        (0.835, 2.665, 0.825, 1.138),
        (0.896, 2.536, 0.860, 1.130),
        (0.912, 2.435, 0.918, 1.112),
    ]
    for sx, tag in [(-1.0, "R"), (1.0, "L")]:
        bm_c = bmesh.new()
        fb, ft, bb, bt = [], [], [], []
        for (xa, zf, yb, yt) in hl_cut_pts:
            nx = min(1.0, max(0.0, (xa - 0.50) / 0.43))
            nz = math.sqrt(max(0.04, 1.0 - nx * nx))
            px, pz = sx * (xa + nx * 0.14), zf + nz * 0.14
            bx, bz = sx * (xa - nx * 0.16), zf - nz * 0.16
            fb.append(bm_c.verts.new(G(px, yb, pz)))
            ft.append(bm_c.verts.new(G(px, yt, pz)))
            bb.append(bm_c.verts.new(G(bx, yb, bz)))
            bt.append(bm_c.verts.new(G(bx, yt, bz)))
        n_hl = len(hl_cut_pts)
        for i in range(n_hl - 1):
            bm_c.faces.new((fb[i], fb[i + 1], ft[i + 1], ft[i])).material_index = 1
            bm_c.faces.new((ft[i], ft[i + 1], bt[i + 1], bt[i])).material_index = 1
            bm_c.faces.new((bb[i], bb[i + 1], fb[i + 1], fb[i])).material_index = 1
            bm_c.faces.new((bt[i], bt[i + 1], bb[i + 1], bb[i])).material_index = 1
        bm_c.faces.new((bb[0], fb[0], ft[0], bt[0])).material_index = 1
        bm_c.faces.new((fb[-1], bb[-1], bt[-1], ft[-1])).material_index = 1
        apply_cab_cut(f"CutHeadlight_{tag}", bm_c)

    # Crisp automotive panel normals after boolean
    es = cab_obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
    es.use_edge_angle = True
    es.split_angle = math.radians(40.0)

    # Subtle recessed dark door shut lines (clean flush profile — no poking bonnet tubes!)
    bm_seams = bmesh.new()
    for sx in (-1.0, 1.0):
        bm_add_tube_g(bm_seams, (sx * 0.975, 0.49, 0.92), (sx * 0.955, 1.28, 0.92), 0.0055, segs=6)
        bm_add_tube_g(bm_seams, (sx * 0.955, 1.28, 0.92), (sx * 0.835, 1.95, 0.92), 0.0055, segs=6)
        bm_add_tube_g(bm_seams, (sx * 0.975, 0.49, 0.92), (sx * 0.975, 0.49, 1.36), 0.0055, segs=6)
        bm_add_tube_g(bm_seams, (sx * 0.985, 1.22, 0.94), (sx * 0.980, 1.22, 1.94), 0.0038, segs=6)
    finalize_mesh_obj("MK7_PanelSeams", bm_seams, mats["PanelSeam"], col_cab, smooth=True)

    # Dark inner wheel-well tub liners inside front arches
    bm_liner = bmesh.new()
    for sx in (-1.0, 1.0):
        bm_add_cyl_x_g(bm_liner, sx * 0.54, sx * 0.62, WHEEL_RADIUS + 0.015, FRONT_Z, 0.44, segs=24)
        for i in range(14):
            a0 = math.pi * (0.02 + 0.96 * i / 14.0)
            a1 = math.pi * (0.02 + 0.96 * (i + 1) / 14.0)
            y0, z0 = WHEEL_RADIUS + 0.015 + 0.44 * math.sin(a0), FRONT_Z + 0.44 * math.cos(a0)
            y1, z1 = WHEEL_RADIUS + 0.015 + 0.44 * math.sin(a1), FRONT_Z + 0.44 * math.cos(a1)
            v0 = bm_liner.verts.new(G(sx * 0.56, y0, z0))
            v1 = bm_liner.verts.new(G(sx * 0.965, y0, z0))
            v2 = bm_liner.verts.new(G(sx * 0.965, y1, z1))
            v3 = bm_liner.verts.new(G(sx * 0.56, y1, z1))
            bm_liner.faces.new((v0, v1, v2, v3))
    finalize_mesh_obj("MK7_WheelWellLiners", bm_liner, mats["RubberBlack"], col_cab, smooth=True, edge_split_deg=50.0)

    # -------------------------------------------------------------------------
    # B. MK7 ICONIC FRONT WHEEL ARCH FLARES & LOWER SILL CLADDING
    # -------------------------------------------------------------------------
    bm_flare = bmesh.new()
    flare_segs = 22
    r_in, r_out = 0.438, 0.514
    for sx in (-1.0, 1.0):
        rings = []
        for i in range(flare_segs + 1):
            ang = math.radians(-10.0 + 200.0 * i / flare_segs)
            ca, sa = math.cos(ang), math.sin(ang)
            y_in = WHEEL_RADIUS + 0.015 + r_in * sa
            z_in = FRONT_Z + r_in * ca
            y_out = WHEEL_RADIUS + 0.015 + r_out * sa
            z_out = FRONT_Z + r_out * ca
            x_base = cab_half_width(max(0.45, y_out), z_out) - 0.012
            x_lip = x_base + 0.048
            x_inner = x_base - 0.028
            p0 = bm_flare.verts.new(G(sx * x_inner, max(0.35, y_in), z_in))
            p1 = bm_flare.verts.new(G(sx * x_lip, max(0.36, y_in + 0.01), z_in))
            p2 = bm_flare.verts.new(G(sx * (x_lip - 0.010), max(0.38, y_out), z_out))
            p3 = bm_flare.verts.new(G(sx * x_base, max(0.38, y_out + 0.005), z_out))
            rings.append((p0, p1, p2, p3))
        for i in range(flare_segs):
            a, b = rings[i], rings[i + 1]
            for k in range(4):
                kn = (k + 1) % 4
                bm_flare.faces.new((a[k], a[kn], b[kn], b[k]))
        bm_flare.faces.new(rings[0])
        bm_flare.faces.new(list(reversed(rings[-1])))

        # Lower rocker sill + recessed step molding seamlessly connecting wheel arch to cab rear
        bm_add_box_g(bm_flare, sx * 0.89, sx * 0.985, 0.37, 0.49, 0.76, 1.38)
        # Signature MK7 wide dark-grey plastic side rubbing strip on lower doors (flush into arch!)
        bm_add_box_g(bm_flare, sx * 0.955, sx * 1.004, 0.60, 0.74, 0.79, 1.36)
        # Seamless tucked bumper-to-arch connector following the oval taper (zero side flap!)
        bm_add_box_g(bm_flare, sx * 0.88, sx * 0.955, 0.38, 0.75, 2.26, 2.54)

    finalize_mesh_obj("MK7_ArchFlares_SideTrim", bm_flare, mats["BumperPlastic"], col_cab,
                      smooth=True, edge_split_deg=42.0, bevel_width=0.006, bevel_segs=2)

    # -------------------------------------------------------------------------
    # C. MK7 SMOOTH OVAL WRAP-AROUND FRONT BUMPER (Rounded Cheeks, Steps & Fogs!)
    # -------------------------------------------------------------------------
    bm_bump = bmesh.new()
    bu_steps = [-1.0, -0.95, -0.88, -0.78, -0.65, -0.50, -0.34, -0.17, 0.0, 0.17, 0.34, 0.50, 0.65, 0.78, 0.88, 0.95, 1.0]
    b_prof = [
        (0.35, -0.07, -0.03),  # Lower tucked chin underside
        (0.39,  0.025, -0.005),# Rounded lower chin lip
        (0.49,  0.088, 0.016), # Smooth lower bumper curve
        (0.62,  0.108, 0.024), # Oval mid bumper crown
        (0.73,  0.092, 0.018), # Soft upper bumper curve
        (0.79,  0.025, 0.002), # Smooth bumper top shelf
        (0.79, -0.15, -0.02),  # Tucked cleanly behind grille
        (0.35, -0.18, -0.03),  # Rear inner backing
    ]
    b_grid = []
    for u in bu_steps:
        au = abs(u)
        sgn = 1.0 if u >= 0 else -1.0
        ring = []
        for (by, bdz, bdx) in b_prof:
            base_z = 2.945 + cab_nose_z_offset(au) * 1.08
            if au > 0.78:
                wt = (au - 0.78) / 0.22
                base_z -= 0.36 * (wt ** 1.65)
            # Smooth elliptical horizontal x scaling so corners stay genuinely oval!
            x_outer = min(0.988, cab_half_width(by, base_z) + bdx)
            bx = sgn * (x_outer * math.sin(au * math.pi * 0.5) if au < 0.95 else (0.985 + bdx * 0.35))
            ring.append(bm_bump.verts.new(G(bx, by, base_z + bdz)))
        b_grid.append(ring)

    nb_u, nb_p = len(bu_steps), len(b_prof)
    for ui in range(nb_u - 1):
        for pi in range(nb_p):
            pi_n = (pi + 1) % nb_p
            bm_bump.faces.new((b_grid[ui][pi], b_grid[ui + 1][pi], b_grid[ui + 1][pi_n], b_grid[ui][pi_n]))
    bm_bump.faces.new(b_grid[0])
    bm_bump.faces.new(list(reversed(b_grid[-1])))

    bm_add_box_g(bm_bump, -0.42, 0.42, 0.37, 0.46, 2.92, 3.015)
    finalize_mesh_obj("MK7_FrontBumper", bm_bump, mats["BumperPlastic"], col_fascia,
                      smooth=True, edge_split_deg=44.0, bevel_width=0.008, bevel_segs=2)

    # Dark recessed bumper lower intake slats + twin footstep pockets + visible fog housings
    bm_bdetail = bmesh.new()
    bm_add_box_g(bm_bdetail, -0.35, 0.35, 0.39, 0.455, 2.98, 3.035)
    for sx in (-1.0, 1.0):
        step_z = 2.945 + cab_nose_z_offset(0.46) * 1.08 + 0.098
        bm_add_box_g(bm_bdetail, sx * 0.34, sx * 0.50, 0.44, 0.54, step_z - 0.05, step_z + 0.012)
        fx = sx * 0.65
        fz = 2.945 + cab_nose_z_offset(0.55) * 1.08 + 0.095
        bm_add_cyl_z_g(bm_bdetail, fx, 0.525, fz - 0.05, fz + 0.025, 0.062, segs=20)
    finalize_mesh_obj("MK7_BumperIntake_Steps", bm_bdetail, mats["GrilleMeshDark"], col_fascia, smooth=True, edge_split_deg=42.0)

    # Chrome fog bezels & glowing round fog lenses proud on oval bumper cheeks
    bm_fog_ring = bmesh.new()
    bm_fog_lens = bmesh.new()
    for sx in (-1.0, 1.0):
        fx = sx * 0.65
        fz = 2.945 + cab_nose_z_offset(0.55) * 1.08 + 0.104
        bm_add_cyl_z_g(bm_fog_ring, fx, 0.525, fz - 0.01, fz + 0.022, 0.050, segs=20)
        bm_add_cyl_z_g(bm_fog_lens, fx, 0.525, fz + 0.012, fz + 0.026, 0.039, segs=20)
    finalize_mesh_obj("MK7_FogBezels", bm_fog_ring, mats["Chrome"], col_fascia, smooth=True, edge_split_deg=45.0)
    finalize_mesh_obj("MK7_FogLenses", bm_fog_lens, mats["HeadlightGlass"], col_fascia, smooth=True)

    # -------------------------------------------------------------------------
    # D. CLEAN UNBRANDED MK7 OVAL-CURVED TWO-BAR TRAPEZOIDAL FRONT GRILLE
    #    (NO blue Ford logo!)
    # -------------------------------------------------------------------------
    bm_gmesh = bmesh.new()
    gu = [-1.0, -0.70, -0.35, 0.0, 0.35, 0.70, 1.0]
    g_rows = []
    for gy, hw, dz in [(0.79, 0.44, 0.008), (0.97, 0.475, 0.006), (1.155, 0.505, -0.018)]:
        row = []
        for u in gu:
            x = hw * u
            z = 2.922 + cab_nose_z_offset(abs(x) / 0.94) + dz
            row.append(bm_gmesh.verts.new(G(x, gy, z)))
        g_rows.append(row)
    for r in range(len(g_rows) - 1):
        for i in range(len(gu) - 1):
            bm_gmesh.faces.new((g_rows[r][i], g_rows[r][i + 1], g_rows[r + 1][i + 1], g_rows[r + 1][i]))
    for xi in range(-9, 10):
        vx = xi * 0.047
        vz = 2.930 + cab_nose_z_offset(abs(vx) / 0.94)
        bm_add_box_g(bm_gmesh, vx - 0.0055, vx + 0.0055, 0.805, 1.148, vz - 0.032, vz + 0.012)
    finalize_mesh_obj("MK7_GrilleMesh", bm_gmesh, mats["GrilleMeshDark"], col_fascia, smooth=False)

    bm_gbars = bmesh.new()

    def add_curved_bar(y0, y1, hw_bot, hw_top, z_front, z_back):
        us = [-1.0, -0.75, -0.50, -0.25, 0.0, 0.25, 0.50, 0.75, 1.0]
        rings = []
        for u in us:
            x_b, x_t = hw_bot * u, hw_top * u
            zb = z_back + cab_nose_z_offset(abs(x_b) / 0.94)
            zf = z_front + cab_nose_z_offset(abs(x_b) / 0.94)
            rings.append((
                bm_gbars.verts.new(G(x_b, y0, zb)),
                bm_gbars.verts.new(G(x_b, y0, zf)),
                bm_gbars.verts.new(G(x_t, y1, zf - 0.004)),
                bm_gbars.verts.new(G(x_t, y1, zb)),
            ))
        for i in range(len(us) - 1):
            a, b = rings[i], rings[i + 1]
            for k in range(4):
                kn = (k + 1) % 4
                bm_gbars.faces.new((a[k], b[k], b[kn], a[kn]))
        bm_gbars.faces.new(rings[0])
        bm_gbars.faces.new(list(reversed(rings[-1])))

    add_curved_bar(1.132, 1.174, 0.502, 0.512, 2.922, 2.860)   # Upper lip flush under oval hood
    add_curved_bar(0.785, 0.822, 0.445, 0.454, 2.958, 2.885)   # Bottom lip flush on bumper
    add_curved_bar(0.992, 1.044, 0.480, 0.488, 2.956, 2.890)   # Clean upper MK7 horizontal bar (no badge!)
    add_curved_bar(0.880, 0.930, 0.460, 0.468, 2.962, 2.895)   # Clean lower MK7 horizontal bar

    for sx in (-1.0, 1.0):
        p_bot = (sx * 0.452, 0.792, 2.948 + cab_nose_z_offset(0.47))
        p_top = (sx * 0.510, 1.166, 2.910 + cab_nose_z_offset(0.53))
        bm_add_tube_g(bm_gbars, p_bot, p_top, 0.028, segs=8)

    finalize_mesh_obj("MK7_GrilleBars", bm_gbars, mats["GrilleBarGrey"], col_fascia,
                      smooth=True, edge_split_deg=38.0, bevel_width=0.005, bevel_segs=2)

    # -------------------------------------------------------------------------
    # E. MK7 OVAL-SWEPT 4-LAYER RECESSED WRAP-AROUND HEADLIGHT CLUSTERS!
    # -------------------------------------------------------------------------
    bm_hl_house = bmesh.new()
    bm_hl_chrome = bmesh.new()
    bm_hl_bulbs = bmesh.new()
    bm_hl_amber = bmesh.new()
    bm_hl_lens = bmesh.new()

    for sx in (-1.0, 1.0):
        # Smooth oval-wrapped headlight contour tucked cleanly under rounded hood shoulder!
        hl_pts = [
            (0.512, 2.882, 0.805, 1.142),
            (0.620, 2.842, 0.804, 1.145),
            (0.735, 2.770, 0.810, 1.143),
            (0.835, 2.665, 0.825, 1.138),
            (0.896, 2.536, 0.860, 1.130),
            (0.912, 2.435, 0.918, 1.112),
        ]

        def add_curved_shell(bm_t, pts_list, out_off, thick):
            fb, ft, bb, bt = [], [], [], []
            for (xa, zf, yb, yt) in pts_list:
                nx = min(1.0, max(0.0, (xa - 0.50) / 0.43))
                nz = math.sqrt(max(0.04, 1.0 - nx * nx))
                px = sx * (xa + nx * out_off)
                pz = zf + nz * out_off
                bx = sx * (xa + nx * (out_off - thick))
                bz = zf + nz * (out_off - thick)
                fb.append(bm_t.verts.new(G(px, yb, pz)))
                ft.append(bm_t.verts.new(G(px, yt, pz - 0.015 * nz)))
                bb.append(bm_t.verts.new(G(bx, yb + 0.008, bz)))
                bt.append(bm_t.verts.new(G(bx, yt - 0.008, bz - 0.015 * nz)))
            n = len(pts_list)
            for i in range(n - 1):
                bm_t.faces.new((fb[i], fb[i + 1], ft[i + 1], ft[i]))
                bm_t.faces.new((ft[i], ft[i + 1], bt[i + 1], bt[i]))
                bm_t.faces.new((bb[i], bb[i + 1], fb[i + 1], fb[i]))
                bm_t.faces.new((bt[i], bt[i + 1], bb[i + 1], bb[i]))
            bm_t.faces.new((bb[0], fb[0], ft[0], bt[0]))
            bm_t.faces.new((fb[-1], bb[-1], bt[-1], ft[-1]))

        add_curved_shell(bm_hl_house, hl_pts, out_off=-0.055, thick=0.075)
        for i in range(len(hl_pts) - 1):
            a, b = hl_pts[i], hl_pts[i + 1]
            bm_add_tube_g(bm_hl_house, (sx * a[0], a[2], a[1]), (sx * b[0], b[2], b[1]), 0.010, segs=6)
            bm_add_tube_g(bm_hl_house, (sx * a[0], a[3], a[1] - 0.012), (sx * b[0], b[3], b[1] - 0.012), 0.010, segs=6)
        bm_add_tube_g(bm_hl_house, (sx * hl_pts[0][0], hl_pts[0][2], hl_pts[0][1]),
                      (sx * hl_pts[0][0], hl_pts[0][3], hl_pts[0][1] - 0.012), 0.010, segs=6)
        bm_add_tube_g(bm_hl_house, (sx * hl_pts[-1][0], hl_pts[-1][2], hl_pts[-1][1]),
                      (sx * hl_pts[-1][0], hl_pts[-1][3], hl_pts[-1][1] - 0.012), 0.010, segs=6)

        # Dual chrome parabolic reflectors + bright bulbs positioned cleanly inside oval curve
        bm_add_cone_z_g(bm_hl_chrome, sx * 0.640, 1.040, 2.740, 2.818, 0.040, 0.092, segs=24)
        bm_add_cyl_z_g(bm_hl_bulbs, sx * 0.640, 1.040, 2.775, 2.820, 0.034, segs=16)
        bm_add_cone_z_g(bm_hl_chrome, sx * 0.625, 0.880, 2.755, 2.825, 0.026, 0.064, segs=20)
        bm_add_cyl_z_g(bm_hl_bulbs, sx * 0.625, 0.880, 2.785, 2.826, 0.024, segs=14)
        bm_add_box_g(bm_hl_chrome, sx * 0.525, sx * 0.765, 0.945, 0.964, 2.735, 2.798)

        amber_pts = [
            (0.765, 2.758, 0.830, 1.150),
            (0.846, 2.660, 0.840, 1.155),
            (0.902, 2.536, 0.875, 1.152),
            (0.914, 2.450, 0.926, 1.132),
        ]
        add_curved_shell(bm_hl_amber, amber_pts, out_off=-0.010, thick=0.042)
        add_curved_shell(bm_hl_lens, hl_pts, out_off=0.008, thick=0.008)

    finalize_mesh_obj("MK7_HeadlightHousings", bm_hl_house, mats["InteriorDark"], col_fascia, smooth=True, edge_split_deg=40.0)
    finalize_mesh_obj("MK7_HeadlightReflectors", bm_hl_chrome, mats["Chrome"], col_fascia, smooth=True, edge_split_deg=45.0)
    finalize_mesh_obj("MK7_HeadlightBulbs", bm_hl_bulbs, mats["HeadlightGlass"], col_fascia, smooth=True)
    finalize_mesh_obj("MK7_FrontAmberSignals", bm_hl_amber, mats["AmberIndicator"], col_fascia, smooth=True, edge_split_deg=40.0)
    finalize_mesh_obj("MK7_HeadlightClearLens", bm_hl_lens, mats["HeadlightLensClear"], col_fascia, smooth=True, edge_split_deg=42.0)

    # Front Turkish License Plate ("34 GRD 45") centered on oval bumper
    bm_pf = bmesh.new()
    bm_add_box_g(bm_pf, -0.280, 0.280, 0.505, 0.635, 3.015, 3.055)
    finalize_mesh_obj("MK7_FrontPlateFrame", bm_pf, mats["RubberBlack"], col_fascia, smooth=False, bevel_width=0.004)
    make_uv_quad_obj(
        "MK7_FrontPlateDecal",
        (-0.268, 0.515, 3.058), (0.268, 0.515, 3.058),
        (0.268, 0.625, 3.058), (-0.268, 0.625, 3.058),
        mats["LicensePlateTR"], col_fascia
    )

    # -------------------------------------------------------------------------
    # F. ZERO-GAP SURFACE-CONFORMED WINDSHIELD, MAŞALLAH STRIP, WIPERS & SIDE GLASS!
    # -------------------------------------------------------------------------
    bm_ws = bmesh.new()
    bm_wgasket = bmesh.new()

    # 1) Recessed curved panoramic windshield glass (tucked -1.3cm behind cab A-pillars & brow!)
    ws_grid = []
    for j in range(ws_nv):
        row = []
        for i in range(ws_nu):
            p, n = ws_glass_samples[j][i]
            pg = p - n * 0.013
            row.append(bm_ws.verts.new(G(pg.x, pg.y, pg.z)))
        ws_grid.append(row)
    for j in range(ws_nv - 1):
        for i in range(ws_nu - 1):
            bm_ws.faces.new((ws_grid[j][i], ws_grid[j][i + 1], ws_grid[j + 1][i + 1], ws_grid[j + 1][i]))

    # 2) Edge-to-edge curved Turkish top sunstrip ("MAŞALLAH" + twin Nazar Boncuğu)
    #    Hugs the exact arched windshield surface (+5mm in front of glass, tucked under rubber gasket!)
    bm_ms = bmesh.new()
    uv_ms = bm_ms.loops.layers.uv.new("UVMap")
    ms_grid = []
    for j in range(ms_nv):
        row = []
        for i in range(ms_nu):
            p, n = ms_samples[j][i]
            pm = p - n * 0.006
            row.append(bm_ms.verts.new(G(pm.x, pm.y, pm.z)))
        ms_grid.append(row)
    for j in range(ms_nv - 1):
        v0_tex = j / (ms_nv - 1)
        v1_tex = (j + 1) / (ms_nv - 1)
        for i in range(ms_nu - 1):
            u0_tex = i / (ms_nu - 1)
            u1_tex = (i + 1) / (ms_nu - 1)
            f = bm_ms.faces.new((ms_grid[j][i], ms_grid[j][i + 1], ms_grid[j + 1][i + 1], ms_grid[j + 1][i]))
            for lp, uv_val in zip(f.loops, [(u0_tex, v0_tex), (u1_tex, v0_tex), (u1_tex, v1_tex), (u0_tex, v1_tex)]):
                lp[uv_ms].uv = uv_val
    finalize_mesh_obj("MK7_WindshieldMasallahStrip", bm_ms, mats["WindshieldMasallah"], col_glass, smooth=True)

    # 3) Continuous surface-hugging rubber windshield weatherstrip perimeter (0.0mm gap!)
    n_perim = len(perim_pts)
    for i in range(n_perim):
        p0, n0 = perim_pts[i]
        p1, n1 = perim_pts[(i + 1) % n_perim]
        q0 = p0 + n0 * 0.002
        q1 = p1 + n1 * 0.002
        bm_add_tube_g(bm_wgasket, (q0.x, q0.y, q0.z), (q1.x, q1.y, q1.z), 0.022, segs=8)

    # 4) Flush contoured black MK7 scuttle / wiper cowl apron hugging base of windshield!
    cb_vs, ct_vs, cb_in, ct_in = [], [], [], []
    for i in range(ws_nu):
        pb, nb = cowl_bot[i]
        pt, nt = cowl_top[i]
        ob, ot = pb + nb * 0.010, pt + nt * 0.012
        ib, it = pb - nb * 0.028, pt - nt * 0.028
        cb_vs.append(bm_wgasket.verts.new(G(ob.x, ob.y, ob.z)))
        ct_vs.append(bm_wgasket.verts.new(G(ot.x, ot.y, ot.z)))
        cb_in.append(bm_wgasket.verts.new(G(ib.x, ib.y, ib.z)))
        ct_in.append(bm_wgasket.verts.new(G(it.x, it.y, it.z)))
    for i in range(ws_nu - 1):
        bm_wgasket.faces.new((cb_vs[i], cb_vs[i + 1], ct_vs[i + 1], ct_vs[i]))
        bm_wgasket.faces.new((ct_vs[i], ct_vs[i + 1], ct_in[i + 1], ct_in[i]))
        bm_wgasket.faces.new((cb_in[i], cb_in[i + 1], cb_vs[i + 1], cb_vs[i]))

    # 5) Twin MK7 windshield wipers resting cleanly directly on the glass surface!
    for ((p_base, n_base), (p_tip, n_tip), (p_b0, n_b0), (p_b1, n_b1)) in wiper_samples:
        a0 = p_base + n_base * 0.005
        a1 = p_tip + n_tip * 0.002
        b0 = p_b0 - n_b0 * 0.004
        b1 = p_b1 - n_b1 * 0.004
        bm_add_tube_g(bm_wgasket, (a0.x, a0.y, a0.z), (a1.x, a1.y, a1.z), 0.010, segs=6)
        bm_add_tube_g(bm_wgasket, (b0.x, b0.y, b0.z), (b1.x, b1.y, b1.z), 0.0085, segs=6)

    # Iconic MK7 front-center roof whip antenna
    bm_add_cyl_y_g(bm_wgasket, 0.0, 2.09, 2.13, 1.46, 0.022, segs=10)
    bm_add_tube_g(bm_wgasket, (0.0, 2.12, 1.46), (0.0, 2.46, 1.10), 0.0055, segs=6)

    # 6) Signature MK7 DIPPING SIDE DOOR WINDOWS (recessed behind skin + surface-hugged gasket!)
    for sx in (-1.0, 1.0):
        # Expand glass polygon by +2.2cm around centroid so glass tucks cleanly behind door metal!
        cy_w = sum(p[0] for p in side_win_poly) / len(side_win_poly)
        cz_w = sum(p[1] for p in side_win_poly) / len(side_win_poly)
        pts_s = side_trim_samples[sx]
        w_verts = []
        for k, (wy, wz) in enumerate(side_win_poly):
            dy, dz = wy - cy_w, wz - cz_w
            dl = max(1e-4, math.hypot(dy, dz))
            ey, ez = wy + 0.022 * (dy / dl), wz + 0.022 * (dz / dl)
            ps, _ns = pts_s[k]
            # Tuck 1.2cm inward behind the outer door panel!
            w_verts.append(bm_ws.verts.new(G(ps.x - sx * 0.012, ey, ez)))
        bm_ws.faces.new(w_verts if sx > 0 else list(reversed(w_verts)))

        # Rubber side window seal traced right on the exact curved cab door surface!
        for i in range(len(pts_s)):
            p0, n0 = pts_s[i]
            p1, n1 = pts_s[(i + 1) % len(pts_s)]
            q0 = p0 + n0 * 0.003
            q1 = p1 + n1 * 0.003
            bm_add_tube_g(bm_wgasket, (q0.x, q0.y, q0.z), (q1.x, q1.y, q1.z), 0.018, segs=8)
        # Signature MK7 front quarter-glass vertical black divider post!
        (pd0, nd0), (pd1, nd1) = side_div_samples[sx]
        qd0, qd1 = pd0 + nd0 * 0.002, pd1 + nd1 * 0.002
        bm_add_tube_g(bm_wgasket, (qd0.x, qd0.y, qd0.z), (qd1.x, qd1.y, qd1.z), 0.014, segs=8)
        # Iconic MK7 vertical black recessed door pull handle
        hx = sx * (cab_half_width(1.06, 1.02) + 0.022)
        bm_add_box_g(bm_wgasket, hx - sx * 0.018, hx + sx * 0.014, 0.98, 1.15, 0.98, 1.05)

    # Rear cab window glass (recessed + tucked cleanly behind rear cab cutout!)
    bm_add_box_g(bm_ws, -0.58, 0.58, 1.41, 1.87, 0.770, 0.785)
    for (p0, p1) in [
        ((-0.56, 1.43, 0.76), (0.56, 1.43, 0.76)),
        ((-0.56, 1.85, 0.76), (0.56, 1.85, 0.76)),
        ((-0.56, 1.43, 0.76), (-0.56, 1.85, 0.76)),
        ((0.56, 1.43, 0.76), (0.56, 1.85, 0.76)),
    ]:
        bm_add_tube_g(bm_wgasket, p0, p1, 0.016, segs=6)

    finalize_mesh_obj("MK7_CabGlass", bm_ws, mats["CabGlass"], col_glass, smooth=True, edge_split_deg=45.0)
    finalize_mesh_obj("MK7_WindowTrim_Wipers", bm_wgasket, mats["RubberBlack"], col_glass, smooth=True, edge_split_deg=45.0)

    # Side fender amber turn-signal repeaters
    bm_rep = bmesh.new()
    for sx in (-1.0, 1.0):
        rx_s = sx * (cab_half_width(0.86, 1.32) + 0.022)
        bm_add_box_g(bm_rep, rx_s - sx * 0.012, rx_s + sx * 0.014, 0.84, 0.895, 1.27, 1.36)
    finalize_mesh_obj("MK7_SideRepeaters", bm_rep, mats["AmberIndicator"], col_fascia, smooth=True, bevel_width=0.005)

    # -------------------------------------------------------------------------
    # G. MK7 COMMERCIAL TWIN-ARM LONG-STEM SIDE MIRRORS
    # -------------------------------------------------------------------------
    bm_marm = bmesh.new()
    bm_mglass = bmesh.new()
    bm_mamber = bmesh.new()
    for sx in (-1.0, 1.0):
        mx_base = sx * 0.925
        mx_out = sx * 1.235
        mz = 1.87
        bm_add_box_g(bm_marm, sx * 0.89, sx * 0.97, 1.28, 1.45, 1.82, 1.95)
        # Dual commercial tubular arms
        bm_add_tube_g(bm_marm, (mx_base, 1.42, mz + 0.01), (mx_out - sx * 0.04, 1.62, mz + 0.01), 0.014, segs=10)
        bm_add_tube_g(bm_marm, (mx_base, 1.32, mz + 0.01), (mx_out - sx * 0.04, 1.37, mz + 0.01), 0.014, segs=10)
        # Sculpted rounded vertical Transit commercial mirror casing
        bm_add_box_g(bm_marm, mx_out - sx * 0.082, mx_out + sx * 0.042, 1.30, 1.71, mz - 0.042, mz + 0.052)
        bm_add_box_g(bm_mglass, mx_out - sx * 0.070, mx_out + sx * 0.030, 1.44, 1.68, mz - 0.050, mz - 0.040)
        bm_add_box_g(bm_mglass, mx_out - sx * 0.070, mx_out + sx * 0.030, 1.32, 1.41, mz - 0.050, mz - 0.040)
        bm_add_box_g(bm_mamber, mx_out - sx * 0.040, mx_out + sx * 0.046, 1.46, 1.54, mz + 0.046, mz + 0.062)

    finalize_mesh_obj("MK7_MirrorHousings", bm_marm, mats["BumperPlastic"], col_cab,
                      smooth=True, edge_split_deg=38.0, bevel_width=0.012, bevel_segs=2)
    finalize_mesh_obj("MK7_MirrorGlasses", bm_mglass, mats["MirrorGlass"], col_glass, smooth=False)
    finalize_mesh_obj("MK7_MirrorIndicators", bm_mamber, mats["AmberIndicator"], col_fascia, smooth=True, bevel_width=0.004)

    # -------------------------------------------------------------------------
    # H. VISIBLE DARK CAB INTERIOR (Dashboard, Steering Wheel, Shifter, 2+1 Seats!)
    # -------------------------------------------------------------------------
    bm_int = bmesh.new()
    bm_seats = bmesh.new()

    # Dark interior cab floor, lower inner door panels, rear bulkhead & roof headliner (cleanly tucked inside Subsurf-2 roof!)
    bm_add_box_g(bm_int, -0.76, 0.76, 0.86, 0.90, 0.84, 1.94)     # Floor mat
    bm_add_box_g(bm_int, -0.62, 0.62, 1.90, 1.94, 0.92, 1.44)     # Tucked headliner
    bm_add_box_g(bm_int, -0.76, 0.76, 0.88, 1.43, 0.82, 0.88)     # Lower rear cab wall
    for sx in (-1.0, 1.0):
        bm_add_box_g(bm_int, sx * 0.74, sx * 0.82, 0.88, 1.26, 0.88, 1.90)  # Inner door cards
        bm_add_box_g(bm_int, sx * 0.66, sx * 0.74, 1.26, 1.84, 0.88, 0.98)  # Tucked inner B-pillars
        # Sun visors under windshield brow
        bm_add_box_g(bm_int, sx * 0.12, sx * 0.54, 1.86, 1.91, 1.48, 1.60)

    # Sculpted MK7 dashboard + instrument binnacle on Left (+X = driver in Turkey!)
    bm_add_box_g(bm_int, -0.78, 0.78, 1.15, 1.41, 1.68, 2.06)
    bm_add_box_g(bm_int, 0.20, 0.66, 1.39, 1.51, 1.72, 1.98)      # Instrument cluster hump
    # Center Transit dash-mounted gear stick
    bm_add_tube_g(bm_int, (0.04, 1.24, 1.70), (0.04, 1.40, 1.56), 0.016, segs=8)
    # 3-spoke steering wheel on driver side (+X = +0.44)
    sw_c = (0.44, 1.46, 1.56)
    sw_r = 0.195
    sw_segs = 18
    for i in range(sw_segs):
        a0 = 2.0 * math.pi * i / sw_segs
        a1 = 2.0 * math.pi * (i + 1) / sw_segs
        p0 = (sw_c[0] + sw_r * math.cos(a0), sw_c[1] + sw_r * math.sin(a0) * 0.88, sw_c[2] - sw_r * math.sin(a0) * 0.45)
        p1 = (sw_c[0] + sw_r * math.cos(a1), sw_c[1] + sw_r * math.sin(a1) * 0.88, sw_c[2] - sw_r * math.sin(a1) * 0.45)
        bm_add_tube_g(bm_int, p0, p1, 0.020, segs=6)
    bm_add_tube_g(bm_int, sw_c, (0.44, 1.36, 1.76), 0.034, segs=8)
    # Interior rearview mirror cleanly tucked INSIDE the windshield (never pokes through top!)
    bm_add_box_g(bm_int, -0.10, 0.10, 1.74, 1.80, 1.56, 1.60)
    bm_add_tube_g(bm_int, (0.0, 1.80, 1.58), (0.0, 1.88, 1.58), 0.009, segs=6)

    # 2+1 Transit cloth seats (clearly visible through dark-tinted windshield & door glass!)
    for (sx0, sx1) in [(0.20, 0.68), (-0.68, -0.22), (-0.20, 0.16)]:
        bm_add_box_g(bm_seats, sx0, sx1, 0.90, 1.07, 1.04, 1.48)
        bm_add_box_g(bm_seats, sx0, sx1, 1.04, 1.65, 0.94, 1.08)
        cx = (sx0 + sx1) * 0.5
        bm_add_box_g(bm_seats, cx - 0.115, cx + 0.115, 1.68, 1.86, 0.96, 1.06)

    finalize_mesh_obj("MK7_InteriorDash", bm_int, mats["InteriorDark"], col_glass, smooth=True, edge_split_deg=45.0)
    finalize_mesh_obj("MK7_InteriorSeats", bm_seats, mats["SeatFabric"], col_glass, smooth=True, bevel_width=0.02, bevel_segs=2)


# =============================================================================
# 2. LADDER CHASSIS, AXLES, EXHAUST, FUEL TANK & UNDERRUN GUARDS
# =============================================================================
def build_chassis_underbody(mats, cols):
    col_ch = cols["06_Chassis_Lights"]
    bm_ch = bmesh.new()

    for sx in (-0.43, 0.43):
        bm_add_box_g(bm_ch, sx - 0.055, sx + 0.055, 0.48, 0.68, -2.86, 2.55)
    for cz in (-2.78, -2.20, -1.78, -1.10, -0.35, 0.45, 1.25, 2.35):
        bm_add_box_g(bm_ch, -0.48, 0.48, 0.51, 0.65, cz - 0.05, cz + 0.05)
    for cz in (-2.80, -2.18, -1.56, -0.94, -0.32, 0.30, 0.62):
        bm_add_box_g(bm_ch, -1.02, 1.02, 0.68, 0.84, cz - 0.04, cz + 0.04)

    bm_add_cyl_x_g(bm_ch, -0.88, 0.88, WHEEL_RADIUS, REAR_Z, 0.068, segs=16)
    bm_add_cyl_z_g(bm_ch, 0.0, WHEEL_RADIUS, REAR_Z - 0.16, REAR_Z + 0.18, 0.145, segs=16)
    bm_add_tube_g(bm_ch, (0.0, WHEEL_RADIUS + 0.04, REAR_Z + 0.16), (0.0, 0.52, 0.70), 0.045, segs=12)
    bm_add_cyl_x_g(bm_ch, -0.82, 0.82, WHEEL_RADIUS, FRONT_Z, 0.055, segs=14)

    for sx in (-0.54, 0.54):
        bm_add_box_g(bm_ch, sx - 0.035, sx + 0.035, 0.43, 0.50, REAR_Z - 0.62, REAR_Z + 0.62)
        bm_add_box_g(bm_ch, sx - 0.04, sx + 0.04, 0.48, 0.60, REAR_Z - 0.66, REAR_Z - 0.56)
        bm_add_box_g(bm_ch, sx - 0.04, sx + 0.04, 0.48, 0.60, REAR_Z + 0.56, REAR_Z + 0.66)

    bm_add_box_g(bm_ch, 0.48, 0.88, 0.42, 0.72, -0.88, 0.12)
    bm_add_box_g(bm_ch, -0.84, -0.48, 0.46, 0.72, -0.35, 0.25)
    bm_add_cyl_y_g(bm_ch, 0.0, 0.36, 0.54, -2.42, 0.34, segs=20)
    bm_add_box_g(bm_ch, -1.03, 1.03, 0.40, 0.54, -2.96, -2.84)

    finalize_mesh_obj("MK7_LadderChassis", bm_ch, mats["ChassisSteel"], col_ch, smooth=True, edge_split_deg=42.0)

    bm_ex = bmesh.new()
    bm_add_cyl_z_g(bm_ex, -0.28, 0.44, -0.90, -0.15, 0.095, segs=14)
    bm_add_tube_g(bm_ex, (-0.28, 0.44, -0.15), (-0.22, 0.48, 0.85), 0.034, segs=10)
    bm_add_tube_g(bm_ex, (-0.28, 0.44, -0.90), (-0.68, 0.42, -1.25), 0.032, segs=10)
    finalize_mesh_obj("MK7_Exhaust", bm_ex, mats["ExhaustSteel"], col_ch, smooth=True, edge_split_deg=45.0)

    bm_guard = bmesh.new()
    for sx in (-1.0, 1.0):
        for gy in (0.43, 0.59):
            bm_add_box_g(bm_guard, sx * 0.96, sx * 1.02, gy - 0.032, gy + 0.032, -1.16, 0.62)
        for gz in (-0.98, 0.40):
            bm_add_box_g(bm_guard, sx * 0.46, sx * 0.99, 0.42, 0.68, gz - 0.025, gz + 0.025)
    finalize_mesh_obj("MK7_SideUnderrunGuards", bm_guard, mats["GalvSteel"], col_ch,
                      smooth=False, bevel_width=0.004, bevel_segs=1)

    bm_mud = bmesh.new()
    for sx in (-1.0, 1.0):
        bm_add_box_g(bm_mud, sx * 0.54, sx * 1.04, 0.16, 0.72, -2.38, -2.35)
        for i in range(12):
            a0 = math.radians(15 + 150 * i / 12)
            a1 = math.radians(15 + 150 * (i + 1) / 12)
            y0, z0 = WHEEL_RADIUS + 0.45 * math.sin(a0), REAR_Z + 0.45 * math.cos(a0)
            y1, z1 = WHEEL_RADIUS + 0.45 * math.sin(a1), REAR_Z + 0.45 * math.cos(a1)
            v0 = bm_mud.verts.new(G(sx * 0.54, y0, z0))
            v1 = bm_mud.verts.new(G(sx * 1.05, y0, z0))
            v2 = bm_mud.verts.new(G(sx * 1.05, y1, z1))
            v3 = bm_mud.verts.new(G(sx * 0.54, y1, z1))
            bm_mud.faces.new((v0, v1, v2, v3))
    finalize_mesh_obj("MK7_RearMudflaps", bm_mud, mats["RubberBlack"], col_ch, smooth=True, edge_split_deg=50.0)


# =============================================================================
# 3. CLEAN OPEN 350L ALUMINUM DROPSIDE FLATBED + LOWER REAR GARDASLAR BANNER
#    (No upper profile cage, no tarp — banner cleanly mounted on lower rear tailgate!)
# =============================================================================
def build_cargo_bed(mats, cols):
    col_bed = cols["04_CargoBed"]
    col_lights = cols["06_Chassis_Lights"]

    bed_z0 = -2.92
    bed_z1 = 0.68
    bed_hw = 1.06
    deck_y = 0.88
    drop_top = 1.44  # Clean 56cm open Turkish commercial aluminum drop-sides & tailgate!

    bm_deck = bmesh.new()
    bm_add_box_g(bm_deck, -bed_hw + 0.03, bed_hw - 0.03, deck_y - 0.06, deck_y, bed_z0 + 0.03, bed_z1 - 0.03)
    finalize_mesh_obj("Bed_DeckFloor", bm_deck, mats["BedDeckFloor"], col_bed, smooth=False)

    bm_drop = bmesh.new()
    for sx in (-1.0, 1.0):
        for (za, zb) in [(bed_z0 + 0.05, -1.17), (-1.07, bed_z1 - 0.05)]:
            bm_add_box_g(bm_drop, sx * (bed_hw - 0.05), sx * bed_hw, deck_y, drop_top, za, zb)
            for ry in (0.99, 1.16, 1.33):
                bm_add_box_g(bm_drop, sx * bed_hw, sx * (bed_hw + 0.018), ry - 0.030, ry + 0.030, za + 0.02, zb - 0.02)
            bm_add_box_g(bm_drop, sx * (bed_hw - 0.055), sx * (bed_hw + 0.014), drop_top - 0.03, drop_top + 0.01, za, zb)
            bm_add_box_g(bm_drop, sx * (bed_hw - 0.055), sx * (bed_hw + 0.014), deck_y - 0.04, deck_y + 0.02, za, zb)

    # Rear tailgate core & front headboard panel (clean open height = drop_top)
    bm_add_box_g(bm_drop, -bed_hw + 0.05, bed_hw - 0.05, deck_y, drop_top, bed_z0, bed_z0 + 0.05)
    bm_add_box_g(bm_drop, -bed_hw + 0.04, bed_hw - 0.04, deck_y, drop_top, bed_z1 - 0.05, bed_z1)
    bm_add_box_g(bm_drop, -bed_hw + 0.04, bed_hw - 0.04, drop_top - 0.03, drop_top + 0.01, bed_z1 - 0.055, bed_z1 + 0.012)

    finalize_mesh_obj("Bed_AluminumDropsides", bm_drop, mats["AluminumDropside"], col_bed,
                      smooth=False, bevel_width=0.004, bevel_segs=1)

    bm_galv = bmesh.new()
    for sx in (-1.0, 1.0):
        bm_add_box_g(bm_galv, sx * (bed_hw - 0.06), sx * (bed_hw + 0.01), deck_y - 0.11, deck_y - 0.02, bed_z0, bed_z1)
    bm_add_box_g(bm_galv, -bed_hw, bed_hw, deck_y - 0.11, deck_y - 0.02, bed_z0 - 0.01, bed_z0 + 0.06)
    bm_add_box_g(bm_galv, -bed_hw, bed_hw, deck_y - 0.11, deck_y - 0.02, bed_z1 - 0.06, bed_z1 + 0.01)

    for sx in (-1.0, 1.0):
        for pz in (bed_z0 + 0.025, -1.12, bed_z1 - 0.025):
            bm_add_box_g(bm_galv, sx * (bed_hw - 0.06), sx * (bed_hw + 0.024), deck_y - 0.08, drop_top + 0.02, pz - 0.042, pz + 0.042)
        for lz in (bed_z0 + 0.10, -1.21, -1.03, bed_z1 - 0.10):
            bm_add_box_g(bm_galv, sx * (bed_hw + 0.012), sx * (bed_hw + 0.036), 1.20, 1.38, lz - 0.018, lz + 0.018)
        for hz in (-2.62, -1.85, -1.35, -0.82, -0.10, 0.44):
            bm_add_box_g(bm_galv, sx * (bed_hw + 0.005), sx * (bed_hw + 0.032), deck_y - 0.06, deck_y + 0.05, hz - 0.025, hz + 0.025)

    # Sleek galvanized frame bordering the lower rear tailgate signboard (y = 0.88 .. 1.45)!
    bm_add_box_g(bm_galv, -1.04, 1.04, deck_y - 0.02, deck_y + 0.015, bed_z0 - 0.026, bed_z0 + 0.03)
    bm_add_box_g(bm_galv, -1.04, 1.04, drop_top - 0.015, drop_top + 0.022, bed_z0 - 0.026, bed_z0 + 0.03)
    for sx in (-1.0, 1.0):
        bm_add_box_g(bm_galv, sx * 0.99, sx * 1.05, deck_y - 0.02, drop_top + 0.022, bed_z0 - 0.026, bed_z0 + 0.03)

    finalize_mesh_obj("Bed_GalvHardware_BannerFrame", bm_galv, mats["GalvSteel"], col_bed,
                      smooth=False, bevel_width=0.004, bevel_segs=1)

    # Seamless matte-black signboard backing spanning full lower rear tailgate!
    bm_bback = bmesh.new()
    bm_add_box_g(bm_bback, -0.995, 0.995, deck_y + 0.012, drop_top - 0.012, bed_z0 - 0.014, bed_z0 + 0.005)
    finalize_mesh_obj("Bed_RearBannerBacking", bm_bback, mats["BannerBackingBlack"], col_bed, smooth=False)

    # Crisp undistorted "GARDASLAR SEBZE MEYVE" banner centered on the lower rear tailgate!
    # Artwork bounds inside 1024x512 PNG: U=[0.06..0.94] (901px), V=[0.15..0.85] (358px) -> 2.52:1 exact ratio!
    # Quad width=1.42m (-0.71..+0.71), height=0.52m (0.90..1.42) -> 2.73:1 (natural, crisp, zero squishing!)
    make_uv_quad_obj(
        "Bed_RearBannerDecal",
        (0.71, 0.90, bed_z0 - 0.018), (-0.71, 0.90, bed_z0 - 0.018),
        (-0.71, 1.42, bed_z0 - 0.018), (0.71, 1.42, bed_z0 - 0.018),
        mats["RearBannerDecal"], col_bed,
        uvs=[(0.06, 0.15), (0.94, 0.15), (0.94, 0.85), (0.06, 0.85)]
    )

    bm_tl_box = bmesh.new()
    bm_tl_red = bmesh.new()
    bm_tl_amb = bmesh.new()
    bm_tl_rev = bmesh.new()

    for sx in (-1.0, 1.0):
        bm_add_box_g(bm_tl_box, sx * 0.56, sx * 0.98, 0.56, 0.77, bed_z0 - 0.03, bed_z0 + 0.08)
        bm_add_box_g(bm_tl_amb, sx * 0.85, sx * 0.96, 0.585, 0.745, bed_z0 - 0.044, bed_z0 - 0.01)
        bm_add_box_g(bm_tl_red, sx * 0.67, sx * 0.84, 0.585, 0.745, bed_z0 - 0.044, bed_z0 - 0.01)
        bm_add_box_g(bm_tl_rev, sx * 0.575, sx * 0.66, 0.585, 0.745, bed_z0 - 0.044, bed_z0 - 0.01)

        for mz in (-2.55, -1.12, 0.34):
            bm_add_box_g(bm_tl_amb, sx * (bed_hw + 0.004), sx * (bed_hw + 0.022), deck_y - 0.095, deck_y - 0.055, mz - 0.045, mz + 0.045)

    bm_add_box_g(bm_tl_box, -0.280, 0.280, 0.59, 0.72, bed_z0 - 0.02, bed_z0 + 0.03)
    make_uv_quad_obj(
        "MK7_RearPlateDecal",
        (0.268, 0.600, bed_z0 - 0.024), (-0.268, 0.600, bed_z0 - 0.024),
        (-0.268, 0.710, bed_z0 - 0.024), (0.268, 0.710, bed_z0 - 0.024),
        mats["LicensePlateTR"], col_lights
    )

    finalize_mesh_obj("MK7_TailLightHousings", bm_tl_box, mats["RubberBlack"], col_lights, smooth=False, bevel_width=0.004)
    finalize_mesh_obj("MK7_TailLightsRed", bm_tl_red, mats["TailLightRed"], col_lights, smooth=False, bevel_width=0.003)
    finalize_mesh_obj("MK7_RearSideAmberMarkers", bm_tl_amb, mats["AmberIndicator"], col_lights, smooth=False, bevel_width=0.003)
    finalize_mesh_obj("MK7_ReverseLights", bm_tl_rev, mats["ReverseWhite"], col_lights, smooth=False, bevel_width=0.003)


# =============================================================================
# 4. LOADED COLORFUL TURKISH HAL PRODUCE CRATES INSIDE THE OPEN FLATBED!
# =============================================================================
def build_cargo_crates(mats, cols):
    col_prod = cols["05_ProduceCrates"]
    rng = random.Random(4534)

    crate_mat_names = ["CrateRed", "CrateGreen", "CrateBlue", "CrateYellow", "CrateOrange"]
    fruit_specs = [
        ("FruitTomato", 0.055, (1.0, 0.85, 1.0)),
        ("FruitWatermelon", 0.135, (1.28, 0.92, 0.92)),
        ("FruitOrange", 0.056, (1.0, 0.95, 1.0)),
        ("FruitLemon", 0.048, (1.35, 0.85, 0.85)),
        ("FruitEggplant", 0.056, (1.55, 0.78, 0.78)),
        ("FruitApple", 0.058, (1.0, 0.94, 1.0)),
        ("FruitOnion", 0.054, (1.0, 0.88, 1.0)),
    ]

    crate_bms = {name: bmesh.new() for name in crate_mat_names}
    fruit_bms = {spec[0]: bmesh.new() for spec in fruit_specs}

    def add_plastic_crate(bm, cx, cy, cz, w=0.58, h=0.31, d=0.44):
        hw, hd, t = w * 0.5, d * 0.5, 0.026
        bm_add_box_g(bm, cx - hw, cx + hw, cy, cy + 0.03, cz - hd, cz + hd)
        for sx in (-1, 1):
            for sz in (-1, 1):
                bm_add_box_g(bm, cx + sx * (hw - 0.04), cx + sx * hw, cy, cy + h, cz + sz * (hd - 0.04), cz + sz * hd)
        for (ry0, ry1) in [(cy + 0.03, cy + 0.12), (cy + h - 0.075, cy + h)]:
            bm_add_box_g(bm, cx - hw, cx + hw, ry0, ry1, cz - hd, cz - hd + t)
            bm_add_box_g(bm, cx - hw, cx + hw, ry0, ry1, cz + hd - t, cz + hd)
            bm_add_box_g(bm, cx - hw, cx - hw + t, ry0, ry1, cz - hd, cz + hd)
            bm_add_box_g(bm, cx + hw - t, cx + hw, ry0, ry1, cz - hd, cz + hd)
        bm_add_box_g(bm, cx - hw - 0.012, cx + hw + 0.012, cy + h - 0.032, cy + h + 0.008, cz - hd - 0.012, cz - hd + 0.028)
        bm_add_box_g(bm, cx - hw - 0.012, cx + hw + 0.012, cy + h - 0.032, cy + h + 0.008, cz + hd - 0.028, cz + hd + 0.012)
        bm_add_box_g(bm, cx - hw - 0.012, cx - hw + 0.028, cy + h - 0.032, cy + h + 0.008, cz - hd - 0.012, cz + hd + 0.012)
        bm_add_box_g(bm, cx + hw - 0.028, cx + hw + 0.012, cy + h - 0.032, cy + h + 0.008, cz - hd - 0.012, cz + hd + 0.012)

    def add_produce_mound(bm, cx, top_y, cz, rad, scale_xyz, count):
        for _ in range(count):
            ox = rng.uniform(-0.20, 0.20)
            oz = rng.uniform(-0.13, 0.13)
            oy = rng.uniform(-0.02, 0.06)
            rot = Euler((rng.uniform(0, 3.14), rng.uniform(0, 3.14), rng.uniform(0, 3.14))).to_matrix().to_4x4()
            scl = Matrix.Diagonal((scale_xyz[0], scale_xyz[2], scale_xyz[1], 1.0))
            mat_t = Matrix.Translation(G(cx + ox, top_y + oy, cz + oz)) @ rot @ scl
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=rad, matrix=mat_t)

    deck_y, crate_h = 0.885, 0.315
    cols_x = [-0.64, 0.0, 0.64]
    rows_z = [0.30, -0.22, -0.74, -1.26, -1.78, -2.30]

    for ri, cz in enumerate(rows_z):
        for ci, cx in enumerate(cols_x):
            # Clean grounded 2-high stacks (peeking naturally just above the 56cm open drop-sides!)
            stack_n = 2 if (ri <= 4 or ci != 1) else 1
            c_name = crate_mat_names[(ri * 3 + ci) % len(crate_mat_names)]
            f_spec = fruit_specs[(ri * 2 + ci) % len(fruit_specs)]

            for lv in range(stack_n):
                add_plastic_crate(crate_bms[c_name], cx + rng.uniform(-0.018, 0.018),
                                  deck_y + lv * crate_h, cz + rng.uniform(-0.018, 0.018))

            top_y = deck_y + stack_n * crate_h - 0.03
            f_mat, f_rad, f_scl = f_spec
            add_produce_mound(fruit_bms[f_mat], cx, top_y, cz, f_rad, f_scl, 3 if f_mat == "FruitWatermelon" else 9)

    for cname, bm in crate_bms.items():
        if len(bm.verts) > 0:
            finalize_mesh_obj(f"Cargo_{cname}", bm, mats[cname], col_prod, smooth=False)
        else:
            bm.free()
    for fname, bm in fruit_bms.items():
        if len(bm.verts) > 0:
            finalize_mesh_obj(f"Cargo_{fname}", bm, mats[fname], col_prod, smooth=True)
        else:
            bm.free()


# =============================================================================
# 5. FORD TRANSIT 350L 6-LUG WHEELS (Single Front + Heavy Dually Rear)
# =============================================================================
def build_transit_wheel_obj(name: str, dually: bool, out_sign: float, center_godot, mats, col):
    bm = bmesh.new()
    mat_list = [mats["TireRubber"], mats["RimSilver"], mats["WheelHubDark"], mats["Chrome"]]
    r, r_rim = WHEEL_RADIUS, 0.215

    def add_sculpted_tire(x_c, width):
        hw = width * 0.5
        prof = [
            (x_c - hw * 0.84, r_rim - 0.008),
            (x_c - hw * 0.96, r_rim + 0.042),
            (x_c - hw * 1.00, r_rim + 0.092),
            (x_c - hw * 0.94, r - 0.022),
            (x_c - hw * 0.78, r),
            (x_c - hw * 0.26, r + 0.003),
            (x_c + hw * 0.26, r + 0.003),
            (x_c + hw * 0.78, r),
            (x_c + hw * 0.94, r - 0.022),
            (x_c + hw * 1.00, r_rim + 0.092),
            (x_c + hw * 0.96, r_rim + 0.042),
            (x_c + hw * 0.84, r_rim - 0.008),
        ]
        bm_add_lathe_x_g(bm, prof, 0.0, 0.0, segs=32, mat_idx=0)
        for i in range(28):
            ang = 2.0 * math.pi * i / 28.0
            ly, lz = (r - 0.002) * math.sin(ang), (r - 0.002) * math.cos(ang)
            rot = Matrix.Rotation(-ang, 4, "X")
            mat_t = Matrix.Translation(G(x_c, ly, lz)) @ rot @ Matrix.Diagonal((width * 0.74, 0.032, 0.014, 1.0))
            ret = bmesh.ops.create_cube(bm, size=1.0, matrix=mat_t)
            vs = set(ret["verts"])
            for f in bm.faces:
                if all(v in vs for v in f.verts):
                    f.material_index = 0

    s = out_sign
    if not dually:
        add_sculpted_tire(0.0, 0.225)
        rim_prof = [
            (-s * 0.105, r_rim), (-s * 0.080, r_rim - 0.022), (s * 0.040, r_rim - 0.028),
            (s * 0.088, r_rim - 0.012), (s * 0.105, r_rim + 0.004), (s * 0.112, r_rim - 0.006),
            (s * 0.092, r_rim - 0.026), (s * 0.070, 0.135), (s * 0.092, 0.095),
            (s * 0.095, 0.052), (s * 0.095, 0.001),
        ]
        bm_add_lathe_x_g(bm, rim_prof, 0.0, 0.0, segs=28, mat_idx=1)
        bm_add_cyl_x_g(bm, -s * 0.095, -s * 0.06, 0.0, 0.0, r_rim - 0.015, segs=24, mat_idx=2)
        for i in range(12):
            a = 2.0 * math.pi * i / 12.0
            bm_add_cyl_x_g(bm, s * 0.072, s * 0.094, 0.156 * math.sin(a), 0.156 * math.cos(a), 0.018, segs=8, mat_idx=2)
        bm_add_cyl_x_g(bm, s * 0.088, s * 0.118, 0.0, 0.0, 0.056, segs=18, mat_idx=2)
        for i in range(6):
            a = 2.0 * math.pi * i / 6.0
            bm_add_cyl_x_g(bm, s * 0.086, s * 0.112, 0.092 * math.sin(a), 0.092 * math.cos(a), 0.013, segs=6, mat_idx=3)
    else:
        add_sculpted_tire(-0.118, 0.195)
        add_sculpted_tire( 0.118, 0.195)
        rim_prof = [
            (-s * 0.195, r_rim), (-s * 0.120, r_rim - 0.025), (s * 0.020, 0.130),
            (s * 0.055, 0.125), (s * 0.185, r_rim - 0.018), (s * 0.210, r_rim + 0.004),
            (s * 0.215, r_rim - 0.012), (s * 0.175, r_rim - 0.032), (s * 0.068, 0.132),
            (s * 0.052, 0.085), (s * 0.052, 0.001),
        ]
        bm_add_lathe_x_g(bm, rim_prof, 0.0, 0.0, segs=28, mat_idx=1)
        bm_add_cyl_x_g(bm, -s * 0.18, -s * 0.08, 0.0, 0.0, r_rim - 0.018, segs=20, mat_idx=2)
        bm_add_cyl_x_g(bm, s * 0.045, s * 0.175, 0.0, 0.0, 0.068, segs=18, mat_idx=2)
        bm_add_cyl_x_g(bm, s * 0.165, s * 0.185, 0.0, 0.0, 0.050, segs=16, mat_idx=1)
        for i in range(6):
            a = 2.0 * math.pi * i / 6.0
            bm_add_cyl_x_g(bm, s * 0.048, s * 0.105, 0.098 * math.sin(a), 0.098 * math.cos(a), 0.015, segs=6, mat_idx=3)
        for i in range(6):
            a = 2.0 * math.pi * (i + 0.5) / 6.0
            bm_add_cyl_x_g(bm, s * 0.11, s * 0.15, 0.158 * math.sin(a), 0.158 * math.cos(a), 0.022, segs=10, mat_idx=2)

    obj = finalize_mesh_obj(name, bm, mat_list, col, smooth=True, edge_split_deg=42.0)
    obj.location = G(*center_godot)
    return obj


# =============================================================================
# 6. STUDIO LIGHTING & 4-ANGLE EEVEE RENDER VERIFICATION
# =============================================================================
def setup_studio_and_render(cols):
    col_studio = ensure_collection("99_StudioRender")
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    scene.view_settings.exposure = 0.08

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.58, 0.68, 0.80, 1.0)
        bg.inputs["Strength"].default_value = 0.78

    bm_floor = bmesh.new()
    bmesh.ops.create_grid(bm_floor, x_segments=1, y_segments=1, size=24.0)
    m_floor = bpy.data.materials.new("StudioFloor")
    bsdf = m_floor.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.30, 0.32, 0.35, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.76
    floor_obj = finalize_mesh_obj("Studio_Floor", bm_floor, m_floor, col_studio, smooth=False)
    floor_obj.location = (0.0, 0.0, -0.002)

    def add_light(name, ltype, loc_g, target_g, energy, color=(1, 1, 1), size=3.0):
        ldata = bpy.data.lights.new(name=name, type=ltype)
        ldata.energy = energy
        ldata.color = color
        if ltype == "AREA":
            ldata.size = size
        elif ltype == "SUN":
            ldata.angle = math.radians(3.5)
        lobj = bpy.data.objects.new(name=name, object_data=ldata)
        link_obj(lobj, col_studio)
        lobj.location = G(*loc_g)
        direction = G(*target_g) - lobj.location
        lobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        return lobj

    add_light("KeySun", "SUN", (-6.0, 9.0, 7.0), (0, 1.2, 0.4), 3.6, (1.0, 0.97, 0.92))
    add_light("FillArea", "AREA", (6.5, 4.5, 5.5), (0, 1.2, 0.5), 360.0, (0.85, 0.92, 1.0), size=6.0)
    add_light("RearRimArea", "AREA", (5.5, 4.2, -7.2), (0, 1.4, -0.8), 260.0, (1.0, 0.96, 0.90), size=5.0)

    cam_data = bpy.data.cameras.new("StudioCam")
    cam_obj = bpy.data.objects.new("StudioCam", cam_data)
    link_obj(cam_obj, col_studio)
    scene.camera = cam_obj

    def render_view(out_path: Path, cam_g, target_g, w=960, h=640, lens=48.0):
        cam_data.lens = lens
        cam_obj.location = G(*cam_g)
        direction = G(*target_g) - cam_obj.location
        cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x = w
        scene.render.resolution_y = h
        scene.render.filepath = str(out_path)
        bpy.ops.render.render(write_still=True)

    # 1. Hero Front-Right 3/4 Closeup (full cab + face + front wheel + bed start)
    render_view(PREVIEW_HERO_PATH, (-3.95, 1.78, 5.85), (0.0, 1.22, 1.15), w=1280, h=800, lens=50.0)

    # 2. 4-Angle Turntable Contact Sheet (full vehicle cleanly framed in every quadrant!)
    tmp_views = [
        (TEX_DIR / "_v1_front34.png", (-5.8, 2.25, 6.5), (0.0, 1.30, 0.0), 46.0),
        (TEX_DIR / "_v2_rear34.png",  (-5.8, 2.35, -6.7), (0.0, 1.35, -0.25), 46.0),
        (TEX_DIR / "_v3_side.png",    (-10.6, 1.42, 0.0), (0.0, 1.30, 0.0), 54.0),
        (TEX_DIR / "_v4_front.png",   (0.0, 1.28, 7.6), (0.0, 1.22, 1.5), 52.0),
    ]
    vw, vh = 640, 420
    panels = []
    for (p, cg, tg, fl) in tmp_views:
        render_view(p, cg, tg, w=vw, h=vh, lens=fl)
        im = bpy.data.images.load(str(p))
        px = np.array(im.pixels[:], dtype=np.float32).reshape((vh, vw, 4))
        panels.append(px)
        bpy.data.images.remove(im)
        p.unlink(missing_ok=True)

    sheet = np.zeros((vh * 2, vw * 2, 4), dtype=np.float32)
    sheet[vh:vh * 2, 0:vw] = panels[0]
    sheet[vh:vh * 2, vw:vw * 2] = panels[1]
    sheet[0:vh, 0:vw] = panels[2]
    sheet[0:vh, vw:vw * 2] = panels[3]
    sheet[vh - 1:vh + 1, :, 0:3] = 0.15
    sheet[:, vw - 1:vw + 1, 0:3] = 0.15

    im_sheet = bpy.data.images.new("PreviewSheet", width=vw * 2, height=vh * 2, alpha=True)
    im_sheet.pixels.foreach_set(sheet.ravel())
    im_sheet.filepath_raw = str(PREVIEW_SHEET_PATH)
    im_sheet.file_format = "PNG"
    im_sheet.save()
    bpy.data.images.remove(im_sheet)

    return col_studio


# =============================================================================
# 7. EXPORT EDITABLE .BLEND + GODOT-READY .GLB FILES
# =============================================================================
def export_glbs(wheel_objs, studio_col):
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    wheel_names = {w.name for w in wheel_objs}
    studio_objs = set(studio_col.objects)
    body_src = [
        o for o in bpy.data.objects
        if o.type == "MESH" and o.name not in wheel_names and o not in studio_objs
    ]

    bpy.ops.object.select_all(action="DESELECT")
    dups = []
    for o in body_src:
        d = o.copy()
        d.data = o.data.copy()
        bpy.context.scene.collection.objects.link(d)
        dups.append(d)

    for d in dups:
        bpy.ops.object.select_all(action="DESELECT")
        d.select_set(True)
        bpy.context.view_layer.objects.active = d
        for m in list(d.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception:
                pass

    bpy.ops.object.select_all(action="DESELECT")
    for d in dups:
        d.select_set(True)
    bpy.context.view_layer.objects.active = dups[0]
    bpy.ops.object.join()
    joined_body = bpy.context.active_object
    joined_body.name = "FordTransitBody"
    joined_body.data.name = "FordTransitBody"

    tri_count = sum(len(p.vertices) - 2 for p in joined_body.data.polygons)
    print(f"EXPORT_STATS FordTransitBody tris={tri_count} mats={[m.name for m in joined_body.data.materials]}")

    def do_glb(path: Path, objs):
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.gltf(
            filepath=str(path),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_materials="EXPORT",
            export_texcoords=True,
            export_normals=True,
        )
        print(f"WROTE {path.name}: {path.stat().st_size} bytes")

    do_glb(MODELS_DIR / "ford_transit_complete.glb", [joined_body] + list(wheel_objs))

    joined_body.name = "FordTransitChassis"
    do_glb(MODELS_DIR / "ford_transit_chassis.glb", [joined_body])

    for (src_w, out_name, obj_name) in [
        (wheel_objs[0], "wheel_front.glb", "WheelFront"),
        (wheel_objs[2], "wheel_rear.glb", "WheelRear"),
    ]:
        wd = src_w.copy()
        wd.data = src_w.data.copy()
        wd.name = obj_name
        wd.location = (0.0, 0.0, 0.0)
        bpy.context.scene.collection.objects.link(wd)
        do_glb(MODELS_DIR / out_name, [wd])
        bpy.data.objects.remove(wd, do_unlink=True)

    bpy.data.objects.remove(joined_body, do_unlink=True)


def main():
    clear_scene()
    TEX_DIR.mkdir(parents=True, exist_ok=True)

    cols = {
        "01_Cab": ensure_collection("01_Cab"),
        "02_FrontFascia": ensure_collection("02_FrontFascia"),
        "03_Windows_Interior": ensure_collection("03_Windows_Interior"),
        "04_CargoBed": ensure_collection("04_CargoBed"),
        "05_ProduceCrates": ensure_collection("05_ProduceCrates"),
        "06_Chassis_Lights": ensure_collection("06_Chassis_Lights"),
        "07_Wheels": ensure_collection("07_Wheels"),
    }

    mats = build_materials()
    build_mk7_cab(mats, cols)
    build_chassis_underbody(mats, cols)
    build_cargo_bed(mats, cols)
    build_cargo_crates(mats, cols)

    w_col = cols["07_Wheels"]
    wheel_objs = [
        build_transit_wheel_obj("Wheel_FL", False, +1.0, (+FRONT_X, WHEEL_RADIUS, FRONT_Z), mats, w_col),
        build_transit_wheel_obj("Wheel_FR", False, -1.0, (-FRONT_X, WHEEL_RADIUS, FRONT_Z), mats, w_col),
        build_transit_wheel_obj("Wheel_RL", True,  +1.0, (+REAR_X,  WHEEL_RADIUS, REAR_Z),  mats, w_col),
        build_transit_wheel_obj("Wheel_RR", True,  -1.0, (-REAR_X,  WHEEL_RADIUS, REAR_Z),  mats, w_col),
    ]

    studio_col = setup_studio_and_render(cols)

    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"SAVED_BLEND {BLEND_PATH} ({BLEND_PATH.stat().st_size} bytes)")

    export_glbs(wheel_objs, studio_col)
    print("BUILD_MK7_DONE")


if __name__ == "__main__":
    main()
