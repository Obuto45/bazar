#!/usr/bin/env python3
"""
Blender 5.3 (bpy) builder for a retro 1980s Turkish Arabesk Cassette Boombox (Arabesk Radyo).
Matches items.gd dimensions (0.32 x 0.18 x 0.11 m, handle at Godot Y=0.215, front at Godot +Z = Blender -Y).
Preserves node name 'Dial' so player.gd frequency color switching & audio beat pulse work seamlessly!
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Vector
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TEX_DIR = SCRIPT_DIR / "textures"
BLEND_PATH = SCRIPT_DIR / "arabesk_radio.blend"
GLB_PATH = SCRIPT_DIR / "arabesk_radio.glb"
PREVIEW_CLOSEUP = SCRIPT_DIR / "preview_closeup.png"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _bsdf(mat):
    if mat.node_tree is None:
        mat.use_nodes = True
    return mat.node_tree.nodes["Principled BSDF"]


def make_mat(name, color, rough=0.40, metal=0.0, coat=0.0, alpha=1.0, emission=None, em_str=0.0):
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
        b.inputs["Coat Roughness"].default_value = 0.25
    if emission is not None and em_str > 0.0:
        b.inputs["Emission Color"].default_value = (*emission, 1.0)
        b.inputs["Emission Strength"].default_value = em_str
    return m


def make_dial_texture(out_path: Path):
    """Retro glowing amber FM/AM frequency scale texture with red indicator needle."""
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    w, h = 512, 96
    img = np.zeros((h, w, 4), dtype=np.float32)
    # Warm vintage backlit amber glass gradient
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    glow = 0.72 + 0.28 * np.sin(yy * math.pi)
    img[:, :, 0] = np.clip(0.98 * glow, 0, 1)
    img[:, :, 1] = np.clip(0.74 * glow, 0, 1)
    img[:, :, 2] = np.clip(0.24 * glow, 0, 1)
    img[:, :, 3] = 1.0

    # Dark frame border
    img[:6, :, :3] *= 0.22
    img[-6:, :, :3] *= 0.22
    img[:, :8, :3] *= 0.22
    img[:, -8:, :3] *= 0.22

    # Horizontal FM / AM guide rails
    img[34:38, 18:-18, :3] = (0.14, 0.08, 0.03)
    img[60:64, 18:-18, :3] = (0.18, 0.11, 0.04)

    # Fine vertical frequency tick marks
    for i in range(44):
        x = int(22 + i * ((w - 44) / 43.0))
        tall = (i % 5 == 0)
        y0 = 18 if tall else 26
        y1 = 44 if tall else 39
        img[y0:y1, max(0, x - 1):min(w, x + 2), :3] = (0.12, 0.06, 0.02)
        if i % 2 == 0:
            img[56:72 if tall else 67, max(0, x - 1):min(w, x + 1), :3] = (0.16, 0.09, 0.03)

    # Iconic crimson FM tuner needle at ~98.4 MHz
    nx = int(w * 0.56)
    img[10:-10, nx - 3:nx + 4, :3] = (0.94, 0.12, 0.08)

    im = bpy.data.images.new("RadioDialTex", width=w, height=h, alpha=False)
    im.pixels[:] = img.ravel()
    im.filepath_raw = str(out_path)
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return out_path


def add_box(name, size, loc, mat, col, rot=(0, 0, 0), bevel_w=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.rotation_euler = Euler(rot, "XYZ")
    bpy.ops.object.transform_apply(scale=True)
    if bevel_w > 0.0:
        b = o.modifiers.new("Bevel", "BEVEL")
        b.width = bevel_w
        b.segments = 2
        bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.unlink(o)
    col.objects.link(o)
    return o


def add_cyl(name, r, depth, loc, mat, col, rot=(0, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = Euler(rot, "XYZ")
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    bpy.context.scene.collection.objects.unlink(o)
    col.objects.link(o)
    return o


def build_radio():
    col = bpy.data.collections.new("ArabeskRadio")
    bpy.context.scene.collection.children.link(col)

    m_body = make_mat("RadioCharcoal", (0.085, 0.085, 0.098), rough=0.40, metal=0.10, coat=0.18)
    m_wood = make_mat("RadioWalnut", (0.24, 0.115, 0.050), rough=0.36, metal=0.0, coat=0.28)
    m_chrome = make_mat("RadioChrome", (0.86, 0.88, 0.91), rough=0.16, metal=0.94)
    m_grille = make_mat("RadioGrille", (0.22, 0.23, 0.26), rough=0.36, metal=0.72)
    m_cone = make_mat("WooferCone", (0.07, 0.07, 0.08), rough=0.72, metal=0.05)
    m_gold = make_mat("RadioGoldTrim", (0.88, 0.72, 0.26), rough=0.24, metal=0.88)
    m_red = make_mat("RecButton", (0.85, 0.14, 0.10), rough=0.32, metal=0.0)
    m_reel = make_mat("CassetteReel", (0.92, 0.90, 0.85), rough=0.45, metal=0.0)
    m_glass = make_mat("DeckGlass", (0.12, 0.15, 0.18), rough=0.08, metal=0.1, alpha=0.35)

    # Dial material with retro frequency scale texture + amber glow
    dial_tex = make_dial_texture(TEX_DIR / "radio_dial.png")
    m_dial = bpy.data.materials.new("RadioDialMat")
    nt = m_dial.node_tree
    bsdf = _bsdf(m_dial)
    tn = nt.nodes.new("ShaderNodeTexImage")
    dimg = bpy.data.images.load(str(dial_tex))
    dimg.pack()
    tn.image = dimg
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.4
    bsdf.inputs["Roughness"].default_value = 0.12

    # 1) Main chassis + vintage walnut side panels + rubber feet
    add_box("RadioChassis", (0.316, 0.106, 0.174), (0.0, 0.0, 0.091), m_body, col, bevel_w=0.008)
    for sx in [-0.157, 0.157]:
        add_box(f"WalnutSide_{sx:+.2f}", (0.012, 0.100, 0.164), (sx, 0.0, 0.091), m_wood, col, bevel_w=0.004)
    for fx in [-0.125, 0.125]:
        for fy in [-0.036, 0.036]:
            add_cyl(f"Foot_{fx:.2f}_{fy:.2f}", 0.012, 0.008, (fx, fy, 0.004), m_cone, col, verts=12)

    # Front brushed chrome bezel frame
    add_box("FrontFrameTop", (0.304, 0.008, 0.008), (0.0, -0.054, 0.168), m_chrome, col)
    add_box("FrontFrameBot", (0.304, 0.008, 0.008), (0.0, -0.054, 0.016), m_chrome, col)
    add_box("FrontFrameMid", (0.304, 0.008, 0.006), (0.0, -0.054, 0.124), m_gold, col)

    # 2) Glowing frequency tuning bar named EXACTLY 'Dial' (front = Blender -Y -> Godot +Z!) with exact front UVs
    bm_d = bmesh.new()
    uv_d = bm_d.loops.layers.uv.new("UVMap")
    hx, hy, hz = 0.139, 0.005, 0.014
    v0 = bm_d.verts.new(Vector((-hx, -hy, -hz)))
    v1 = bm_d.verts.new(Vector((hx, -hy, -hz)))
    v2 = bm_d.verts.new(Vector((hx, -hy, hz)))
    v3 = bm_d.verts.new(Vector((-hx, -hy, hz)))
    v4 = bm_d.verts.new(Vector((-hx, hy, -hz)))
    v5 = bm_d.verts.new(Vector((hx, hy, -hz)))
    v6 = bm_d.verts.new(Vector((hx, hy, hz)))
    v7 = bm_d.verts.new(Vector((-hx, hy, hz)))
    f_front = bm_d.faces.new((v0, v1, v2, v3))
    for lp, uv in zip(f_front.loops, [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]):
        lp[uv_d].uv = uv
    for verts in [(v5, v4, v7, v6), (v4, v0, v3, v7), (v1, v5, v6, v2), (v3, v2, v6, v7), (v4, v5, v1, v0)]:
        ff = bm_d.faces.new(verts)
        for lp in ff.loops:
            lp[uv_d].uv = (0.02, 0.5)
    dmesh = bpy.data.meshes.new("Dial")
    bm_d.to_mesh(dmesh)
    bm_d.free()
    dmesh.materials.append(m_dial)
    dial_obj = bpy.data.objects.new("Dial", dmesh)
    dial_obj.location = Vector((0.0, -0.055, 0.146))
    col.objects.link(dial_obj)
    # Also rear subtle gold emblem strip (Blender +Y -> Godot -Z)
    add_box("RearStrip", (0.260, 0.008, 0.020), (0.0, 0.054, 0.146), m_gold, col)
    for vy in range(5):
        add_box(f"RearVent_{vy}", (0.22, 0.006, 0.007), (0.0, 0.054, 0.040 + vy * 0.016), m_cone, col)

    # 3) Twin stereo speaker rings + dark woofer cones + chrome dust domes + concentric grille bars
    for side_tag, sx in [("L", -0.098), ("R", 0.098)]:
        # Outer chrome ring
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.048, minor_radius=0.0045, location=(sx, -0.055, 0.070),
            rotation=Euler((math.pi * 0.5, 0.0, 0.0), "XYZ"),
        )
        ring = bpy.context.active_object
        ring.name = f"SpeakerRing_{side_tag}"
        ring.data.materials.append(m_chrome)
        bpy.ops.object.shade_smooth()
        bpy.context.scene.collection.objects.unlink(ring)
        col.objects.link(ring)

        # Recessed dark woofer backing & chrome dust cap
        add_cyl(f"SpeakerBack_{side_tag}", 0.046, 0.008, (sx, -0.052, 0.070), m_cone, col, rot=(math.pi * 0.5, 0, 0), verts=24)
        add_cyl(f"SpeakerDome_{side_tag}", 0.014, 0.010, (sx, -0.055, 0.070), m_chrome, col, rot=(math.pi * 0.5, 0, 0), verts=16)

        # Grille horizontal slats
        for sl in range(-3, 4):
            sz = 0.070 + sl * 0.0115
            half_w = math.sqrt(max(0.044 ** 2 - (sl * 0.0115) ** 2, 0.0001)) * 1.92
            add_box(f"Grille_{side_tag}_{sl}", (half_w, 0.004, 0.003), (sx, -0.057, sz), m_grille, col)

    # 4) Center cassette deck door + visible tape reels + smoked glass window
    add_box("CassetteBezel", (0.088, 0.010, 0.074), (0.0, -0.055, 0.068), m_grille, col, bevel_w=0.003)
    add_box("CassetteRecess", (0.074, 0.006, 0.054), (0.0, -0.058, 0.068), m_cone, col)
    for rx in [-0.018, 0.018]:
        add_cyl(f"TapeReel_{rx:+.2f}", 0.011, 0.006, (rx, -0.059, 0.068), m_reel, col, rot=(math.pi * 0.5, 0, 0), verts=12)
        add_cyl(f"TapeHub_{rx:+.2f}", 0.0045, 0.007, (rx, -0.0595, 0.068), m_cone, col, rot=(math.pi * 0.5, 0, 0), verts=8)
    add_box("CassetteWindow", (0.072, 0.003, 0.036), (0.0, -0.061, 0.068), m_glass, col)
    add_box("CassetteLabel", (0.068, 0.003, 0.010), (0.0, -0.0605, 0.090), m_gold, col)

    # 5) Top tactile piano buttons (PLAY / REW / FF / STOP / REC)
    btn_xs = [-0.046, -0.023, 0.0, 0.023, 0.046]
    for bi, bx in enumerate(btn_xs):
        bmat = m_red if bi == 4 else m_chrome
        add_box(f"KeyBtn_{bi}", (0.018, 0.022, 0.012), (bx, -0.016, 0.181), bmat, col, bevel_w=0.002)

    # Side rotary tuning & volume knobs (right side +X)
    add_cyl("TuneKnob", 0.015, 0.016, (0.166, -0.012, 0.132), m_chrome, col, rot=(0, math.pi * 0.5, 0), verts=18)
    add_cyl("VolKnob", 0.013, 0.014, (0.166, -0.012, 0.082), m_chrome, col, rot=(0, math.pi * 0.5, 0), verts=18)

    # 6) Folding chrome carry handle (top bar at Z=0.215 -> matches Godot FP_GRIP!)
    add_box("HandleBar", (0.244, 0.016, 0.014), (0.0, 0.0, 0.215), m_chrome, col, bevel_w=0.003)
    for hx in [-0.118, 0.118]:
        add_box(f"HandleArm_{hx:+.2f}", (0.012, 0.014, 0.046), (hx, 0.0, 0.194), m_chrome, col, bevel_w=0.002)

    # 7) Telescoping chrome antenna angled stylishly up from top-right rear
    add_cyl("AntennaBase", 0.0055, 0.09, (0.125, 0.022, 0.215), m_chrome, col, rot=(0.0, 0.26, 0.0), verts=10)
    add_cyl("AntennaMid", 0.0040, 0.11, (0.150, 0.022, 0.305), m_chrome, col, rot=(0.0, 0.26, 0.0), verts=10)
    add_cyl("AntennaTip", 0.0028, 0.09, (0.173, 0.022, 0.390), m_chrome, col, rot=(0.0, 0.26, 0.0), verts=10)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.006, location=(0.185, 0.022, 0.432))
    tip_ball = bpy.context.active_object
    tip_ball.name = "AntennaBall"
    tip_ball.data.materials.append(m_chrome)
    bpy.context.scene.collection.objects.unlink(tip_ball)
    col.objects.link(tip_ball)

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
    bg.inputs["Color"].default_value = (0.06, 0.06, 0.07, 1.0)
    bg.inputs["Strength"].default_value = 0.72

    for lname, loc, tgt, energy, color, sz in [
        ("Key", (0.45, -0.55, 0.42), (0.0, 0.0, 0.12), 20.0, (1.0, 0.95, 0.88), 0.40),
        ("Fill", (-0.48, -0.32, 0.22), (0.0, 0.0, 0.12), 9.0, (0.85, 0.92, 1.0), 0.45),
        ("Rim", (0.0, 0.45, 0.35), (0.0, 0.0, 0.14), 12.0, (1.0, 0.88, 0.72), 0.32),
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
    col = build_radio()

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
    cam.location = Vector((0.36, -0.54, 0.28))
    cam.rotation_euler = (Vector((0.02, 0.0, 0.13)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(PREVIEW_CLOSEUP)
    bpy.ops.render.render(write_still=True)
    print("RADIO_BUILD_OK")


if __name__ == "__main__":
    main()
