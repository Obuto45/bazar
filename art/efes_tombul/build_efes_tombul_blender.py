#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for the iconic Turkish 50 cl
Efes Pilsen Tombul Sise ("Tombul Efes") dark-amber stubby beer bottle.

Run headless:
    blender --background --python art/efes_tombul/build_efes_tombul_blender.py

Outputs:
  - art/efes_tombul/efes_tombul.blend         (editable Blender project)
  - art/efes_tombul/efes_tombul.glb           (game-ready glTF/GLB for Godot 4.7)
  - art/efes_tombul/preview_4angle.png        (4-angle studio turntable sheet)
  - art/efes_tombul/preview_closeup.png       (hero front 3/4 macro close-up)
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TEX_DIR = SCRIPT_DIR / "textures"
BLEND_PATH = SCRIPT_DIR / "efes_tombul.blend"
GLB_PATH = SCRIPT_DIR / "efes_tombul.glb"
PREVIEW_4ANGLE = SCRIPT_DIR / "preview_4angle.png"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"

# =============================================================================
# AUTHENTIC TOMBUL EFES (50 cl Euro/Steinie Stubby) PROFILE (radius, z) in meters
# Total height: 0.210 m (21.0 cm), stout wide diameter: 0.0776 m (7.76 cm)
# =============================================================================
BOTTLE_PROFILE = [
    # Recessed punt bottom
    (0.0000, 0.0052),
    (0.0120, 0.0048),
    (0.0220, 0.0028),
    (0.0285, 0.0005),
    (0.0322, 0.0000),
    (0.0352, 0.0014),
    # Chunky curved heel
    (0.0374, 0.0050),
    (0.0384, 0.0100),
    (0.0388, 0.0145),
    # Classic stout cylindrical Tombul body (label zone: z = 0.018 .. 0.100)
    (0.0388, 0.0260),
    (0.0388, 0.0480),
    (0.0388, 0.0720),
    (0.0388, 0.0940),
    (0.0387, 0.1020),
    # Iconic wide plump Tombul rounded shoulder!
    (0.0380, 0.1100),
    (0.0365, 0.1180),
    (0.0340, 0.1255),
    (0.0306, 0.1325),
    (0.0268, 0.1390),
    (0.0230, 0.1450),
    (0.0196, 0.1510),
    (0.0172, 0.1570),
    # Short stubby tapered neck (neck foil zone: z = 0.160 .. 0.189)
    (0.0158, 0.1625),
    (0.0150, 0.1700),
    (0.0143, 0.1780),
    (0.0137, 0.1860),
    (0.0133, 0.1920),
    (0.0131, 0.1955),
    # Classic glass collar ring under crown cap
    (0.0144, 0.1975),
    (0.0147, 0.1998),
    (0.0137, 0.2018),
    (0.0145, 0.2040),
    (0.0140, 0.2062),
    (0.0114, 0.2070),
    (0.0100, 0.2060),
    # Closed throat inside cap
    (0.0100, 0.1960),
    (0.0000, 0.1960),
]

# Inner dark golden-amber beer liquid (fills up into lower neck)
LIQUID_PROFILE = [
    (0.0000, 0.0115),
    (0.0300, 0.0115),
    (0.0352, 0.0155),
    (0.0356, 0.0260),
    (0.0356, 0.1010),
    (0.0338, 0.1160),
    (0.0294, 0.1290),
    (0.0234, 0.1410),
    (0.0176, 0.1520),
    (0.0140, 0.1630),
    (0.0128, 0.1745),
    (0.0112, 0.1758),
    (0.0000, 0.1758),
]


def interp_bottle_radius(z: float) -> float:
    """Interpolate outer radius of the bottle at height z (for conformal labels)."""
    pts = BOTTLE_PROFILE[4:33]
    if z <= pts[0][1]:
        return pts[0][0]
    if z >= pts[-1][1]:
        return pts[-1][0]
    for i in range(len(pts) - 1):
        r0, z0 = pts[i]
        r1, z1 = pts[i + 1]
        if z0 <= z <= z1 and abs(z1 - z0) > 1e-7:
            t = (z - z0) / (z1 - z0)
            return r0 + (r1 - r0) * t
    return pts[-1][0]


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
    if obj.type != "MESH":
        return
    for poly in obj.data.polygons:
        poly.use_smooth = True


def build_lathe_mesh(name: str, profile, segs: int = 64) -> bpy.types.Object:
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            v = bm.verts.new((0.0, 0.0, z))
            rings.append([v])
        else:
            ring = []
            for i in range(segs):
                a = (i / segs) * math.tau
                ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
            rings.append(ring)

    for k in range(len(rings) - 1):
        r0 = rings[k]
        r1 = rings[k + 1]
        if len(r0) == 1 and len(r1) > 1:
            v0 = r0[0]
            for i in range(segs):
                bm.faces.new((v0, r1[(i + 1) % segs], r1[i]))
        elif len(r0) > 1 and len(r1) == 1:
            v1 = r1[0]
            for i in range(segs):
                bm.faces.new((r0[i], r0[(i + 1) % segs], v1))
        elif len(r0) > 1 and len(r1) > 1:
            for i in range(segs):
                ni = (i + 1) % segs
                bm.faces.new((r0[i], r0[ni], r1[ni], r1[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    set_smooth(obj)
    return obj


def build_conformal_label(
    name: str,
    z_min: float,
    z_max: float,
    ang_center_deg: float,
    ang_span_deg: float,
    radial_offset: float = 0.00038,
    u_segs: int = 40,
    v_segs: int = 16,
    full_wrap: bool = False,
) -> bpy.types.Object:
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    grid = []
    for iv in range(v_segs + 1):
        v_t = iv / v_segs
        z = z_min + (z_max - z_min) * v_t
        r = interp_bottle_radius(z) + radial_offset
        row = []
        for iu in range(u_segs + 1):
            u_t = iu / u_segs
            if full_wrap:
                ang = math.radians(ang_center_deg) + (u_t - 0.5) * math.tau
            else:
                ang = math.radians(ang_center_deg + (u_t - 0.5) * ang_span_deg)
            row.append(bm.verts.new((math.cos(ang) * r, math.sin(ang) * r, z)))
        grid.append(row)

    for iv in range(v_segs):
        v0 = iv / v_segs
        v1 = (iv + 1) / v_segs
        for iu in range(u_segs):
            u0 = iu / u_segs
            u1 = (iu + 1) / u_segs
            f = bm.faces.new((
                grid[iv][iu],
                grid[iv][iu + 1],
                grid[iv + 1][iu + 1],
                grid[iv + 1][iu],
            ))
            for loop, uv in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                loop[uv_layer].uv = uv

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    set_smooth(obj)
    return obj


def build_crown_cap(name: str = "CrownCap") -> bpy.types.Object:
    """Authentic 21-crimp metallic Efes navy & gold crown cap."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    crimps = 21
    segs = crimps * 4

    z_bot = 0.2028
    z_mid = 0.2064
    z_top = 0.2100
    z_dome = 0.2106
    r_inner = 0.0144
    r_top = 0.0142

    ring_bot, ring_mid, ring_top, ring_in = [], [], [], []
    for i in range(segs):
        a = (i / segs) * math.tau
        flute = 0.5 + 0.5 * math.cos(a * crimps)
        r_b = 0.0149 + 0.00115 * flute
        r_m = 0.0145 + 0.00055 * flute
        ring_bot.append(bm.verts.new((math.cos(a) * r_b, math.sin(a) * r_b, z_bot)))
        ring_mid.append(bm.verts.new((math.cos(a) * r_m, math.sin(a) * r_m, z_mid)))
        ring_top.append(bm.verts.new((math.cos(a) * r_top, math.sin(a) * r_top, z_top)))
        ring_in.append(bm.verts.new((math.cos(a) * r_inner, math.sin(a) * r_inner, z_bot + 0.0006)))

    v_center = bm.verts.new((0.0, 0.0, z_dome))
    for i in range(segs):
        ni = (i + 1) % segs
        for f in (
            bm.faces.new((ring_bot[i], ring_bot[ni], ring_mid[ni], ring_mid[i])),
            bm.faces.new((ring_mid[i], ring_mid[ni], ring_top[ni], ring_top[i])),
            bm.faces.new((ring_in[i], ring_in[ni], ring_bot[ni], ring_bot[i])),
        ):
            for loop in f.loops:
                loop[uv_layer].uv = (0.04, 0.04)

    for i in range(segs):
        ni = (i + 1) % segs
        f = bm.faces.new((ring_top[i], ring_top[ni], v_center))
        for loop in f.loops:
            co = loop.vert.co
            loop[uv_layer].uv = (0.5 + co.x / (r_top * 2.05), 0.5 + co.y / (r_top * 2.05))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    set_smooth(obj)
    return obj


# =============================================================================
# MATERIALS (Rich Dark Chestnut-Amber Glass + Crisp Paper/Foil Labels)
# =============================================================================
def _get_bsdf(mat: bpy.types.Material):
    if not mat.node_tree:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def make_amber_glass_mat() -> bpy.types.Material:
    mat = bpy.data.materials.new("AmberGlass")
    bsdf = _get_bsdf(mat)
    # Deep authentic dark chestnut-amber Turkish beer bottle glass
    bsdf.inputs["Base Color"].default_value = (0.068, 0.017, 0.0025, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.02
    bsdf.inputs["Roughness"].default_value = 0.055
    if "IOR" in bsdf.inputs:
        bsdf.inputs["IOR"].default_value = 1.54
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = 0.28
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 1.0
        bsdf.inputs["Coat Roughness"].default_value = 0.03
    bsdf.inputs["Alpha"].default_value = 0.90
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    return mat


def make_beer_liquid_mat() -> bpy.types.Material:
    mat = bpy.data.materials.new("BeerLiquid")
    bsdf = _get_bsdf(mat)
    bsdf.inputs["Base Color"].default_value = (0.26, 0.085, 0.006, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.14
    return mat


def make_foam_mat() -> bpy.types.Material:
    mat = bpy.data.materials.new("BeerFoam")
    bsdf = _get_bsdf(mat)
    bsdf.inputs["Base Color"].default_value = (0.94, 0.89, 0.74, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.75
    return mat


def make_textured_mat(name: str, tex_path: Path, roughness: float = 0.32, metallic: float = 0.10, use_alpha: bool = False) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    bsdf = _get_bsdf(mat)
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(tex_path))
    img.pack()
    tex.image = img
    tex.extension = "CLIP" if use_alpha else "REPEAT"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if use_alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if hasattr(mat, "blend_method"):
            mat.blend_method = "CLIP"
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.18
        bsdf.inputs["Coat Roughness"].default_value = 0.24
    return mat


def build_bottle():
    col = ensure_collection("EfesTombul")
    root = bpy.data.objects.new("EfesTombulBottle", None)
    link_obj(root, col)

    mat_glass = make_amber_glass_mat()
    mat_liquid = make_beer_liquid_mat()
    mat_foam = make_foam_mat()
    mat_front = make_textured_mat("LabelFrontMat", TEX_DIR / "label_front.png", roughness=0.34, metallic=0.12, use_alpha=True)
    mat_neck = make_textured_mat("LabelNeckMat", TEX_DIR / "label_neck.png", roughness=0.24, metallic=0.45, use_alpha=False)
    mat_back = make_textured_mat("LabelBackMat", TEX_DIR / "label_back.png", roughness=0.38, metallic=0.05, use_alpha=True)
    mat_cap = make_textured_mat("CrownCapMat", TEX_DIR / "cap_top.png", roughness=0.22, metallic=0.72, use_alpha=False)

    bottle = build_lathe_mesh("AmberBottleGlass", BOTTLE_PROFILE, segs=64)
    bottle.data.materials.append(mat_glass)
    bottle.parent = root
    link_obj(bottle, col)

    liquid = build_lathe_mesh("PilsnerLiquid", LIQUID_PROFILE, segs=40)
    liquid.data.materials.append(mat_liquid)
    liquid.parent = root
    link_obj(liquid, col)

    foam_prof = [
        (0.0000, 0.1756),
        (0.0108, 0.1758),
        (0.0124, 0.1778),
        (0.0124, 0.1790),
        (0.0092, 0.1792),
        (0.0000, 0.1772),
    ]
    foam = build_lathe_mesh("BeerFoam", foam_prof, segs=32)
    foam.data.materials.append(mat_foam)
    foam.parent = root
    link_obj(foam, col)

    # Front Iconic Oval/Shield Efes Label (stout broad wrap on cylindrical belly)
    lbl_front = build_conformal_label(
        "LabelFront",
        z_min=0.018,
        z_max=0.100,
        ang_center_deg=-90.0,
        ang_span_deg=128.0,
        radial_offset=0.00040,
        u_segs=40,
        v_segs=14,
    )
    lbl_front.data.materials.append(mat_front)
    lbl_front.parent = root
    link_obj(lbl_front, col)

    # Metallic Gold & Navy Neck Collar Foil
    lbl_neck = build_conformal_label(
        "LabelNeckFoil",
        z_min=0.159,
        z_max=0.189,
        ang_center_deg=-90.0,
        ang_span_deg=360.0,
        radial_offset=0.00035,
        u_segs=48,
        v_segs=10,
        full_wrap=True,
    )
    lbl_neck.data.materials.append(mat_neck)
    lbl_neck.parent = root
    link_obj(lbl_neck, col)

    # Back Heritage & Barcode Label
    lbl_back = build_conformal_label(
        "LabelBack",
        z_min=0.022,
        z_max=0.094,
        ang_center_deg=90.0,
        ang_span_deg=86.0,
        radial_offset=0.00040,
        u_segs=24,
        v_segs=12,
    )
    lbl_back.data.materials.append(mat_back)
    lbl_back.parent = root
    link_obj(lbl_back, col)

    # 21-Crimp Crown Cap
    cap = build_crown_cap("CrownCap")
    cap.data.materials.append(mat_cap)
    cap.parent = root
    link_obj(cap, col)

    return root, col


def setup_studio():
    col = ensure_collection("Studio")
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.15

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.045, 0.052, 0.072, 1.0)
    bg.inputs["Strength"].default_value = 0.55

    # Dark matte slate plinth so gold/cream labels never blow out!
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.45, depth=0.015, location=(0.0, 0.0, -0.0075))
    floor = bpy.context.active_object
    floor.name = "StudioPlinth"
    fmat = bpy.data.materials.new("PlinthMat")
    fbsdf = _get_bsdf(fmat)
    fbsdf.inputs["Base Color"].default_value = (0.06, 0.065, 0.08, 1.0)
    fbsdf.inputs["Roughness"].default_value = 0.42
    floor.data.materials.append(fmat)
    link_obj(floor, col)

    # Balanced commercial product lighting: crisp softbox key + cool fill + warm amber rim!
    lights = [
        ("KeyLight", "AREA", (0.36, -0.44, 0.30), (0.0, 0.0, 0.105), 11.5, (1.0, 0.96, 0.90), 0.34),
        ("FillLight", "AREA", (-0.42, -0.30, 0.22), (0.0, 0.0, 0.105), 5.5, (0.80, 0.88, 1.0), 0.48),
        ("RimAmberL", "AREA", (-0.28, 0.26, 0.15), (0.0, 0.0, 0.100), 14.0, (1.0, 0.62, 0.18), 0.16),
        ("RimAmberR", "AREA", (0.28, 0.26, 0.15), (0.0, 0.0, 0.100), 14.0, (1.0, 0.68, 0.24), 0.16),
        ("TopSpec", "AREA", (0.0, -0.14, 0.46), (0.0, 0.0, 0.15), 5.0, (1.0, 0.98, 0.94), 0.24),
    ]
    for lname, ltype, loc, tgt, energy, color, sz in lights:
        ldata = bpy.data.lights.new(lname, type=ltype)
        ldata.energy = energy
        ldata.color = color
        ldata.size = sz
        lobj = bpy.data.objects.new(lname, ldata)
        lobj.location = Vector(loc)
        lobj.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        link_obj(lobj, col)

    cam_data = bpy.data.cameras.new("StudioCam")
    cam_data.lens = 78.0
    cam = bpy.data.objects.new("StudioCam", cam_data)
    link_obj(cam, col)
    scene.camera = cam
    return cam, col


def render_view(cam, loc, tgt, out_path: Path, res_x: int, res_y: int, lens: float = 78.0):
    scene = bpy.context.scene
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
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


def export_glb(bottle_col):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bottle_col.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )


def main():
    clear_scene()
    _, bottle_col = build_bottle()
    export_glb(bottle_col)

    cam, _ = setup_studio()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    tmp_dir = SCRIPT_DIR / "_tmp_renders"
    tmp_dir.mkdir(exist_ok=True)
    views = [
        ("front", (0.0, -0.52, 0.115), (0.0, 0.0, 0.104), 78.0),
        ("hero34", (0.31, -0.41, 0.165), (0.0, 0.0, 0.104), 76.0),
        ("side", (0.52, 0.0, 0.115), (0.0, 0.0, 0.104), 78.0),
        ("back", (0.0, 0.52, 0.115), (0.0, 0.0, 0.104), 78.0),
    ]
    tmp_paths = []
    for tag, loc, tgt, lens in views:
        p = tmp_dir / f"{tag}.png"
        render_view(cam, loc, tgt, p, 640, 760, lens)
        tmp_paths.append(p)
    stitch_2x2(tmp_paths, PREVIEW_4ANGLE)

    render_view(cam, (0.20, -0.34, 0.145), (0.0, 0.0, 0.106), PREVIEW_CLOSEUP, 1024, 1152, 78.0)

    for p in tmp_paths:
        p.unlink(missing_ok=True)
    tmp_dir.rmdir()
    print("EFES_TOMBUL_BUILD_OK")


if __name__ == "__main__":
    main()
