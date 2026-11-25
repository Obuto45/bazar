extends RefCounted
## Pazar ürün kataloğu ve her meyve/sebze için özgün düşük poligonlu 3D modeller.

const LP := preload("res://lowpoly.gd")

# Temel 4 ürün tezgah arkasında da bulunur; 3 özel ürün (patlıcan, muz, karpuz) Toptancı Kamyonundan alınır.
const ITEMS := {
	"domates": {
		"name": "Domates", "base": 10, "crate_cost": 48, "tier": 0,
		"color": Color(0.92, 0.16, 0.13), "accent": Color(0.98, 0.34, 0.22), "stem": Color(0.18, 0.62, 0.18),
	},
	"elma": {
		"name": "Elma", "base": 12, "crate_cost": 58, "tier": 0,
		"color": Color(0.42, 0.78, 0.2), "accent": Color(0.86, 0.22, 0.18), "stem": Color(0.38, 0.22, 0.1),
	},
	"sogan": {
		"name": "Soğan", "base": 8, "crate_cost": 36, "tier": 0,
		"color": Color(0.86, 0.62, 0.28), "accent": Color(0.72, 0.45, 0.18), "stem": Color(0.55, 0.44, 0.2),
	},
	"portakal": {
		"name": "Portakal", "base": 14, "crate_cost": 70, "tier": 0,
		"color": Color(0.98, 0.52, 0.08), "accent": Color(1.0, 0.66, 0.16), "stem": Color(0.2, 0.56, 0.16),
	},
	"patlican": {
		"name": "Patlıcan", "base": 17, "crate_cost": 85, "tier": 1,
		"color": Color(0.32, 0.11, 0.44), "accent": Color(0.45, 0.18, 0.58), "stem": Color(0.22, 0.56, 0.18),
	},
	"muz": {
		"name": "Muz", "base": 19, "crate_cost": 96, "tier": 1,
		"color": Color(0.98, 0.84, 0.16), "accent": Color(0.42, 0.28, 0.12), "stem": Color(0.48, 0.52, 0.16),
	},
	"karpuz": {
		"name": "Karpuz", "base": 26, "crate_cost": 135, "tier": 1,
		"color": Color(0.16, 0.5, 0.2), "accent": Color(0.56, 0.82, 0.36), "stem": Color(0.36, 0.52, 0.18),
	},
}

const BASIC_ORDER := ["domates", "elma", "sogan", "portakal"]
const EXOTIC_ORDER := ["patlican", "muz", "karpuz"]
const ITEM_ORDER := ["domates", "elma", "sogan", "portakal", "patlican", "muz", "karpuz"]

static var _mesh_cache := {}
static var _mat_cache := {}


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

	var m_main := _cached_mat(item_id + "_main", info["color"], 0.52 if item_id in ["domates", "elma", "patlican", "karpuz"] else 0.78)
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

		_:
			var fb := _cached_mesh("fb_sph", func(): return LP.sphere(0.08, 7, 4))
			_part(holder, fb, m_main, Vector3.ZERO)

	return holder
