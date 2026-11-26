extends RefCounted
## Pazarcı kişisel envanter eşyaları (P mağazasından alınır; meyve kasaları ASLA envantere girmez).
## Sigara, Küba Purosu, El Megafonu, Meyve Bıçağı ve Arabesk Radyo için 3D model ve tanımlar.

const LP := preload("res://lowpoly.gd")

const CATALOG := {
	"sigara": {
		"name": "Sigara Paketi",
		"short": "Sigara",
		"icon": "🚬",
		"cost": 15,
		"uses": 5, # 5 dal
		"puffs_per_use": 5,
		"consumable": true,
		"desc": "5 dal sigara. Sol tıkla nefes çek: ucu korlanır, yanıp kısalır ve duman çıkarır!",
	},
	"puro": {
		"name": "Küba Purosu",
		"short": "Puro",
		"icon": "🪵",
		"cost": 45,
		"uses": 3, # 3 puro
		"puffs_per_use": 8,
		"consumable": true,
		"desc": "Kalın altın bantlı 3 puro. Yoğun duman + Ağır Abi prestiji (+%18 müşteri ilgisi)!",
	},
	"megafon": {
		"name": "El Megafonu",
		"short": "Megafon",
		"icon": "📢",
		"cost": 75,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"desc": "Eldeyken bağırma dB'ini fırlatır (+12 dB / 1.85x), uzak müşterileri anında çeker!",
	},
	"bicak": {
		"name": "Meyve Bıçağı",
		"short": "Bıçak",
		"icon": "🔪",
		"cost": 60,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"desc": "Sol tıkla rakip pazarcıya saldır! Dikkat: Zabıta anında koşup -50 TL keser ve el koyar!",
	},
	"radyo": {
		"name": "Arabesk Radyo",
		"short": "Radyo",
		"icon": "📻",
		"cost": 90,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"desc": "Sol tıkla Hicaz Arabesk müzik aç/kapat; tezgahına koyup tüm sokağı inletebilirsin!",
	},
}

const ORDER := ["sigara", "puro", "megafon", "bicak", "radyo"]


## Birinci veya üçüncü şahıs için detaylı 3D eşya modeli üretir.
## Sigara ve puroda "Tip" ve "Ember" düğümleri dinamik yanma/kısalma animasyonu için adlandırılır.
static func build_item_model(item_id: String, burn_ratio := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Item_" + item_id
	var rem := clampf(1.0 - burn_ratio, 0.22, 1.0) # kalan uzunluk oranı

	match item_id:
		"sigara":
			# Turuncu filtre + beyaz kağıt gövde (yandıkça kısalır) + kül halkası + yanan kor uç!
			LP.add(root, LP.cyl(0.0085, 0.0085, 0.036, 8), Vector3(0, 0, 0.018), Color(0.84, 0.54, 0.24), Vector3(PI / 2, 0, 0))
			var body_len := 0.095 * rem
			LP.add(root, LP.cyl(0.0084, 0.0084, body_len, 8), Vector3(0, 0, -body_len * 0.5), Color(0.96, 0.95, 0.92), Vector3(PI / 2, 0, 0))
			# Kül ve kızgın kor ucu
			var tip_z := -body_len
			LP.add(root, LP.cyl(0.0082, 0.0084, 0.011, 7), Vector3(0, 0, tip_z - 0.004), Color(0.42, 0.42, 0.44), Vector3(PI / 2, 0, 0))
			var ember := LP.add(root, LP.sphere(0.0088, 6, 4), Vector3(0, 0, tip_z - 0.010), Color(1.0, 0.34, 0.06))
			ember.name = "Ember"
			var em := ember.material_override as StandardMaterial3D
			em.emission_enabled = true
			em.emission = Color(1.0, 0.32, 0.05)
			em.emission_energy_multiplier = 2.6
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0, tip_z - 0.014)
			root.add_child(tip)

		"puro":
			# Kalın kahverengi sarma Küba purosu + altın şerit + geniş kızgın kor ucu!
			var body_len := 0.145 * rem
			LP.add(root, LP.cyl(0.0165, 0.0155, body_len, 9), Vector3(0, 0, 0.02 - body_len * 0.5), Color(0.32, 0.18, 0.09), Vector3(PI / 2, 0, 0), 0.78)
			LP.add(root, LP.cyl(0.0172, 0.0172, 0.018, 9), Vector3(0, 0, 0.005), Color(0.95, 0.78, 0.22), Vector3(PI / 2, 0, 0), 0.25, 0.85)
			var tip_z := 0.02 - body_len
			LP.add(root, LP.cyl(0.0158, 0.0165, 0.016, 8), Vector3(0, 0, tip_z - 0.006), Color(0.48, 0.47, 0.48), Vector3(PI / 2, 0, 0))
			var ember := LP.add(root, LP.ellipsoid(0.016, 0.016, 0.012, 7, 4), Vector3(0, 0, tip_z - 0.015), Color(1.0, 0.28, 0.04))
			ember.name = "Ember"
			var em := ember.material_override as StandardMaterial3D
			em.emission_enabled = true
			em.emission = Color(1.0, 0.26, 0.04)
			em.emission_energy_multiplier = 3.2
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0, tip_z - 0.022)
			root.add_child(tip)

		"megafon":
			# Beyaz-kırmızı klasik pazarcı el megafonu + kabza
			LP.add(root, LP.cyl(0.038, 0.12, 0.24, 10), Vector3(0, 0.04, -0.10), Color(0.96, 0.95, 0.92), Vector3(PI / 2, 0, 0), 0.42)
			LP.add(root, LP.torus(0.105, 0.125, 12, 6), Vector3(0, 0.04, -0.22), Color(0.88, 0.18, 0.14), Vector3(PI / 2, 0, 0), 0.35)
			LP.add(root, LP.cyl(0.036, 0.036, 0.07, 8), Vector3(0, 0.04, 0.05), Color(0.88, 0.18, 0.14), Vector3(PI / 2, 0, 0), 0.45)
			LP.add(root, LP.box(Vector3(0.032, 0.11, 0.042)), Vector3(0, -0.045, 0.02), Color(0.22, 0.22, 0.24), Vector3(0.22, 0, 0))

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
			var dm := dial.material_override as StandardMaterial3D
			dm.emission_enabled = true
			dm.emission = Color(1.0, 0.72, 0.22)
			dm.emission_energy_multiplier = 1.4
			for sx in [-0.095, 0.095]:
				LP.add(root, LP.cyl(0.052, 0.052, 0.014, 10), Vector3(sx, 0.072, 0.056), Color(0.28, 0.28, 0.32), Vector3(PI / 2, 0, 0), 0.4, 0.6)
				LP.add(root, LP.cyl(0.052, 0.052, 0.014, 10), Vector3(sx, 0.072, -0.056), Color(0.28, 0.28, 0.32), Vector3(PI / 2, 0, 0), 0.4, 0.6)
			# Kaset kapağı + tutma sapı + krom anten
			LP.add(root, LP.box(Vector3(0.085, 0.065, 0.018)), Vector3(0, 0.072, 0.056), Color(0.12, 0.12, 0.14))
			LP.add(root, LP.box(Vector3(0.24, 0.018, 0.02)), Vector3(0, 0.215, 0), Color(0.75, 0.76, 0.8), Vector3.ZERO, 0.25, 0.85)
			LP.add(root, LP.cyl(0.004, 0.006, 0.26, 6), Vector3(0.13, 0.29, -0.02), Color(0.84, 0.86, 0.9), Vector3(0, 0, -0.28), 0.2, 0.9)

	return root
