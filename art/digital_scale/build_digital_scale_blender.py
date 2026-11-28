#!/usr/bin/env python3
"""Blender 5.3 builder: pazar tezgahı dijital terazisi (beyaz gövde, paslanmaz kefe, öne eğik LCD paneli).
Ölçüler metre. Blender -Y = Godot +Z (ön yüz oyuncuya bakar). LCD camı "LCD" adlı malzemede; rakamları Godot Label3D yazar.
Çalıştır: blender -b -P build_digital_scale_blender.py
"""
from pathlib import Path
import bpy, bmesh
from mathutils import Vector

D = Path(__file__).resolve().parent
GLB = D.parent.parent / "models" / "digital_scale.glb"


def mat(name, col, rough=0.5, metal=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 0.6
    return m


def rbox(name, size, loc, m, bevel=0.006, segs=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        md = o.modifiers.new("b", "BEVEL"); md.width = bevel; md.segments = segs
        bpy.ops.object.modifier_apply(modifier="b")
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


bpy.ops.wm.read_factory_settings(use_empty=True)
body = mat("Body", (0.92, 0.92, 0.9), 0.45)
dark = mat("Trim", (0.12, 0.12, 0.13), 0.6)
steel = mat("Steel", (0.82, 0.83, 0.85), 0.32, 0.55)
lcd = mat("LCD", (0.16, 0.28, 0.14), 0.15, 0.0, emit=(0.35, 0.6, 0.25))
key_r = mat("KeyRed", (0.8, 0.12, 0.1), 0.4)
key_g = mat("KeyGrey", (0.55, 0.56, 0.58), 0.4)
rubber = mat("Rubber", (0.05, 0.05, 0.05), 0.9)

parts = []
parts.append(rbox("Base", (0.26, 0.22, 0.045), (0, 0, 0.0275), body, 0.012))
for x in (-0.11, 0.11):
    for y in (-0.09, 0.09):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=0.008, location=(x, y, 0.004), vertices=12)
        f = bpy.context.active_object; f.data.materials.append(rubber); parts.append(f)
parts.append(rbox("PlatterPost", (0.05, 0.05, 0.012), (0, 0.015, 0.056), dark, 0.002))
parts.append(rbox("Platter", (0.24, 0.17, 0.008), (0, 0.015, 0.066), steel, 0.004))
# Öne eğik ekran gövdesi
pod = rbox("DisplayPod", (0.2, 0.05, 0.05), (0, -0.098, 0.06), body, 0.008)
pod.rotation_euler.x = -0.45
parts.append(pod)
bpy.ops.object.select_all(action="DESELECT"); pod.select_set(True); bpy.context.view_layer.objects.active = pod
bpy.ops.object.transform_apply(rotation=True)
# LCD camı + çerçeve + tuşlar: pod'un ön yüzüne paralel
import math
n = Vector((0, -math.cos(0.45), math.sin(0.45)))  # pod ön yüz normali
up = Vector((0, math.sin(0.45), math.cos(0.45)))
c = Vector((0, -0.098, 0.06)) + n * 0.026
for nm, w, h, off_u, off_x, m, d in [("Bezel", 0.15, 0.034, 0.004, 0.0, dark, 0.003), ("LCD", 0.13, 0.024, 0.004, 0.0, lcd, 0.0045)]:
    o = rbox(nm, (w, 0.004, h), c + n * d + up * off_u, m, 0.001, 1)
    o.rotation_euler.x = -0.45; parts.append(o)
for i, (kx, km) in enumerate([(-0.06, key_r), (-0.02, key_g), (0.02, key_g), (0.06, key_g)]):
    o = rbox("Key%d" % i, (0.022, 0.005, 0.008), c + n * 0.003 - up * 0.019 + Vector((kx, 0, 0)), km, 0.001, 1)
    o.rotation_euler.x = -0.45; parts.append(o)

for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
scale_obj = bpy.context.active_object
scale_obj.name = "DigitalScale"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.wm.save_as_mainfile(filepath=str(D / "digital_scale.blend"))
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=False)

# Önizleme
bpy.ops.object.camera_add(location=(0.32, -0.42, 0.3)); cam = bpy.context.active_object
cam.rotation_euler = (math.radians(62), 0, math.radians(36)); bpy.context.scene.camera = cam
bpy.ops.object.light_add(type="SUN", location=(0, 0, 1)); bpy.context.active_object.data.energy = 4
w = bpy.data.worlds.new("W"); bpy.context.scene.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.55, 0.6, 1)
s = bpy.context.scene; s.render.engine = "BLENDER_EEVEE"; s.render.resolution_x = 800; s.render.resolution_y = 600
s.render.filepath = str(D / "preview.png"); bpy.ops.render.render(write_still=True)
print("SCALE_OK", GLB)
