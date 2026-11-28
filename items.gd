extends RefCounted
## Pazarcı kişisel envanter eşyaları (P mağazasından veya gezici çaycı/simitçiden alınır; meyve kasaları ASLA envantere girmez).
## Sigara, Küba Purosu, İnce Belli Çay, Susamlı Simit, El Megafonu, Meyve Bıçağı, Arabesk Radyo ve Su Fısfısı.

const LP := preload("res://lowpoly.gd")
const VFX := preload("res://vfx.gd")
const BEER_MODEL := preload("res://models/pazar_pilsen.glb")
const TEA_MODEL := preload("res://models/turkish_tea.glb")
const CIG_MODEL := preload("res://models/cigarette.glb")
const CIGAR_MODEL := preload("res://models/cuban_cigar.glb")
const SIMIT_MODEL := preload("res://models/simit.glb")
const ACMA_MODEL := preload("res://models/acma.glb")
const MEGA_MODEL := preload("res://models/megaphone.glb")
const RADIO_MODEL := preload("res://models/arabesk_radio.glb")
const SPRAY_MODEL := preload("res://models/spray_bottle.glb")
const KNIFE_MODEL := preload("res://models/fruit_knife.glb")
const BAT_MODEL := preload("res://models/baseball_bat.glb")

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
		"desc": "5 dal sigara. Sol tıkla çekip üfle (+12sn Keyif; rakip tezgaha üflersen -%10 çürütür, Zabıta gelir!), sağ tıkla kül silk.",
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
		"desc": "Altın bantlı 3 puro. Prestij (+%18 müşteri ilgisi) verir; rakip tezgaha duman üflersen -%10 çürütür (Zabıta gelir!).",
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
		"right_hint": "Kuşa / kediye at",
		"desc": "Fırından taze çıtır simit (3 ısırık). Sol tıkla ısır (+18sn +%15 hız), sağ tıkla kuşlara ve kediye parça at!",
	},
	"acma": {
		"name": "Açma",
		"short": "Açma",
		"icon": "🥯",
		"cost": 12,
		"uses": 1, # 1 açma (3 ısırık)
		"puffs_per_use": 3,
		"consumable": true,
		"left_hint": "Isır (+18sn Hız)",
		"right_hint": "Kuşa / kediye at",
		"desc": "Fırından yumuşacık, yağlı açma (3 ısırık). Sol tıkla ısır, sağ tıkla kuşlara ve kediye parça at!",
	},
	"bira": {
		"name": "Pazar Pilsen",
		"short": "Bira",
		"icon": "🍺",
		"cost": 20,
		"uses": 1, # 1 şişe (2 yudum)
		"puffs_per_use": 2,
		"consumable": true,
		"left_hint": "Yudumla (cesaret!)",
		"right_hint": "Fırlat  •  [Q] Fırlat",
		"desc": "Tombul kehribar şişe, 50 cl. Sol tıkla iç, sağ tık/[Q] ile fırlat: rakibi düşürüp kokutur, tezgahını 4x hızlı çürütür (Zabıta gelir!).",
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
		"right_hint": "Sonraki Şarkı  •  [Tekerlek] Şarkı Seç",
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
	"sopa": {
		"name": "Beyzbol Sopası",
		"short": "Sopa",
		"icon": "🏏",
		"cost": 60,
		"uses": 1,
		"puffs_per_use": 1,
		"consumable": false,
		"left_hint": "Salla (vurulan bayılır)",
		"right_hint": "[Q] Fırlat",
		"desc": "Sol tıkla salla (1.8 m menzil), [Q] ile fırlat. Vurduğun pazarcı 2 sn bayılıp yere yığılır!",
	},
}

const ORDER := ["sigara", "puro", "bira", "cay", "simit", "acma", "megafon", "bicak", "radyo", "spray", "sopa"]


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
## ash_ratio (0..1): sigara külünün uzama oranı (sağ tıkla silkince sıfırlanır).
static func build_item_model(item_id: String, burn_ratio := 0.0, ash_ratio := 0.22) -> Node3D:
	var root := Node3D.new()
	root.name = "Item_" + item_id
	var rem := clampf(1.0 - burn_ratio, 0.22, 1.0) # kalan uzunluk/doluluk oranı

	match item_id:
		"sigara":
			# Blender'da modellenen mantar filtreli, çizgili kağıtlı, uzayan katmanlı küllü gerçekçi sigara!
			var c_inst := CIG_MODEL.instantiate()
			c_inst.name = "CigaretteMesh"
			root.add_child(c_inst)
			var pap := c_inst.find_child("CigPaper", true, false) as Node3D
			if pap:
				pap.scale.z = rem
			var tip_grp := c_inst.find_child("CigTipGroup", true, false) as Node3D
			if tip_grp:
				tip_grp.position.z = -0.088 * rem
				var ash_b := tip_grp.find_child("AshBody", true, false) as Node3D
				if ash_b:
					ash_b.scale.z = lerpf(0.28, 2.15, clampf(ash_ratio, 0.0, 1.0))
				var emb := tip_grp.find_child("Ember", true, false) as MeshInstance3D
				if emb and emb.mesh and emb.mesh.get_surface_count() > 0:
					var base_m := emb.mesh.surface_get_material(0)
					if base_m is StandardMaterial3D:
						var em := (base_m as StandardMaterial3D).duplicate() as StandardMaterial3D
						em.emission_enabled = true
						em.emission_energy_multiplier = 2.6
						emb.material_override = em
				var tip := Node3D.new()
				tip.name = "SmokeTip"
				tip.position = Vector3(0, 0, -0.004)
				tip_grp.add_child(tip)
				tip.add_child(_make_continuous_wisp(false, false))
			else:
				var tip_fb := Node3D.new()
				tip_fb.name = "SmokeTip"
				tip_fb.position = Vector3(0, 0, -0.088 * rem)
				root.add_child(tip_fb)
				tip_fb.add_child(_make_continuous_wisp(false, false))

		"puro":
			# Blender'da modellenen Maduro sarma yapraklı, kırmızı-altın bantlı Küba purosu + uzayan kül + kızgın kor!
			var p_inst := CIGAR_MODEL.instantiate()
			p_inst.name = "CubanCigarMesh"
			root.add_child(p_inst)
			var ppap := p_inst.find_child("CigPaper", true, false) as Node3D
			if ppap:
				ppap.scale.z = rem
			var ptip_grp := p_inst.find_child("CigTipGroup", true, false) as Node3D
			if ptip_grp:
				ptip_grp.set_meta("burn_len", 0.118)
				ptip_grp.position.z = -0.118 * rem
				var pash_b := ptip_grp.find_child("AshBody", true, false) as Node3D
				if pash_b:
					pash_b.scale.z = lerpf(0.30, 2.0, clampf(ash_ratio, 0.0, 1.0))
				var pemb := ptip_grp.find_child("Ember", true, false) as MeshInstance3D
				if pemb and pemb.mesh and pemb.mesh.get_surface_count() > 0:
					var base_pm := pemb.mesh.surface_get_material(0)
					var pem := (base_pm.duplicate() as StandardMaterial3D) if (base_pm is StandardMaterial3D) else StandardMaterial3D.new()
					pem.emission_enabled = true
					pem.emission = Color(1.0, 0.28, 0.04)
					pem.emission_energy_multiplier = 3.2
					pemb.material_override = pem
				var tip := Node3D.new()
				tip.name = "SmokeTip"
				tip.position = Vector3(0, 0, -0.008)
				ptip_grp.add_child(tip)
				tip.add_child(_make_continuous_wisp(true, false))
			else:
				var tip_fb2 := Node3D.new()
				tip_fb2.name = "SmokeTip"
				tip_fb2.position = Vector3(0, 0, -0.118 * rem)
				root.add_child(tip_fb2)
				tip_fb2.add_child(_make_continuous_wisp(true, false))

		"cay":
			# Blender'da modellenen ince belli cam bardak, desenli porselen tabak, 2 küp şeker, dönen kaşık + tavşan kanı çay!
			var t_inst := TEA_MODEL.instantiate()
			t_inst.name = "TurkishTeaMesh"
			root.add_child(t_inst)
			var fill := clampf(1.0 - burn_ratio * 0.88, 0.14, 1.0)
			var liq := t_inst.find_child("TeaLiquid", true, false) as MeshInstance3D
			if liq:
				liq.scale.y = fill
				# Godot Forward+ şeffaflık sıralaması: iç çay opak yakut kırmızı, dış cam yarı saydam olmalı!
				var lm := StandardMaterial3D.new()
				lm.albedo_color = Color(0.56, 0.055, 0.012)
				lm.roughness = 0.08
				lm.metallic_specular = 0.85
				lm.emission_enabled = true
				lm.emission = Color(0.45, 0.04, 0.008)
				lm.emission_energy_multiplier = 0.35
				liq.material_override = lm
			var glass_m := t_inst.find_child("TeaGlass", true, false) as MeshInstance3D
			if glass_m:
				var gm := StandardMaterial3D.new()
				gm.albedo_color = Color(0.95, 0.98, 1.0, 0.22)
				gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gm.roughness = 0.05
				gm.metallic_specular = 1.0
				glass_m.material_override = gm
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0.112, 0)
			root.add_child(tip)
			if burn_ratio < 0.85:
				tip.add_child(_make_continuous_wisp(false, true))

		"simit":
			# Blender'da modellenen pekmez kabuklu, bol susamlı çift burgu sokak simidi (10 parça; ısırıldıkça eksilir!)
			var s_inst := SIMIT_MODEL.instantiate()
			s_inst.name = "SimitMesh"
			root.add_child(s_inst)
			var keep_segs := clampi(int(round((1.0 - burn_ratio * 0.72) * 10.0)), 3, 10)
			for i in 10:
				var seg := s_inst.find_child("SimitSeg_%d" % i, true, false) as Node3D
				if seg:
					seg.visible = i < keep_segs
			var tip := Node3D.new()
			tip.name = "SmokeTip"
			tip.position = Vector3(0, 0.075, 0)
			root.add_child(tip)

		"acma":
			# Blender'da modellenen yumurta sarılı parlak, puf pastane açması + çörek otu (8 parça; ısırıldıkça eksilir!)
			var a_inst := ACMA_MODEL.instantiate()
			a_inst.name = "AcmaMesh"
			root.add_child(a_inst)
			var keep_n := clampi(int(round((1.0 - burn_ratio * 0.72) * 8.0)), 3, 8)
			for i in 8:
				var aseg := a_inst.find_child("AcmaSeg_%d" % i, true, false) as Node3D
				if aseg:
					aseg.visible = i < keep_n
			var tip_a := Node3D.new()
			tip_a.name = "SmokeTip"
			tip_a.position = Vector3(0, 0.07, 0)
			root.add_child(tip_a)

		"bira":
			# Blender'da modellenen telifsiz 50 cl Pazar Pilsen tombul kehribar şişe!
			var b_inst := BEER_MODEL.instantiate()
			b_inst.name = "PazarPilsenMesh"
			b_inst.rotation_degrees = Vector3(0.0, -14.0, 0.0) # etiket 1. şahısta oyuncuya dönük
			root.add_child(b_inst)
			# İlk yudumdan sonra kapağı açılmış ve sıvı seviyesi inmiş görünür
			if burn_ratio > 0.05:
				var cap := b_inst.find_child("CrownCap", true, false) as Node3D
				if cap:
					cap.visible = false
				var liq := b_inst.find_child("PilsnerLiquid", true, false) as Node3D
				if liq:
					liq.scale.y = clampf(1.0 - burn_ratio * 0.72, 0.28, 1.0)
				var foam := b_inst.find_child("BeerFoam", true, false) as Node3D
				if foam:
					foam.visible = false
			var tip_b := Node3D.new()
			tip_b.name = "SmokeTip"
			tip_b.position = Vector3(0, 0.21, 0)
			root.add_child(tip_b)

		"megafon":
			# Blender'da modellenen kırmızı-beyaz pazarcı el megafonu (huni + akustik koni + kabza + tetik)!
			var m_inst := MEGA_MODEL.instantiate()
			m_inst.name = "MegaphoneMesh"
			root.add_child(m_inst)
			var bell := Node3D.new()
			bell.name = "SmokeTip"
			bell.position = Vector3(0, 0.04, -0.24)
			root.add_child(bell)

		"bicak":
			# Blender'da modellenen ceviz saplı, pirinç balçaklı, keskin bileyli çelik pazarcı meyve bıçağı
			var k_inst := KNIFE_MODEL.instantiate()
			k_inst.name = "FruitKnifeMesh"
			root.add_child(k_inst)

		"radyo":
			# Blender'da modellenen 80'ler retro Arabesk kasetçalar boombox (çift hoparlör, kaset yuvası, ışıklı FM kadranı, teleskopik anten)!
			var r_inst := RADIO_MODEL.instantiate()
			r_inst.name = "ArabeskRadioMesh"
			root.add_child(r_inst)
			var dial := r_inst.find_child("Dial", true, false) as MeshInstance3D
			if dial and dial.mesh and dial.mesh.get_surface_count() > 0:
				var base_dm := dial.mesh.surface_get_material(0)
				var dm := (base_dm.duplicate() as StandardMaterial3D) if (base_dm is StandardMaterial3D) else StandardMaterial3D.new()
				dm.emission_enabled = true
				dm.emission = Color(1.0, 0.72, 0.22)
				dm.emission_energy_multiplier = 1.4
				dial.material_override = dm

		"sopa":
			# Blender'da modellenen torna dişbudak ahşap, deri sargı saplı ve çukur uçlu beyzbol sopası
			var bat_inst := BAT_MODEL.instantiate()
			bat_inst.name = "BaseballBatMesh"
			root.add_child(bat_inst)

		"spray":
			# Blender'da modellenen ince belli yarı saydam mavi Su Fısfısı + iç su + hareketli tetik + nozul!
			var sp_inst := SPRAY_MODEL.instantiate()
			sp_inst.name = "SprayBottleMesh"
			root.add_child(sp_inst)
			var sb_m := sp_inst.find_child("SprayBody", true, false) as MeshInstance3D
			if sb_m:
				var pm := StandardMaterial3D.new()
				pm.albedo_color = Color(0.68, 0.88, 1.0, 0.28)
				pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				pm.roughness = 0.06
				pm.metallic_specular = 1.0
				sb_m.material_override = pm
			var sw_m := sp_inst.find_child("SprayWater", true, false) as MeshInstance3D
			if sw_m:
				var wm := StandardMaterial3D.new()
				wm.albedo_color = Color(0.10, 0.54, 0.96)
				wm.roughness = 0.07
				wm.metallic_specular = 0.9
				wm.emission_enabled = true
				wm.emission = Color(0.08, 0.42, 0.85)
				wm.emission_energy_multiplier = 0.18
				sw_m.material_override = wm
			var nozzle := Node3D.new()
			nozzle.name = "SmokeTip" # duman ucu ile aynı adı paylaşır: buğu buradan çıkar
			nozzle.position = Vector3(0, 0.132, -0.098)
			root.add_child(nozzle)

	return root
