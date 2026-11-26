"""Bazar — karakter tipleri (Blender 5.3, headless).

Çalıştır:
  blender -b art/character.blend --python art/characters/build_characters.py

Temel: art/character.blend (pazarcı kafası, gözler, ağız, eller, ayaklar).
Her tip bu tabanın kopyasından türetilir, böylece kod sözleşmesi korunur:
  nesneler  Body, Head(EyeL/EyeR > PupilL/PupilR, Mouth), HandL/R, FootL/R
  materyaller Skin, Lid, SkinLid, Hair, Shirt, Pants, Hat, HatDetail, Shoe, Sole,
              EyeWhite, Pupil, EyeGlint, Mouth (+ tipe özel: Brow, Mustache, Glasses,
              Apron, Vest, Gold, Cheek, Drawstring)
Kod nesne transform'unu sıfırlayıp yalnızca konumu kullandığı için tüm eğimler
(emekli kamburluğu vb.) mesh verisine işlenir.

Çıktılar:
  models/char_<tip>.glb, art/characters/preview_<tip>.png, art/characters/lineup.png,
  art/characters/characters.blend
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix, Euler

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_MODELS = os.path.join(ROOT, "models")
OUT_ART = os.path.join(ROOT, "art", "characters")
PARTS = ["Body", "Head", "HandL", "HandR", "FootL", "FootR"]
ONLY = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else []

# --------------------------------------------------------------------------- taban
for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
BASE_OBJS = {o.name: o for o in bpy.data.objects}
for o in BASE_OBJS.values():
    o.name = "BASE_" + o.name
BASE_MATS = {m.name: m for m in bpy.data.materials}
for m in BASE_MATS.values():
    m.name = "BASE_" + m.name
base_col = bpy.data.collections.new("BASE")
bpy.context.scene.collection.children.link(base_col)
for o in BASE_OBJS.values():
    for c in list(o.users_collection):
        c.objects.unlink(o)
    base_col.objects.link(o)
base_col.hide_render = True
base_col.hide_viewport = True


def srgb(c):
    """sRGB 0-1 -> lineer (Principled giriş rengi)."""
    return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


class Variant:
    def __init__(self, key, colors):
        self.key = key
        self.col = bpy.data.collections.new("CH_" + key)
        bpy.context.scene.collection.children.link(self.col)
        self.mats = {}
        for n, m in BASE_MATS.items():
            c = m.copy()
            c.name = n
            self.mats[n] = c
        for n, rgb in colors.items():
            self.mat(n, rgb)
        self.obj = {}
        for n, o in BASE_OBJS.items():
            c = o.copy()
            c.data = o.data.copy()
            c.name = n
            self.col.objects.link(c)
            self.obj[n] = c
        for n, o in BASE_OBJS.items():
            if o.parent:
                self.obj[n].parent = self.obj[o.parent.name[5:]]
        for o in self.obj.values():
            for i, s in enumerate(o.material_slots):
                if s.material:
                    s.material = self.mats[s.material.name[5:]]

    def mat(self, name, rgb=None, rough=0.75, metal=0.0):
        m = self.mats.get(name)
        if m is None:
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            self.mats[name] = m
        if rgb is not None:
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = (*srgb(rgb), 1.0)
            b.inputs["Roughness"].default_value = rough
            b.inputs["Metallic"].default_value = metal
            m.diffuse_color = (*srgb(rgb), 1.0)
        return m

    def finish(self):
        """Dışa aktarılınca adlar çakışmasın diye önek ekle."""
        for o in self.obj.values():
            o.name = self.key + "_" + o.name
        for m in self.mats.values():
            m.name = self.key + "_" + m.name


# --------------------------------------------------------------------------- bmesh yardımcıları
def slot(obj, mat):
    for i, s in enumerate(obj.material_slots):
        if s.material == mat:
            return i
    obj.data.materials.append(mat)
    return len(obj.material_slots) - 1


class Edit:
    """with Edit(obj) as bm: ... — mesh'i bmesh olarak düzenle."""
    def __init__(self, obj):
        self.obj = obj

    def __enter__(self):
        self.bm = bmesh.new()
        self.bm.from_mesh(self.obj.data)
        return self.bm

    def __exit__(self, *a):
        self.bm.to_mesh(self.obj.data)
        self.bm.free()
        self.obj.data.update()


def islands(bm):
    bm.faces.ensure_lookup_table()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        comp = []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(comp)
    return out


def isl_center(comp):
    vs = {v for f in comp for v in f.verts}
    return sum((v.co for v in vs), Vector()) / len(vs), vs


def mat_name(obj, f):
    m = obj.material_slots[f.material_index].material
    return m.name if m else ""


def delete_mats(obj, names):
    with Edit(obj) as bm:
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if mat_name(obj, f) in names], context="FACES")


def head_hair_op(obj, v, brow="Brow", mustache="Hair", cap="keep", side="keep",
                 brow_scale=1.0, brow_tilt=0.0, mus_scale=1.0):
    """Taban saç adalarını işle. mustache/brow: hedef materyal adı ya da None (sil)."""
    with Edit(obj) as bm:
        groups = {}
        for comp in islands(bm):
            if mat_name(obj, comp[0]) != "Hair":
                continue
            c, vs = isl_center(comp)
            if len(comp) > 1000:
                k = "cap"
            elif c.y < -0.2 and c.z > 0.05:
                k = "brow"
            elif c.y < -0.2 and c.z < 0.0:
                k = "mustache"
            else:
                k = "side"
            groups.setdefault(k, []).append((comp, c, vs))
        kill = []
        for k, lst in groups.items():
            target = {"brow": brow, "mustache": mustache, "cap": cap, "side": side}[k]
            for comp, c, vs in lst:
                if target is None:
                    kill.extend(comp)
                    continue
                if target not in ("keep",):
                    idx = slot(obj, v.mats[target]) if target in v.mats else slot(obj, v.mat(target))
                    for f in comp:
                        f.material_index = idx
                if k == "brow" and (brow_scale != 1.0 or brow_tilt):
                    tilt = brow_tilt * (1 if c.x > 0 else -1)
                    m = Matrix.Rotation(tilt, 4, "Y")
                    for vv in vs:
                        vv.co = c + m @ ((vv.co - c) * brow_scale)
                if k == "mustache" and mus_scale != 1.0:
                    for vv in vs:
                        d = vv.co - c
                        vv.co = c + Vector((d.x * mus_scale, d.y, d.z * mus_scale * 1.1))
        bmesh.ops.delete(bm, geom=list(set(kill)), context="FACES")


def _finish_geom(bm, verts, faces, mat_idx, mtx):
    bmesh.ops.transform(bm, matrix=mtx, verts=verts)
    for f in faces:
        f.material_index = mat_idx
        f.smooth = True


def add_sphere(obj, mat, r, at, rot=(0, 0, 0), seg=24, rings=14, cut=None, shape=None):
    """Elipsoid. cut(dir)->True ise o yön silinir (açıklık). shape(dir)->Vector ölçek düzeltmesi."""
    idx = slot(obj, mat)
    with Edit(obj) as bm:
        res = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
        verts = res["verts"]
        faces = list({f for v in verts for f in v.link_faces})
        if cut:
            dead = [f for f in faces if all(cut(v.co.normalized()) for v in f.verts)]
            bmesh.ops.delete(bm, geom=dead, context="FACES")
            verts = [v for v in verts if v.is_valid]
            faces = [f for f in faces if f.is_valid]
        for v in verts:
            d = v.co.copy()
            if shape:
                d = shape(d)
            v.co = Vector((d.x * r[0], d.y * r[1], d.z * r[2]))
        _finish_geom(bm, verts, faces, idx, Matrix.Translation(at) @ Euler(rot).to_matrix().to_4x4())


def add_rbox(obj, mat, size, at, rot=(0, 0, 0), p=0.35, seg=16, rings=10):
    """Yuvarlatılmış kutu (süper-elipsoid)."""
    def shp(d):
        return Vector(tuple(math.copysign(abs(x) ** p, x) for x in d))
    add_sphere(obj, mat, (size[0] / 2, size[1] / 2, size[2] / 2), at, rot, seg, rings, shape=shp)


def add_cyl(obj, mat, r1, r2, h, at, rot=(0, 0, 0), seg=24, cap=True):
    idx = slot(obj, mat)
    with Edit(obj) as bm:
        res = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=h)
        verts = res["verts"]
        faces = list({f for v in verts for f in v.link_faces})
        _finish_geom(bm, verts, faces, idx, Matrix.Translation(at) @ Euler(rot).to_matrix().to_4x4())
        # kapakları düz gölgelendir
        for f in faces:
            if len(f.verts) > 4:
                f.smooth = False


def add_torus(obj, mat, R, r, at, rot=(0, 0, 0), seg=28, rseg=8, squash=(1, 1)):
    idx = slot(obj, mat)
    with Edit(obj) as bm:
        grid = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            row = []
            for j in range(rseg):
                b = 2 * math.pi * j / rseg
                rr = R + r * math.cos(b) * squash[0]
                row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b) * squash[1])))
            grid.append(row)
        faces = []
        for i in range(seg):
            for j in range(rseg):
                a, b = grid[i][j], grid[(i + 1) % seg][j]
                c, d = grid[(i + 1) % seg][(j + 1) % rseg], grid[i][(j + 1) % rseg]
                faces.append(bm.faces.new((a, b, c, d)))
        verts = [v for row in grid for v in row]
        _finish_geom(bm, verts, faces, idx, Matrix.Translation(at) @ Euler(rot).to_matrix().to_4x4())


def add_tube(obj, mat, pts, r, seg=8):
    """Noktalar boyunca ince boru (ip, gözlük sapı)."""
    idx = slot(obj, mat)
    with Edit(obj) as bm:
        rings = []
        for i, p in enumerate(pts):
            p = Vector(p)
            t = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            u = t.orthogonal().normalized()
            w = t.cross(u)
            rings.append([bm.verts.new(p + (u * math.cos(2 * math.pi * k / seg) + w * math.sin(2 * math.pi * k / seg)) * r) for k in range(seg)])
        faces = []
        for i in range(len(rings) - 1):
            for k in range(seg):
                faces.append(bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][(k + 1) % seg], rings[i][(k + 1) % seg])))
        for ring in (rings[0], rings[-1]):
            faces.append(bm.faces.new(ring))
        for f in faces:
            f.material_index = idx
            f.smooth = True


def deform(obj, fn, mats=None):
    """Vertex'leri fn(co)->co ile biçimlendir (yalnızca verilen materyallerdeki yüzlerin vertex'leri)."""
    with Edit(obj) as bm:
        vs = bm.verts if mats is None else {v for f in bm.faces if mat_name(obj, f) in mats for v in f.verts}
        for v in vs:
            v.co = fn(v.co.copy())


def wrap_panel(obj, mat, z0, z1, phi_lo, phi_hi, offset=0.014, nu=40, nv=18, trim=None, trim_r=0.009, trim_edges="lrb"):
    """Gövdeye sarılan pürüzsüz panel (önlük, yelek).
    phi: önden (-Y) ölçülen açı, +X tarafına pozitif. Her z satırında [phi_lo(z), phi_hi(z)] aralığı
    gövdeye dışarıdan ışın atılarak yüzeye oturtulur, offset kadar dışarı itilir. trim: kenar biyesi."""
    from mathutils.bvhtree import BVHTree
    idx = slot(obj, mat)
    with Edit(obj) as bm:
        bm.normal_update()
        tree = BVHTree.FromBMesh(bm)
        def surf(phi, z):
            d = Vector((math.sin(phi), -math.cos(phi), 0.0))
            o = Vector((0, 0, z)) + d * 1.2
            hit, nrm, _, _ = tree.ray_cast(o, -d, 2.0)
            if hit is None:
                return Vector((0, 0, z)) + d * 0.2
            return hit + nrm.normalized() * offset
        grid = []
        for j in range(nv + 1):
            z = z1 + (z0 - z1) * j / nv
            lo, hi = phi_lo(z), phi_hi(z)
            grid.append([surf(lo + (hi - lo) * i / nu, z) for i in range(nu + 1)])
        vs = [[bm.verts.new(p) for p in row] for row in grid]
        for j in range(nv):
            for i in range(nu):
                f = bm.faces.new((vs[j][i], vs[j + 1][i], vs[j + 1][i + 1], vs[j][i + 1]))
                f.material_index = idx
                f.smooth = True
    if trim is not None:
        if "l" in trim_edges:
            add_tube(obj, trim, [tuple(r[0]) for r in grid], trim_r)
        if "r" in trim_edges:
            add_tube(obj, trim, [tuple(r[-1]) for r in grid], trim_r)
        if "b" in trim_edges:
            add_tube(obj, trim, [tuple(p) for p in grid[-1]], trim_r)
        if "t" in trim_edges:
            add_tube(obj, trim, [tuple(p) for p in grid[0]], trim_r)


def add_open_shell(obj, mat, R, at, front=0.4, shape=None, seg=36, rings=18, rot=(0, 0, 0)):
    """Önü açık küre kabuğu (yemeni, kapüşon). Kutup +Y'de (ense); açıklık d.y < -front
    kesiminde pürüzsüz bir halka. shape(dir)->dir biçim düzeltmesi."""
    idx = slot(obj, mat)
    tmax = math.acos(-front)
    with Edit(obj) as bm:
        def P(t, a):
            d = Vector((math.sin(t) * math.cos(a), math.cos(t), math.sin(t) * math.sin(a)))
            if shape:
                d = shape(d)
            return Vector((d.x * R[0], d.y * R[1], d.z * R[2]))
        pole = bm.verts.new(P(0, 0))
        ringsv = []
        for j in range(1, rings + 1):
            t = tmax * j / rings
            ringsv.append([bm.verts.new(P(t, 2 * math.pi * i / seg)) for i in range(seg)])
        faces = [bm.faces.new((pole, ringsv[0][(i + 1) % seg], ringsv[0][i])) for i in range(seg)]
        for j in range(rings - 1):
            for i in range(seg):
                faces.append(bm.faces.new((ringsv[j][i], ringsv[j][(i + 1) % seg], ringsv[j + 1][(i + 1) % seg], ringsv[j + 1][i])))
        verts = [pole] + [v for r in ringsv for v in r]
        _finish_geom(bm, verts, faces, idx, Matrix.Translation(at) @ Euler(rot).to_matrix().to_4x4())
        # dış yüze baksın
        bm.normal_update()
        c = Vector(at)
        flip = [f for f in faces if f.normal.dot(f.calc_center_median() - c) < 0]
        bmesh.ops.reverse_faces(bm, faces=flip)
    # açıklık halkasının merkezi ve yarıçapı (torus kenar için)
    return Vector(at) + Vector((0, -front * R[1], 0)), math.sqrt(1 - front * front) * R[0]


def bake_rotation(obj, rot, pivot):
    m = Matrix.Translation(pivot) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Translation(-Vector(pivot))
    with Edit(obj) as bm:
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


# Başın ölçüleri (taban): yarıçap ~0.29, merkez Head orijini, yüz -Y.
EYE_Z = 0.044
EYE_X = 0.094


def glasses(v, head, frame_rgb, mat="Glasses", r=0.062, gold=False):
    m = v.mat(mat, frame_rgb, rough=0.3, metal=0.85 if gold else 0.2)
    for sx in (-EYE_X, EYE_X):
        add_torus(head, m, r, 0.0085, Vector((sx, -0.305, EYE_Z)), rot=(math.pi / 2, 0, 0), seg=28, rseg=6)
    add_tube(head, m, [(-EYE_X + r * 0.85, -0.31, EYE_Z + 0.012), (0, -0.322, EYE_Z + 0.02), (EYE_X - r * 0.85, -0.31, EYE_Z + 0.012)], 0.0075)
    for sx in (-1, 1):
        add_tube(head, m, [(sx * (EYE_X + r), -0.3, EYE_Z), (sx * 0.27, -0.2, EYE_Z + 0.01), (sx * 0.3, -0.02, EYE_Z), (sx * 0.29, 0.06, EYE_Z - 0.04)], 0.007)


def cheeks(v, head, rgb=(0.96, 0.55, 0.55)):
    m = v.mat("Cheek", rgb, rough=0.9)
    for sx in (-1, 1):
        add_sphere(head, m, (0.05, 0.012, 0.032), Vector((sx * 0.155, -0.252, -0.055)), rot=(0, 0, sx * 0.55), seg=14, rings=8)


def headscarf(v, head, scarf_rgb, oya_rgb, k=1.0):
    """Yemeni: başı saran kabuk, yüz açık + kenar oyası + çene altı düğümü."""
    hat = v.mat("Hat", scarf_rgb, rough=0.85)
    det = v.mat("HatDetail", oya_rgb, rough=0.8)
    R = (0.335 * k, 0.33 * k, 0.345 * k)
    c = Vector((0, 0.025, 0.0))
    rc, rr = add_open_shell(head, hat, R, c, front=0.5)
    # yüz çevresinde yumuşak kıvrım
    add_torus(head, hat, rr, 0.036 * k, rc, rot=(math.pi / 2, 0, 0), seg=36, rseg=8)
    # oyalar: kenarda küçük boncuklar
    for i in range(11):
        a = math.radians(-125 + i * 25)
        add_sphere(head, det, (0.021, 0.016, 0.021), rc + Vector((math.sin(a) * rr, -0.032, math.cos(a) * rr)), seg=10, rings=6)
    # çene altında düğüm + ense sarkması
    add_sphere(head, hat, (0.065, 0.05, 0.05), Vector((0.0, rc.y - 0.02, -rr - 0.01)), seg=12, rings=8)
    add_sphere(head, hat, (0.045, 0.03, 0.1), Vector((0.05, rc.y - 0.03, -rr - 0.08)), rot=(0, 0.3, 0), seg=12, rings=8)
    add_sphere(head, hat, (0.24 * k, 0.14 * k, 0.2 * k), Vector((0, 0.24 * k, -0.2 * k)), rot=(0.4, 0, 0), seg=20, rings=10)


def hair_cap(v, head, rgb, front=0.3, up=0.42, low=-0.35, R=(0.308, 0.305, 0.305), at=(0, 0.02, 0.03), side_low=None):
    hm = v.mat("Hair", rgb, rough=0.85)
    def cut(d):
        if d.y < -front and d.z < up:
            return True
        if side_low is not None and d.z < side_low and d.y < 0.2:
            return True
        return d.z < low
    add_sphere(head, hm, R, Vector(at), seg=32, rings=18, cut=cut)
    return hm


# --------------------------------------------------------------------------- gövde şekilleri
def body_scale(v, sx=1.0, sy=1.0, sz=1.0, belly=0.0, hips=0.0, top=0.0):
    """Body: genel ölçek + karın (önde) + kalça (altta) + omuz daraltma."""
    def fn(co):
        z = co.z
        w = sx * (1 + hips * max(0.0, -z / 0.28) ** 1.3 - top * max(0.0, z / 0.28) ** 2)
        d = sy * (1 + hips * 0.6 * max(0.0, -z / 0.28) ** 1.3 - top * max(0.0, z / 0.28) ** 2)
        y = co.y * d
        if co.y < 0:
            y -= belly * math.exp(-((z + 0.02) / 0.15) ** 2) * (-co.y / 0.24)
        return Vector((co.x * w, y, z * sz))
    deform(v.obj["Body"], fn)


def move(v, name, loc):
    v.obj[name].location = Vector(loc)


def feet(v, scale=1.0, dx=0.14, z=0.11):
    for n, s in (("FootL", 1), ("FootR", -1)):
        if scale != 1.0:
            deform(v.obj[n], lambda co: co * scale)
        move(v, n, (s * dx, 0, z * scale))


def hands(v, x=0.36, y=-0.04, z=0.52, scale=1.0):
    for n, s in (("HandL", 1), ("HandR", -1)):
        if scale != 1.0:
            deform(v.obj[n], lambda co: co * scale)
        move(v, n, (s * x, y, z))


# --------------------------------------------------------------------------- tipler
def build_pazarci():
    """Oyuncu pazarcı: kasket + gür bıyık + belde para kemerli pazarcı önlüğü."""
    v = Variant("pazarci", {"Apron": (0.28, 0.42, 0.26)})
    head = v.obj["Head"]
    head_hair_op(head, v, brow="Brow", mustache="Hair", mus_scale=1.12)
    v.mat("Brow", (0.12, 0.08, 0.06), rough=0.9)
    b = v.obj["Body"]
    ap = v.mat("Apron", (0.3, 0.45, 0.3), rough=0.9)
    wrap_panel(b, ap, -0.27, -0.035, lambda z: -1.15, lambda z: 1.15, offset=0.016, trim=ap, trim_r=0.008, trim_edges="b")
    add_rbox(b, ap, (0.14, 0.02, 0.09), Vector((-0.1, -0.252, -0.15)), rot=(0.1, 0, 0.3))
    # para kemeri: önlüğün üst kenarında kemer + bel çantası
    add_torus(b, v.mats["Shoe"], 0.245, 0.016, Vector((0, 0, -0.03)), seg=32, rseg=6)
    add_rbox(b, v.mat("Pouch", (0.42, 0.26, 0.14), rough=0.7), (0.15, 0.07, 0.1), Vector((0.1, -0.24, -0.08)), rot=(0, 0, -0.35))
    add_rbox(b, v.mats["Pouch"], (0.14, 0.02, 0.04), Vector((0.1, -0.272, -0.045)), rot=(0, 0, -0.35))
    return v


def build_teyze():
    """İkonik pazar teyzesi: yemeni + oyalar, altın gözlük, al yanak, tombul, uzun etek + önlük."""
    v = Variant("teyze", {
        "Shirt": (0.72, 0.3, 0.42), "Pants": (0.3, 0.2, 0.34), "Skin": (0.95, 0.78, 0.65),
        "Lid": (0.9, 0.72, 0.6), "SkinLid": (0.93, 0.75, 0.62), "Shoe": (0.26, 0.19, 0.17)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache=None, cap=None, side=None, brow_scale=0.95)
    v.mat("Brow", (0.32, 0.24, 0.2), rough=0.9)
    headscarf(v, head, (0.3, 0.5, 0.7), (0.98, 0.95, 0.86))
    glasses(v, head, (0.88, 0.72, 0.22), gold=True, r=0.058)
    cheeks(v, head)
    move(v, "Head", (0, 0, 1.06))
    b = v.obj["Body"]
    body_scale(v, sx=1.18, sy=1.12, sz=0.96, belly=0.035, hips=0.12)
    # uzun etek (Pants) — bel altından ayak bileğine
    pm = v.mats["Pants"]
    add_cyl(b, pm, 0.31, 0.27, 0.27, Vector((0, 0, -0.2)), seg=32, cap=False)
    add_torus(b, pm, 0.305, 0.022, Vector((0, 0, -0.335)), seg=32, rseg=6)
    add_cyl(b, pm, 0.3, 0.3, 0.01, Vector((0, 0, -0.335)), seg=32)
    # desenli önlük
    ap = v.mat("Apron", (0.97, 0.93, 0.86), rough=0.9)
    wrap_panel(b, ap, -0.33, 0.0, lambda z: -0.55 - z * 0.3, lambda z: 0.55 + z * 0.3, offset=0.01,
               trim=v.mat("Lace", (0.95, 0.6, 0.7), rough=0.8), trim_r=0.009, trim_edges="lrb")
    fl = v.mat("Flower", (0.95, 0.4, 0.55), rough=0.8)
    for x, z in ((-0.08, -0.07), (0.06, -0.15), (-0.03, -0.24), (0.09, -0.04), (-0.1, -0.2)):
        add_sphere(b, fl, (0.022, 0.01, 0.022), Vector((x, -0.312 + abs(x) * 0.25, z)), seg=10, rings=6)
    # hırka düğmeleri
    for z in (0.1, 0.17):
        add_sphere(b, v.mat("Button", (0.95, 0.9, 0.7), rough=0.4), (0.016, 0.01, 0.016), Vector((0, -0.24 + z * 0.15, z)), seg=10, rings=6)
    hands(v, x=0.38, y=-0.05, z=0.5)
    feet(v, scale=0.92, dx=0.12)
    return v


def build_emekli():
    """Emekli amca: kasket, yuvarlak gözlük, kır gür bıyık, yelek, öne eğik (kambur)."""
    v = Variant("emekli", {
        "Hair": (0.78, 0.77, 0.74), "Shirt": (0.86, 0.84, 0.76), "Pants": (0.36, 0.33, 0.3),
        "Hat": (0.36, 0.33, 0.3), "HatDetail": (0.28, 0.26, 0.24), "Skin": (0.9, 0.7, 0.55),
        "Lid": (0.84, 0.64, 0.5), "SkinLid": (0.87, 0.67, 0.52)})
    head = v.obj["Head"]
    head_hair_op(head, v, brow="Brow", mustache="Hair", brow_scale=1.35, brow_tilt=-0.15, mus_scale=1.3)
    v.mat("Brow", (0.82, 0.81, 0.78), rough=0.9)
    glasses(v, head, (0.12, 0.1, 0.1), r=0.064)
    # kulak arkası kır saç biraz kabarık (taban kabuğu kalsın)
    b = v.obj["Body"]
    body_scale(v, sx=1.04, sy=1.06, belly=0.05, top=0.05)
    vest = v.mat("Vest", (0.45, 0.33, 0.22), rough=0.95)
    wrap_panel(b, vest, -0.13, 0.215, lambda z: 0.22 + max(0.0, z + 0.02) * 1.6, lambda z: 2 * math.pi - 0.22 - max(0.0, z + 0.02) * 1.6,
               offset=0.014, nu=64, trim=v.mat("VestTrim", (0.33, 0.23, 0.15), rough=0.95), trim_r=0.01, trim_edges="lrb")
    # kambur: gövdeyi alt merkezden öne eğ, başı öne-aşağı al
    bake_rotation(b, (math.radians(-13), 0, 0), (0, 0, -0.27))
    move(v, "Head", (0, -0.13, 1.04))
    hands(v, x=0.35, y=-0.13, z=0.48)
    feet(v, dx=0.13)
    return v


def build_zabita():
    """Zabıta: lacivert üniforma, siperlikli resmi şapka + altın arma, apolet, kemer."""
    v = Variant("zabita", {
        "Shirt": (0.11, 0.2, 0.42), "Pants": (0.08, 0.12, 0.24), "Hair": (0.08, 0.06, 0.05),
        "Shoe": (0.06, 0.06, 0.07), "Hat": (0.09, 0.16, 0.36), "HatDetail": (0.04, 0.05, 0.08)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache="Hair", cap="keep", brow_tilt=-0.12)
    v.mat("Brow", (0.08, 0.06, 0.05), rough=0.9)
    hat = v.mats["Hat"]
    det = v.mats["HatDetail"]
    gold = v.mat("Gold", (1.0, 0.8, 0.22), rough=0.25, metal=0.9)
    tilt = (math.radians(6), 0, 0)
    add_cyl(head, det, 0.312, 0.318, 0.07, Vector((0, 0.0, 0.215)), rot=tilt, seg=32)            # bant
    add_cyl(head, hat, 0.32, 0.37, 0.12, Vector((0, 0.01, 0.31)), rot=tilt, seg=32)             # tepe
    add_sphere(head, hat, (0.37, 0.37, 0.035), Vector((0, 0.012, 0.37)), rot=tilt, seg=32, rings=10)
    add_sphere(head, det, (0.25, 0.17, 0.022), Vector((0, -0.3, 0.19)), rot=(math.radians(-14), 0, 0), seg=28, rings=10,
               cut=lambda d: d.y > 0.35)                                                          # siperlik
    add_torus(head, gold, 0.2, 0.008, Vector((0, -0.07, 0.21)), rot=(math.radians(6), 0, 0), seg=28, rseg=5)  # altın kordon (önde görünür)
    add_cyl(head, gold, 0.05, 0.05, 0.02, Vector((0, -0.345, 0.3)), rot=(math.pi / 2 - 0.2, 0, 0), seg=20)     # arma
    add_sphere(head, gold, (0.03, 0.012, 0.035), Vector((0, -0.357, 0.3)), rot=(-0.2, 0, 0), seg=12, rings=8)
    b = v.obj["Body"]
    body_scale(v, sx=1.06, sy=1.04, top=-0.05)
    # kemeri kalınlaştır + altın toka
    deform(b, lambda co: Vector((co.x * 1.03, co.y * 1.03, -0.105 + (co.z + 0.105) * 1.8)), mats=["Shoe"])
    add_rbox(b, gold, (0.08, 0.025, 0.06), Vector((0, -0.252, -0.105)))
    # apoletler + düğmeler + göğüs cebi
    for sx in (-1, 1):
        add_rbox(b, v.mats["Shirt"], (0.13, 0.08, 0.025), Vector((sx * 0.15, 0.0, 0.245)), rot=(0, sx * -0.55, 0))
        add_sphere(b, gold, (0.012, 0.012, 0.012), Vector((sx * 0.12, -0.03, 0.27)), seg=8, rings=6)
        add_rbox(b, v.mats["Shirt"], (0.08, 0.02, 0.07), Vector((sx * 0.11, -0.228, 0.1)), rot=(0.25, 0, sx * -0.4))
    for z in (0.15, 0.06, -0.03):
        add_sphere(b, gold, (0.013, 0.01, 0.013), Vector((0, -0.243 + (0.15 - z) * -0.05, z)), seg=10, rings=6)
    hands(v)
    feet(v)
    return v


def build_kapkac():
    """Kapkaççı velet: kapüşonlu (kapüşon = Shirt, koddaki hoodie rengini alır), çatık kaş, çil."""
    v = Variant("kapkac", {
        "Shirt": (0.45, 0.47, 0.52), "Pants": (0.2, 0.22, 0.28), "Shoe": (0.9, 0.9, 0.92),
        "Skin": (0.9, 0.7, 0.54), "Lid": (0.84, 0.64, 0.5), "SkinLid": (0.87, 0.67, 0.52), "Hair": (0.16, 0.1, 0.06)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache=None, cap=None, side=None, brow_scale=1.15, brow_tilt=-0.45)
    v.mat("Brow", (0.14, 0.09, 0.06), rough=0.9)
    sh = v.mats["Shirt"]
    # kapüşon: hafif sivri arka, yüz açıklığı
    def hood_shape(d):
        k = max(0.0, d.y) * max(0.0, d.z)
        return Vector((d.x, d.y + k * 0.35, d.z + k * 0.2))
    c = Vector((0, 0.03, 0.02))
    R = (0.36, 0.355, 0.37)
    rc, rr = add_open_shell(head, sh, R, c, front=0.45, shape=hood_shape)
    add_torus(head, sh, rr, 0.045, rc + Vector((0, -0.005, 0)), rot=(math.pi / 2, 0, 0), seg=36, rseg=8)
    # perçem
    for x, rz in ((-0.05, 0.4), (0.03, -0.1), (0.1, -0.5)):
        add_sphere(head, v.mats["Hair"], (0.055, 0.03, 0.03), Vector((x, -0.25, 0.215 - abs(x) * 0.2)), rot=(0.7, 0, rz), seg=12, rings=6)
    ds = v.mat("Drawstring", (0.94, 0.94, 0.94), rough=0.8)
    for sx in (-0.09, 0.09):
        add_tube(head, ds, [(sx, -0.2, -0.27), (sx * 1.05, -0.23, -0.36), (sx * 1.1, -0.24, -0.44)], 0.009)
        add_sphere(head, ds, (0.016, 0.016, 0.02), Vector((sx * 1.1, -0.24, -0.455)), seg=8, rings=6)
    # çiller
    fr = v.mat("Freckle", (0.72, 0.45, 0.32), rough=0.9)
    for sx in (-1, 1):
        for dx, dz in ((0.0, 0.0), (0.03, 0.012), (0.018, -0.02)):
            add_sphere(head, fr, (0.007, 0.004, 0.007), Vector((sx * (0.14 + dx), -0.262 + dx * 0.15, -0.035 + dz)), seg=8, rings=5)
    move(v, "Head", (0, 0, 1.06))
    b = v.obj["Body"]
    delete_mats(b, ["Shoe"])  # kemer kapüşonlunun altında kalsın (Shoe kodda beyaz boyanıyor)
    body_scale(v, sx=0.9, sy=0.92, sz=0.92)
    # kapüşonlu gövde: alt bant (Shirt) + kanguru cebi
    add_torus(b, sh, 0.205, 0.03, Vector((0, 0, -0.035)), seg=32, rseg=8)
    add_rbox(b, sh, (0.25, 0.04, 0.12), Vector((0, -0.205, 0.0)), rot=(0.12, 0, 0))
    hands(v, x=0.33, scale=0.95)
    feet(v, scale=0.95, dx=0.13)
    return v


def build_cocuk():
    """Çocuk: iri kafa, küçük gövde, kâküllü saç, al yanaklar."""
    v = Variant("cocuk", {"Shirt": (1.0, 0.82, 0.2), "Pants": (0.25, 0.35, 0.6), "Hair": (0.3, 0.18, 0.08),
                          "Skin": (0.96, 0.8, 0.66), "Lid": (0.92, 0.75, 0.6), "SkinLid": (0.94, 0.78, 0.63)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache=None, cap=None, side=None, brow_scale=0.9)
    v.mat("Brow", (0.3, 0.18, 0.08), rough=0.9)
    hm = hair_cap(v, head, (0.3, 0.18, 0.08), front=0.25, up=0.5, low=-0.3, R=(0.315, 0.315, 0.31), at=(0, 0.025, 0.035))
    for i in range(5):
        x = -0.16 + i * 0.08
        add_sphere(head, hm, (0.06, 0.04, 0.05), Vector((x, -0.235 + abs(x) * 0.3, 0.215 - abs(x) * 0.25)), rot=(0.6, 0, -x * 2), seg=14, rings=8)
    cheeks(v, head, (0.98, 0.6, 0.6))
    # biraz daha iri gözler
    move(v, "Head", (0, 0, 0.98))
    body_scale(v, sx=0.86, sy=0.88, sz=0.82)
    v.obj["Body"].location = (0, 0, 0.46)
    hands(v, x=0.31, z=0.47, scale=0.95)
    feet(v, scale=0.9, dx=0.12)
    return v


def build_musteri_erkek():
    """Genel erkek müşteri: kısa saç (Hair), ayrı bıyık (Mustache), kasket (koddan seçmeli)."""
    v = Variant("musteri_erkek", {"Hair": (0.12, 0.08, 0.05), "Shirt": (0.35, 0.55, 0.75)})
    head = v.obj["Head"]
    head_hair_op(head, v, brow="Brow", mustache="Mustache", cap=None, side="keep", mus_scale=0.95)
    v.mat("Brow", (0.12, 0.08, 0.05), rough=0.9)
    v.mat("Mustache", (0.12, 0.08, 0.05), rough=0.85)
    hm = hair_cap(v, head, (0.12, 0.08, 0.05), front=0.3, up=0.42, low=-0.4, R=(0.307, 0.305, 0.3), at=(0, 0.022, 0.03))
    add_sphere(head, hm, (0.13, 0.05, 0.045), Vector((-0.05, -0.235, 0.2)), rot=(0.7, 0, 0.2), seg=16, rings=8)
    # yaka
    b = v.obj["Body"]
    for sx in (-1, 1):
        add_rbox(b, v.mats["Shirt"], (0.1, 0.02, 0.07), Vector((sx * 0.055, -0.115, 0.245)), rot=(0.9, 0, sx * 0.5))
    return v


def build_musteri_kadin():
    """Genel kadın müşteri: küt saç + kâkül, kirpik, ince bel/geniş kalça."""
    v = Variant("musteri_kadin", {"Hair": (0.22, 0.12, 0.06), "Shirt": (0.85, 0.4, 0.5), "Pants": (0.25, 0.28, 0.42),
                                  "Mouth": (0.7, 0.12, 0.18)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache=None, cap=None, side=None, brow_scale=0.85)
    v.mat("Brow", (0.2, 0.12, 0.07), rough=0.9)
    hm = hair_cap(v, head, (0.22, 0.12, 0.06), front=0.34, up=0.45, low=-0.95, R=(0.318, 0.318, 0.315), at=(0, 0.02, 0.035),
                  side_low=-0.15)
    # küt arka + yan saçlar
    add_sphere(head, hm, (0.3, 0.22, 0.24), Vector((0, 0.09, -0.13)), seg=28, rings=12)
    for sx in (-1, 1):
        add_sphere(head, hm, (0.07, 0.13, 0.2), Vector((sx * 0.255, -0.05, -0.12)), rot=(0.2, 0, 0), seg=16, rings=10)
    add_sphere(head, hm, (0.22, 0.07, 0.07), Vector((0.05, -0.225, 0.2)), rot=(0.65, 0, -0.35), seg=18, rings=8)
    # kirpikler
    lash = v.mat("Lash", (0.06, 0.04, 0.04), rough=0.9)
    for sx in (-1, 1):
        for k in range(3):
            a = (k - 1) * 0.5
            p0 = Vector((sx * (EYE_X + 0.03 + k * 0.012), -0.27, EYE_Z + 0.045 - k * 0.012))
            add_tube(head, lash, [tuple(p0), tuple(p0 + Vector((sx * 0.025, -0.01, 0.018)))], 0.005, seg=5)
    cheeks(v, head, (0.97, 0.62, 0.62))
    body_scale(v, sx=0.94, sy=0.94, hips=0.1, top=0.1)
    hands(v, x=0.34, scale=0.92)
    feet(v, scale=0.9, dx=0.13)
    return v


def build_cayci():
    """Çaycı: beyaz gömlek, siyah yelek + papyon, taranmış saç, bıyık."""
    v = Variant("cayci", {"Shirt": (0.95, 0.94, 0.9), "Pants": (0.14, 0.14, 0.17), "Hair": (0.1, 0.07, 0.05),
                          "Skin": (0.86, 0.66, 0.5), "Lid": (0.8, 0.6, 0.46), "SkinLid": (0.83, 0.63, 0.48)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache="Hair", cap=None, side="keep", mus_scale=1.05)
    v.mat("Brow", (0.1, 0.07, 0.05), rough=0.9)
    hm = hair_cap(v, head, (0.1, 0.07, 0.05), front=0.32, up=0.4, low=-0.4, R=(0.31, 0.31, 0.3), at=(0, 0.02, 0.035))
    add_sphere(head, hm, (0.12, 0.06, 0.05), Vector((-0.08, -0.23, 0.22)), rot=(0.7, 0, 0.5), seg=16, rings=8)  # yana taralı perçem
    v.mats["Hair"].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.35
    b = v.obj["Body"]
    vest = v.mat("Vest", (0.1, 0.1, 0.12), rough=0.6)
    wrap_panel(b, vest, -0.15, 0.2, lambda z: 0.16 + max(0.0, z + 0.05) * 2.0, lambda z: 2 * math.pi - 0.16 - max(0.0, z + 0.05) * 2.0,
               offset=0.014, nu=64, trim=vest, trim_r=0.008, trim_edges="lrb")
    bow = v.mat("Bow", (0.65, 0.08, 0.08), rough=0.6)
    for sx in (-1, 1):
        add_sphere(b, bow, (0.045, 0.02, 0.03), Vector((sx * 0.04, -0.13, 0.245)), rot=(0.9, 0, 0), seg=12, rings=8)
    add_sphere(b, bow, (0.018, 0.018, 0.018), Vector((0, -0.14, 0.245)), seg=10, rings=6)
    ap = v.mat("Apron", (0.97, 0.97, 0.95), rough=0.9)
    wrap_panel(b, ap, -0.29, -0.13, lambda z: -1.0, lambda z: 1.0, offset=0.03, trim=ap, trim_r=0.008, trim_edges="b")
    return v


def build_simitci():
    """Simitçi: kasket, kahverengi iş gömleği, beyaz önlük, gür bıyık (tabla kodda başa konur)."""
    v = Variant("simitci", {"Shirt": (0.55, 0.32, 0.24), "Pants": (0.2, 0.2, 0.24), "Hat": (0.3, 0.3, 0.32),
                            "HatDetail": (0.22, 0.22, 0.24), "Hair": (0.15, 0.1, 0.08),
                            "Skin": (0.86, 0.66, 0.5), "Lid": (0.8, 0.6, 0.46), "SkinLid": (0.83, 0.63, 0.48)})
    head = v.obj["Head"]
    head_hair_op(head, v, brow="Brow", mustache="Hair", mus_scale=1.2, brow_scale=1.15)
    v.mat("Brow", (0.15, 0.1, 0.08), rough=0.9)
    # başa simit tablası için yastık (halka bez)
    add_torus(head, v.mat("Cloth", (0.92, 0.9, 0.85), rough=0.95), 0.09, 0.035, Vector((0, 0.0, 0.36)), seg=20, rseg=8)
    b = v.obj["Body"]
    ap = v.mat("Apron", (0.96, 0.95, 0.9), rough=0.9)
    wrap_panel(b, ap, -0.27, 0.17, lambda z: -0.75 + max(0.0, z - 0.05) * 1.5, lambda z: 0.75 - max(0.0, z - 0.05) * 1.5,
               offset=0.016, trim=ap, trim_r=0.008, trim_edges="lrb")
    add_tube(b, ap, [(-0.12, -0.17, 0.2), (-0.08, -0.05, 0.27), (0, 0.0, 0.29), (0.08, -0.05, 0.27), (0.12, -0.17, 0.2)], 0.01)
    return v


def build_hirsiz():
    """Keko tıraşlı hırsız: yanlar kazınmış, üstü jöleli, siyah şişme mont, spor ayakkabı, çatık kaş, yara bandı."""
    v = Variant("hirsiz", {
        "Shirt": (0.07, 0.07, 0.08), "Pants": (0.2, 0.24, 0.34), "Shoe": (0.96, 0.96, 0.96), "Sole": (0.85, 0.15, 0.15),
        "Skin": (0.88, 0.68, 0.53), "Lid": (0.82, 0.62, 0.48), "SkinLid": (0.85, 0.65, 0.5)})
    head = v.obj["Head"]
    delete_mats(head, ["Hat", "HatDetail"])
    head_hair_op(head, v, brow="Brow", mustache=None, cap=None, side=None, brow_scale=1.2, brow_tilt=-0.5)
    v.mat("Brow", (0.12, 0.09, 0.07), rough=0.9)
    # keko tıraşı: yanlar/ense sıfıra yakın kazınmış (Fade), üstte jöleli dikleştirilmiş kısa saç
    # bloğu (Hair), arada net çizgi + yanda kazınmış "çizik"
    fade = v.mat("Fade", (0.5, 0.38, 0.32), rough=1.0)
    add_sphere(head, fade, (0.296, 0.295, 0.297), Vector((0, 0.003, 0.004)), seg=36, rings=18,
               cut=lambda d: (d.y < -0.28 and d.z < 0.62) or d.z < -0.22)
    hm = v.mat("Hair", (0.08, 0.06, 0.05), rough=0.35)
    add_sphere(head, hm, (0.312, 0.312, 0.335), Vector((0, 0.01, 0.0)), seg=36, rings=20, cut=lambda d: d.z < 0.6)
    # önde jöleyle dikleştirilmiş tutamlar (alın çizgisi boyunca)
    for x in (-0.15, -0.09, -0.03, 0.03, 0.09, 0.15):
        y = -math.sqrt(max(0.0, 0.245 ** 2 - x * x)) + 0.02
        add_cyl(head, hm, 0.042, 0.003, 0.085, Vector((x, y - 0.02, 0.25)), rot=(-0.6, x * 1.8, 0), seg=10)
    for x, y in ((-0.06, -0.08), (0.05, -0.06), (0.0, 0.05), (-0.1, 0.03), (0.1, 0.04)):
        add_cyl(head, hm, 0.045, 0.003, 0.06, Vector((x, y, 0.335 - (x * x + y * y) * 0.5)), rot=(-0.25, x, 0), seg=10)
    add_tube(head, v.mats["Skin"], [(0.287, -0.06, 0.14), (0.293, 0.0, 0.135), (0.288, 0.06, 0.15)], 0.007, seg=6)
    # sakal gölgesi (çene)
    add_sphere(head, v.mat("Stubble", (0.72, 0.56, 0.47), rough=1.0), (0.19, 0.2, 0.12), Vector((0, -0.085, -0.19)), seg=24, rings=12,
               cut=lambda d: d.y > -0.3 or d.z > -0.05)
    # yara bandı (alında çapraz)
    bd = v.mat("Bandage", (0.98, 0.9, 0.78), rough=0.8)
    for rz in (0.75, -0.75):
        add_rbox(head, bd, (0.12, 0.016, 0.035), Vector((0.13, -0.24, 0.17)), rot=(0.65, 0.45, rz - 0.4))
    b = v.obj["Body"]
    delete_mats(b, ["Shoe"])  # kemer montun altında
    body_scale(v, sx=1.08, sy=1.06, belly=0.02)
    # şişme mont: Shirt bölgesine yatay dikiş şişkinlikleri
    def puff(co):
        if co.z < -0.15:
            return co
        k = 1.0 + 0.085 * abs(math.sin((co.z + 0.2) * math.pi / 0.1)) ** 0.5 + 0.02
        return Vector((co.x * k, co.y * k, co.z))
    deform(b, puff, mats=["Shirt"])
    # mont eteği pantolonu biraz örtsün
    add_torus(b, v.mats["Shirt"], 0.262, 0.04, Vector((0, 0, -0.1)), seg=36, rseg=8)
    # dik yaka + fermuar + cepler
    add_torus(b, v.mats["Shirt"], 0.13, 0.05, Vector((0, 0, 0.265)), seg=32, rseg=8, squash=(1.0, 1.6))
    zp = v.mat("Zipper", (0.72, 0.72, 0.75), rough=0.3, metal=0.9)
    add_tube(b, zp, [(0, -0.183, 0.27), (0, -0.258, 0.15), (0, -0.282, 0.04), (0, -0.282, -0.06), (0, -0.268, -0.12)], 0.007, seg=6)
    add_rbox(b, zp, (0.022, 0.012, 0.04), Vector((0, -0.19, 0.25)), rot=(0.6, 0, 0))
    for sx in (-1, 1):
        add_tube(b, zp, [(sx * 0.1, -0.265, -0.02), (sx * 0.16, -0.235, -0.07)], 0.005, seg=6)
    # spor ayakkabı: kalın taban (Sole) + yan şerit + bağcıklar
    st = v.mat("Stripe", (0.85, 0.15, 0.15), rough=0.5)
    lace = v.mat("Lace", (0.15, 0.15, 0.17), rough=0.8)
    for fn in ("FootL", "FootR"):
        f = v.obj[fn]
        deform(f, lambda co: Vector((co.x * 1.05, co.y * 1.08, co.z - 0.012)), mats=["Sole"])
        deform(f, lambda co: Vector((co.x, co.y, co.z * 1.25 - 0.012)) if co.z < -0.08 else co, mats=["Sole"])
        for sx in (-1, 1):
            add_tube(f, st, [(sx * 0.083, 0.04, -0.03), (sx * 0.085, -0.04, -0.015), (sx * 0.075, -0.11, -0.04)], 0.009, seg=6)
        for i in range(3):
            add_rbox(f, lace, (0.07, 0.014, 0.012), Vector((0, -0.04 - i * 0.035, 0.03 - i * 0.012)), rot=(0.3, 0, 0))
    hands(v, x=0.37)
    return v


BUILDERS = [
    ("pazarci", build_pazarci), ("musteri_erkek", build_musteri_erkek), ("musteri_kadin", build_musteri_kadin),
    ("teyze", build_teyze), ("emekli", build_emekli), ("cocuk", build_cocuk), ("kapkac", build_kapkac),
    ("hirsiz", build_hirsiz), ("zabita", build_zabita), ("cayci", build_cayci), ("simitci", build_simitci),
]


# --------------------------------------------------------------------------- dışa aktarım + render
def export_glb(v):
    bpy.ops.object.select_all(action="DESELECT")
    for o in v.obj.values():
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = v.obj["Body"]
    path = os.path.join(OUT_MODELS, "char_%s.glb" % v.key)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="EXPORT", export_texcoords=True, export_normals=True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in v.obj.values())
    print("WROTE", path, "tris=%d" % tris)


def studio():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "AgX"
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("StudioW")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb((0.66, 0.7, 0.76)), 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    col = bpy.data.collections.new("STUDIO")
    sc.collection.children.link(col)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    me = bpy.data.meshes.new("Floor")
    bm.to_mesh(me)
    fl = bpy.data.objects.new("Floor", me)
    fm = bpy.data.materials.new("FloorM")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb((0.62, 0.62, 0.6)), 1)
    me.materials.append(fm)
    col.objects.link(fl)

    def light(name, kind, rot, energy, size=1.0):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        if kind == "AREA":
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        col.objects.link(lo)
        lo.rotation_euler = rot
        return lo
    light("Key", "SUN", (math.radians(50), 0, math.radians(-30)), 3.2)
    f = light("Fill", "AREA", (math.radians(70), 0, math.radians(40)), 400, size=5)
    f.location = (4, -5, 4)
    cd = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cd)
    col.objects.link(cam)
    sc.camera = cam
    return cam


def look(cam, loc, target, lens):
    cam.location = Vector(loc)
    cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def render(path, w, h):
    sc = bpy.context.scene
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT_ART, exist_ok=True)
    cam = studio()
    done = []
    for key, fn in BUILDERS:
        if ONLY and key not in ONLY:
            continue
        v = fn()
        for o in v.obj.values():
            if o.parent is None:
                pass
        export_glb(v)
        # tekil önizleme: önden 3/4 + yandan
        for c in bpy.data.collections:
            if c.name.startswith("CH_"):
                c.hide_render = c.name != "CH_" + key
        look(cam, (1.25, -3.0, 1.15), (0, 0, 0.8), 55)
        render(os.path.join(OUT_ART, "preview_%s.png" % key), 640, 800)
        v.finish()
        done.append(v)
    # sıra dizilimi
    for c in bpy.data.collections:
        if c.name.startswith("CH_"):
            c.hide_render = False
    n = len(done)
    gap = 1.0
    for i, v in enumerate(done):
        off = Vector(((i - (n - 1) / 2) * gap, 0, 0))
        for o in v.obj.values():
            if o.parent is None:
                o.location += off
    if n > 1:
        look(cam, (0, -12.5, 2.0), (0, 0, 0.8), 42)
        render(os.path.join(OUT_ART, "lineup.png"), 1800, 640)
    if not ONLY:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_ART, "characters.blend"), compress=True)


main()
