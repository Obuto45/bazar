extends RefCounted
## Pazarcı kişisel envanter eşyaları (P mağazasından veya gezici çaycı/simitçiden alınır; meyve kasaları ASLA envantere girmez).
## Sigara, Küba Purosu, İnce Belli Çay, Susamlı Simit, El Megafonu, Meyve Bıçağı, Arabesk Radyo ve Su Fısfısı.

const LP := preload("res://lowpoly.gd")
const VFX := preload("res://vfx.gd")

const CATALOG := {
	"sigara": {
		"name": "Sigara Paketi",
		"short": "Sigara",
		"icon": "🚬",
		"cost": 15,
		"uses": 5, # 5 dal
		"puffs_per_use": 5,
		"consumable": true,
		"left_hint": "Nefes Çek (+12sn %25 Hız)",
		"right_hint": "Kül Silk",
		"desc": "5 dal sigara. Elde sürekli tüter! Sol tıkla nefes çekip duman üfle (+12sn Keyif), sağ tıkla kül silk.",
	},
	"puro": {
		"name": "Küba Purosu",
		"short": "Puro",
		"icon": "🪵",
		"cost": 45,
		"uses": 3, # 3 puro
		"puffs_per_use": 8,
		"consumable": true,
		"left_hint": "Derin Çek & Halka Üfle (+16sn Hız)",
		"right_hint": "Kül Silk",
		"desc": "Altın bantlı 3 puro. Yoğun duman halkası üfler + Ağır Abi prestiji (+%18 müşteri ilgisi)!",
	},
	"cay": {
		"name": "İnce Belli Çay",
		"short": "Çay",
		"icon": "🍵",
		"cost": 10,
		"uses": 1, # 1 bardak (4 yudum)
		"puffs_per_use": 4,
		"consumable": true,
		"left_hint": "Yudumla (+15sn Bağırma)",
		"right_hint": "Kaşıkla Karıştır",
		"desc": "Tavşan kanı sıcak çay (4 yudum). Sol tıkla yudumla (her yudum +15sn bağırma +%25), sağ tıkla kaşıkla karıştır!",
	},
	"simit": {
		"name": "Susamlı Simit",
		"short": "Simit",
		"icon": "🥯",
		"cost": 15,
		"uses": 1, # 1 simit (3 ısırık)
		"puffs_per_use": 3,
		"consumable": true,
		"left_hint": "Isır (+18sn Hız)",
		"right_hint": "Kokla & Çevir",
		"desc": "Fırından taze çıtır simit (3 ısırık). Sol tıkla ısır (+18sn +%15 hız), sağ tıkla sıcak kokusunu çek!",
	},
	"megafon": {
		"name": "El Megafonu",
		"short": "Megafon",
		"icon": "📢",
		"cost": 75,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"left_hint": "Anons Patlat",
		"right_hint": "Dikkat Sireni",
		"desc": "Eldeyken bağırma dB'ini fırlatır (+12 dB / 1.85x), bağırırken ağza kalkar! Sağ tıkla kısa siren çal.",
	},
	"bicak": {
		"name": "Meyve Bıçağı",
		"short": "Bıçak",
		"icon": "🔪",
		"cost": 60,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"left_hint": "Savur",
		"right_hint": "Bıçak Çevir",
		"desc": "Sol tıkla rakip pazarcıya saldır (Zabıta -50 TL keser!). Sağ tıkla pazarcı usulü bıçak çevir!",
	},
	"radyo": {
		"name": "Arabesk Radyo",
		"short": "Radyo",
		"icon": "📻",
		"cost": 90,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"left_hint": "Aç / Kapat",
		"right_hint": "Frekans Değiştir",
		"desc": "Sol tıkla Hicaz Arabesk aç/kapat, sağ tıkla frekans/ton değiştir; tezgahına koyup tüm sokağı inlet!",
	},
	"spray": {
		"name": "Su Fısfısı",
		"short": "Fısfıs",
		"icon": "💦",
		"cost": 25,
		"uses": 4, # 4 fıs
		"puffs_per_use": 1,
		"consumable": true,
		"left_hint": "Ürünleri Tazele",
		"right_hint": "Şişeyi Çalkala",
		"desc": "4 fıs. Tezgahına bakıp sol tıkla: ürünler ışıl ışıl tazelenir (+%35 tazelik), sağ tıkla çalkala!",
	},
}

const ORDER := ["sigara", "puro", "cay", "simit", "megafon", "bicak", "radyo", "spray"]


## Sürekli tüten duman (sigara/puro) veya sıcak buhar (çay) yayan lokal-olmayan partikül yayıcı.
static func _make_continuous_wisp(thick: bool, is_steam := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "TeaSteamEmitter" if is_steam else "IdleSmokeEmitter"
	p.one_shot = false
	p.local_coords = false
	p.amount = 12 if is_steam else (22 if thick else 16)
	p.lifetime = 1.25 if is_steam else (1.95 if thick else 1.55)
	p.preprocess = 0.25
	VFX._soften(p, 0.06 if is_steam else (0.075 if thick else 0.05))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.018 if is_steam else (0.008 if thick else 0.005)
	p.direction = Vector3(0.06, 1.0, 0.04).normalized()
	p.spread = 22.0 if is_steam else (18.0 if thick else 14.0)
	p.initial_velocity_min = 0.14 if is_steam else (0.16 if thick else 0.13)
	p.initial_velocity_max = 0.28 if is_steam else (0.34 if thick else 0.25)
	p.gravity = Vector3(0.05, 0.22, 0.03) if is_steam else Vector3(0.08, 0.28, 0.05)
	p.damping_min = 0.25
	p.damping_max = 0.55
	var sc := Curve.new()
	sc.max_value = 3.2
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.45, 1.45 if thick else 1.15))
	sc.add_point(Vector2(1.0, 2.75 if thick else 2.1))
	p.scale_amount_curve = sc
	var c0 := Color(0.98, 0.97, 0.94, 0.26) if is_steam else (Color(0.76, 0.80, 0.86, 0.44) if thick else Color(0.86, 0.88, 0.92, 0.36))
	p.color_ramp = VFX.ramp([0.0, 0.14, 0.62, 1.0], [Color(c0, 0.0), c0, Color(c0, c0.a * 0.48), Color(c0, 0.0)])
	p.emitting = true
	return p


## Birinci veya üçüncü şahıs için detaylı 3D eşya modeli üretir.
## burn_ratio (0..1): sigara/puroyu kısaltır, çay seviyesini düşürür, simitten ısırık alır.
static func build_item_model(item_id: String, burn_ratio := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Item_" + item_id
	var rem := clampf(1.0 - burn_ratio, 0.22, 1.0) # kalan uzunluk/doluluk oranı

	match item_id:
		"sigara":
			# Turuncu filtre + beyaz kağıt gövde (yandıkça kısalır) + kül halkası + yanan kor uç + sürekli duman!
			LP.add(root, LP.cyl(0.0085, 0.0085, 0.036, 8), Vector3(0, 0, 0.018), Color(0.84, 0.54, 0.24), Vector3(PI / 2, 0, 0))
			var body_len := 0.095 * rem
			LP.add(root, LP.cyl(0.0084, 0.0084, body_len, 8), Vector3(0, 0, -body_len * 0.5), Color(0.96, 0.95, 0.92), Vector3(PI / 2, 0, 0))
			# Kül ve kızgın kor ucu
			var tip_z := -body_len
			var ash := LP.add(root, LP.cyl(0.0082, 0.0084, 0.012, 7), Vector3(0, 0, tip_z - 0.0045), Color(0.44, 0.44, 0.46), Vector3(PI / 2, 0, 0))
			ash.name = "AshRing"
			var ember := LP.add(root, LP.sphere(0.0088, 6, 4), Vector3(0, 0, tip_z - 0.0105), Color(1.0, 0.34, 0.06))
			ember.name = "Ember"
			var em := ember.material_override as StandardMaterial3D
			em.emission_enabled = true
			em.emission = Color(1.0, 0.32, 0.05)
			em.emission_energy_multiplier = 2.6
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0, tip_z - 0.015)
			root.add_child(tip)
			tip.add_child(_make_continuous_wisp(false, false))

		"puro":
			# Kalın kahverengi sarma Küba purosu + altın şerit + geniş kızgın kor ucu + yoğun sürekli duman!
			var body_len := 0.145 * rem
			LP.add(root, LP.cyl(0.0165, 0.0155, body_len, 9), Vector3(0, 0, 0.02 - body_len * 0.5), Color(0.32, 0.18, 0.09), Vector3(PI / 2, 0, 0), 0.78)
			LP.add(root, LP.cyl(0.0172, 0.0172, 0.018, 9), Vector3(0, 0, 0.005), Color(0.95, 0.78, 0.22), Vector3(PI / 2, 0, 0), 0.25, 0.85)
			var tip_z := 0.02 - body_len
			var ash := LP.add(root, LP.cyl(0.0158, 0.0165, 0.018, 8), Vector3(0, 0, tip_z - 0.007), Color(0.50, 0.49, 0.50), Vector3(PI / 2, 0, 0))
			ash.name = "AshRing"
			var ember := LP.add(root, LP.ellipsoid(0.016, 0.016, 0.012, 7, 4), Vector3(0, 0, tip_z - 0.016), Color(1.0, 0.28, 0.04))
			ember.name = "Ember"
			var em := ember.material_override as StandardMaterial3D
			em.emission_enabled = true
			em.emission = Color(1.0, 0.26, 0.04)
			em.emission_energy_multiplier = 3.2
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0, tip_z - 0.023)
			root.add_child(tip)
			tip.add_child(_make_continuous_wisp(true, false))

		"cay":
			# Klasik Türk ince belli çay bardağı + kırmızı şeritli porselen tabak + tavşan kanı çay + dönen çay kaşığı + sıcak buhar!
			var saucer := Node3D.new()
			saucer.name = "Saucer"
			root.add_child(saucer)
			LP.add(saucer, LP.cyl(0.068, 0.048, 0.012, 14), Vector3(0, 0.006, 0), Color(0.97, 0.96, 0.94), Vector3.ZERO, 0.16)
			LP.add(saucer, LP.torus(0.062, 0.069, 16, 6), Vector3(0, 0.012, 0), Color(0.78, 0.12, 0.12), Vector3.ZERO, 0.22)
			LP.add(saucer, LP.cyl(0.032, 0.034, 0.004, 12), Vector3(0, 0.013, 0), Color(0.91, 0.90, 0.88), Vector3.ZERO, 0.22)

			# İçindeki tavşan kanı çay (her yudumda seviye iner!)
			var fill := clampf(1.0 - burn_ratio * 0.88, 0.16, 1.0)
			var liq_pivot := Node3D.new()
			liq_pivot.name = "TeaLiquid"
			liq_pivot.position = Vector3(0, 0.022, 0)
			liq_pivot.scale = Vector3(1.0, fill, 1.0)
			root.add_child(liq_pivot)
			var tea_c := Color(0.56, 0.09, 0.03, 0.90)
			var l1 := LP.add(liq_pivot, LP.cyl(0.030, 0.024, 0.038, 12), Vector3(0, 0.019, 0), tea_c, Vector3.ZERO, 0.08)
			(l1.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var l2 := LP.add(liq_pivot, LP.cyl(0.024, 0.030, 0.030, 12), Vector3(0, 0.053, 0), tea_c, Vector3.ZERO, 0.08)
			(l2.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var l3 := LP.add(liq_pivot, LP.cyl(0.031, 0.024, 0.024, 12), Vector3(0, 0.080, 0), Color(0.68, 0.16, 0.04, 0.92), Vector3.ZERO, 0.05)
			(l3.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

			# İnce belli şeffaf cam bardak profili (kalın cam taban -> alt göbek -> ince bel -> açılan ağız + altın şerit)
			var glass_c := Color(0.92, 0.97, 1.0, 0.30)
			var g_base := LP.add(root, LP.cyl(0.027, 0.026, 0.014, 12), Vector3(0, 0.018, 0), Color(0.88, 0.94, 0.98, 0.48), Vector3.ZERO, 0.06)
			(g_base.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var g_parts := [
				[0.035, 0.028, 0.036, 0.042], # alt göbek
				[0.027, 0.035, 0.028, 0.074], # ince bel daralması
				[0.036, 0.027, 0.034, 0.105], # üst ağız açılması
			]
			for gp: Array in g_parts:
				var seg := LP.add(root, LP.cyl(float(gp[0]), float(gp[1]), float(gp[2]), 14), Vector3(0, float(gp[3]), 0), glass_c, Vector3.ZERO, 0.05)
				var gm := seg.material_override as StandardMaterial3D
				gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gm.metallic_specular = 0.95
			LP.add(root, LP.torus(0.034, 0.0365, 16, 6), Vector3(0, 0.122, 0), Color(0.96, 0.80, 0.32), Vector3.ZERO, 0.22, 0.85)

			# Dönen paslanmaz çay kaşığı (sağ tıkla karıştırırken Y ekseninde hızla döner!)
			var sp_piv := Node3D.new()
			sp_piv.name = "SpoonPivot"
			sp_piv.position = Vector3(0, 0.028, 0)
			root.add_child(sp_piv)
			var sp_arm := Node3D.new()
			sp_arm.position = Vector3(0.012, 0.052, 0.0)
			sp_arm.rotation_degrees = Vector3(0, 0, -18)
			sp_piv.add_child(sp_arm)
			LP.add(sp_arm, LP.cyl(0.0022, 0.0032, 0.115, 6), Vector3(0, 0.01, 0), Color(0.86, 0.89, 0.93), Vector3.ZERO, 0.15, 0.92)
			LP.add(sp_arm, LP.ellipsoid(0.0085, 0.012, 0.004, 6, 4), Vector3(0, -0.048, 0), Color(0.88, 0.91, 0.95), Vector3.ZERO, 0.14, 0.94)

			# Sıcak çay buharı kaynağı
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0.130, 0)
			root.add_child(tip)
			if burn_ratio < 0.85:
				tip.add_child(_make_continuous_wisp(false, true))

		"simit":
			# Altın kızarmış örgülü susamlı sokak simidi (12 yay parçası; her ısırıkta parça eksilir!)
			var seg_count := 12
			var keep_segs := clampi(int(round((1.0 - burn_ratio * 0.72) * float(seg_count))), 4, seg_count)
			var ring_r := 0.068
			var crust_c := Color(0.76, 0.44, 0.15)
			var crust_hi := Color(0.84, 0.52, 0.19)
			var sesame_c := Color(0.96, 0.90, 0.72)
			for i in keep_segs:
				var ang := float(i) / float(seg_count) * TAU - PI * 0.35
				var p := Vector3(cos(ang) * ring_r, sin(ang) * ring_r, 0.0)
				var rot := Vector3(0.0, 0.0, ang)
				var col := crust_c if i % 2 == 0 else crust_hi
				LP.add(root, LP.ellipsoid(0.022, 0.026, 0.019, 7, 5), p, col, rot, 0.78)
				# Örgü burgu kabartısı
				var p2 := Vector3(cos(ang + 0.14) * ring_r, sin(ang + 0.14) * ring_r, 0.003 if i % 2 == 0 else -0.003)
				LP.add(root, LP.ellipsoid(0.017, 0.021, 0.015, 6, 4), p2, crust_hi, Vector3(0.25, 0, ang + 0.35), 0.74)
				# Susam taneleri (ön & üst yüzeyde)
				for s_k in 2:
					var sa := ang + (0.08 if s_k == 0 else -0.08)
					var sr := ring_r + (0.010 if s_k == 0 else -0.008)
					var sz := 0.017 if s_k == 0 else -0.016
					LP.add(root, LP.box(Vector3(0.0055, 0.0032, 0.0025)), Vector3(cos(sa) * sr, sin(sa) * sr, sz), sesame_c, Vector3(0, 0, sa + 0.5), 0.65)
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0.075, 0)
			root.add_child(tip)

		"megafon":
			# Beyaz-kırmızı klasik pazarcı el megafonu + kabza
			LP.add(root, LP.cyl(0.038, 0.12, 0.24, 10), Vector3(0, 0.04, -0.10), Color(0.96, 0.95, 0.92), Vector3(PI / 2, 0, 0), 0.42)
			LP.add(root, LP.torus(0.105, 0.125, 12, 6), Vector3(0, 0.04, -0.22), Color(0.88, 0.18, 0.14), Vector3(PI / 2, 0, 0), 0.35)
			LP.add(root, LP.cyl(0.036, 0.036, 0.07, 8), Vector3(0, 0.04, 0.05), Color(0.88, 0.18, 0.14), Vector3(PI / 2, 0, 0), 0.45)
			LP.add(root, LP.box(Vector3(0.032, 0.11, 0.042)), Vector3(0, -0.045, 0.02), Color(0.22, 0.22, 0.24), Vector3(0.22, 0, 0))
			var bell := Node3D.new()
			bell.name = "SmokeTip"
			bell.position = Vector3(0, 0.04, -0.24)
			root.add_child(bell)

		"bicak":
			# Ahşap saplı parlak çelik Türk meyve bıçağı
			LP.add(root, LP.box(Vector3(0.024, 0.030, 0.11)), Vector3(0, 0, 0.04), Color(0.48, 0.27, 0.14), Vector3.ZERO, 0.72)
			LP.add(root, LP.cyl(0.004, 0.004, 0.028, 5), Vector3(0, 0, 0.02), Color(0.86, 0.74, 0.32), Vector3(0, 0, PI / 2), 0.3, 0.8)
			LP.add(root, LP.cyl(0.004, 0.004, 0.028, 5), Vector3(0, 0, 0.06), Color(0.86, 0.74, 0.32), Vector3(0, 0, PI / 2), 0.3, 0.8)
			# Çelik namlu + sivri uç
			LP.add(root, LP.box(Vector3(0.005, 0.026, 0.14)), Vector3(0, 0.004, -0.085), Color(0.84, 0.88, 0.92), Vector3.ZERO, 0.18, 0.92)
			LP.add(root, LP.prism(Vector3(0.026, 0.055, 0.005)), Vector3(0, 0.004, -0.182), Color(0.88, 0.92, 0.96), Vector3(-PI / 2, 0, PI / 2), 0.16, 0.94)

		"radyo":
			# Retro kasetçalar / transistörlü Arabesk radyo (çift hoparlör + parlayan frekans kadranı + krom anten)
			LP.add(root, LP.box(Vector3(0.32, 0.18, 0.11)), Vector3(0, 0.09, 0), Color(0.18, 0.17, 0.19), Vector3.ZERO, 0.55)
			LP.add(root, LP.box(Vector3(0.30, 0.032, 0.015)), Vector3(0, 0.145, -0.055), Color(0.95, 0.78, 0.32), Vector3.ZERO, 0.25)
			var dial := LP.add(root, LP.box(Vector3(0.28, 0.024, 0.016)), Vector3(0, 0.145, 0.056), Color(1.0, 0.82, 0.35))
			dial.name = "Dial"
			var dm := dial.material_override as StandardMaterial3D
			dm.emission_enabled = true
			dm.emission = Color(1.0, 0.72, 0.22)
			dm.emission_energy_multiplier = 1.4
			for sx: float in [-0.095, 0.095]:
				LP.add(root, LP.cyl(0.052, 0.052, 0.014, 10), Vector3(sx, 0.072, 0.056), Color(0.28, 0.28, 0.32), Vector3(PI / 2, 0, 0), 0.4, 0.6)
				LP.add(root, LP.cyl(0.052, 0.052, 0.014, 10), Vector3(sx, 0.072, -0.056), Color(0.28, 0.28, 0.32), Vector3(PI / 2, 0, 0), 0.4, 0.6)
			# Kaset kapağı + tutma sapı + krom anten
			LP.add(root, LP.box(Vector3(0.085, 0.065, 0.018)), Vector3(0, 0.072, 0.056), Color(0.12, 0.12, 0.14))
			LP.add(root, LP.box(Vector3(0.24, 0.018, 0.02)), Vector3(0, 0.215, 0), Color(0.75, 0.76, 0.8), Vector3.ZERO, 0.25, 0.85)
			LP.add(root, LP.cyl(0.004, 0.006, 0.26, 6), Vector3(0.13, 0.29, -0.02), Color(0.84, 0.86, 0.9), Vector3(0, 0, -0.28), 0.2, 0.9)

		"spray":
			# Yarı saydam mavi plastik fısfıs şişesi + içinde su + beyaz tetikli başlık ve uzun nozul
			var bottle := LP.add(root, LP.cyl(0.036, 0.04, 0.15, 9), Vector3(0, 0.0, 0), Color(0.55, 0.82, 1.0, 0.55), Vector3.ZERO, 0.12)
			var bm := bottle.material_override as StandardMaterial3D
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bm.metallic_specular = 0.9
			LP.add(root, LP.cyl(0.031, 0.035, 0.1, 9), Vector3(0, -0.02, 0), Color(0.3, 0.62, 0.98), Vector3.ZERO, 0.1)
			LP.add(root, LP.cyl(0.026, 0.036, 0.03, 9), Vector3(0, 0.088, 0), Color(0.96, 0.96, 0.98), Vector3.ZERO, 0.4)
			LP.add(root, LP.box(Vector3(0.05, 0.05, 0.07)), Vector3(0, 0.124, -0.012), Color(0.96, 0.96, 0.98), Vector3.ZERO, 0.4)
			LP.add(root, LP.cyl(0.008, 0.01, 0.05, 6), Vector3(0, 0.134, -0.065), Color(0.2, 0.62, 0.95), Vector3(PI / 2, 0, 0), 0.35)
			var trig := LP.add(root, LP.box(Vector3(0.016, 0.05, 0.016)), Vector3(0, 0.096, -0.046), Color(0.2, 0.62, 0.95), Vector3(-0.35, 0, 0), 0.4)
			trig.name = "Trigger"
			var nozzle := Node3D.new()
			nozzle.name = "SmokeTip" # duman ucu ile aynı adı paylaşır: buğu buradan çıkar
			nozzle.position = Vector3(0, 0.134, -0.095)
			root.add_child(nozzle)

	return root
