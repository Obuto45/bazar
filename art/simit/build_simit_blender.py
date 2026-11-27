#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for an authentic Turkish Street Simit (Susamli Simit).
Two-strand braided sesame ring split into 10 angular segments (SimitSeg_0..9)
so player.gd bites remove segments progressively.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TEX_DIR = SCRIPT_DIR / "textures"
BLEND_PATH = SCRIPT_DIR / "simit.blend"
GLB_PATH = SCRIPT_DIR / "simit.glb"
PREVIEW_4ANGLE = SCRIPT_DIR / "preview_4angle.png"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"

SEG_COUNT = 10
RING_R = 0.068
STRAND_OFFSET = 0.0062
STRAND_R = 0.0148
TWISTS_PER_RING = 5  # graceful classic 2-strand Turkish simit rope braid


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _bsdf(mat):
    if mat.node_tree is None:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def make_crust_texture(out_path: Path):
    """Generate procedural baked pekmez-golden simit crust texture (512x512)."""
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    w, h = 512, 512
    rng = np.random.default_rng(42)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / w
    v = yy / h

    # Multi-frequency baked dough crust mottling & blister spots
    n1 = np.sin(u * math.tau * 6.0 + np.cos(v * math.tau * 5.0) * 1.4) * 0.5 + 0.5
    n2 = np.sin(u * math.tau * 17.0 - v * math.tau * 13.0) * 0.5 + 0.5
    n3 = np.cos(u * math.tau * 31.0 + v * math.tau * 29.0) * 0.5 + 0.5
    grain = rng.normal(0.0, 0.045, (h, w)).astype(np.float32)
    # Smooth grain slightly with box roll
    grain = (grain + np.roll(grain, 1, 0) + np.roll(grain, 1, 1) + np.roll(grain, -1, 0)) * 0.25

    t = np.clip(0.45 * n1 + 0.35 * n2 + 0.20 * n3 + grain, 0.0, 1.0)
    # Warm golden-pekmez toasted Turkish street simit crust (bright & appetizing in both sun and stall shade)
    dark = np.array([0.38, 0.17, 0.042], dtype=np.float32)
    mid = np.array([0.66, 0.34, 0.095], dtype=np.float32)
    hi = np.array([0.82, 0.49, 0.165], dtype=np.float32)

    col = np.zeros((h, w, 4), dtype=np.float32)
    for c in range(3):
        col[:, :, c] = np.where(
            t < 0.5,
            dark[c] + (mid[c] - dark[c]) * (t * 2.0),
            mid[c] + (hi[c] - mid[c]) * ((t - 0.5) * 2.0),
        )
    # Subtle fine oven blisters (slightly darker dots)
    blisters = np.clip((n3 * n2 - 0.62) * 3.5, 0.0, 1.0)
    for c in range(3):
        col[:, :, c] = np.clip(col[:, :, c] * (1.0 - blisters * 0.28), 0.02, 1.0)
    col[:, :, 3] = 1.0

    im = bpy.data.images.new("SimitCrustTex", width=w, height=h, alpha=False)
    im.pixels[:] = col.ravel()
    im.filepath_raw = str(out_path)
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return out_path


def make_materials():
    tex_path = make_crust_texture(TEX_DIR / "simit_crust.png")

    crust_mat = bpy.data.materials.new("SimitCrust")
    nt = crust_mat.node_tree
    bsdf = _bsdf(crust_mat)
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(tex_path))
    img.pack()
    tex_node.image = img
    nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.58
    bsdf.inputs["Specular IOR Level"].default_value = 0.48
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.18
        bsdf.inputs["Coat Roughness"].default_value = 0.42

    sesame_light = bpy.data.materials.new("SesameLight")
    sb1 = _bsdf(sesame_light)
    sb1.inputs["Base Color"].default_value = (0.86, 0.72, 0.44, 1.0)
    sb1.inputs["Roughness"].default_value = 0.54

    sesame_toast = bpy.data.materials.new("SesameToasted")
    sb2 = _bsdf(sesame_toast)
    sb2.inputs["Base Color"].default_value = (0.68, 0.48, 0.22, 1.0)
    sb2.inputs["Roughness"].default_value = 0.50

    return crust_mat, sesame_light, sesame_toast


def add_sesame_seed(bm: bmesh.types.BMesh, center: Vector, normal: Vector, tangent: Vector, mat_idx: int, rng):
    """Build a flat oval 3D sesame seed pressed snugly into the pekmez crust."""
    length = rng.uniform(0.0036, 0.0048)
    width = length * rng.uniform(0.56, 0.68)
    thick = length * 0.22
    ang = rng.uniform(0.0, math.tau)
    n = normal.normalized()
    t1 = tangent.normalized()
    t2 = n.cross(t1).normalized()
    t1 = t2.cross(n).normalized()
    d1 = t1 * math.cos(ang) + t2 * math.sin(ang)
    d2 = -t1 * math.sin(ang) + t2 * math.cos(ang)

    c = center + n * (thick * 0.15)
    v_tip = bm.verts.new(c + d1 * (length * 0.54))
    v_tail = bm.verts.new(c - d1 * (length * 0.46))
    v_l = bm.verts.new(c + d2 * (width * 0.5))
    v_r = bm.verts.new(c - d2 * (width * 0.5))
    v_top = bm.verts.new(c + n * thick)
    v_bot = bm.verts.new(c - n * (thick * 0.35))

    faces = [
        (v_tip, v_l, v_top), (v_l, v_tail, v_top), (v_tail, v_r, v_top), (v_r, v_tip, v_top),
        (v_l, v_tip, v_bot), (v_tail, v_l, v_bot), (v_r, v_tail, v_bot), (v_tip, v_r, v_bot),
    ]
    for verts in faces:
        f = bm.faces.new(verts)
        f.material_index = mat_idx
        f.smooth = True


def build_segment(seg_idx: int, mats, rng, col):
    """Build one angular slice of the 2-strand braided simit + generous toasted sesame seeds."""
    crust_mat, ses_l, ses_t = mats
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    a0 = (seg_idx / SEG_COUNT) * math.tau - math.pi * 0.35
    a1 = ((seg_idx + 1) / SEG_COUNT) * math.tau - math.pi * 0.35
    pad = 0.008
    steps = 14
    ring_pts = 16

    for strand in range(2):
        phase = strand * math.pi
        rings = []
        for s in range(steps + 1):
            frac = s / steps
            theta = (a0 - pad) + ((a1 - a0) + 2.0 * pad) * frac
            rad_dir = Vector((math.cos(theta), 0.0, math.sin(theta)))
            tan_dir = Vector((-math.sin(theta), 0.0, math.cos(theta)))
            up_dir = Vector((0.0, 1.0, 0.0))

            twist_ang = theta * TWISTS_PER_RING + phase
            h_radial = math.cos(twist_ang) * STRAND_OFFSET
            h_up = math.sin(twist_ang) * STRAND_OFFSET * 0.72
            center = rad_dir * (RING_R + h_radial) + up_dir * h_up

            n1 = rad_dir
            n2 = up_dir
            r_mod = STRAND_R * (1.0 + 0.04 * math.sin(theta * 5.0 + strand))

            ring = []
            for k in range(ring_pts):
                phi = (k / ring_pts) * math.tau
                off = n1 * (math.cos(phi) * r_mod) + n2 * (math.sin(phi) * r_mod * 0.88)
                v = bm.verts.new(center + off)
                ring.append((v, frac, k / ring_pts))
            rings.append((ring, center, rad_dir, tan_dir, up_dir, r_mod, s))

        for s in range(steps):
            r_cur = rings[s][0]
            r_nxt = rings[s + 1][0]
            for k in range(ring_pts):
                kn = (k + 1) % ring_pts
                v00, u0, v0 = r_cur[k]
                v10, u1, _ = r_nxt[k]
                v11, _, v1 = r_nxt[kn]
                v01, _, _ = r_cur[kn]
                f = bm.faces.new((v00, v10, v11, v01))
                f.material_index = 0
                f.smooth = True
                for loop, uv in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                    loop[uv_layer].uv = uv

        for end_i, flip in [(0, True), (steps, False)]:
            r_end, c_end, _, _, _, _, _ = rings[end_i]
            vc = bm.verts.new(c_end)
            for k in range(ring_pts):
                kn = (k + 1) % ring_pts
                verts = (vc, r_end[kn][0], r_end[k][0]) if flip else (vc, r_end[k][0], r_end[kn][0])
                f = bm.faces.new(verts)
                f.material_index = 0
                f.smooth = True

        # Generous authentic Turkish street simit sesame coat pressed flush onto the crust
        for s in range(1, steps):
            _, c_pt, rdir, tdir, udir, r_mod, _ = rings[s]
            for _ in range(7):
                phi = rng.uniform(0.0, math.tau)
                n_loc = (rdir * math.cos(phi) + udir * math.sin(phi) * 0.88).normalized()
                pos = c_pt + (rdir * math.cos(phi) * r_mod + udir * math.sin(phi) * r_mod * 0.88) * 0.96
                if (pos - Vector((rdir.x * RING_R, 0.0, rdir.z * RING_R))).length < STRAND_R * 0.78:
                    continue
                mat_i = 1 if rng.random() < 0.58 else 2
                add_sesame_seed(bm, pos, n_loc, tdir, mat_i, rng)

    mesh = bpy.data.meshes.new(f"SimitSeg_{seg_idx}")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(crust_mat)
    mesh.materials.append(ses_l)
    mesh.materials.append(ses_t)

    obj = bpy.data.objects.new(f"SimitSeg_{seg_idx}", mesh)
    col.objects.link(obj)
    return obj


def build_simit():
    col = bpy.data.collections.new("Simit")
    bpy.context.scene.collection.children.link(col)
    mats = make_materials()
    rng = np.random.default_rng(1337)
    for i in range(SEG_COUNT):
        build_segment(i, mats, rng, col)
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
    bg.inputs["Color"].default_value = (0.07, 0.06, 0.055, 1.0)
    bg.inputs["Strength"].default_value = 0.7

    for lname, loc, tgt, energy, color, sz in [
        ("Key", (0.24, -0.32, 0.24), (0.0, 0.0, 0.0), 12.0, (1.0, 0.95, 0.86), 0.28),
        ("Fill", (-0.28, -0.22, 0.16), (0.0, 0.0, 0.0), 5.0, (0.88, 0.93, 1.0), 0.34),
        ("Rim", (0.0, 0.28, 0.22), (0.0, 0.0, 0.0), 8.0, (1.0, 0.85, 0.65), 0.24),
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


def render_view(cam, loc, tgt, out_path: Path, rx: int, ry: int, lens: float = 72.0):
    scene = bpy.context.scene
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    cam.data.lens = lens
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(out_path)
    bpy.ops.render.render(write_still=True)


def main():
    clear_scene()
    col = build_simit()

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
    render_view(cam, (0.14, -0.26, 0.11), (0.0, 0.0, 0.0), PREVIEW_CLOSEUP, 768, 768, 68.0)
    print("SIMIT_BUILD_OK")


if __name__ == "__main__":
    main()
