extends Node3D
## Gerçekçi Türk Semt Pazarı: fıskiye kaldırıldı; dokulu asfalt cadde, kaldırım bordürleri,
## demir boru iskele üstü mavi/yeşil/çizgili pazar brandaları, sallanan ampuller, plastik hal kasaları,
## Türk mahalle apartmanları, Kuzey/Güney Giriş-Çıkış kapıları ve dinamik gün döngüsü.

const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")

const HALF_X := 14.5
const HALF_Z := 21.5
# Ana asfalt caddenin iki yanında 8 oyuncu tezgahı (ortadaki meydan Ford Transit Toptancı için açık!)
const PLAYER_STALL_SPOTS := [
	[Vector3(-6.3, 0, -7.8), PI / 2],
	[Vector3(6.3, 0, -7.8), -PI / 2],
	[Vector3(-6.3, 0, 7.8), PI / 2],
	[Vector3(6.3, 0, 7.8), -PI / 2],
	[Vector3(-6.3, 0, -14.2), PI / 2],
	[Vector3(6.3, 0, -14.2), -PI / 2],
	[Vector3(-6.3, 0, 14.2), PI / 2],
	[Vector3(6.3, 0, 14.2), -PI / 2],
]
const TARP_COLORS := [
	Color(0.14, 0.44, 0.78), # klasik mavi pazar brandası
	Color(0.16, 0.50, 0.30), # koyu pazar yeşili branda
	Color(0.92, 0.89, 0.82), # güneş görmüş beyaz branda
	Color(0.86, 0.36, 0.16), # turuncu-kırmızı çizgili branda
	Color(0.18, 0.56, 0.74), # açık turkuaz branda
]
const PLASTIC_CRATES := [
	Color(0.10, 0.45, 0.88), Color(0.88, 0.18, 0.16),
	Color(0.94, 0.76, 0.12), Color(0.16, 0.62, 0.26),
]
const WOOD := Color(0.54, 0.36, 0.21)
const STEEL := Color(0.52, 0.54, 0.57)
const TERRACOTTA := Color(0.76, 0.38, 0.24)

var interactive := false
var rng := RandomNumberGenerator.new()

var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _env: Environment
var _street_lights: Array[OmniLight3D] = []
var _bulb_mats: Array[StandardMaterial3D] = []
var _clouds: Array = []
var _cloud_mats: Array[StandardMaterial3D] = []
var _hanging_sways: Array[Node3D] = []
var _day_progress := 0.38
var _anim_t := 0.0


func _ready() -> void:
	rng.seed = 1453
	_env_setup()
	_build_street_and_sidewalks()
	_build_overhead_tarps_and_lights()
	_build_gates()
	if not interactive:
		for spot in PLAYER_STALL_SPOTS:
			_decor_stall(spot[0], spot[1])
	# Orta yanlarda mahalle tezgahları (tekstil / kuruyemiş / züccaciye havası)
	for sx in [-10.8, 10.8]:
		_decor_stall(Vector3(sx, 0, 0.0), PI / 2 if sx < 0 else -PI / 2)
	_build_mahalle_apartments()
	_build_market_clutter_and_trees()
	_build_clouds()
	_build_boundaries()
	set_day_progress(_day_progress)


func _process(dt: float) -> void:
	_anim_t += dt
	for c in _clouds:
		var n: Node3D = c[0]
		n.position.x += float(c[1]) * dt
		if n.position.x > 66.0:
			n.position.x = -66.0
		n.position.y = float(c[2]) + sin(_anim_t * 0.32 + float(c[3])) * 0.22
	for i in _hanging_sways.size():
		_hanging_sways[i].rotation.x = sin(_anim_t * 1.7 + float(i) * 0.85) * 0.045
	var night_k := clampf((_day_progress - 0.60) / 0.28, 0.0, 1.0)
	if night_k > 0.02:
		for i in _street_lights.size():
			var fl := 1.0 + sin(_anim_t * 7.0 + float(i) * 1.9) * 0.06
			_street_lights[i].light_energy = lerpf(0.25, 2.05, night_k) * fl


func set_day_progress(p: float) -> void:
	_day_progress = clampf(p, 0.0, 1.0)
	if _sun == null or _sky_mat == null or _env == null:
		return
	var sun_elev := sin(clampf(_day_progress, 0.0, 0.96) * PI / 0.96)
	_sun.rotation_degrees = Vector3(lerpf(-11.0, -68.0, sun_elev), lerpf(-112.0, 62.0, _day_progress), 0.0)

	var sky_top: Color; var sky_hor: Color; var sun_col: Color; var fog_col: Color; var cloud_col: Color
	var sun_e: float; var amb_e: float
	if _day_progress < 0.38:
		var k := _day_progress / 0.38
		sky_top = Color(0.22, 0.48, 0.88).lerp(Color(0.14, 0.44, 0.90), k)
		sky_hor = Color(0.96, 0.80, 0.66).lerp(Color(0.74, 0.86, 0.97), k)
		sun_col = Color(1.0, 0.86, 0.66).lerp(Color(1.0, 0.97, 0.88), k)
		fog_col = Color(0.94, 0.83, 0.70).lerp(Color(0.86, 0.88, 0.86), k)
		cloud_col = Color(1.0, 0.94, 0.88).lerp(Color(0.99, 0.99, 1.0), k)
		sun_e = lerpf(1.08, 1.42, k)
		amb_e = lerpf(0.82, 0.96, k)
	elif _day_progress < 0.78:
		var k := (_day_progress - 0.38) / 0.40
		sky_top = Color(0.14, 0.44, 0.90).lerp(Color(0.24, 0.24, 0.54), k)
		sky_hor = Color(0.74, 0.86, 0.97).lerp(Color(0.98, 0.54, 0.28), k)
		sun_col = Color(1.0, 0.97, 0.88).lerp(Color(1.0, 0.60, 0.28), k)
		fog_col = Color(0.86, 0.88, 0.86).lerp(Color(0.92, 0.60, 0.40), k)
		cloud_col = Color(0.99, 0.99, 1.0).lerp(Color(1.0, 0.70, 0.48), k)
		sun_e = lerpf(1.42, 1.05, k)
		amb_e = lerpf(0.96, 0.72, k)
	else:
		var k := (_day_progress - 0.78) / 0.22
		sky_top = Color(0.24, 0.24, 0.54).lerp(Color(0.05, 0.08, 0.20), k)
		sky_hor = Color(0.98, 0.54, 0.28).lerp(Color(0.26, 0.22, 0.36), k)
		sun_col = Color(1.0, 0.60, 0.28).lerp(Color(0.55, 0.64, 0.92), k)
		fog_col = Color(0.92, 0.60, 0.40).lerp(Color(0.16, 0.16, 0.26), k)
		cloud_col = Color(1.0, 0.70, 0.48).lerp(Color(0.32, 0.30, 0.46), k)
		sun_e = lerpf(1.05, 0.38, k)
		amb_e = lerpf(0.72, 0.48, k)

	_sky_mat.sky_top_color = sky_top
	_sky_mat.sky_horizon_color = sky_hor
	_sky_mat.ground_horizon_color = fog_col
	_sun.light_color = sun_col
	_sun.light_energy = sun_e
	_env.ambient_light_energy = amb_e
	_env.fog_light_color = fog_col
	_env.fog_density = lerpf(0.0014, 0.0034, clampf((_day_progress - 0.55) / 0.45, 0.0, 1.0))
	for cm in _cloud_mats:
		cm.albedo_color = cloud_col
	var night_k := clampf((_day_progress - 0.58) / 0.28, 0.0, 1.0)
	for bm in _bulb_mats:
		bm.emission_energy_multiplier = lerpf(0.35, 3.6, night_k)
	for sl in _street_lights:
		sl.light_energy = lerpf(0.25, 2.05, night_k)


func _env_setup() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.16, 0.45, 0.90)
	_sky_mat.sky_horizon_color = Color(0.76, 0.85, 0.95)
	_sky_mat.ground_horizon_color = Color(0.84, 0.78, 0.70)
	_sky_mat.ground_bottom_color = Color(0.32, 0.30, 0.28)
	_sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.94
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.05
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.14
	_env.adjustment_contrast = 1.05
	_env.glow_enabled = true
	_env.glow_intensity = 0.40
	_env.glow_bloom = 0.14
	_env.glow_hdr_threshold = 1.06
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.92, 0.86, 0.78)
	_env.fog_density = 0.0014
	_env.fog_sky_affect = 0.08
	_env.ssao_enabled = true
	_env.ssao_radius = 1.15
	_env.ssao_intensity = 1.55
	_env.ssao_light_affect = 0.35

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -35, 0)
	_sun.light_color = Color(1.0, 0.95, 0.84)
	_sun.light_energy = 1.35
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 72.0
	_sun.shadow_bias = 0.04
	add_child(_sun)


## Türk semt pazarı zemini: dokulu şehir asfaltı, solmuş şerit çizgileri, beyaz-gri kaldırım bordürleri ve beton pazar alanı.
func _build_street_and_sidewalks() -> void:
	var asphalt_mat := LP.mat_tex(Color(0.86, 0.86, 0.88), LP.tex_asphalt(), 0.94, Vector3(26.0, 26.0, 1.0))
	var concrete_mat := LP.mat_tex(Color(0.94, 0.91, 0.86), LP.tex_concrete(), 0.92, Vector3(14.0, 22.0, 1.0))

	# Geniş asfalt zemin + çarpıştırıcı
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90.0, 96.0)
	road.mesh = pm
	road.material_override = asphalt_mat
	add_child(road)
	LP.solid(self, Vector3(0, -0.5, 0), Vector3(90.0, 1.0, 96.0))

	# Sol ve sağ beton pazar kaldırımı / tezgah alanı
	for sx in [-9.6, 9.6]:
		LP.add_mat(self, LP.box(Vector3(10.8, 0.04, 48.0)), Vector3(sx, 0.02, 0.0), concrete_mat)

	# Beyaz-gri boyalı belediye kaldırım bordür taşları (x = ±4.2)
	for sx in [-4.2, 4.2]:
		for i in range(-19, 20):
			var c := Color(0.88, 0.87, 0.84) if (i % 2 == 0) else Color(0.46, 0.47, 0.49)
			LP.add(self, LP.box(Vector3(0.24, 0.09, 1.02)), Vector3(sx, 0.045, float(i) * 1.08), c, Vector3.ZERO, 0.9)

	# Asfaltta solmuş beyaz yol şerit çizgileri + kenar şeritleri
	var stripe_col := Color(0.76, 0.75, 0.72)
	for z in range(-22, 23, 4):
		LP.add(self, LP.box(Vector3(0.16, 0.012, 1.8)), Vector3(0.0, 0.008, float(z)), stripe_col, Vector3.ZERO, 0.96)
	for sx in [-3.85, 3.85]:
		LP.add(self, LP.box(Vector3(0.12, 0.012, 46.0)), Vector3(sx, 0.008, 0.0), stripe_col.darkened(0.08), Vector3.ZERO, 0.96)

	# Rögar kapağı & yerde minik taze pazar detayı (düşmüş birkaç yeşil yaprak)
	LP.add(self, LP.cyl(0.42, 0.42, 0.02, 10), Vector3(1.6, 0.012, -3.5), Color(0.25, 0.26, 0.28), Vector3.ZERO, 0.6, 0.55)
	LP.add(self, LP.cyl(0.42, 0.42, 0.02, 10), Vector3(-1.8, 0.012, 5.2), Color(0.25, 0.26, 0.28), Vector3.ZERO, 0.6, 0.55)
	for i in 18:
		var lx := rng.randf_range(-4.0, 4.0)
		var lz := rng.randf_range(-17.0, 17.0)
		LP.add(self, LP.box(Vector3(0.12, 0.01, 0.06)), Vector3(lx, 0.01, lz),
			Color(0.28, 0.58, 0.22) if i % 2 == 0 else Color(0.84, 0.62, 0.26), Vector3(0, rng.randf() * TAU, 0))


## İkonik Türk semt pazarı üstü: demir boru iskeleler, mavi/yeşil/çizgili eğik naylon brandalar ve sallanan pazarcı ampulleri!
func _build_overhead_tarps_and_lights() -> void:
	var tarp_tex := LP.tex_tarp()
	var pipe_mat := LP.mat(STEEL, 0.42, 0.72)

	# Demir boru pazar iskelesi direkleri (cadde kenarları ve tezgah arkası)
	var z_posts: Array[float] = [-17.5, -11.0, -4.5, 4.5, 11.0, 17.5]
	for zp: float in z_posts:
		for xp: float in [-4.3, 4.3]:
			LP.add_mat(self, LP.cyl(0.048, 0.055, 4.25, 7), Vector3(xp, 2.12, zp), pipe_mat)
			LP.add(self, LP.cyl(0.12, 0.14, 0.18, 7), Vector3(xp, 0.09, zp), Color(0.42, 0.42, 0.44))
		# İki yakayı bağlayan yüksek çelik gergi borusu (y=4.15 -> Ford Transit rahatça geçer!)
		LP.add_mat(self, LP.cyl(0.036, 0.036, 8.7, 6), Vector3(0, 4.15, zp), pipe_mat, Vector3(0, 0, PI / 2))
		# Cadde boyunca uzunlamasına yan bağlama boruları
		if zp < 17.5:
			var next_z: float = z_posts[z_posts.find(zp) + 1]
			var seg_l: float = next_z - zp
			var mid_z: float = (zp + next_z) * 0.5
			for xp: float in [-4.3, 4.3]:
				LP.add_mat(self, LP.cyl(0.035, 0.035, seg_l, 6), Vector3(xp, 4.10, mid_z), pipe_mat, Vector3(PI / 2, 0, 0))

	# Üstü kapatan geniş, renkli, güneş sızdıran semt pazarı brandaları (kuzey ve güney koridorları)
	var tarp_spans := [
		[-16.8, -11.6, 0], [-10.4, -5.2, 1],
		[5.2, 10.4, 2], [11.6, 16.8, 3],
	]
	for sp in tarp_spans:
		var z0: float = sp[0]; var z1: float = sp[1]; var ci: int = sp[2]
		var zc := (z0 + z1) * 0.5
		var zl := (z1 - z0)
		var col_l: Color = TARP_COLORS[ci % TARP_COLORS.size()]
		var col_r: Color = TARP_COLORS[(ci + 2) % TARP_COLORS.size()]
		var m_l := LP.mat_tex(col_l, tarp_tex, 0.72, Vector3(3.0, 3.0, 1.0))
		var m_r := LP.mat_tex(col_r, tarp_tex, 0.72, Vector3(3.0, 3.0, 1.0))
		# Çift eğimli (ortada hafif ışık aralığı bırakan) gerçekçi pazar brandası!
		LP.add_mat(self, LP.box(Vector3(4.2, 0.04, zl)), Vector3(-2.35, 4.26, zc), m_l, Vector3(0, 0, 0.14))
		LP.add_mat(self, LP.box(Vector3(4.2, 0.04, zl)), Vector3(2.35, 4.26, zc), m_r, Vector3(0, 0, -0.14))

	# Orta meydan (z=-4.5..+4.5) üstü açık gökyüzü + çapraz kablolarda parlayan pazarcı ampulleri ve renkli flamalar!
	for z in [-14.2, -7.8, -4.5, 4.5, 7.8, 14.2]:
		var holder := Node3D.new()
		holder.position = Vector3(0.0, 3.98, z)
		add_child(holder)
		_hanging_sways.append(holder)
		LP.add(holder, LP.box(Vector3(8.6, 0.02, 0.02)), Vector3.ZERO, Color(0.12, 0.12, 0.13))
		for bx in [-2.6, 0.0, 2.6]:
			# Siyah kablo + klasik çıplak sıcak pazarcı ampulü
			LP.add(holder, LP.cyl(0.008, 0.008, 0.34, 4), Vector3(bx, -0.17, 0), Color(0.1, 0.1, 0.11))
			var bulb := LP.add(holder, LP.sphere(0.085, 7, 4), Vector3(bx, -0.36, 0), Color(1.0, 0.92, 0.65), Vector3.ZERO, 0.15)
			var bm := bulb.material_override as StandardMaterial3D
			bm.emission_enabled = true
			bm.emission = Color(1.0, 0.80, 0.38)
			bm.emission_energy_multiplier = 0.6
			_bulb_mats.append(bm)
		# Orta ışık kaynağı
		var ol := OmniLight3D.new()
		ol.position = Vector3(0, -0.5, 0)
		ol.light_color = Color(1.0, 0.82, 0.48)
		ol.light_energy = 0.45
		ol.omni_range = 10.5
		holder.add_child(ol)
		_street_lights.append(ol)

	# Direklerden sarkan kurutulmuş kırmızı biber ve sarımsak dizileri + poşet ruloları!
	for zp in [-11.0, -4.5, 4.5, 11.0]:
		for xp in [-4.3, 4.3]:
			var off_x: float = 0.26 if xp < 0 else -0.26
			for k in 5:
				var pepper_c := Color(0.82, 0.14, 0.10) if (int(zp) + k) % 2 == 0 else Color(0.95, 0.92, 0.84)
				LP.add(self, LP.ellipsoid(0.045, 0.08, 0.045, 5, 3), Vector3(xp + off_x, 3.45 - float(k) * 0.13, zp), pepper_c)


## Kuzey ve Güney Semt Pazarı Giriş / Çıkış kemerleri (NPC'ler ve Ford Transit buradan girip çıkar!).
func _build_gates() -> void:
	var pipe_mat := LP.mat(Color(0.2, 0.32, 0.48), 0.48, 0.55)
	for gz in [-20.5, 20.5]:
		var g := Node3D.new()
		g.position = Vector3(0, 0, gz)
		add_child(g)
		for gx in [-4.35, 4.35]:
			LP.add_mat(g, LP.box(Vector3(0.45, 4.8, 0.45)), Vector3(gx, 2.4, 0), pipe_mat)
		LP.add_mat(g, LP.box(Vector3(9.4, 0.88, 0.36)), Vector3(0, 4.65, 0), LP.mat(Color(0.12, 0.32, 0.62), 0.55))
		LP.add(g, LP.box(Vector3(9.5, 0.12, 0.42)), Vector3(0, 5.12, 0), Color(0.98, 0.78, 0.18))
		LP.add(g, LP.box(Vector3(9.5, 0.12, 0.42)), Vector3(0, 4.18, 0), Color(0.98, 0.78, 0.18))
		var lbl_in := Label3D.new()
		lbl_in.text = "SEMT PAZARI  •  %s" % ("KUZEY KAPISI" if gz < 0 else "GÜNEY KAPISI")
		lbl_in.position = Vector3(0, 4.65, 0.22 if gz < 0 else -0.22)
		lbl_in.rotation.y = 0.0 if gz < 0 else PI
		lbl_in.font_size = 54
		lbl_in.outline_size = 12
		lbl_in.modulate = Color(1.0, 0.94, 0.76)
		g.add_child(lbl_in)
		# Giriş kenarına renkli flama şeridi
		for i in 10:
			var fx := -3.8 + float(i) * 0.84
			var fc: Color = PLASTIC_CRATES[i % PLASTIC_CRATES.size()]
			LP.add(g, LP.prism(Vector3(0.42, 0.38, 0.03)), Vector3(fx, 3.92, 0), fc, Vector3(0, 0, PI))


## Çevreleyen gerçekçi Türk mahallesi apartmanları (balkonlar, dükkan kepenkleri, kiremit çatılar).
func _build_mahalle_apartments() -> void:
	var plaster_tex := LP.tex_plaster()
	var wall_cols := [
		Color(0.93, 0.85, 0.72), Color(0.90, 0.78, 0.64), Color(0.84, 0.88, 0.82),
		Color(0.95, 0.89, 0.80), Color(0.88, 0.74, 0.64), Color(0.82, 0.85, 0.90),
	]
	var shop_names := ["ÇAY OCAĞI", "BAKKAL", "BERBER", "FIRIN", "MANAV", "NALBUR", "KIRAATHANE", "BÖREKÇİ"]
	var shop_idx := 0

	# Batı ve Doğu sokağı çevreleyen apartman sırası
	for side in [-1.0, 1.0]:
		var bx: float = side * 19.2
		for z in [-19.0, -10.5, -2.0, 6.5, 15.0, 23.0]:
			var w := rng.randf_range(6.8, 8.0)
			var d := rng.randf_range(6.5, 7.8)
			var floors := rng.randi_range(3, 4)
			var h := float(floors) * 3.1 + 1.2
			var col: Color = wall_cols[rng.randi() % wall_cols.size()]
			var m_wall := LP.mat_tex(col, plaster_tex, 0.92, Vector3(2.0, float(floors), 1.0), 0.0, true)
			var apt := Node3D.new()
			apt.position = Vector3(bx + side * (d * 0.5 - 3.0), 0, z)
			add_child(apt)
			LP.add_mat(apt, LP.box(Vector3(d, h, w)), Vector3(0, h * 0.5, 0), m_wall)
			# Kiremit çatı
			LP.add(apt, LP.prism(Vector3(d + 0.6, 1.8, w + 0.6)), Vector3(0, h + 0.9, 0), TERRACOTTA.darkened(rng.randf_range(0.0, 0.16)))
			# Sokağa bakan cephe: zemin kat mahalle dükkanı + üst kat balkonlar & pencereler
			var face_x: float = -side * (d * 0.5 + 0.05)
			var shop_c: Color = TARP_COLORS[shop_idx % TARP_COLORS.size()]
			LP.add(apt, LP.box(Vector3(0.14, 2.5, w * 0.72)), Vector3(face_x, 1.25, 0), Color(0.28, 0.30, 0.34))
			LP.add(apt, LP.box(Vector3(0.18, 0.62, w * 0.78)), Vector3(face_x - side * 0.08, 2.82, 0), shop_c)
			var slbl := Label3D.new()
			slbl.text = shop_names[shop_idx % shop_names.size()]
			shop_idx += 1
			slbl.position = Vector3(face_x - side * 0.22, 2.82, 0)
			slbl.rotation.y = -PI / 2 if side > 0 else PI / 2
			slbl.font_size = 34
			slbl.outline_size = 6
			slbl.modulate = Color(1.0, 0.96, 0.86)
			apt.add_child(slbl)
			for fl in range(1, floors):
				var fy := 1.8 + float(fl) * 3.0
				# Balkon çıkması + korkuluk
				LP.add(apt, LP.box(Vector3(0.85, 0.16, 2.4)), Vector3(face_x - side * 0.4, fy - 0.55, 0), col.darkened(0.08))
				LP.add(apt, LP.box(Vector3(0.06, 0.82, 2.4)), Vector3(face_x - side * 0.8, fy - 0.12, 0), Color(0.26, 0.27, 0.3))
				for wz in [-w * 0.28, w * 0.28]:
					LP.add(apt, LP.box(Vector3(0.10, 1.2, 0.95)), Vector3(face_x, fy + 0.1, wz), Color(0.24, 0.32, 0.42), Vector3.ZERO, 0.25)
					LP.add(apt, LP.box(Vector3(0.14, 0.12, 1.05)), Vector3(face_x - side * 0.04, fy - 0.52, wz), Color(0.92, 0.90, 0.86))

	# Kuzey ve Güney kapı arkası apartman siluetleri (kapı aksı x=-5..+5 açık kalır!)
	for gz in [-31.0, 31.0]:
		for bx in [-13.5, 13.5]:
			var h := rng.randf_range(9.5, 13.5)
			var c: Color = wall_cols[rng.randi() % wall_cols.size()]
			var m_w := LP.mat_tex(c, plaster_tex, 0.92, Vector3(2.0, 3.0, 1.0), 0.0, true)
			LP.add_mat(self, LP.box(Vector3(9.5, h, 7.0)), Vector3(bx, h * 0.5, gz), m_w)
			LP.add(self, LP.prism(Vector3(10.0, 1.9, 7.5)), Vector3(bx, h + 0.95, gz), TERRACOTTA)

	# Uzak şehir ufku ve yumuşak tepeler
	for i in 12:
		var a := float(i) * TAU / 12.0 + 0.1
		var dist := rng.randf_range(58.0, 74.0)
		var rx := rng.randf_range(18.0, 28.0)
		var ry := rng.randf_range(7.0, 15.0)
		var hc := Color(0.44, 0.54, 0.36).lerp(Color(0.64, 0.56, 0.44), rng.randf_range(0.15, 0.6))
		var hm := LP.add(self, LP.ellipsoid(rx, ry, rx * 0.8, 9, 5), Vector3(cos(a) * dist, ry * 0.22 - 1.5, sin(a) * dist), hc, Vector3(0, a, 0), 0.96)
		hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Renkli plastik hal kasası yığınları, çınar ağaçları ve dekoratif tezgahlar.
func _build_market_clutter_and_trees() -> void:
	# Renkli plastik hal kasaları yığınları (Türk pazarının vazgeçilmezi!)
	var stack_pts := [
		Vector3(-9.8, 0, -11.0), Vector3(9.8, 0, -11.0),
		Vector3(-9.8, 0, 11.0), Vector3(9.8, 0, 11.0),
		Vector3(-9.6, 0, -4.5), Vector3(9.6, 0, -4.5),
		Vector3(-9.6, 0, 4.5), Vector3(9.6, 0, 4.5),
	]
	for sp: Vector3 in stack_pts:
		var cnt := rng.randi_range(2, 4)
		for k in cnt:
			var col: Color = PLASTIC_CRATES[rng.randi() % PLASTIC_CRATES.size()]
			var p: Vector3 = sp + Vector3(rng.randf_range(-0.18, 0.18), 0.16 + float(k) * 0.32, rng.randf_range(-0.18, 0.18))
			_plastic_crate_prop(p, col, rng.randf_range(-0.25, 0.25))
		LP.solid(self, sp + Vector3(0, 0.5, 0), Vector3(0.8, 1.0, 0.8))

	# Kaldırım ve kapı yanlarında çınar & selvi ağaçları
	for tp in [
		Vector3(-12.8, 0, -17.5), Vector3(12.8, 0, -17.5),
		Vector3(-12.8, 0, 17.5), Vector3(12.8, 0, 17.5),
		Vector3(-13.2, 0, -5.0), Vector3(13.2, 0, -5.0),
		Vector3(-13.2, 0, 5.0), Vector3(13.2, 0, 5.0),
	]:
		if rng.randf() < 0.38:
			_cypress(tp)
		else:
			_tree(tp)


func _plastic_crate_prop(p: Vector3, c: Color, yaw: float) -> void:
	var n := Node3D.new()
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	LP.add(n, LP.box(Vector3(0.58, 0.04, 0.44)), Vector3(0, -0.14, 0), c.darkened(0.14), Vector3.ZERO, 0.55)
	LP.add(n, LP.box(Vector3(0.58, 0.28, 0.04)), Vector3(0, 0, 0.20), c, Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.58, 0.28, 0.04)), Vector3(0, 0, -0.20), c, Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.04, 0.28, 0.40)), Vector3(-0.27, 0, 0), c.lightened(0.05), Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.04, 0.28, 0.40)), Vector3(0.27, 0, 0), c.lightened(0.05), Vector3.ZERO, 0.52)


func _decor_stall(p: Vector3, yaw: float) -> void:
	var s := Node3D.new()
	s.position = p
	s.rotation.y = yaw
	add_child(s)
	var wood_m := LP.mat_tex(WOOD, LP.tex_wood(), 0.88, Vector3(2.0, 1.0, 1.0))
	var awn: Color = TARP_COLORS[rng.randi() % TARP_COLORS.size()]
	var awn_m := LP.mat_tex(awn, LP.tex_tarp(), 0.72, Vector3(2.0, 2.0, 1.0))
	LP.add_mat(s, LP.box(Vector3(3.2, 0.82, 1.12)), Vector3(0, 0.41, 0.3), wood_m)
	LP.add_mat(s, LP.box(Vector3(3.34, 0.07, 1.24)), Vector3(0, 0.85, 0.3), LP.mat_tex(WOOD.lightened(0.14), LP.tex_wood(), 0.85))
	for x in [-1.5, 1.5]:
		for z in [-0.6, 1.05]:
			LP.add(s, LP.cyl(0.045, 0.05, 2.5, 6), Vector3(x, 1.25, z), STEEL, Vector3.ZERO, 0.45, 0.65)
	LP.add_mat(s, LP.box(Vector3(3.5, 0.05, 2.15)), Vector3(0, 2.54, 0.25), awn_m, Vector3(0.18, 0, 0))
	for i in 3:
		var item_id: String = Produce.ITEM_ORDER[rng.randi() % Produce.ITEM_ORDER.size()]
		var base := Vector3(-1.0 + float(i) * 1.0, 0.94, 0.3)
		var pc: Color = PLASTIC_CRATES[(i + rng.randi()) % PLASTIC_CRATES.size()]
		LP.add(s, LP.box(Vector3(0.76, 0.14, 0.64)), base, pc, Vector3.ZERO, 0.55)
		for j in 6:
			var o := Vector3(rng.randf_range(-0.22, 0.22), 0.14 + (0.10 if j > 3 else 0.0), rng.randf_range(-0.17, 0.17))
			Produce.build_mesh(s, item_id, base + o, 0.082)
	LP.solid(s, Vector3(0, 0.5, 0.25), Vector3(3.3, 1.0, 1.32))


func _tree(p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	t.scale = Vector3.ONE * rng.randf_range(0.9, 1.35)
	add_child(t)
	LP.add(t, LP.cyl(0.18, 0.25, 2.0, 6), Vector3(0, 1.0, 0), WOOD.darkened(0.32))
	var g := Color(0.30, 0.58, 0.26).darkened(rng.randf_range(0.0, 0.20))
	LP.add(t, LP.ellipsoid(1.3, 0.95, 1.3, 7, 4), Vector3(0, 2.65, 0), g)
	LP.add(t, LP.ellipsoid(0.95, 0.78, 0.95, 7, 4), Vector3(0.45, 3.2, -0.25), g.lightened(0.09))
	LP.add(t, LP.ellipsoid(0.8, 0.65, 0.8, 6, 4), Vector3(-0.48, 3.0, 0.3), g.darkened(0.06))
	LP.solid(t, Vector3(0, 1.2, 0), Vector3(0.5, 2.4, 0.5))


func _cypress(p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	t.scale = Vector3.ONE * rng.randf_range(0.95, 1.35)
	add_child(t)
	LP.add(t, LP.cyl(0.11, 0.16, 1.2, 5), Vector3(0, 0.6, 0), WOOD.darkened(0.35))
	var g := Color(0.18, 0.44, 0.22).darkened(rng.randf_range(0.0, 0.15))
	LP.add(t, LP.cyl(0.45, 0.62, 2.1, 7), Vector3(0, 1.95, 0), g)
	LP.add(t, LP.cyl(0.02, 0.48, 2.3, 7), Vector3(0, 3.9, 0), g.lightened(0.06))
	LP.solid(t, Vector3(0, 1.0, 0), Vector3(0.42, 2.0, 0.42))


func _build_clouds() -> void:
	var cloud_root := Node3D.new()
	add_child(cloud_root)
	for i in 12:
		var c := Node3D.new()
		var by := rng.randf_range(17.5, 26.0)
		c.position = Vector3(rng.randf_range(-58.0, 58.0), by, rng.randf_range(-52.0, 52.0))
		c.rotation.y = rng.randf() * TAU
		var mat := LP.mat(Color(0.98, 0.98, 0.99), 0.95)
		_cloud_mats.append(mat)
		var puffs := rng.randi_range(3, 5)
		for j in puffs:
			var mi := MeshInstance3D.new()
			var r := rng.randf_range(1.6, 3.0)
			mi.mesh = LP.ellipsoid(r * 1.35, r * 0.6, r * 0.95, 7, 4)
			mi.material_override = mat
			mi.position = Vector3((float(j) - float(puffs) * 0.5) * 2.1, rng.randf_range(-0.35, 0.48), rng.randf_range(-0.9, 0.9))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.add_child(mi)
		cloud_root.add_child(c)
		_clouds.append([c, rng.randf_range(0.5, 1.3), by, rng.randf() * TAU])


## Oyuncuların pazar dışına taşmaması için görünmez sınır (NPC'ler ve Ford Transit kinematik olduğu için kapılardan rahat geçer).
func _build_boundaries() -> void:
	LP.solid(self, Vector3(-HALF_X, 2.5, 0), Vector3(0.8, 5.0, HALF_Z * 2.0 + 4.0))
	LP.solid(self, Vector3(HALF_X, 2.5, 0), Vector3(0.8, 5.0, HALF_Z * 2.0 + 4.0))
	LP.solid(self, Vector3(0, 2.5, -HALF_Z), Vector3(HALF_X * 2.0 + 4.0, 5.0, 0.8))
	LP.solid(self, Vector3(0, 2.5, HALF_Z), Vector3(HALF_X * 2.0 + 4.0, 5.0, 0.8))
