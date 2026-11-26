extends RefCounted
## Pazar ürün kataloğu, her meyve/sebze için özgün düşük poligonlu 3D modeller ve
## MultiMesh tabanlı "yığın" (pile) sistemi: tezgahta stok azaldıkça tepeden eriyen bereketli ürün dağları.

const LP := preload("res://lowpoly.gd")

# Temel 6 ürün tezgah arkasında da bulunur; 5 özel ürün (patlıcan, muz, karpuz, çilek, limon) Toptancı Kamyonundan alınır.
# "shelf": tazelik kaybı çarpanı (1.0 = ortalama; çilek çabuk bozulur, soğan/limon dayanıklıdır).
# "pile": yığın yerleşimi — fx/fz taban ayak izi (m), h katman yüksekliği, y0 taban merkez yüksekliği,
#         yaw "rand" (yuvarlak ürünler rastgele döner) / "fix" (uzun ürünler yan yana dizilir), rot = yatırma açısı.
const ITEMS := {
	"domates": {
		"name": "Domates", "base": 10, "crate_cost": 48, "tier": 0, "shelf": 1.1,
		"color": Color(0.92, 0.16, 0.13), "accent": Color(0.98, 0.34, 0.22), "stem": Color(0.18, 0.62, 0.18),
		"pile": {"fx": 0.165, "fz": 0.165, "h": 0.105, "y0": 0.072, "yaw": "rand"},
	},
	"elma": {
		"name": "Elma", "base": 12, "crate_cost": 58, "tier": 0, "shelf": 0.8,
		"color": Color(0.42, 0.78, 0.2), "accent": Color(0.86, 0.22, 0.18), "stem": Color(0.38, 0.22, 0.1),
		"pile": {"fx": 0.16, "fz": 0.16, "h": 0.11, "y0": 0.08, "yaw": "rand"},
	},
	"sogan": {
		"name": "Soğan", "base": 8, "crate_cost": 36, "tier": 0, "shelf": 0.55,
		"color": Color(0.86, 0.62, 0.28), "accent": Color(0.72, 0.45, 0.18), "stem": Color(0.55, 0.44, 0.2),
		"pile": {"fx": 0.16, "fz": 0.16, "h": 0.1, "y0": 0.08, "yaw": "rand"},
	},
	"portakal": {
		"name": "Portakal", "base": 14, "crate_cost": 70, "tier": 0, "shelf": 0.75,
		"color": Color(0.98, 0.52, 0.08), "accent": Color(1.0, 0.66, 0.16), "stem": Color(0.2, 0.56, 0.16),
		"pile": {"fx": 0.165, "fz": 0.165, "h": 0.115, "y0": 0.08, "yaw": "rand"},
	},
	"salatalik": {
		"name": "Salatalık", "base": 9, "crate_cost": 42, "tier": 0, "shelf": 1.05,
		"color": Color(0.17, 0.42, 0.15), "accent": Color(0.55, 0.76, 0.32), "stem": Color(0.92, 0.82, 0.30),
		"pile": {"fx": 0.30, "fz": 0.082, "h": 0.064, "y0": 0.038, "yaw": "fix"},
	},
	"biber": {
		"name": "Sivri Biber", "base": 11, "crate_cost": 52, "tier": 0, "shelf": 1.0,
		"color": Color(0.52, 0.78, 0.22), "accent": Color(0.40, 0.66, 0.16), "stem": Color(0.22, 0.46, 0.13),
		"pile": {"fx": 0.30, "fz": 0.062, "h": 0.046, "y0": 0.028, "yaw": "fix"},
	},
	"patlican": {
		"name": "Patlıcan", "base": 17, "crate_cost": 85, "tier": 1, "shelf": 1.0,
		"color": Color(0.32, 0.11, 0.44), "accent": Color(0.45, 0.18, 0.58), "stem": Color(0.22, 0.56, 0.18),
		"pile": {"fx": 0.26, "fz": 0.14, "h": 0.105, "y0": 0.066, "yaw": "fix", "rot": Vector3(0, 0, -PI / 2)},
	},
	"muz": {
		"name": "Muz", "base": 19, "crate_cost": 96, "tier": 1, "shelf": 1.25,
		"color": Color(0.98, 0.84, 0.16), "accent": Color(0.42, 0.28, 0.12), "stem": Color(0.48, 0.52, 0.16),
		"pile": {"fx": 0.16, "fz": 0.2, "h": 0.075, "y0": 0.045, "yaw": "fix", "rot": Vector3(PI / 2, 0, 0)},
	},
	"karpuz": {
		"name": "Karpuz", "base": 26, "crate_cost": 135, "tier": 1, "shelf": 0.7,
		"color": Color(0.16, 0.5, 0.2), "accent": Color(0.56, 0.82, 0.36), "stem": Color(0.36, 0.52, 0.18),
		"pile": {"fx": 0.22, "fz": 0.19, "h": 0.135, "y0": 0.085, "yaw": "fix"},
	},
	"cilek": {
		"name": "Çilek", "base": 22, "crate_cost": 108, "tier": 1, "shelf": 1.45,
		"color": Color(0.90, 0.10, 0.16), "accent": Color(1.0, 0.88, 0.42), "stem": Color(0.20, 0.60, 0.20),
		"pile": {"fx": 0.105, "fz": 0.105, "h": 0.066, "y0": 0.046, "yaw": "rand", "rot": Vector3(0.45, 0, 0)},
	},
	"limon": {
		"name": "Limon", "base": 15, "crate_cost": 72, "tier": 1, "shelf": 0.6,
		"color": Color(0.98, 0.88, 0.18), "accent": Color(0.94, 0.78, 0.10), "stem": Color(0.24, 0.56, 0.18),
		"pile": {"fx": 0.2, "fz": 0.135, "h": 0.1, "y0": 0.062, "yaw": "fix"},
	},
}

const BASIC_ORDER := ["domates", "elma", "sogan", "portakal", "salatalik", "biber"]
const EXOTIC_ORDER := ["patlican", "muz", "karpuz", "cilek", "limon"]
const ITEM_ORDER := ["domates", "elma", "sogan", "portakal", "salatalik", "biber", "patlican", "muz", "karpuz", "cilek", "limon"]

static var _mesh_cache := {}
static var _mat_cache := {}
static var _parts_cache := {}


static func _cached_mesh(key: String, builder: Callable) -> ArrayMesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = builder.call()
	return _mesh_cache[key]


static func _cached_mat(key: String, c: Color, rough := 0.72) -> StandardMaterial3D:
	if not _mat_cache.has(key):
		_mat_cache[key] = LP.mat(c, rough)
	return _mat_cache[key]


static func _part(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


## Her meyve ve sebzeyi ayırt edilebilir, parlak low-poly biçimde üretir.
static func build_mesh(parent: Node, item_id: String, pos: Vector3, radius := 0.082) -> Node3D:
	var info: Dictionary = ITEMS.get(item_id, ITEMS["domates"])
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var s := radius / 0.082 # standart boyuta göre ölçek
	holder.scale = Vector3.ONE * s

	var glossy := item_id in ["domates", "elma", "patlican", "karpuz", "biber", "cilek", "salatalik", "limon"]
	var m_main := _cached_mat(item_id + "_main", info["color"], 0.5 if glossy else 0.78)
	var m_acc := _cached_mat(item_id + "_acc", info["accent"], 0.65)
	var m_stem := _cached_mat(item_id + "_stem", info["stem"], 0.82)

	match item_id:
		"domates":
			# Hafif basık, oluklu parlak domates + 4 yapraklı yıldız çanak
			var body := _cached_mesh("tom_body", func(): return LP.ellipsoid(0.086, 0.072, 0.086, 8, 5))
			var leaf := _cached_mesh("tom_leaf", func(): return LP.box(Vector3(0.075, 0.012, 0.018)))
			var stem := _cached_mesh("tom_stem", func(): return LP.cyl(0.008, 0.012, 0.032, 5))
			_part(holder, body, m_main, Vector3.ZERO)
			_part(holder, leaf, m_stem, Vector3(0, 0.069, 0), Vector3(0, 0.2, 0.14))
			_part(holder, leaf, m_stem, Vector3(0, 0.069, 0), Vector3(0, PI * 0.5 + 0.2, -0.14))
			_part(holder, stem, m_stem, Vector3(0, 0.082, 0), Vector3(0.15, 0, 0.1))

		"elma":
			# Üstü geniş altı dar elma gövdesi + kahverengi sap + yeşil yaprak
			var top := _cached_mesh("app_top", func(): return LP.ellipsoid(0.082, 0.068, 0.082, 7, 4))
			var bot := _cached_mesh("app_bot", func(): return LP.ellipsoid(0.068, 0.056, 0.068, 7, 4))
			var stem := _cached_mesh("app_stem", func(): return LP.cyl(0.007, 0.01, 0.045, 5))
			var leaf := _cached_mesh("app_leaf", func(): return LP.ellipsoid(0.036, 0.008, 0.018, 5, 3))
			var m_leaf := _cached_mat("app_leaf_m", Color(0.22, 0.65, 0.2), 0.78)
			_part(holder, top, m_main, Vector3(0, 0.016, 0))
			_part(holder, bot, m_main, Vector3(0, -0.022, 0))
			_part(holder, stem, m_stem, Vector3(0, 0.086, 0), Vector3(0.22, 0.3, 0))
			_part(holder, leaf, m_leaf, Vector3(0.028, 0.092, 0.005), Vector3(0.2, 0.2, -0.45))

		"sogan":
			# Damla biçimli sarı/kehribar soğan + sivri uç + alt kök püskülü
			var bulb := _cached_mesh("oni_bulb", func(): return LP.ellipsoid(0.082, 0.070, 0.082, 8, 5))
			var tip := _cached_mesh("oni_tip", func(): return LP.cyl(0.004, 0.042, 0.072, 6))
			var root := _cached_mesh("oni_root", func(): return LP.cyl(0.024, 0.014, 0.018, 5))
			_part(holder, bulb, m_main, Vector3(0, -0.008, 0))
			_part(holder, tip, m_acc, Vector3(0, 0.066, 0))
			_part(holder, root, m_stem, Vector3(0, -0.072, 0))

		"portakal":
			# Dolgun canlı portakal + minik yeşil göbek + parlak yaprak
			var body := _cached_mesh("ora_body", func(): return LP.sphere(0.084, 8, 5))
			var nub := _cached_mesh("ora_nub", func(): return LP.cyl(0.018, 0.022, 0.014, 5))
			var leaf := _cached_mesh("ora_leaf", func(): return LP.ellipsoid(0.032, 0.007, 0.016, 5, 3))
			_part(holder, body, m_main, Vector3.ZERO)
			_part(holder, nub, m_stem, Vector3(0, 0.082, 0))
			_part(holder, leaf, m_stem, Vector3(0.024, 0.084, 0), Vector3(0.15, 0.5, -0.3))

		"salatalik":
			# Uzun, hafif kavisli koyu yeşil salatalık + açık yeşil pürüz kabarcıkları + sarı çiçek ucu
			var seg := _cached_mesh("cuc_seg", func(): return LP.ellipsoid(0.078, 0.036, 0.036, 7, 4))
			var bump := _cached_mesh("cuc_bump", func(): return LP.box(Vector3(0.014, 0.012, 0.014)))
			var stub := _cached_mesh("cuc_stub", func(): return LP.cyl(0.007, 0.012, 0.022, 5))
			var m_bump := _cached_mat("cuc_bump_m", info["accent"], 0.8)
			_part(holder, seg, m_main, Vector3(-0.062, -0.004, 0.0), Vector3(0, 0, 0.09))
			_part(holder, seg, m_main, Vector3(0.062, -0.004, 0.0), Vector3(0, 0, -0.09))
			for b in 7:
				var bx := -0.108 + float(b) * 0.036
				var bz := 0.016 if b % 2 == 0 else -0.016
				_part(holder, bump, m_bump, Vector3(bx, 0.027 - absf(bx) * 0.12, bz), Vector3(0.4, float(b) * 0.9, 0.3))
			_part(holder, stub, m_acc, Vector3(-0.142, 0.006, 0.0), Vector3(0, 0, PI / 2))
			_part(holder, stub, m_stem, Vector3(0.142, 0.006, 0.0), Vector3(0, 0, -PI / 2))

		"biber":
			# Türk sivri biberi: uca doğru incelen kavisli parlak yeşil gövde + koyu çanak + kıvrık sap
			var s0 := _cached_mesh("pep_s0", func(): return LP.cyl(0.023, 0.025, 0.074, 6))
			var s1 := _cached_mesh("pep_s1", func(): return LP.cyl(0.015, 0.023, 0.07, 6))
			var s2 := _cached_mesh("pep_s2", func(): return LP.cyl(0.002, 0.015, 0.07, 5))
			var cap := _cached_mesh("pep_cap", func(): return LP.cyl(0.027, 0.02, 0.018, 6))
			var stem := _cached_mesh("pep_stem", func(): return LP.cyl(0.005, 0.008, 0.045, 5))
			_part(holder, s0, m_main, Vector3(-0.07, 0.0, 0.0), Vector3(0, 0, PI / 2))
			_part(holder, s1, m_main, Vector3(0.0, -0.005, 0.0), Vector3(0, 0, PI / 2 + 0.14))
			_part(holder, s2, m_acc, Vector3(0.066, -0.02, 0.0), Vector3(0, 0, PI / 2 + 0.36))
			_part(holder, cap, m_stem, Vector3(-0.113, 0.0, 0.0), Vector3(0, 0, PI / 2))
			_part(holder, stem, m_stem, Vector3(-0.138, 0.012, 0.0), Vector3(0, 0, PI / 2 - 0.65))

		"patlican":
			# Parlak mor armut/damla gövde + geniş yeşil çanak ve kıvrık sap
			var bot := _cached_mesh("egg_bot", func(): return LP.ellipsoid(0.066, 0.088, 0.066, 7, 5))
			var top := _cached_mesh("egg_top", func(): return LP.cyl(0.034, 0.056, 0.076, 7))
			var cap := _cached_mesh("egg_cap", func(): return LP.cyl(0.022, 0.046, 0.032, 6))
			var stem := _cached_mesh("egg_stem", func(): return LP.cyl(0.009, 0.014, 0.045, 5))
			_part(holder, bot, m_main, Vector3(0, -0.012, 0), Vector3(0.28, 0.4, 0.1))
			_part(holder, top, m_main, Vector3(0.005, 0.048, 0.012), Vector3(0.2, 0.4, 0.1))
			_part(holder, cap, m_stem, Vector3(0.012, 0.084, 0.022), Vector3(0.22, 0, 0))
			_part(holder, stem, m_stem, Vector3(0.015, 0.112, 0.03), Vector3(0.55, 0, -0.15))

		"muz":
			# 3'lü kavisli sarı muz hevengi + kahverengi uçlar
			var seg := _cached_mesh("ban_seg", func(): return LP.cyl(0.020, 0.024, 0.092, 6))
			var tip := _cached_mesh("ban_tip", func(): return LP.cyl(0.006, 0.018, 0.028, 5))
			var crown := _cached_mesh("ban_crw", func(): return LP.box(Vector3(0.068, 0.024, 0.028)))
			for b: float in [-1.0, 0.0, 1.0]:
				var bx: float = b * 0.028
				_part(holder, seg, m_main, Vector3(bx, 0.022, -0.016), Vector3(0.45, 0, b * 0.12))
				_part(holder, seg, m_main, Vector3(bx, -0.026, 0.016), Vector3(-0.45, 0, b * 0.08))
				_part(holder, tip, m_acc, Vector3(bx, -0.064, 0.044), Vector3(-0.75, 0, 0))
			_part(holder, crown, m_stem, Vector3(0, 0.068, -0.036), Vector3(0.4, 0, 0))

		"karpuz":
			# Büyük oval koyu yeşil karpuz + açık yeşil boyuna çizgiler + sap
			var body := _cached_mesh("mel_body", func(): return LP.ellipsoid(0.106, 0.086, 0.086, 9, 5))
			var stripe := _cached_mesh("mel_str", func(): return LP.ellipsoid(0.109, 0.022, 0.088, 8, 3))
			var stem := _cached_mesh("mel_stem", func(): return LP.cyl(0.008, 0.014, 0.036, 5))
			_part(holder, body, m_main, Vector3(0, 0.01, 0))
			for ang in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
				_part(holder, stripe, m_acc, Vector3(0, 0.01, 0), Vector3(ang, 0, 0))
			_part(holder, stem, m_stem, Vector3(0.104, 0.018, 0), Vector3(0, 0, -1.35))

		"cilek":
			# Kalp/koni biçimli kırmızı çilek + sarı tohum noktaları + yıldız yaprak taç + sap
			var top := _cached_mesh("str_top", func(): return LP.ellipsoid(0.052, 0.034, 0.052, 7, 4))
			var cone := _cached_mesh("str_cone", func(): return LP.cyl(0.051, 0.008, 0.068, 7))
			var seed_m := _cached_mesh("str_seed", func(): return LP.box(Vector3(0.009, 0.009, 0.009)))
			var leaf := _cached_mesh("str_leaf", func(): return LP.ellipsoid(0.03, 0.006, 0.013, 5, 3))
			var stem := _cached_mesh("str_stem", func(): return LP.cyl(0.004, 0.006, 0.026, 4))
			_part(holder, top, m_main, Vector3(0, 0.012, 0))
			_part(holder, cone, m_main, Vector3(0, -0.026, 0), Vector3(PI, 0, 0))
			for k in 9:
				var a := float(k) * TAU / 9.0 + float(k % 3) * 0.5
				var ring := k % 3
				var yy := 0.002 - float(ring) * 0.02
				var rr := 0.05 - float(ring) * 0.013
				_part(holder, seed_m, m_acc, Vector3(cos(a) * rr, yy, sin(a) * rr), Vector3(0.4, a, 0.3))
			for k in 5:
				var a2 := float(k) * TAU / 5.0
				_part(holder, leaf, m_stem, Vector3(cos(a2) * 0.024, 0.042, sin(a2) * 0.024), Vector3(0, -a2, -0.28))
			_part(holder, stem, m_stem, Vector3(0, 0.056, 0), Vector3(0.2, 0, 0.1))

		"limon":
			# Oval parlak sarı limon + iki sivri uç memesi + minik yaprak
			var body := _cached_mesh("lem_body", func(): return LP.ellipsoid(0.088, 0.064, 0.064, 8, 5))
			var nub := _cached_mesh("lem_nub", func(): return LP.cyl(0.005, 0.024, 0.026, 6))
			var leaf := _cached_mesh("lem_leaf", func(): return LP.ellipsoid(0.036, 0.006, 0.016, 5, 3))
			_part(holder, body, m_main, Vector3.ZERO)
			_part(holder, nub, m_acc, Vector3(0.094, 0.0, 0.0), Vector3(0, 0, -PI / 2))
			_part(holder, nub, m_acc, Vector3(-0.094, 0.0, 0.0), Vector3(0, 0, PI / 2))
			_part(holder, leaf, m_stem, Vector3(-0.098, 0.026, 0.018), Vector3(0.3, 0.7, 0.5))

		_:
			var fb := _cached_mesh("fb_sph", func(): return LP.sphere(0.08, 7, 4))
			_part(holder, fb, m_main, Vector3.ZERO)

	return holder


# ---------- Yığın (Pile) Sistemi ----------

## Ürün modelinin parçaları (mesh, materyal, yerel dönüşüm) — MultiMesh yığınları için önbelleğe alınır.
static func _item_parts(item_id: String) -> Array:
	if _parts_cache.has(item_id):
		return _parts_cache[item_id]
	var tmp := Node3D.new()
	var holder := build_mesh(tmp, item_id, Vector3.ZERO, 0.082)
	var out := []
	for c in holder.get_children():
		var mi := c as MeshInstance3D
		if mi:
			out.append({"mesh": mi.mesh, "mat": mi.material_override, "xf": mi.transform})
	tmp.free()
	_parts_cache[item_id] = out
	return out


## Bir tepsi (w x d) üzerinde alttan üste piramit yığın konumları üretir.
## Sıralama: önce taban katmanı, en son tepe — böylece görünür sayı azaldıkça yığın tepeden erir.
static func pile_layout(item_id: String, w: float, d: float, max_layers := 3, scale := 1.0, seed_val := 0) -> Array[Transform3D]:
	var info: Dictionary = ITEMS.get(item_id, ITEMS["domates"])
	var pl: Dictionary = info.get("pile", {"fx": 0.165, "fz": 0.165, "h": 0.1, "y0": 0.075, "yaw": "rand"})
	var fx: float = float(pl["fx"]) * scale
	var fz: float = float(pl["fz"]) * scale
	var h: float = float(pl["h"]) * scale
	var y0: float = float(pl["y0"]) * scale
	var rand_yaw: bool = str(pl.get("yaw", "rand")) == "rand"
	var lay_rot: Vector3 = pl.get("rot", Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item_id) ^ (seed_val * 7919 + 17)
	var nx := maxi(int(floor(w / fx)), 1)
	var nz := maxi(int(floor(d / fz)), 1)
	var out: Array[Transform3D] = []
	for layer in max_layers:
		var cx := nx - layer
		var cz := nz - layer
		if cx < 1 or cz < 1:
			break
		var ox := -float(cx - 1) * fx * 0.5
		var oz := -float(cz - 1) * fz * 0.5
		var layer_pts: Array[Transform3D] = []
		for iz in cz:
			for ix in cx:
				var p := Vector3(ox + float(ix) * fx, y0 + float(layer) * h, oz + float(iz) * fz)
				p += Vector3(rng.randf_range(-0.012, 0.012), rng.randf_range(-0.004, 0.006), rng.randf_range(-0.01, 0.01)) * scale
				var yaw := rng.randf_range(-PI, PI) if rand_yaw else rng.randf_range(-0.16, 0.16) + (PI if rng.randf() < 0.5 else 0.0)
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), yaw, rng.randf_range(-0.12, 0.12)))
				b = b * Basis.from_euler(lay_rot)
				layer_pts.append(Transform3D(b * Basis.from_scale(Vector3.ONE * scale), p))
		# Katman içi karıştır ki tepe katman düzensiz erisin
		for i in range(layer_pts.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t := layer_pts[i]
			layer_pts[i] = layer_pts[j]
			layer_pts[j] = t
		out.append_array(layer_pts)
	return out


## Verilen dönüşümlere MultiMesh ile çok ucuz bir ürün yığını kurar (parça başına tek çizim çağrısı).
static func build_pile(parent: Node, item_id: String, xforms: Array[Transform3D], visible_n := -1) -> Node3D:
	var root := Node3D.new()
	root.name = "Pile_" + item_id
	parent.add_child(root)
	for part: Dictionary in _item_parts(item_id):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part["mesh"]
		mm.instance_count = xforms.size()
		var pxf: Transform3D = part["xf"]
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * pxf)
		mm.visible_instance_count = clampi(visible_n, -1, xforms.size())
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = part["mat"]
		root.add_child(mmi)
	root.set_meta("pile_size", xforms.size())
	return root


static func set_pile_visible(root: Node3D, n: int) -> void:
	if root == null:
		return
	for c in root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi and mmi.multimesh:
			mmi.multimesh.visible_instance_count = clampi(n, 0, mmi.multimesh.instance_count)


static func set_pile_overlay(root: Node3D, overlay: Material) -> void:
	if root == null:
		return
	for c in root.get_children():
		var gi := c as GeometryInstance3D
		if gi:
			gi.material_overlay = overlay


## Stok sayısını yığındaki görünür ürün adedine çevirir (en az 1, stok dolunca tüm yığın).
static func pile_visible_for(count: int, capacity: int, pile_size: int) -> int:
	if count <= 0:
		return 0
	return clampi(int(ceil(float(count) / float(maxi(capacity, 1)) * float(pile_size))), 1, pile_size)


## Basit, renkli ve tam dolu bir kasa içeriği (toptancı rafı / tezgah arkası yedek kasaları için).
static func build_crate_fill(parent: Node, item_id: String, pos: Vector3, w: float, d: float, scale := 0.86, layers := 2, seed_val := 0) -> Node3D:
	var xf := pile_layout(item_id, w, d, layers, scale, seed_val)
	var pile := build_pile(parent, item_id, xf)
	pile.position = pos
	return pile
