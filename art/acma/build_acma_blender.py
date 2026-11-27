#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for a plump, egg-wash glazed Turkish Acma (Pastane Acmasi).
Soft twisted brioche ring split into 8 angular segments (AcmaSeg_0..7)
with glossy golden top crust, creamy pale dough creases, and sparse nigella (corek otu) seeds.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TEX_DIR = SCRIPT_DIR / "textures"
BLEND_PATH = SCRIPT_DIR / "acma.blend"
GLB_PATH = SCRIPT_DIR / "acma.glb"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"

SEG_COUNT = 8
RING_R = 0.056
TUBE_R = 0.0285
TWISTS_PER_RING = 6


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _bsdf(mat):
    if mat.node_tree is None:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def make_acma_texture(out_path: Path):
    """Egg-wash glossy golden top transitioning to creamy pale buttery folds."""
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    w, h = 512, 512
    rng = np.random.default_rng(77)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / w
    v = yy / h

    # v wraps around tube cross-section: top/front gets deep glossy egg-wash gold, crease gets pale cream
    top_band = 0.5 + 0.5 * np.cos((v - 0.25) * math.tau)
    rib = 0.5 + 0.5 * np.sin(u * math.tau * 3.0 + v * math.tau * 2.0)
    mottle = 0.5 + 0.5 * np.sin(u * math.tau * 9.0 + np.cos(v * math.tau * 7.0))
    noise = rng.normal(0.0, 0.025, (h, w)).astype(np.float32)

    bake = np.clip(0.55 * top_band + 0.28 * rib + 0.17 * mottle + noise, 0.0, 1.0)
    pale = np.array([0.78, 0.54, 0.24], dtype=np.float32)
    gold = np.array([0.62, 0.34, 0.095], dtype=np.float32)
    deep = np.array([0.44, 0.19, 0.040], dtype=np.float32)

    col = np.zeros((h, w, 4), dtype=np.float32)
    for c in range(3):
        col[:, :, c] = np.where(
            bake < 0.55,
            pale[c] + (gold[c] - pale[c]) * (bake / 0.55),
            gold[c] + (deep[c] - gold[c]) * ((bake - 0.55) / 0.45),
        )
    col[:, :, 3] = 1.0

    im = bpy.data.images.new("AcmaGlazeTex", width=w, height=h, alpha=False)
    im.pixels[:] = col.ravel()
    im.filepath_raw = str(out_path)
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return out_path


def make_materials():
    tex_path = make_acma_texture(TEX_DIR / "acma_glaze.png")

    dough_mat = bpy.data.materials.new("AcmaDough")
    nt = dough_mat.node_tree
    bsdf = _bsdf(dough_mat)
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(tex_path))
    img.pack()
    tex_node.image = img
    nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    # Glossy egg-wash finish distinguishes acma instantly from matte crusty simit
    bsdf.inputs["Roughness"].default_value = 0.28
    bsdf.inputs["Specular IOR Level"].default_value = 0.65
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.45
        bsdf.inputs["Coat Roughness"].default_value = 0.22

    nigella_mat = bpy.data.materials.new("CorekOtu")
    nb = _bsdf(nigella_mat)
    nb.inputs["Base Color"].default_value = (0.06, 0.055, 0.06, 1.0)
    nb.inputs["Roughness"].default_value = 0.42

    return dough_mat, nigella_mat


def add_corek_otu(bm, center: Vector, normal: Vector, tangent: Vector, rng):
    length = rng.uniform(0.0038, 0.0052)
    width = length * 0.48
    thick = length * 0.34
    ang = rng.uniform(0.0, math.tau)
    n = normal.normalized()
    t1 = tangent.normalized()
    t2 = n.cross(t1).normalized()
    t1 = t2.cross(n).normalized()
    d1 = t1 * math.cos(ang) + t2 * math.sin(ang)
    d2 = -t1 * math.sin(ang) + t2 * math.cos(ang)

    c = center + n * (thick * 0.2)
    v_tip = bm.verts.new(c + d1 * (length * 0.62))
    v_l = bm.verts.new(c + d2 * (width * 0.5) - d1 * (length * 0.38))
    v_r = bm.verts.new(c - d2 * (width * 0.5) - d1 * (length * 0.38))
    v_top = bm.verts.new(c + n * thick)
    for verts in [(v_tip, v_l, v_top), (v_l, v_r, v_top), (v_r, v_tip, v_top), (v_l, v_tip, v_r)]:
        f = bm.faces.new(verts)
        f.material_index = 1
        f.smooth = True


def build_segment(seg_idx: int, mats, rng, col):
    dough_mat, nigella_mat = mats
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    a0 = (seg_idx / SEG_COUNT) * math.tau - math.pi * 0.35
    a1 = ((seg_idx + 1) / SEG_COUNT) * math.tau - math.pi * 0.35
    pad = 0.008
    steps = 16
    ring_pts = 22

    rings = []
    for s in range(steps + 1):
        frac = s / steps
        theta = (a0 - pad) + ((a1 - a0) + 2.0 * pad) * frac
        rad_dir = Vector((math.cos(theta), 0.0, math.sin(theta)))
        tan_dir = Vector((-math.sin(theta), 0.0, math.cos(theta)))
        up_dir = Vector((0.0, 1.0, 0.0))

        center = rad_dir * (RING_R + 0.0018 * math.sin(theta * 4.0))
        ring = []
        for k in range(ring_pts):
            phi = (k / ring_pts) * math.tau
            twist = phi + theta * 4.0
            lobe = 1.0 + 0.085 * math.cos(twist * 2.0)
            r_loc = TUBE_R * lobe
            off = rad_dir * (math.cos(phi) * r_loc) + up_dir * (math.sin(phi) * r_loc * 0.90)
            v = bm.verts.new(center + off)
            ring.append((v, frac, k / ring_pts))
        rings.append((ring, center, rad_dir, tan_dir, up_dir))

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
        r_end, c_end, _, _, _ = rings[end_i]
        vc = bm.verts.new(c_end)
        for k in range(ring_pts):
            kn = (k + 1) % ring_pts
            verts = (vc, r_end[kn][0], r_end[k][0]) if flip else (vc, r_end[k][0], r_end[kn][0])
            f = bm.faces.new(verts)
            f.material_index = 0
            f.smooth = True

    # Sparse stylish black corek otu seeds on front/top puff
    for s in range(2, steps - 1, 3):
        _, c_pt, rdir, tdir, udir = rings[s]
        for _ in range(2):
            phi = rng.uniform(-0.85, 0.85) + (math.pi * 0.5 if rng.random() < 0.5 else -math.pi * 0.5)
            n_loc = (rdir * math.cos(phi) + udir * math.sin(phi)).normalized()
            pos = c_pt + n_loc * (TUBE_R * 1.02)
            add_corek_otu(bm, pos, n_loc, tdir, rng)

    mesh = bpy.data.meshes.new(f"AcmaSeg_{seg_idx}")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(dough_mat)
    mesh.materials.append(nigella_mat)
    obj = bpy.data.objects.new(f"AcmaSeg_{seg_idx}", mesh)
    col.objects.link(obj)
    return obj


def build_acma():
    col = bpy.data.collections.new("Acma")
    bpy.context.scene.collection.children.link(col)
    mats = make_materials()
    rng = np.random.default_rng(2026)
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
        ("Rim", (0.0, 0.28, 0.22), (0.0, 0.0, 0.0), 8.0, (1.0, 0.88, 0.72), 0.24),
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
    col = build_acma()

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
    cam.location = Vector((0.14, -0.25, 0.10))
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(PREVIEW_CLOSEUP)
    bpy.ops.render.render(write_still=True)
    print("ACMA_BUILD_OK")


if __name__ == "__main__":
    main()
