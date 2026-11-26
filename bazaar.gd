extends Node3D
## Gerçekçi Türk Semt Pazarı: dokulu asfalt cadde, parke taşı kaldırımlar, demir boru iskele üstü pazar
## brandaları, sallanan ampuller, Türk mahalle apartmanları (dükkanlar, balkonlar, çamaşırlar, çanak antenler),
## katmanlı şehir silüeti + cami & minareler, evli tepeler, prosedürel gökyüzü (güneş, bulut, yıldız),
## hava durumu (açık / bulutlu / yağmur + şimşek), akşam lambaları ve kozmetik mahalle hayatı (ambient.gd).
##
## Public API: set_day_progress(p), set_weather(kind), set_quality(high), interactive, PLAYER_STALL_SPOTS.

const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const VFX := preload("res://vfx.gd")
const AmbientScript := preload("res://ambient.gd")

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
const WALL_COLS := [
	Color(0.93, 0.85, 0.72), Color(0.90, 0.76, 0.62), Color(0.80, 0.86, 0.80),
	Color(0.95, 0.90, 0.80), Color(0.88, 0.72, 0.64), Color(0.80, 0.84, 0.90),
	Color(0.96, 0.82, 0.58), Color(0.86, 0.80, 0.86),
]
const SHOP_NAMES := ["BAKKAL", "BERBER", "FIRIN", "ECZANE", "KASAP", "ÇİÇEKÇİ",
	"KIRTASİYE", "BÜFE", "TERZİ", "NALBUR", "KIRAATHANE", "BÖREKÇİ"]
const SHUTTER_COLS := [Color(0.18, 0.36, 0.62), Color(0.62, 0.16, 0.14), Color(0.16, 0.46, 0.28),
	Color(0.85, 0.62, 0.12), Color(0.34, 0.34, 0.38)]
const CLOTH_COLS := [Color(0.92, 0.92, 0.9), Color(0.85, 0.2, 0.2), Color(0.22, 0.4, 0.78),
	Color(0.96, 0.78, 0.2), Color(0.3, 0.62, 0.4), Color(0.95, 0.55, 0.7), Color(0.25, 0.25, 0.3)]
# Gün içi gökyüzü anahtar kareleri:
# [p, güneş yüks.(°), tepe, ufuk, güneş parıltısı, güneş rengi, güneş enerjisi, ortam rengi, sis]
const SKY_KEYS := [
	[0.00, 12.0, Color(0.30, 0.45, 0.70), Color(1.00, 0.80, 0.64), Color(1.00, 0.60, 0.36), Color(1.00, 0.80, 0.60), 1.5, Color(0.74, 0.68, 0.66), Color(0.95, 0.82, 0.72)],
	[0.18, 34.0, Color(0.22, 0.46, 0.82), Color(0.82, 0.88, 0.95), Color(1.00, 0.85, 0.65), Color(1.00, 0.93, 0.82), 2.0, Color(0.70, 0.74, 0.80), Color(0.84, 0.87, 0.90)],
	[0.45, 58.0, Color(0.16, 0.42, 0.86), Color(0.72, 0.84, 0.96), Color(1.00, 0.95, 0.85), Color(1.00, 0.98, 0.94), 2.25, Color(0.72, 0.78, 0.86), Color(0.78, 0.84, 0.92)],
	[0.68, 27.0, Color(0.20, 0.40, 0.76), Color(0.98, 0.84, 0.62), Color(1.00, 0.68, 0.32), Color(1.00, 0.82, 0.55), 2.1, Color(0.80, 0.72, 0.64), Color(0.94, 0.82, 0.66)],
	[0.84, 8.0, Color(0.22, 0.24, 0.52), Color(1.00, 0.55, 0.28), Color(1.00, 0.45, 0.18), Color(1.00, 0.56, 0.26), 1.6, Color(0.72, 0.56, 0.54), Color(0.90, 0.58, 0.42)],
	[0.93, 2.0, Color(0.10, 0.12, 0.30), Color(0.62, 0.36, 0.36), Color(0.85, 0.32, 0.22), Color(0.90, 0.45, 0.35), 0.45, Color(0.44, 0.42, 0.56), Color(0.40, 0.32, 0.40)],
	[1.00, -3.0, Color(0.04, 0.06, 0.16), Color(0.25, 0.22, 0.34), Color(0.40, 0.18, 0.18), Color(0.50, 0.55, 0.85), 0.12, Color(0.30, 0.32, 0.46), Color(0.16, 0.16, 0.24)],
]

const _SKY_SHADER := """
shader_type sky;
uniform vec3 top_col : source_color = vec3(0.2, 0.45, 0.85);
uniform vec3 hor_col : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 ground_col : source_color = vec3(0.35, 0.33, 0.31);
uniform vec3 glow_col : source_color = vec3(1.0, 0.8, 0.6);
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_dark : source_color = vec3(0.7, 0.74, 0.8);
uniform float sky_energy = 1.0;
uniform float cloud_cover = 0.35;
uniform float stars = 0.0;
uniform float flash = 0.0;
uniform float sun_vis = 1.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.07 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sdir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float mu = max(dot(d, sdir), 0.0);
	float hz = clamp(h, 0.0, 1.0);
	vec3 col = mix(hor_col, top_col, pow(hz, 0.45));
	float band = exp(-abs(h) * 5.0);
	col += glow_col * (pow(mu, 7.0) * (0.25 + 0.75 * band) + pow(mu, 1.6) * band * 0.18);
	if (h < 0.0) {
		col = mix(col, ground_col, clamp(-h * 6.0, 0.0, 1.0));
	}
	col *= sky_energy;
	// yıldızlar
	if (stars > 0.001 && h > 0.02) {
		vec2 sp = d.xz / (h + 0.6) * 160.0;
		vec2 cell = floor(sp);
		float r = hash(cell);
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + r * 40.0);
		float s = step(0.985, r) * smoothstep(0.45, 0.0, length(fract(sp) - 0.5)) * tw;
		col += vec3(0.9, 0.92, 1.0) * s * stars * smoothstep(0.02, 0.25, h);
	}
	// güneş diski
	if (LIGHT0_ENABLED) {
		float disc = smoothstep(0.99935, 0.9997, mu);
		col += LIGHT0_COLOR * (disc * 14.0 + pow(mu, 280.0) * 1.2) * sun_vis * min(LIGHT0_ENERGY, 1.5);
	}
	// prosedürel bulutlar (düzlem izdüşümü)
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.09);
		vec2 drift = vec2(TIME * 0.006, TIME * 0.0025);
		float n = fbm(uv * 1.9 + drift * 4.0);
		float n2 = fbm(uv * 5.2 - drift * 6.0 + 3.0);
		float m = n * 0.75 + n2 * 0.35;
		float dens = smoothstep(1.02 - cloud_cover, 1.02 - cloud_cover + 0.32, m);
		float inner = smoothstep(0.35, 0.95, n2);
		vec3 cc = mix(cloud_lit, cloud_dark, clamp(inner * 0.55 + dens * 0.35, 0.0, 1.0)) * sky_energy;
		cc += glow_col * pow(mu, 6.0) * (1.0 - dens * 0.6) * 0.9 * sky_energy;
		float fade = smoothstep(0.0, 0.16, h);
		col = mix(col, cc, dens * fade);
	}
	col += vec3(0.8, 0.85, 1.0) * flash;
	COLOR = col;
}
"""

var interactive := false
var rng := RandomNumberGenerator.new()

var _sun: DirectionalLight3D
var _flash_light: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _sky: Sky
var _env: Environment
var _street_lights: Array[OmniLight3D] = []
var _bulb_mats: Array[StandardMaterial3D] = []
var _hanging_sways: Array[Node3D] = []
var _spinners: Array[Node3D] = []
var _batch_mats: Array[ShaderMaterial] = []
var _win_mats: Array[ShaderMaterial] = []
var _sign_mat: ShaderMaterial
var _sign_labels: Array[Label3D] = []
var _asphalt_mat: StandardMaterial3D
var _paver_mat: StandardMaterial3D
var _puddle_mat: StandardMaterial3D
var _puddles: Array[MeshInstance3D] = []
var _flag_mats: Array[ShaderMaterial] = []
var _rain: Node3D
var _ambient: Node3D
var _day_progress := 0.38
var _applied_p := -9.0
var _anim_t := 0.0

var _weather := "clear"
var _cloud_k := 0.0
var _rain_k := 0.0
var _wet_k := 0.0
var _quality_high := true
var _flash := 0.0
var _flash_cd := 9.0
var _flash_seq: Array[float] = []
var _night_k := 0.0
var _crate_tops: Array = [] # ambient kediler için [Vector3, yaw]


func _ready() -> void:
	rng.seed = 1453
	_env_setup()
	var near := LP.batch()
	var glass := LP.batch()
	var lit := LP.batch()
	var signs := LP.batch()
	_build_street_and_sidewalks(near)
	_build_overhead_tarps_and_lights(near)
	_build_gates(near)
	if not interactive:
		for spot in PLAYER_STALL_SPOTS:
			_decor_stall(spot[0], spot[1])
	# Orta yanlarda mahalle tezgahları (tekstil / kuruyemiş / züccaciye havası)
	for sx in [-10.8, 10.8]:
		_decor_stall(Vector3(sx, 0, 0.0), PI / 2 if sx < 0 else -PI / 2)
	_build_mahalle_apartments(near, glass, lit, signs)
	_build_market_clutter_and_trees(near)
	_build_street_details(near)
	_build_cay_ocagi(near)
	_build_lamp_posts(near)
	_build_bunting_and_cables(near)
	_commit(near, 0.86, true, 1.0)
	var gm := _commit(glass, 0.12, false, 0.0, 0.35)
	if gm:
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_win_mats.append(_commit_lit(lit, Color(1.0, 0.72, 0.38)))
	var sm := signs.commit(self, LP.batch_material(0.6, 0.0, 0.0), true)
	if sm:
		_sign_mat = sm.material_override as ShaderMaterial
	_build_skyline()
	_build_boundaries()
	_build_rain()
	if true: # kozmetik mahalle hayatı (menüde de canlı)
		_ambient = AmbientScript.new()
		_ambient.name = "Ambient"
		_ambient.set("bazaar", self)
		_ambient.set("cat_spots", _crate_tops)
		add_child(_ambient)
	set_day_progress(_day_progress)
	set_quality(true)


func _commit(b, rough: float, shadows: bool, ground_ao := 1.0, metal := 0.0) -> MeshInstance3D:
	var m := LP.batch_material(rough, metal, ground_ao)
	var mi: MeshInstance3D = b.commit(self, m, shadows)
	if mi:
		_batch_mats.append(m)
	return mi


func _commit_lit(b, emit_col: Color) -> ShaderMaterial:
	var m := LP.batch_material(0.15, 0.25, 0.0)
	m.set_shader_parameter("emit_col", emit_col)
	b.commit(self, m, false)
	return m


# ---------------------------------------------------------------------------
# Kare döngüsü
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_anim_t += dt
	for i in _hanging_sways.size():
		_hanging_sways[i].rotation.x = sin(_anim_t * 1.7 + float(i) * 0.85) * (0.045 + _rain_k * 0.04)
	for s in _spinners:
		s.rotation.y += dt * 1.6
	# Hava geçişleri (yumuşak)
	var tc := 0.0; var tr := 0.0
	match _weather:
		"cloudy": tc = 0.58
		"rain":
			tc = 1.0
			tr = 1.0
	var changed := false
	if absf(_cloud_k - tc) > 0.001 or absf(_rain_k - tr) > 0.001:
		_cloud_k = move_toward(_cloud_k, tc, dt * 0.22)
		_rain_k = move_toward(_rain_k, tr, dt * 0.3)
		changed = true
	var tw := 1.0 if _weather == "rain" else 0.0
	if absf(_wet_k - tw) > 0.001:
		_wet_k = move_toward(_wet_k, tw, dt * (0.12 if tw > _wet_k else 0.03))
		changed = true
	if changed:
		_apply_visuals()
	# Yağmur kamerayı takip eder
	if _rain and _rain.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var cp := cam.global_position
			_rain.global_position = Vector3(cp.x, 0.0, cp.z)
	# Şimşek (sadece görsel; gök gürültüsünü sfx.gd kendi çalar)
	if _rain_k > 0.7:
		_flash_cd -= dt
		if _flash_cd <= 0.0:
			_flash_cd = rng.randf_range(9.0, 22.0)
			_flash_seq = [0.0, 0.11, 0.24]
			if rng.randf() < 0.5:
				_flash_seq.append(0.4)
	if not _flash_seq.is_empty():
		for i in _flash_seq.size():
			_flash_seq[i] -= dt
		if _flash_seq[0] <= 0.0:
			_flash_seq.pop_front()
			_flash = rng.randf_range(0.7, 1.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 7.0)
		_flash_light.visible = _flash > 0.01
		_flash_light.light_energy = _flash * 2.2
		_sky_mat.set_shader_parameter("flash", _flash * 0.9)
	# Akşam lamba titreşimi
	if _night_k > 0.02:
		for i in _street_lights.size():
			var fl := 1.0 + sin(_anim_t * 7.0 + float(i) * 1.9) * 0.05
			_street_lights[i].light_energy = _street_lights[i].get_meta("base", 1.0) * _night_k * fl


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_day_progress(p: float) -> void:
	_day_progress = clampf(p, 0.0, 1.0)
	# Sky radyansını boşuna yenilememek için küçük adımlarda güncelle
	if absf(_day_progress - _applied_p) >= 0.0025 or _day_progress <= 0.0 or _day_progress >= 1.0:
		_apply_visuals()


## kind: "clear" | "cloudy" | "rain". instant=true geçişsiz uygular (ör. geç katılan oyuncu).
func set_weather(kind: String, instant := false) -> void:
	if kind != "clear" and kind != "cloudy" and kind != "rain":
		kind = "clear"
	_weather = kind
	set_meta("weather", kind)
	_flash_cd = rng.randf_range(4.0, 9.0)
	if instant:
		_cloud_k = 0.58 if kind == "cloudy" else (1.0 if kind == "rain" else 0.0)
		_rain_k = 1.0 if kind == "rain" else 0.0
		_wet_k = _rain_k
		_apply_visuals()


func get_weather() -> String:
	return _weather


func set_quality(high: bool) -> void:
	_quality_high = high
	if _env == null:
		return
	_env.ssao_enabled = high
	_env.ssil_enabled = high
	_env.glow_enabled = high
	_env.volumetric_fog_enabled = high
	_env.ssr_enabled = high and _wet_k > 0.15
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 70.0 if high else 42.0
	_sky.radiance_size = Sky.RADIANCE_SIZE_128 if high else Sky.RADIANCE_SIZE_32
	if _rain:
		VFX.set_rain_amount(_rain, _rain_k * (1.0 if high else 0.45))
	for f in _flag_mats:
		f.set_shader_parameter("wind", 1.0 + _cloud_k * 0.8)


# ---------------------------------------------------------------------------
# Işık / gökyüzü / hava uygulaması
# ---------------------------------------------------------------------------

func _sample_keys(p: float) -> Array:
	for i in range(SKY_KEYS.size() - 1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		if p <= float(b[0]):
			var k := smoothstep(float(a[0]), float(b[0]), p)
			var out := []
			for j in range(1, a.size()):
				if a[j] is Color:
					out.append((a[j] as Color).lerp(b[j], k))
				else:
					out.append(lerpf(float(a[j]), float(b[j]), k))
			return out
	var last: Array = SKY_KEYS[SKY_KEYS.size() - 1]
	return last.slice(1)


static func _grey(c: Color, k: float, dark := 0.0) -> Color:
	var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
	return c.lerp(Color(l, l, l * 1.04), k).darkened(dark)


func _apply_visuals() -> void:
	if _sun == null or _sky_mat == null or _env == null:
		return
	_applied_p = _day_progress
	var p := _day_progress
	var s := _sample_keys(p)
	var el: float = s[0]
	var top: Color = s[1]; var hor: Color = s[2]; var glow: Color = s[3]
	var sun_col: Color = s[4]; var sun_e: float = s[5]
	var amb: Color = s[6]; var fog_c: Color = s[7]

	var ck := _cloud_k
	var rk := _rain_k
	var grey_k := clampf(ck * 0.62 + rk * 0.3, 0.0, 0.95)
	top = _grey(top, grey_k, rk * 0.35)
	hor = _grey(hor, grey_k * 0.85, rk * 0.3)
	glow = glow.lerp(hor, ck * 0.7)
	fog_c = _grey(fog_c, grey_k * 0.8, rk * 0.25)
	amb = _grey(amb, grey_k * 0.6)
	sun_e *= 1.0 - ck * 0.5 - rk * 0.32
	sun_col = _grey(sun_col, ck * 0.4)

	# Güneş yönü: sabah güneydoğu, gün batımı caddenin kuzey ucunda (caminin arkasında)
	var az := lerpf(2.55, -0.22, p)
	var el_l := deg_to_rad(maxf(el, 4.0))
	var sdir := Vector3(sin(az) * cos(el_l), sin(el_l), -cos(az) * cos(el_l)).normalized()
	_sun.basis = Basis.looking_at(-sdir, Vector3.UP)
	_sun.light_color = sun_col
	_sun.light_energy = sun_e * (smoothstep(-3.0, 5.0, el) * 0.85 + 0.15)
	_sun.shadow_opacity = lerpf(1.0, 0.55, ck)

	_sky_mat.set_shader_parameter("top_col", top)
	_sky_mat.set_shader_parameter("hor_col", hor)
	_sky_mat.set_shader_parameter("ground_col", fog_c.darkened(0.45))
	_sky_mat.set_shader_parameter("glow_col", glow * (1.0 - ck * 0.6))
	var cl := Color(1.0, 0.98, 0.96).lerp(glow.lerp(Color.WHITE, 0.35), clampf((p - 0.6) * 2.2, 0.0, 0.85))
	cl = _grey(cl, ck * 0.5, rk * 0.45 + smoothstep(0.88, 1.0, p) * 0.6)
	_sky_mat.set_shader_parameter("cloud_lit", cl)
	_sky_mat.set_shader_parameter("cloud_dark", _grey(cl.darkened(0.28 + rk * 0.2), 0.3).lerp(top, 0.25))
	_sky_mat.set_shader_parameter("cloud_cover", 0.47 + ck * 0.5)
	_sky_mat.set_shader_parameter("stars", smoothstep(0.9, 1.0, p) * (1.0 - ck))
	_sky_mat.set_shader_parameter("sun_vis", 1.0 - ck * 0.92)
	_sky_mat.set_shader_parameter("sky_energy", lerpf(1.0, 0.8, rk))

	_env.ambient_light_color = amb
	_env.ambient_light_energy = lerpf(0.75, 0.95, ck) * lerpf(1.0, 0.7, smoothstep(0.9, 1.0, p))
	_env.fog_light_color = fog_c
	_env.fog_density = 0.0030 + ck * 0.002 + rk * 0.008 + smoothstep(0.85, 1.0, p) * 0.002
	_env.fog_height_density = 0.02 + rk * 0.06
	_env.volumetric_fog_albedo = fog_c.lightened(0.2)
	_env.volumetric_fog_density = 0.0022 + rk * 0.01
	_env.tonemap_exposure = lerpf(1.0, 1.18, smoothstep(0.86, 1.0, p)) + rk * 0.1

	# Akşam lambaları (yağmurda daha erken yanar)
	_night_k = maxf(smoothstep(0.72, 0.9, p), rk * 0.55 * smoothstep(0.3, 0.7, p) + rk * 0.25)
	for bm in _bulb_mats:
		bm.emission_energy_multiplier = lerpf(0.25, 4.2, _night_k)
	for sl in _street_lights:
		sl.visible = _night_k > 0.03
		sl.light_energy = float(sl.get_meta("base", 1.0)) * _night_k
	for wm in _win_mats:
		wm.set_shader_parameter("emit", _night_k * 1.8)
	if _sign_mat:
		_sign_mat.set_shader_parameter("emit_self", _night_k * 0.9)

	# Islak zemin
	var wet := _wet_k
	for bm2 in _batch_mats:
		bm2.set_shader_parameter("wet", wet)
		bm2.set_shader_parameter("wind", 1.0 + ck * 0.8 + rk * 0.6)
	if _asphalt_mat:
		_asphalt_mat.roughness = lerpf(0.94, 0.28, wet)
		_asphalt_mat.albedo_color = Color(0.86, 0.86, 0.88).darkened(wet * 0.38)
		_asphalt_mat.metallic_specular = lerpf(0.5, 0.75, wet)
	if _paver_mat:
		_paver_mat.roughness = lerpf(0.9, 0.42, wet)
		_paver_mat.albedo_color = Color(0.95, 0.93, 0.9).darkened(wet * 0.3)
	if _puddle_mat:
		_puddle_mat.albedo_color = Color(0.12, 0.13, 0.15, 0.7 * smoothstep(0.15, 0.8, wet))
	for pd in _puddles:
		pd.visible = wet > 0.12
	_env.ssr_enabled = _quality_high and wet > 0.15
	if _rain:
		VFX.set_rain_amount(_rain, rk * (1.0 if _quality_high else 0.45))
	for f in _flag_mats:
		f.set_shader_parameter("wind", 1.0 + ck * 0.8)


func _env_setup() -> void:
	var sh := Shader.new()
	sh.code = _SKY_SHADER
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sh
	_sky = Sky.new()
	_sky.sky_material = _sky_mat
	_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_sky.radiance_size = Sky.RADIANCE_SIZE_128

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = _sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.55
	_env.ambient_light_energy = 0.8
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.06
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_light_color = Color(0.92, 0.86, 0.78)
	_env.fog_density = 0.0042
	_env.fog_sky_affect = 0.0
	_env.fog_aerial_perspective = 0.55
	_env.fog_height = 1.2
	_env.fog_height_density = 0.02
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 1.8
	_env.ssao_power = 1.4
	_env.ssao_light_affect = 0.25
	_env.ssil_enabled = true
	_env.ssil_radius = 4.0
	_env.ssil_intensity = 0.7
	_env.ssr_enabled = false
	_env.ssr_max_steps = 48
	_env.ssr_fade_in = 0.1
	_env.ssr_fade_out = 2.5
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.006
	_env.volumetric_fog_length = 48.0
	_env.volumetric_fog_anisotropy = 0.55
	_env.volumetric_fog_sky_affect = 0.0
	_env.volumetric_fog_ambient_inject = 0.15

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -35, 0)
	_sun.light_color = Color(1.0, 0.95, 0.84)
	_sun.light_energy = 1.35
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_max_distance = 70.0
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	_sun.shadow_blur = 1.3
	_sun.light_volumetric_fog_energy = 1.4
	add_child(_sun)

	_flash_light = DirectionalLight3D.new()
	_flash_light.rotation_degrees = Vector3(-70, 20, 0)
	_flash_light.light_color = Color(0.8, 0.86, 1.0)
	_flash_light.shadow_enabled = false
	_flash_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_flash_light.visible = false
	add_child(_flash_light)


func _build_rain() -> void:
	_rain = VFX.spawn_rain(self, 2400)
	VFX.set_rain_amount(_rain, 0.0)
	# Brandaların altına yağmur düşmesin
	for sp in [[-16.8, -11.6], [-10.4, -5.2], [5.2, 10.4], [11.6, 16.8]]:
		var cb := GPUParticlesCollisionBox3D.new()
		cb.size = Vector3(9.0, 0.5, float(sp[1]) - float(sp[0]) + 0.6)
		cb.position = Vector3(0, 4.35, (float(sp[0]) + float(sp[1])) * 0.5)
		add_child(cb)
	var ground := GPUParticlesCollisionBox3D.new()
	ground.size = Vector3(400, 2, 400)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)


# ---------------------------------------------------------------------------
# Zemin: asfalt cadde, parke taşı kaldırımlar, bordürler, rögarlar, su birikintileri
# ---------------------------------------------------------------------------

func _build_street_and_sidewalks(b) -> void:
	_asphalt_mat = LP.mat_tex(Color(0.86, 0.86, 0.88), LP.tex_asphalt(), 0.94, Vector3(14.0, 15.0, 1.0))
	_paver_mat = LP.mat_tex(Color(0.95, 0.93, 0.9), LP.tex_pavers(), 0.9, Vector3(9.0, 40.0, 1.0))

	# Şehir zemini (pazarın ötesi)
	var city := MeshInstance3D.new()
	var cpm := PlaneMesh.new()
	cpm.size = Vector2(520.0, 520.0)
	city.mesh = cpm
	city.position = Vector3(0, -0.04, 0)
	city.material_override = LP.mat(Color(0.46, 0.44, 0.40), 0.95)
	city.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(city)

	# Asfalt cadde + çarpıştırıcı
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90.0, 96.0)
	road.mesh = pm
	road.material_override = _asphalt_mat
	add_child(road)
	LP.solid(self, Vector3(0, -0.5, 0), Vector3(90.0, 1.0, 96.0))

	# Sol ve sağ parke taşı pazar kaldırımı / tezgah alanı (dış kaldırım binalara kadar)
	for sx in [-10.2, 10.2]:
		var side := MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = Vector2(12.0, 70.0)
		side.mesh = sp
		side.position = Vector3(sx, 0.04, 2.0)
		side.material_override = _paver_mat
		add_child(side)

	# Beyaz-gri boyalı belediye kaldırım bordür taşları (x = ±4.2)
	for sx in [-4.2, 4.2]:
		for i in range(-30, 32):
			var c := Color(0.90, 0.89, 0.86) if (i % 2 == 0) else Color(0.30, 0.31, 0.33)
			b.box(Vector3(0.24, 0.12, 1.06), Vector3(sx, 0.06, float(i) * 1.08), c)
	# Yol çizgileri
	var stripe_col := Color(0.80, 0.79, 0.74)
	for z in range(-30, 31, 4):
		b.box(Vector3(0.16, 0.012, 1.8), Vector3(0.0, 0.006, float(z)), stripe_col)
	for sx in [-3.85, 3.85]:
		b.box(Vector3(0.12, 0.012, 62.0), Vector3(sx, 0.006, 0.0), stripe_col.darkened(0.12))
	# Yaya geçidi (kapı önlerinde)
	for gz in [-23.6, 23.6]:
		for i in 7:
			b.box(Vector3(0.5, 0.012, 2.4), Vector3(-3.0 + float(i) * 1.0, 0.007, gz), stripe_col)

	# Rögar kapakları (alfa kesimli dokulu)
	var mh_mat := LP.mat_tex(Color(1, 1, 1), LP.tex_manhole(), 0.55, Vector3.ONE, 0.55)
	mh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mh_mat.alpha_scissor_threshold = 0.5
	for mp in [Vector3(1.6, 0.012, -3.5), Vector3(-1.8, 0.012, 5.2), Vector3(2.2, 0.012, 13.0), Vector3(-2.4, 0.012, -12.6)]:
		var mh := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(0.9, 0.9)
		mh.mesh = q
		mh.position = mp
		mh.rotation.y = rng.randf() * TAU
		mh.material_override = mh_mat
		mh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mh)

	# Su birikintileri (sadece yağmurda görünür, parlak)
	_puddle_mat = StandardMaterial3D.new()
	_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puddle_mat.albedo_color = Color(0.05, 0.06, 0.07, 0.0)
	_puddle_mat.roughness = 0.03
	_puddle_mat.metallic = 0.2
	_puddle_mat.metallic_specular = 1.0
	var puddle_pts := [
		[Vector3(-2.6, 0.014, -6.5), Vector3(1.4, 1, 0.8)], [Vector3(1.9, 0.014, 6.2), Vector3(1.1, 1, 1.6)],
		[Vector3(-1.2, 0.014, 15.5), Vector3(0.9, 1, 0.7)], [Vector3(2.6, 0.014, -15.0), Vector3(1.3, 1, 0.9)],
		[Vector3(-3.3, 0.014, 1.8), Vector3(0.6, 1, 1.1)], [Vector3(0.4, 0.014, -19.4), Vector3(1.5, 1, 0.8)],
		[Vector3(9.2, 0.05, 2.6), Vector3(0.8, 1, 0.6)], [Vector3(-9.0, 0.05, -2.8), Vector3(0.9, 1, 0.7)],
	]
	for pp in puddle_pts:
		var pd := MeshInstance3D.new()
		pd.mesh = LP.cyl(1.0, 1.0, 0.004, 14)
		pd.position = pp[0]
		pd.scale = pp[1]
		pd.rotation.y = rng.randf() * TAU
		pd.material_override = _puddle_mat
		pd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pd.visible = false
		add_child(pd)
		_puddles.append(pd)


## İkonik Türk semt pazarı üstü: demir boru iskeleler, mavi/yeşil/çizgili eğik naylon brandalar ve sallanan pazarcı ampulleri!
func _build_overhead_tarps_and_lights(b) -> void:
	var tarp_tex := LP.tex_tarp()
	var steel := STEEL

	var z_posts: Array[float] = [-17.5, -11.0, -4.5, 4.5, 11.0, 17.5]
	for zi in z_posts.size():
		var zp: float = z_posts[zi]
		for xp: float in [-4.3, 4.3]:
			b.cyl(0.048, 0.055, 4.25, Vector3(xp, 2.12, zp), steel)
			b.cyl(0.12, 0.14, 0.18, Vector3(xp, 0.09, zp), Color(0.42, 0.42, 0.44))
		b.cyl(0.036, 0.036, 8.7, Vector3(0, 4.15, zp), steel, Vector3(0, 0, PI / 2), 6)
		if zi < z_posts.size() - 1:
			var next_z: float = z_posts[zi + 1]
			for xp: float in [-4.3, 4.3]:
				b.cyl(0.035, 0.035, next_z - zp, Vector3(xp, 4.10, (zp + next_z) * 0.5), steel, Vector3(PI / 2, 0, 0), 6)

	var tarp_spans := [[-16.8, -11.6, 0], [-10.4, -5.2, 1], [5.2, 10.4, 2], [11.6, 16.8, 3]]
	for sp in tarp_spans:
		var z0: float = sp[0]; var z1: float = sp[1]; var ci: int = sp[2]
		var zc := (z0 + z1) * 0.5
		var zl := (z1 - z0)
		var col_l: Color = TARP_COLORS[ci % TARP_COLORS.size()]
		var col_r: Color = TARP_COLORS[(ci + 2) % TARP_COLORS.size()]
		var m_l := LP.mat_tex(col_l, tarp_tex, 0.72, Vector3(3.0, 3.0, 1.0))
		var m_r := LP.mat_tex(col_r, tarp_tex, 0.72, Vector3(3.0, 3.0, 1.0))
		for m: StandardMaterial3D in [m_l, m_r]:
			m.backlight_enabled = true
			m.backlight = m.albedo_color * 0.55
		LP.add_mat(self, LP.box(Vector3(4.2, 0.04, zl)), Vector3(-2.35, 4.26, zc), m_l, Vector3(0, 0, 0.14))
		LP.add_mat(self, LP.box(Vector3(4.2, 0.04, zl)), Vector3(2.35, 4.26, zc), m_r, Vector3(0, 0, -0.14))
		# Branda kenar sarkıntısı (fırfır)
		for sx in [-4.42, 4.42]:
			b.box(Vector3(0.03, 0.22, zl), Vector3(sx, 3.88, zc), (col_l if sx < 0 else col_r).darkened(0.1), Vector3.ZERO, 0.4)

	var bulb_mat := LP.mat(Color(1.0, 0.92, 0.65), 0.15)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.78, 0.38)
	bulb_mat.emission_energy_multiplier = 0.4
	_bulb_mats.append(bulb_mat)
	var bulb_mesh := LP.sphere(0.085, 7, 4)
	for z in [-14.2, -7.8, -4.5, 4.5, 7.8, 14.2]:
		var holder := Node3D.new()
		holder.position = Vector3(0.0, 3.98, z)
		add_child(holder)
		_hanging_sways.append(holder)
		LP.add(holder, LP.box(Vector3(8.6, 0.02, 0.02)), Vector3.ZERO, Color(0.12, 0.12, 0.13))
		for bx in [-3.6, -1.8, 0.0, 1.8, 3.6]:
			LP.add(holder, LP.cyl(0.008, 0.008, 0.34, 4), Vector3(bx, -0.17, 0), Color(0.1, 0.1, 0.11))
			LP.add(holder, LP.cyl(0.03, 0.045, 0.05, 6), Vector3(bx, -0.3, 0), Color(0.2, 0.2, 0.2))
			LP.add_mat(holder, bulb_mesh, Vector3(bx, -0.38, 0), bulb_mat)
		var ol := OmniLight3D.new()
		ol.position = Vector3(0, -0.5, 0)
		ol.light_color = Color(1.0, 0.80, 0.46)
		ol.omni_range = 10.5
		ol.omni_attenuation = 1.4
		ol.set_meta("base", 2.2)
		ol.light_volumetric_fog_energy = 0.6
		holder.add_child(ol)
		_street_lights.append(ol)

	# Direklerden sarkan kurutulmuş kırmızı biber ve sarımsak dizileri
	for zp in [-11.0, -4.5, 4.5, 11.0]:
		for xp in [-4.3, 4.3]:
			var off_x: float = 0.26 if xp < 0 else -0.26
			b.rod(Vector3(xp, 4.05, zp), Vector3(xp + off_x, 3.55, zp), 0.006, Color(0.4, 0.3, 0.2))
			for k in 6:
				var pepper_c := Color(0.78, 0.10, 0.08) if (int(zp) + k) % 3 != 0 else Color(0.95, 0.92, 0.84)
				b.ellipsoid(Vector3(0.045, 0.08, 0.045), Vector3(xp + off_x, 3.45 - float(k) * 0.12, zp), pepper_c, Vector3(0, k, 0), 5, 3, 0.25)


## Kuzey ve Güney Semt Pazarı Giriş / Çıkış kemerleri (NPC'ler ve Ford Transit buradan girip çıkar!).
func _build_gates(b) -> void:
	for gz in [-20.5, 20.5]:
		for gx in [-4.35, 4.35]:
			b.box(Vector3(0.45, 4.8, 0.45), Vector3(gx, 2.4, gz), Color(0.2, 0.32, 0.48))
			b.box(Vector3(0.6, 0.3, 0.6), Vector3(gx, 0.15, gz), Color(0.3, 0.3, 0.32))
		b.box(Vector3(9.4, 0.88, 0.36), Vector3(0, 4.65, gz), Color(0.12, 0.32, 0.62))
		b.box(Vector3(9.5, 0.12, 0.42), Vector3(0, 5.12, gz), Color(0.98, 0.78, 0.18))
		b.box(Vector3(9.5, 0.12, 0.42), Vector3(0, 4.18, gz), Color(0.98, 0.78, 0.18))
		for side in [-1.0, 1.0]:
			var lbl_in := Label3D.new()
			lbl_in.text = "SEMT PAZARI  •  %s" % ("KUZEY KAPISI" if gz < 0 else "GÜNEY KAPISI")
			lbl_in.position = Vector3(0, 4.65, gz + side * 0.2)
			lbl_in.rotation.y = 0.0 if side > 0 else PI
			lbl_in.font_size = 54
			lbl_in.outline_size = 12
			lbl_in.modulate = Color(1.0, 0.94, 0.76)
			add_child(lbl_in)
		# Renkli flama şeridi
		for i in 10:
			var fx := -3.8 + float(i) * 0.84
			var fc: Color = PLASTIC_CRATES[i % PLASTIC_CRATES.size()]
			b.prism(Vector3(0.42, 0.38, 0.03), Vector3(fx, 3.92, gz), fc, Vector3(0, 0, PI), 0.6)
		# Kapı tepesinde dalgalanan Türk bayrakları
		for gx in [-4.35, 4.35]:
			b.cyl(0.03, 0.035, 2.4, Vector3(gx, 6.3, gz), Color(0.85, 0.85, 0.88))
			b.sphere(0.06, Vector3(gx, 7.52, gz), Color(0.95, 0.78, 0.2))
			_add_flag(Vector3(gx, 7.15, gz), 1.35, Vector3(0, PI if gx > 0 else 0.0, 0))


func _add_flag(pole_top: Vector3, w: float, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = LP.flag_mesh(w)
	var m := LP.flag_material(rng.randf() * TAU)
	mi.material_override = m
	_flag_mats.append(m)
	mi.position = pole_top + Vector3(0, -w / 3.0, 0)
	mi.rotation = rot
	add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# Mahalle apartmanları (cephe çerçevesinde parça parça)
# ---------------------------------------------------------------------------

var _wall_mats := {}


func _wall_mat(ci: int) -> StandardMaterial3D:
	if not _wall_mats.has(ci):
		_wall_mats[ci] = LP.mat_tex(WALL_COLS[ci], LP.tex_plaster(), 0.92, Vector3(0.35, 0.35, 0.35), 0.0, true)
	return _wall_mats[ci]


func _build_mahalle_apartments(b, glass, lit, signs) -> void:
	var shop_idx := 0
	for side in [-1.0, 1.0]:
		for z in [-19.0, -10.5, -2.0, 6.5, 15.0, 23.5]:
			var w := rng.randf_range(7.4, 8.2)
			var d := rng.randf_range(7.0, 8.5)
			var floors := rng.randi_range(3, 5)
			var o := Vector3(-side, 0, 0)
			var fc := Vector3(side * 16.15, 0, z)
			_apartment(b, glass, lit, signs, fc, o, w, d, floors, rng.randi() % WALL_COLS.size(), SHOP_NAMES[shop_idx % SHOP_NAMES.size()])
			shop_idx += 1
	# Kuzey ve Güney kapı arkası apartmanlar (kapıya bakar; kapı aksı açık kalır)
	for gz in [-31.0, 31.0]:
		for bx in [-13.5, 13.5]:
			var o2 := Vector3(0, 0, -signf(gz))
			var fc2 := Vector3(bx, 0, gz + o2.z * 3.6)
			var gshop: String = SHOP_NAMES[shop_idx % SHOP_NAMES.size()] if rng.randf() < 0.6 else ""
			_apartment(b, glass, lit, signs, fc2, o2, 9.4, 7.2, rng.randi_range(4, 5), rng.randi() % WALL_COLS.size(), gshop)
			shop_idx += 1


## fc: cephe ortası (zemin), o: cepheden sokağa doğru normal, w: cephe genişliği, d: derinlik.
func _apartment(b, glass, lit, signs, fc: Vector3, o: Vector3, w: float, d: float, floors: int, ci: int, shop: String) -> void:
	var up := Vector3.UP
	var t := o.cross(up)
	var basis := Basis(o, up, t)
	var fr := Transform3D(basis, fc)
	var col: Color = WALL_COLS[ci]
	var h := 3.4 + float(floors - 1) * 2.9 + 0.4
	# Ana kütle (sıvalı doku)
	var mass := MeshInstance3D.new()
	mass.mesh = LP.box(Vector3(d, h, w))
	mass.transform = fr * Transform3D(Basis.IDENTITY, Vector3(-d * 0.5, h * 0.5, 0))
	mass.material_override = _wall_mat(ci)
	add_child(mass)
	for bb in [b, glass, lit, signs]:
		bb.frame = fr
	var trim := col.darkened(0.16)
	var stone := Color(0.62, 0.6, 0.56)
	# Zemin taşı, kat silmeleri, çatı
	b.box(Vector3(d + 0.08, 0.5, w + 0.08), Vector3(-d * 0.5, 0.25, 0), stone)
	for fl in range(1, floors):
		var fy := 3.4 + float(fl - 1) * 2.9
		b.box(Vector3(d + 0.12, 0.14, w + 0.12), Vector3(-d * 0.5, fy, 0), trim)
	b.box(Vector3(d + 0.2, 0.22, w + 0.2), Vector3(-d * 0.5, h - 0.11, 0), trim.darkened(0.05))
	var roof_c := TERRACOTTA.darkened(rng.randf_range(0.0, 0.2))
	var roof_h := rng.randf_range(1.5, 2.1)
	b.prism(Vector3(d + 0.7, roof_h, w + 0.7), Vector3(-d * 0.5, h + roof_h * 0.5, 0), roof_c)
	b.box(Vector3(0.18, 0.12, w + 0.75), Vector3(-d * 0.5, h + roof_h, 0), roof_c.darkened(0.25))
	# Çatı: baca, çanak antenler, güneş enerjili su ısıtıcısı, TV anteni
	var slope_y := func(a: float) -> float:
		return h + roof_h * (1.0 - absf(a + d * 0.5) / ((d + 0.7) * 0.5))
	var chim_b := rng.randf_range(-w * 0.35, w * 0.35)
	b.box(Vector3(0.5, 1.4, 0.5), Vector3(-d * 0.62, slope_y.call(-d * 0.62) + 0.4, chim_b), Color(0.62, 0.36, 0.28))
	b.box(Vector3(0.62, 0.1, 0.62), Vector3(-d * 0.62, slope_y.call(-d * 0.62) + 1.12, chim_b), Color(0.4, 0.4, 0.42))
	for k in rng.randi_range(1, 3):
		var da := -rng.randf_range(0.6, d * 0.42)
		var db := rng.randf_range(-w * 0.4, w * 0.4)
		_dish(b, Vector3(da, slope_y.call(da), db), rng.randf_range(0.35, 0.55))
	if rng.randf() < 0.75:
		var sa := -d * 0.3
		var sy: float = slope_y.call(sa)
		var sb := rng.randf_range(-w * 0.25, w * 0.25)
		b.box(Vector3(1.0, 0.06, 1.6), Vector3(sa, sy + 0.5, sb), Color(0.12, 0.16, 0.3), Vector3(0, 0, 0.55))
		b.cyl(0.22, 0.22, 1.7, Vector3(sa - 0.55, sy + 1.05, sb), Color(0.9, 0.9, 0.9), Vector3(PI / 2, 0, 0), 8)
		b.box(Vector3(0.05, 0.9, 0.05), Vector3(sa + 0.3, sy + 0.4, sb - 0.7), Color(0.6, 0.6, 0.62))
		b.box(Vector3(0.05, 0.9, 0.05), Vector3(sa + 0.3, sy + 0.4, sb + 0.7), Color(0.6, 0.6, 0.62))
	if rng.randf() < 0.5:
		var ab := rng.randf_range(-w * 0.3, w * 0.3)
		b.box(Vector3(0.04, 2.0, 0.04), Vector3(-d * 0.5, h + roof_h + 0.9, ab), Color(0.5, 0.5, 0.52))
		for k in 3:
			b.box(Vector3(0.03, 0.03, 0.9 - float(k) * 0.2), Vector3(-d * 0.5, h + roof_h + 1.2 + float(k) * 0.3, ab), Color(0.5, 0.5, 0.52))

	# ---- Zemin kat: dükkan + apartman kapısı
	var shop_w := w * 0.6
	var shop_b := -w * 0.14
	var door_b := w * 0.33
	if shop != "":
		var sc: Color = SHUTTER_COLS[rng.randi() % SHUTTER_COLS.size()]
		# Vitrin (gece içi ışıklı)
		var shop_glass = lit if rng.randf() < 0.75 else glass
		shop_glass.box(Vector3(0.08, 2.0, shop_w - 0.3), Vector3(0.02, 1.15, shop_b), Color(0.3, 0.32, 0.3))
		b.box(Vector3(0.14, 2.6, 0.14), Vector3(0.05, 1.3, shop_b - shop_w * 0.5), Color(0.25, 0.25, 0.27))
		b.box(Vector3(0.14, 2.6, 0.14), Vector3(0.05, 1.3, shop_b + shop_w * 0.5), Color(0.25, 0.25, 0.27))
		b.box(Vector3(0.1, 0.08, shop_w), Vector3(0.05, 1.0, shop_b), Color(0.25, 0.25, 0.27))
		b.box(Vector3(0.12, 0.1, 0.08), Vector3(0.05, 1.5, shop_b), Color(0.25, 0.25, 0.27))
		# Yarı açık kepenk
		b.box(Vector3(0.12, 0.55, shop_w), Vector3(0.08, 2.45, shop_b), Color(0.66, 0.67, 0.7))
		for k in 4:
			b.box(Vector3(0.13, 0.02, shop_w), Vector3(0.09, 2.22 + float(k) * 0.14, shop_b), Color(0.5, 0.51, 0.54))
		# Tabela (gece kendinden ışıklı)
		signs.box(Vector3(0.16, 0.66, shop_w + 0.5), Vector3(0.12, 3.0, shop_b), sc)
		signs.box(Vector3(0.18, 0.06, shop_w + 0.54), Vector3(0.13, 3.34, shop_b), sc.lightened(0.3))
		var lbl := Label3D.new()
		lbl.text = shop
		lbl.font_size = 46
		lbl.outline_size = 8
		lbl.modulate = Color(1.0, 0.97, 0.88)
		lbl.outline_modulate = sc.darkened(0.5)
		lbl.transform = fr * Transform3D(Basis(up.cross(Vector3.RIGHT), up, Vector3.RIGHT), Vector3(0.22, 3.0, shop_b))
		add_child(lbl)
		# Çizgili tente
		var awn_c: Color = TARP_COLORS[rng.randi() % TARP_COLORS.size()]
		var stripes := int(shop_w / 0.45)
		for k in stripes:
			var zb := shop_b - shop_w * 0.5 + (float(k) + 0.5) * shop_w / float(stripes)
			var cc := awn_c if k % 2 == 0 else Color(0.95, 0.94, 0.9)
			b.box(Vector3(1.15, 0.03, shop_w / float(stripes) + 0.01), Vector3(0.6, 2.55, zb), cc, Vector3(0, 0, -0.38), 0.12)
			b.box(Vector3(0.02, 0.2, shop_w / float(stripes) + 0.01), Vector3(1.13, 2.24, zb), cc, Vector3.ZERO, 0.5)
		_shop_extras(b, signs, fr, shop, shop_b, shop_w)
	else:
		for k in 2:
			var zz := shop_b - shop_w * 0.25 + float(k) * shop_w * 0.5
			b.box(Vector3(0.08, 1.35, 1.05), Vector3(0.03, 1.6, zz), Color(0.92, 0.9, 0.86))
			(lit if rng.randf() < 0.4 else glass).box(Vector3(0.06, 1.2, 0.9), Vector3(0.06, 1.6, zz), Color(0.2, 0.26, 0.32))
			b.box(Vector3(0.05, 1.1, 0.08), Vector3(0.12, 1.6, zz - 0.25), Color(0.25, 0.25, 0.27))
			b.box(Vector3(0.05, 1.1, 0.08), Vector3(0.12, 1.6, zz + 0.25), Color(0.25, 0.25, 0.27))
	# Apartman kapısı + mavi kapı numarası + kapı lambası
	b.box(Vector3(0.1, 2.5, 1.35), Vector3(0.03, 1.25, door_b), Color(0.85, 0.83, 0.78))
	b.box(Vector3(0.08, 2.2, 1.1), Vector3(0.07, 1.1, door_b), Color(0.36, 0.22, 0.14))
	glass.box(Vector3(0.06, 0.7, 0.8), Vector3(0.1, 1.6, door_b), Color(0.25, 0.3, 0.35))
	b.box(Vector3(0.04, 0.2, 0.3), Vector3(0.1, 2.4, door_b + 0.75), Color(0.1, 0.25, 0.65))
	b.box(Vector3(0.6, 0.1, 1.5), Vector3(0.3, 0.05, door_b), stone.lightened(0.1))
	lit.sphere(0.09, Vector3(0.18, 2.6, door_b), Color(0.9, 0.85, 0.7))
	if rng.randf() < 0.6:
		_pot_plant(b, Vector3(0.45, 0.0, door_b + 0.85), rng.randf() < 0.5)

	# ---- Üst katlar: pencereler, balkonlar, klimalar, çamaşırlar
	for fl in range(1, floors):
		var fy := 3.4 + float(fl - 1) * 2.9
		var has_bal := rng.randf() < 0.75
		var slots := [-w * 0.32, 0.0, w * 0.32]
		for si in slots.size():
			var zb: float = slots[si]
			if si == 1 and has_bal:
				_balcony(b, glass, lit, Vector3(0, fy, zb), col)
				continue
			_window(b, glass, lit, Vector3(0, fy, zb), fl == floors - 1)
	for bb in [b, glass, lit, signs]:
		bb.frame = Transform3D.IDENTITY
	# Cephede asılı kocaman bayrak (ara sıra)
	if floors >= 4 and rng.randf() < 0.3:
		var ftop := fr * Vector3(0.0, h - 0.5, -w * 0.32)
		var fm := _add_flag(ftop, 2.6, Vector3.ZERO)
		fm.transform = Transform3D(Basis(-up, t, -up.cross(t)), ftop + o * 0.16)
	# Duvar çarpıştırıcıya gerek yok: sınır duvarları zaten içeride.


func _window(b, glass, lit, base: Vector3, top_floor: bool) -> void:
	var y := base.y + 1.45
	var z := base.z
	b.box(Vector3(0.08, 1.4, 1.1), Vector3(0.03, y, z), Color(0.93, 0.92, 0.88))
	var is_lit := rng.randf() < 0.42
	(lit if is_lit else glass).box(Vector3(0.06, 1.22, 0.92), Vector3(0.06, y, z), Color(0.2, 0.25, 0.3))
	b.box(Vector3(0.04, 1.22, 0.05), Vector3(0.1, y, z), Color(0.93, 0.92, 0.88))
	b.box(Vector3(0.22, 0.07, 1.2), Vector3(0.1, y - 0.72, z), Color(0.88, 0.86, 0.82))
	var r := rng.randf()
	if r < 0.35:
		var sc: Color = [Color(0.24, 0.42, 0.26), Color(0.42, 0.28, 0.18), Color(0.3, 0.42, 0.55)][rng.randi() % 3]
		b.box(Vector3(0.05, 1.32, 0.5), Vector3(0.1, y, z - 0.8), sc)
		b.box(Vector3(0.05, 1.32, 0.5), Vector3(0.1, y, z + 0.8), sc)
	elif r < 0.6:
		# Klima dış ünitesi
		b.box(Vector3(0.36, 0.52, 0.78), Vector3(0.2, y - 1.05, z + 0.15), Color(0.92, 0.92, 0.9))
		b.cyl(0.17, 0.17, 0.02, Vector3(0.39, y - 1.05, z + 0.08), Color(0.3, 0.3, 0.32), Vector3(0, 0, PI / 2), 8)
		b.box(Vector3(0.1, 0.04, 0.04), Vector3(0.1, y - 0.75, z + 0.4), Color(0.85, 0.85, 0.85))
	elif r < 0.8:
		# Pencere önü saksı (sardunya)
		b.box(Vector3(0.24, 0.18, 0.9), Vector3(0.2, y - 0.6, z), Color(0.7, 0.36, 0.22))
		for k in 4:
			b.sphere(0.09, Vector3(0.22, y - 0.45, z - 0.33 + float(k) * 0.22), Color(0.88, 0.16, 0.22) if k % 2 == 0 else Color(0.3, 0.6, 0.25))
	elif not top_floor:
		# Pencere dışı makaralı çamaşır ipi
		_laundry_line(b, Vector3(0.1, y - 0.55, z - 0.7), Vector3(0.1, y - 0.55, z + 0.7), 1.0)
	if rng.randf() < 0.12:
		_dish(b, Vector3(0.35, y - 0.7, z - 0.75), 0.3)


func _balcony(b, glass, lit, base: Vector3, wall: Color) -> void:
	var y := base.y
	var z := base.z
	var bw := 2.6
	b.box(Vector3(1.15, 0.16, bw), Vector3(0.57, y + 0.08, z), wall.darkened(0.1))
	# Balkon kapısı
	b.box(Vector3(0.08, 2.2, 1.05), Vector3(0.03, y + 1.15, z), Color(0.93, 0.92, 0.88))
	(lit if rng.randf() < 0.4 else glass).box(Vector3(0.06, 2.0, 0.88), Vector3(0.06, y + 1.15, z), Color(0.2, 0.25, 0.3))
	# Korkuluk (alt parapet + demir parmaklık)
	var rail := Color(0.2, 0.21, 0.24)
	b.box(Vector3(0.08, 0.36, bw), Vector3(1.1, y + 0.34, z), wall.darkened(0.04))
	b.box(Vector3(0.06, 0.05, bw), Vector3(1.1, y + 1.02, z), rail)
	for k in 9:
		b.box(Vector3(0.025, 0.5, 0.025), Vector3(1.1, y + 0.76, z - bw * 0.5 + 0.1 + float(k) * (bw - 0.2) / 8.0), rail)
	for s in [-1.0, 1.0]:
		b.box(Vector3(1.1, 0.05, 0.05), Vector3(0.57, y + 1.02, z + s * bw * 0.5), rail)
		b.box(Vector3(1.1, 0.36, 0.06), Vector3(0.57, y + 0.34, z + s * bw * 0.5), wall.darkened(0.04))
	var r := rng.randf()
	if r < 0.45:
		# Çamaşır kurutmalığı
		for k in 2:
			_laundry_line(b, Vector3(0.95 - float(k) * 0.3, y + 1.15, z - 1.05), Vector3(0.95 - float(k) * 0.3, y + 1.15, z + 1.05), 0.8)
	elif r < 0.7:
		_pot_plant(b, Vector3(0.75, y + 0.16, z - 0.9), true)
		_pot_plant(b, Vector3(0.75, y + 0.16, z + 0.85), false)
	elif r < 0.85:
		# Plastik sandalye + sehpa (çay keyfi)
		var pc := Color(0.95, 0.95, 0.93)
		b.box(Vector3(0.42, 0.05, 0.42), Vector3(0.6, y + 0.58, z - 0.5), pc)
		b.box(Vector3(0.05, 0.45, 0.42), Vector3(0.38, y + 0.82, z - 0.5), pc)
		b.cyl(0.25, 0.25, 0.04, Vector3(0.62, y + 0.62, z + 0.3), pc, Vector3.ZERO, 8)
		b.cyl(0.03, 0.03, 0.45, Vector3(0.62, y + 0.38, z + 0.3), pc)
	if rng.randf() < 0.35:
		_dish(b, Vector3(1.0, y + 1.2, z + 1.05), 0.32)


func _laundry_line(b, a: Vector3, c: Vector3, sway: float) -> void:
	b.rod(a, c, 0.008, Color(0.85, 0.85, 0.85))
	var n := rng.randi_range(2, 4)
	for k in n:
		var t := (float(k) + 0.5 + rng.randf_range(-0.2, 0.2)) / float(n)
		var p := a.lerp(c, t)
		var cc: Color = CLOTH_COLS[rng.randi() % CLOTH_COLS.size()]
		var kind := rng.randi() % 3
		var sz := Vector3(0.02, 0.5, 0.42) if kind == 0 else (Vector3(0.02, 0.7, 0.36) if kind == 1 else Vector3(0.02, 0.24, 0.14))
		b.box(sz, p + Vector3(0, -sz.y * 0.5, 0), cc, Vector3.ZERO, sway)


func _dish(b, p: Vector3, r: float) -> void:
	b.cyl(0.02, 0.02, 0.4, p + Vector3(0, 0.2, 0), Color(0.6, 0.6, 0.62))
	b.cyl(r, r * 0.25, r * 0.28, p + Vector3(0.05, 0.45, 0), Color(0.9, 0.9, 0.9), Vector3(0, 0, 0.9), 9)
	b.rod(p + Vector3(0.1, 0.42, 0), p + Vector3(0.1 + r * 0.6, 0.45 + r * 0.6, 0), 0.01, Color(0.4, 0.4, 0.42))


func _pot_plant(b, p: Vector3, flowers: bool) -> void:
	if rng.randf() < 0.4:
		# Eski yağ tenekesi saksı
		b.box(Vector3(0.26, 0.34, 0.26), p + Vector3(0, 0.17, 0), Color(0.72, 0.7, 0.66))
		b.box(Vector3(0.27, 0.1, 0.27), p + Vector3(0, 0.2, 0), Color(0.85, 0.65, 0.15))
	else:
		b.cyl(0.18, 0.13, 0.3, p + Vector3(0, 0.15, 0), TERRACOTTA)
	var g := Color(0.26, 0.52, 0.22).darkened(rng.randf_range(0.0, 0.2))
	b.ellipsoid(Vector3(0.22, 0.2, 0.22), p + Vector3(0, 0.45, 0), g, Vector3(0, rng.randf() * 3, 0), 6, 3, 0.15)
	if flowers:
		var fc: Color = [Color(0.9, 0.12, 0.2), Color(0.95, 0.5, 0.7), Color(0.98, 0.9, 0.95)][rng.randi() % 3]
		for k in 4:
			var a := float(k) * TAU / 4.0 + rng.randf()
			b.sphere(0.05, p + Vector3(cos(a) * 0.13, 0.58, sin(a) * 0.13), fc, 5, 3)


func _shop_extras(b, signs, fr: Transform3D, shop: String, sb: float, sw: float) -> void:
	match shop:
		"BERBER":
			var pole := Node3D.new()
			pole.transform = fr * Transform3D(Basis.IDENTITY, Vector3(0.25, 1.9, sb + sw * 0.5 + 0.3))
			add_child(pole)
			var m := LP.mat_tex(Color.WHITE, LP.tex_barber(), 0.3, Vector3(1.0, 1.0, 1.0))
			m.emission_enabled = true
			m.emission = Color(0.3, 0.3, 0.3)
			var mi := LP.add_mat(pole, LP.cyl(0.09, 0.09, 0.8, 10), Vector3.ZERO, m)
			mi.mesh = _smooth_cyl(0.09, 0.8)
			LP.add(pole, LP.sphere(0.11, 8, 4), Vector3(0, 0.45, 0), Color(0.9, 0.9, 0.92), Vector3.ZERO, 0.2, 0.8)
			LP.add(pole, LP.sphere(0.11, 8, 4), Vector3(0, -0.45, 0), Color(0.9, 0.9, 0.92), Vector3.ZERO, 0.2, 0.8)
			_spinners.append(pole)
		"ECZANE":
			# Sokağa dik çıkıntılı kırmızı "E" levhası
			signs.box(Vector3(0.8, 0.8, 0.1), Vector3(0.6, 3.1, sb + sw * 0.5 + 0.6), Color(0.85, 0.08, 0.1))
			for s in [-1.0, 1.0]:
				var e := Label3D.new()
				e.text = "E"
				e.font_size = 96
				e.outline_size = 0
				e.modulate = Color(1, 1, 1)
				e.transform = fr * Transform3D(Basis(Vector3.UP, 0.0 if s > 0 else PI), Vector3(0.6, 3.1, sb + sw * 0.5 + 0.6 + s * 0.06))
				add_child(e)
		"BAKKAL", "BÜFE":
			# Dışarıda kasalar ve su şişeleri, gazete standı
			b.box(Vector3(0.5, 0.6, 1.2), Vector3(0.45, 0.3, sb - sw * 0.3), Color(0.5, 0.36, 0.22))
			for k in 8:
				b.cyl(0.05, 0.05, 0.28, Vector3(0.32 + float(k % 2) * 0.2, 0.74, sb - sw * 0.3 - 0.45 + float(k / 2) * 0.3), Color(0.55, 0.75, 0.95), Vector3.ZERO, 6)
			b.box(Vector3(0.7, 1.1, 0.5), Vector3(0.45, 0.55, sb + sw * 0.25), Color(0.85, 0.12, 0.12))
			signs.box(Vector3(0.05, 0.2, 0.46), Vector3(0.81, 0.95, sb + sw * 0.25), Color(1.0, 0.95, 0.9))
		"ÇİÇEKÇİ":
			for k in 5:
				var p := Vector3(0.5 + float(k % 2) * 0.35, 0.0, sb - sw * 0.35 + float(k) * 0.42)
				b.cyl(0.16, 0.13, 0.36, p + Vector3(0, 0.18, 0), Color(0.3, 0.32, 0.36), Vector3.ZERO, 7)
				var fc: Color = [Color(0.95, 0.2, 0.3), Color(0.98, 0.85, 0.2), Color(0.9, 0.5, 0.85), Color(1, 1, 1), Color(0.95, 0.45, 0.15)][k]
				for j in 6:
					b.sphere(0.06, p + Vector3(rng.randf_range(-0.1, 0.1), 0.5 + rng.randf() * 0.12, rng.randf_range(-0.1, 0.1)), fc, 5, 3)
				b.ellipsoid(Vector3(0.14, 0.12, 0.14), p + Vector3(0, 0.42, 0), Color(0.25, 0.5, 0.22))
		"FIRIN", "BÖREKÇİ":
			# Vitrinde tepsi tepsi ekmek / simit
			b.box(Vector3(0.5, 0.9, sw * 0.6), Vector3(0.35, 0.45, sb), Color(0.6, 0.42, 0.26))
			for k in 6:
				b.ellipsoid(Vector3(0.12, 0.06, 0.22), Vector3(0.35, 0.96, sb - sw * 0.25 + float(k) * sw * 0.1), Color(0.82, 0.56, 0.26))
		"KASAP":
			signs.box(Vector3(0.06, 0.4, 1.2), Vector3(0.15, 1.9, sb), Color(0.9, 0.9, 0.85))
		"KIRAATHANE":
			for k in 2:
				var p := Vector3(1.4, 0.0, sb - 0.8 + float(k) * 1.6)
				b.box(Vector3(0.7, 0.04, 0.7), p + Vector3(0, 0.72, 0), Color(0.75, 0.15, 0.15))
				b.cyl(0.03, 0.04, 0.7, p + Vector3(0, 0.36, 0), Color(0.3, 0.3, 0.3))
				for s in [-1.0, 1.0]:
					b.cyl(0.17, 0.15, 0.04, p + Vector3(s * 0.55, 0.45, 0), Color(0.5, 0.33, 0.2), Vector3.ZERO, 8)
					b.cyl(0.02, 0.02, 0.44, p + Vector3(s * 0.55, 0.22, 0), Color(0.3, 0.3, 0.3))


func _smooth_cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 1
	return c


# ---------------------------------------------------------------------------
# Pazar dağınıklığı, ağaçlar, sokak detayları
# ---------------------------------------------------------------------------

func _build_market_clutter_and_trees(b) -> void:
	var stack_pts := [
		Vector3(-9.8, 0, -11.0), Vector3(9.8, 0, -11.0),
		Vector3(-9.8, 0, 11.0), Vector3(9.8, 0, 11.0),
		Vector3(-9.6, 0, -4.5), Vector3(9.6, 0, -4.5),
		Vector3(-9.6, 0, 4.5), Vector3(9.6, 0, 4.5),
	]
	for sp: Vector3 in stack_pts:
		var cnt := rng.randi_range(2, 4)
		var on_pallet := rng.randf() < 0.5
		var y0 := 0.0
		if on_pallet:
			_pallet(b, sp, rng.randf_range(-0.2, 0.2))
			y0 = 0.14
		var last_yaw := 0.0
		for k in cnt:
			var col: Color = PLASTIC_CRATES[rng.randi() % PLASTIC_CRATES.size()]
			last_yaw = rng.randf_range(-0.25, 0.25)
			var p: Vector3 = sp + Vector3(rng.randf_range(-0.12, 0.12), y0 + 0.16 + float(k) * 0.32, rng.randf_range(-0.12, 0.12))
			_plastic_crate(b, p, col, last_yaw)
		_crate_tops.append([sp + Vector3(0, y0 + float(cnt) * 0.32 + 0.02, 0), last_yaw])
		LP.solid(self, sp + Vector3(0, 0.5, 0), Vector3(0.8, 1.0, 0.8))

	for tp in [
		Vector3(-12.8, 0, -17.5), Vector3(12.8, 0, -17.5),
		Vector3(-12.8, 0, 17.5), Vector3(12.8, 0, 17.5),
		Vector3(-13.2, 0, -5.0), Vector3(13.2, 0, -5.0),
		Vector3(-13.2, 0, 5.0), Vector3(13.2, 0, 5.0),
	]:
		if rng.randf() < 0.38:
			_cypress(b, tp)
		else:
			_tree(b, tp)


func _plastic_crate(b, p: Vector3, c: Color, yaw: float) -> void:
	var r := Vector3(0, yaw, 0)
	var bs := Basis.from_euler(r)
	b.box(Vector3(0.58, 0.04, 0.44), p + bs * Vector3(0, -0.14, 0), c.darkened(0.14), r)
	b.box(Vector3(0.58, 0.28, 0.04), p + bs * Vector3(0, 0, 0.20), c, r)
	b.box(Vector3(0.58, 0.28, 0.04), p + bs * Vector3(0, 0, -0.20), c, r)
	b.box(Vector3(0.04, 0.28, 0.40), p + bs * Vector3(-0.27, 0, 0), c.lightened(0.05), r)
	b.box(Vector3(0.04, 0.28, 0.40), p + bs * Vector3(0.27, 0, 0), c.lightened(0.05), r)
	b.box(Vector3(0.6, 0.04, 0.46), p + bs * Vector3(0, 0.13, 0), c.darkened(0.05), r)


func _pallet(b, p: Vector3, yaw: float) -> void:
	var r := Vector3(0, yaw, 0)
	var bs := Basis.from_euler(r)
	var wc := Color(0.66, 0.5, 0.32)
	for k in 5:
		b.box(Vector3(0.1, 0.025, 1.2), p + bs * Vector3(-0.4 + float(k) * 0.2, 0.125, 0), wc.darkened(rng.randf() * 0.15), r)
	for k in 3:
		b.box(Vector3(1.0, 0.09, 0.1), p + bs * Vector3(0, 0.06, -0.5 + float(k) * 0.5), wc.darkened(0.2), r)


func _decor_stall(p: Vector3, yaw: float) -> void:
	var s := Node3D.new()
	s.position = p
	s.rotation.y = yaw
	add_child(s)
	var wood_m := LP.mat_tex(WOOD, LP.tex_wood(), 0.88, Vector3(2.0, 1.0, 1.0))
	var awn: Color = TARP_COLORS[rng.randi() % TARP_COLORS.size()]
	var awn_m := LP.mat_tex(awn, LP.tex_tarp(), 0.72, Vector3(2.0, 2.0, 1.0))
	awn_m.backlight_enabled = true
	awn_m.backlight = awn * 0.5
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


func _tree(b, p: Vector3) -> void:
	var sc := rng.randf_range(0.9, 1.35)
	var trunk := WOOD.darkened(0.32)
	b.cyl(0.18 * sc, 0.25 * sc, 2.0 * sc, p + Vector3(0, 1.0 * sc, 0), trunk)
	b.cyl(0.07 * sc, 0.1 * sc, 1.0 * sc, p + Vector3(0.3 * sc, 2.2 * sc, 0), trunk, Vector3(0, 0, -0.6))
	b.cyl(0.6 * sc, 0.6 * sc, 0.06, p + Vector3(0, 0.03, 0), Color(0.42, 0.34, 0.26), Vector3.ZERO, 8)
	var g := Color(0.30, 0.55, 0.24).darkened(rng.randf_range(0.0, 0.18))
	var blobs := [[Vector3(0, 2.65, 0), Vector3(1.3, 0.95, 1.3), 0.0], [Vector3(0.55, 3.2, -0.3), Vector3(0.95, 0.78, 0.95), 0.09],
		[Vector3(-0.5, 3.0, 0.35), Vector3(0.85, 0.7, 0.85), -0.06], [Vector3(0.1, 3.6, 0.2), Vector3(0.7, 0.55, 0.7), 0.14],
		[Vector3(-0.2, 2.4, -0.6), Vector3(0.8, 0.6, 0.8), -0.1]]
	for bl in blobs:
		var cc: Color = g.lightened(bl[2]) if float(bl[2]) > 0 else g.darkened(-float(bl[2]))
		b.ellipsoid(bl[1] * sc, p + bl[0] * sc, cc, Vector3(0, rng.randf() * 3, 0), 7, 4, 0.12)
	LP.solid(self, p + Vector3(0, 1.2, 0), Vector3(0.5, 2.4, 0.5))


func _cypress(b, p: Vector3) -> void:
	var sc := rng.randf_range(0.95, 1.35)
	b.cyl(0.11 * sc, 0.16 * sc, 1.2 * sc, p + Vector3(0, 0.6 * sc, 0), WOOD.darkened(0.35))
	var g := Color(0.18, 0.42, 0.22).darkened(rng.randf_range(0.0, 0.15))
	b.cyl(0.45 * sc, 0.62 * sc, 2.1 * sc, p + Vector3(0, 1.95 * sc, 0), g)
	b.cyl(0.02 * sc, 0.48 * sc, 2.3 * sc, p + Vector3(0, 4.15 * sc, 0), g.lightened(0.06))
	LP.solid(self, p + Vector3(0, 1.0, 0), Vector3(0.42, 2.0, 0.42))


## Yerdeki yapraklar, kağıtlar, poşetler, park halindeki kurye motoru, çöp konteyneri, bank, saksılar...
func _build_street_details(b) -> void:
	# Saçılmış yapraklar, gazete kağıtları, soğan kabukları, plastik bardaklar
	for i in 70:
		var on_street := i < 40
		var lx := rng.randf_range(-4.0, 4.0) if on_street else (rng.randf_range(5.0, 13.5) * (1.0 if rng.randf() < 0.5 else -1.0))
		if on_street and rng.randf() < 0.6:
			lx = (3.6 + rng.randf() * 0.4) * (1.0 if rng.randf() < 0.5 else -1.0) # bordür diplerinde birikir
		var lz := rng.randf_range(-20.0, 20.0)
		var y := 0.012 if on_street else 0.05
		var r := rng.randf()
		var rot := Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))
		if r < 0.5:
			var lc: Color = [Color(0.3, 0.55, 0.22), Color(0.78, 0.55, 0.2), Color(0.62, 0.38, 0.16), Color(0.82, 0.7, 0.3)][rng.randi() % 4]
			b.box(Vector3(0.13, 0.008, 0.07), Vector3(lx, y, lz), lc, rot)
		elif r < 0.78:
			b.box(Vector3(0.22, 0.006, 0.16), Vector3(lx, y, lz), Color(0.88, 0.87, 0.82).darkened(rng.randf() * 0.2), rot)
		elif r < 0.9:
			b.cyl(0.035, 0.028, 0.09, Vector3(lx, y + 0.03, lz), Color(0.95, 0.95, 0.95), Vector3(PI / 2, rot.y, 0), 6)
		else:
			b.ellipsoid(Vector3(0.05, 0.01, 0.04), Vector3(lx, y, lz), Color(0.85, 0.6, 0.45), rot, 5, 2)

	# Paletler (boş ve yığılı)
	for pp in [Vector3(-12.0, 0.04, -8.5), Vector3(12.2, 0.04, -8.8), Vector3(-12.4, 0.04, 9.0)]:
		_pallet(b, pp, rng.randf_range(-0.4, 0.4))
		if rng.randf() < 0.6:
			_pallet(b, pp + Vector3(0, 0.15, 0), rng.randf_range(-0.4, 0.4))
		LP.solid(self, pp + Vector3(0, 0.15, 0), Vector3(1.1, 0.3, 1.1))

	# Kurye motoru (scooter) - batı arka kaldırım
	_scooter(b, Vector3(-12.2, 0.04, 12.6), 0.4, Color(0.82, 0.12, 0.1), true)
	_scooter(b, Vector3(15.2, 0.04, -14.0), PI * 0.5, Color(0.15, 0.3, 0.6), false)
	LP.solid(self, Vector3(-12.2, 0.5, 12.6), Vector3(0.8, 1.0, 1.8), 0.4)

	# Çöp konteyneri (kedilerin favori yeri)
	var cp := Vector3(-13.0, 0.04, -19.6)
	b.box(Vector3(1.6, 1.0, 1.1), cp + Vector3(0, 0.62, 0), Color(0.28, 0.42, 0.3))
	b.box(Vector3(1.66, 0.08, 1.16), cp + Vector3(0, 1.16, 0), Color(0.22, 0.34, 0.24), Vector3(0.06, 0, 0))
	for sx in [-0.6, 0.6]:
		for sz in [-0.4, 0.4]:
			b.cyl(0.07, 0.07, 0.06, cp + Vector3(sx, 0.08, sz), Color(0.1, 0.1, 0.1), Vector3(0, 0, PI / 2), 6)
	b.box(Vector3(0.3, 0.02, 0.5), cp + Vector3(0.9, 0.05, 0.6), Color(0.9, 0.9, 0.88), Vector3(0, 0.6, 0))
	LP.solid(self, cp + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.1))
	_crate_tops.append([cp + Vector3(0.2, 1.22, 0), 0.4])

	# Ağaç altı tahta bank
	for bp in [[Vector3(-12.2, 0.04, 2.0), PI / 2], [Vector3(12.4, 0.04, -2.4), -PI / 2]]:
		var p: Vector3 = bp[0]
		var yaw: float = bp[1]
		var bs := Basis(Vector3.UP, yaw)
		var r := Vector3(0, yaw, 0)
		for k in 3:
			b.box(Vector3(1.6, 0.04, 0.12), p + bs * Vector3(0, 0.45, -0.15 + float(k) * 0.15), Color(0.55, 0.36, 0.2), r)
		for k in 2:
			b.box(Vector3(1.6, 0.12, 0.04), p + bs * Vector3(0, 0.7 + float(k) * 0.16, -0.25), Color(0.55, 0.36, 0.2), r + Vector3(-0.15, 0, 0))
		for sx in [-0.7, 0.7]:
			b.box(Vector3(0.06, 0.45, 0.4), p + bs * Vector3(sx, 0.22, -0.05), Color(0.15, 0.15, 0.16), r)
		LP.solid(self, p + Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 1.6) if absf(sin(yaw)) > 0.5 else Vector3(1.6, 0.8, 0.6))

	# Saksılar (kaldırım kenarı)
	for pp in [Vector3(-13.6, 0.04, -10.6), Vector3(13.7, 0.04, 8.0), Vector3(13.7, 0.04, 14.6), Vector3(-13.7, 0.04, 15.8), Vector3(-13.7, 0.04, -1.0)]:
		_pot_plant(b, pp, rng.randf() < 0.6)

	# Elektrik / aydınlatma direği tabanları ve yangın musluğu
	b.cyl(0.12, 0.14, 0.7, Vector3(-4.7, 0.35, 19.0), Color(0.75, 0.12, 0.1), Vector3.ZERO, 8)
	b.sphere(0.13, Vector3(-4.7, 0.72, 19.0), Color(0.75, 0.12, 0.1), 8, 4)


func _scooter(b, p: Vector3, yaw: float, c: Color, delivery_box: bool) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var r := Vector3(0, yaw, 0)
	var tire := Color(0.08, 0.08, 0.09)
	for wz in [-0.62, 0.62]:
		b.cyl(0.24, 0.24, 0.1, p + bs * Vector3(0, 0.24, wz), tire, r + Vector3(0, 0, PI / 2), 12)
		b.cyl(0.12, 0.12, 0.11, p + bs * Vector3(0, 0.24, wz), Color(0.7, 0.7, 0.72), r + Vector3(0, 0, PI / 2), 8)
	b.box(Vector3(0.36, 0.12, 0.9), p + bs * Vector3(0, 0.36, 0.05), Color(0.15, 0.15, 0.16), r)
	b.box(Vector3(0.38, 0.42, 0.62), p + bs * Vector3(0, 0.6, 0.32), c, r)
	b.box(Vector3(0.32, 0.12, 0.6), p + bs * Vector3(0, 0.86, 0.3), Color(0.1, 0.1, 0.1), r)
	b.box(Vector3(0.4, 0.75, 0.16), p + bs * Vector3(0, 0.72, -0.5), c, r + Vector3(-0.25, 0, 0))
	b.cyl(0.025, 0.025, 0.6, p + bs * Vector3(0, 1.1, -0.58), Color(0.3, 0.3, 0.32), r + Vector3(-0.25, 0, 0))
	b.box(Vector3(0.7, 0.04, 0.04), p + bs * Vector3(0, 1.38, -0.65), Color(0.15, 0.15, 0.15), r)
	b.sphere(0.07, p + bs * Vector3(0, 1.25, -0.72), Color(0.95, 0.95, 0.85))
	b.box(Vector3(0.5, 0.42, 0.06), p + bs * Vector3(0, 1.25, -0.6), Color(0.6, 0.7, 0.8), r + Vector3(-0.3, 0, 0))
	if delivery_box:
		b.box(Vector3(0.5, 0.45, 0.48), p + bs * Vector3(0, 1.15, 0.5), Color(0.95, 0.75, 0.1), r)
		b.box(Vector3(0.51, 0.08, 0.49), p + bs * Vector3(0, 1.32, 0.5), Color(0.85, 0.15, 0.1), r)


## Köşedeki çay ocağı: semaver, ince belli bardaklar, tabureler, minik masalar, tüp.
func _build_cay_ocagi(b) -> void:
	var p := Vector3(12.6, 0.04, 11.2)
	var bs := Basis(Vector3.UP, -PI / 2)
	var r := Vector3(0, -PI / 2, 0)
	var wood := Color(0.5, 0.32, 0.18)
	# Tezgah kulübesi
	b.box(Vector3(2.4, 1.0, 0.8), p + bs * Vector3(0, 0.5, 0), wood, r)
	b.box(Vector3(2.5, 0.06, 0.9), p + bs * Vector3(0, 1.03, 0), Color(0.75, 0.72, 0.68), r)
	for sx in [-1.15, 1.15]:
		b.box(Vector3(0.08, 2.4, 0.08), p + bs * Vector3(sx, 1.2, -0.35), wood.darkened(0.2), r)
		b.box(Vector3(0.08, 2.2, 0.08), p + bs * Vector3(sx, 1.1, 0.75), wood.darkened(0.2), r)
	b.box(Vector3(2.7, 0.05, 1.6), p + bs * Vector3(0, 2.35, 0.25), Color(0.75, 0.15, 0.12), r + Vector3(0.12, 0, 0))
	b.box(Vector3(2.7, 0.22, 0.03), p + bs * Vector3(0, 2.15, 1.05), Color(0.95, 0.92, 0.85), r, 0.3)
	# Semaver
	var sp := p + bs * Vector3(-0.7, 1.06, 0.0)
	var chrome := Color(0.82, 0.82, 0.84)
	b.cyl(0.2, 0.24, 0.42, sp + Vector3(0, 0.21, 0), chrome, Vector3.ZERO, 10)
	b.cyl(0.12, 0.2, 0.1, sp + Vector3(0, 0.47, 0), chrome, Vector3.ZERO, 10)
	b.cyl(0.11, 0.08, 0.16, sp + Vector3(0, 0.6, 0), Color(0.85, 0.55, 0.3), Vector3.ZERO, 8)
	b.cyl(0.06, 0.1, 0.1, sp + Vector3(0, 0.72, 0), Color(0.85, 0.85, 0.85), Vector3.ZERO, 8)
	b.box(Vector3(0.12, 0.03, 0.03), sp + bs * Vector3(0, 0.12, 0.25), chrome, r)
	# Tepsi + ince belli bardaklar
	var tp := p + bs * Vector3(0.3, 1.07, 0.1)
	b.cyl(0.25, 0.25, 0.02, tp, Color(0.8, 0.78, 0.74), Vector3.ZERO, 12)
	for k in 5:
		var a := float(k) * TAU / 5.0
		var gp := tp + Vector3(cos(a) * 0.14, 0.05, sin(a) * 0.14)
		b.cyl(0.026, 0.02, 0.08, gp, Color(0.7, 0.22, 0.08), Vector3.ZERO, 6)
		b.cyl(0.035, 0.035, 0.008, gp + Vector3(0, -0.045, 0), Color(0.9, 0.9, 0.95), Vector3.ZERO, 6)
	# Tüp
	b.cyl(0.16, 0.16, 0.6, p + bs * Vector3(1.4, 0.3, -0.2), Color(0.15, 0.35, 0.75), Vector3.ZERO, 8)
	b.cyl(0.05, 0.08, 0.1, p + bs * Vector3(1.4, 0.65, -0.2), Color(0.5, 0.5, 0.52), Vector3.ZERO, 6)
	# Masalar ve tabureler
	for tz in [[-0.6, 1.7], [0.9, 2.1]]:
		var mp: Vector3 = p + bs * Vector3(float(tz[0]), 0, float(tz[1]))
		b.box(Vector3(0.55, 0.04, 0.55), mp + Vector3(0, 0.55, 0), Color(0.62, 0.45, 0.28))
		b.cyl(0.03, 0.04, 0.53, mp + Vector3(0, 0.27, 0), Color(0.25, 0.25, 0.25))
		b.cyl(0.026, 0.02, 0.08, mp + Vector3(0.1, 0.61, 0.05), Color(0.7, 0.22, 0.08), Vector3.ZERO, 6)
		for k in 3:
			var a := float(k) * TAU / 3.0 + 0.5
			var st := mp + Vector3(cos(a) * 0.55, 0, sin(a) * 0.55)
			b.cyl(0.15, 0.15, 0.04, st + Vector3(0, 0.33, 0), Color(0.55, 0.35, 0.2), Vector3.ZERO, 8)
			for j in 3:
				var la := float(j) * TAU / 3.0
				b.cyl(0.015, 0.015, 0.33, st + Vector3(cos(la) * 0.1, 0.16, sin(la) * 0.1), Color(0.4, 0.26, 0.15), Vector3.ZERO, 4)
		if tz[0] < 0.0:
			_crate_tops.append([mp + Vector3(cos(0.5) * 0.55, 0.36, sin(0.5) * 0.55), 1.2])
	LP.solid(self, p + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 2.5))
	var lbl := Label3D.new()
	lbl.text = "ÇAY OCAĞI"
	lbl.font_size = 40
	lbl.outline_size = 8
	lbl.modulate = Color(1.0, 0.95, 0.85)
	lbl.outline_modulate = Color(0.45, 0.08, 0.05)
	lbl.position = p + bs * Vector3(0, 2.15, 1.08)
	lbl.rotation.y = -PI / 2
	add_child(lbl)
	_pot_plant(b, p + bs * Vector3(-1.5, 0, 0.9), true)
	_pot_plant(b, p + bs * Vector3(1.6, 0, 1.0), false)
	# Semaver buharı
	VFX.spawn_steam(self, sp + Vector3(0, 0.82, 0), 0.8)
	set_meta("cay_pos", p + bs * Vector3(0, 0, 1.2))


## Akşam yanan mahalle sokak lambaları (eğik kollu belediye direkleri).
func _build_lamp_posts(b) -> void:
	var head_mat := LP.mat(Color(1.0, 0.9, 0.7), 0.2)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.72, 0.4)
	head_mat.emission_energy_multiplier = 0.3
	_bulb_mats.append(head_mat)
	var pole_c := Color(0.22, 0.24, 0.27)
	for lp in [Vector3(-14.0, 0, -12.6), Vector3(14.0, 0, -12.6), Vector3(-14.0, 0, 0.4),
			Vector3(14.0, 0, 0.6), Vector3(-14.0, 0, 7.6), Vector3(14.0, 0, 17.6),
			Vector3(-4.75, 0, -19.4), Vector3(4.75, 0, 19.4)]:
		var dir := Vector3(-signf(lp.x), 0, 0)
		b.cyl(0.07, 0.1, 5.6, lp + Vector3(0, 2.8, 0), pole_c, Vector3.ZERO, 8)
		b.cyl(0.16, 0.18, 0.5, lp + Vector3(0, 0.25, 0), pole_c, Vector3.ZERO, 8)
		b.rod(lp + Vector3(0, 5.5, 0), lp + dir * 1.1 + Vector3(0, 5.75, 0), 0.04, pole_c)
		b.box(Vector3(0.5, 0.12, 0.3), lp + dir * 1.15 + Vector3(0, 5.72, 0), pole_c)
		LP.add_mat(self, LP.box(Vector3(0.36, 0.06, 0.22)), lp + dir * 1.15 + Vector3(0, 5.64, 0), head_mat)
		var ol := OmniLight3D.new()
		ol.position = lp + dir * 1.15 + Vector3(0, 5.4, 0)
		ol.light_color = Color(1.0, 0.72, 0.42)
		ol.omni_range = 11.0
		ol.omni_attenuation = 1.2
		ol.set_meta("base", 3.0)
		ol.light_volumetric_fog_energy = 1.2
		add_child(ol)
		_street_lights.append(ol)
		LP.solid(self, lp + Vector3(0, 1.5, 0), Vector3(0.3, 3.0, 0.3))


## Meydan üstü ay-yıldızlı flamalar ve binalar arası sarkan elektrik kabloları.
func _build_bunting_and_cables(b) -> void:
	for bz in [-3.2, -0.6, 2.4]:
		var a := Vector3(-16.1, 7.2 + rng.randf() * 0.6, bz)
		var c := Vector3(16.1, 7.0 + rng.randf() * 0.6, bz + rng.randf_range(-1.5, 1.5))
		var sag := 1.4
		b.wire(a, c, sag, 0.012, Color(0.15, 0.15, 0.15), 10)
		var n := 34
		for k in range(1, n):
			var t := float(k) / float(n)
			var pp := a.lerp(c, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
			var cc := Color(0.89, 0.05, 0.1) if k % 2 == 0 else Color(0.97, 0.97, 0.97)
			if bz > 2.0:
				cc = PLASTIC_CRATES[k % PLASTIC_CRATES.size()]
			b.prism(Vector3(0.36, 0.42, 0.02), pp + Vector3(0, -0.22, 0), cc, Vector3(0, atan2(c.z - a.z, c.x - a.x) * -1.0, PI), 0.5)
	# Dağınık elektrik/telefon kabloları
	for i in 6:
		var z0 := rng.randf_range(-22.0, 24.0)
		var a2 := Vector3(-16.1, rng.randf_range(8.0, 10.5), z0)
		var c2 := Vector3(16.1, rng.randf_range(8.0, 10.5), z0 + rng.randf_range(-5.0, 5.0))
		if absf(z0) < 5.0:
			continue
		b.wire(a2, c2, rng.randf_range(0.6, 1.4), 0.014, Color(0.08, 0.08, 0.09), 8)


# ---------------------------------------------------------------------------
# Uzak şehir silüeti, cami & minareler, evli tepeler
# ---------------------------------------------------------------------------

func _build_skyline() -> void:
	var far := LP.batch()
	var far_lit := LP.batch()
	var mid := LP.batch()
	var mid_glass := LP.batch()
	var mid_lit := LP.batch()
	# Orta halka: yakın sıraların arkasında yükselen apartmanlar (sokaktan görünür katman)
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 600:
		tries += 1
		var x := rng.randf_range(-62.0, 62.0)
		var z := rng.randf_range(-70.0, 70.0)
		if absf(x) < 33.0 and absf(z) < 42.0:
			continue
		if absf(x) < 19.0 and z < -36.0:
			continue # caminin önü açık kalsın
		if Vector2(x, z + 92.0).length() < 26.0:
			continue
		var fl := rng.randi_range(5, 9)
		_mid_building(mid, mid_glass, mid_lit, Vector3(x, 0, z), fl)
		placed += 1
	# Uzak halka: sade, yüksek bloklar
	for i in 120:
		var a := rng.randf() * TAU
		var r := rng.randf_range(72.0, 112.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x, z + 92.0).length() < 30.0 or (absf(x) < 14.0 and z < -60.0):
			continue
		var w := rng.randf_range(6.0, 12.0)
		var d := rng.randf_range(6.0, 12.0)
		var h := float(rng.randi_range(4, 12)) * 3.0
		var c: Color = WALL_COLS[rng.randi() % WALL_COLS.size()].lerp(Color(0.8, 0.8, 0.82), 0.3)
		far.box(Vector3(w, h, d), Vector3(x, h * 0.5, z), c, Vector3(0, a, 0))
		if rng.randf() < 0.55:
			far.prism(Vector3(w + 0.4, 2.0, d + 0.4), Vector3(x, h + 1.0, z), TERRACOTTA.darkened(rng.randf() * 0.2), Vector3(0, a, 0))
		else:
			far.cyl(0.8, 0.8, 1.6, Vector3(x, h + 0.8, z), Color(0.85, 0.85, 0.85), Vector3.ZERO, 6)
		# Gece pencere ışıkları (merkeze bakan yüzde nokta nokta)
		var face := Vector3(-cos(a), 0, -sin(a))
		var tang := Vector3(-face.z, 0, face.x)
		var face_off := _box_face_offset(face, a, w, d)
		for k in int(h / 3.0) * 2:
			if rng.randf() < 0.35:
				var fy := 1.8 + float(k / 2) * 3.0
				var off := (rng.randf() - 0.5) * w * 0.8
				var pos := Vector3(x, fy, z) + face_off + tang * off
				far_lit.box(Vector3(0.9, 1.0, 0.9), pos, Color(0.25, 0.25, 0.3), Vector3(0, a, 0))
	_mosque(far, far_lit, Vector3(0, 0, -92), 1.0, true)
	_mosque(far, far_lit, Vector3(-58, 0, 96), 0.6, false)
	_hills(far)
	_commit(mid, 0.9, true, 0.0)
	_commit(mid_glass, 0.15, false, 0.0, 0.3)
	_win_mats.append(_commit_lit(mid_lit, Color(1.0, 0.75, 0.42)))
	var fm := _commit(far, 0.95, false, 0.0)
	if fm:
		fm.extra_cull_margin = 10.0
	_win_mats.append(_commit_lit(far_lit, Color(1.0, 0.8, 0.5)))


func _box_face_offset(face: Vector3, a: float, w: float, d: float) -> Vector3:
	# Döndürülmüş kutunun merkeze bakan yüzüne yaklaşık mesafe
	var bs := Basis(Vector3.UP, -a)
	var lf := bs * face
	var ext := absf(lf.x) * w * 0.5 + absf(lf.z) * d * 0.5
	return face * (ext * 0.98)


func _mid_building(b, glass, lit, p: Vector3, floors: int) -> void:
	var w := rng.randf_range(8.0, 12.0)
	var d := rng.randf_range(8.0, 11.0)
	var h := float(floors) * 2.9 + 0.6
	var col: Color = WALL_COLS[rng.randi() % WALL_COLS.size()]
	# Merkeze (pazara) bakan cephe
	var to_c := Vector3(-p.x, 0, -p.z)
	var o := Vector3(signf(to_c.x), 0, 0) if absf(p.x) > absf(p.z) * 0.55 else Vector3(0, 0, signf(to_c.z))
	var basis := Basis(o, Vector3.UP, o.cross(Vector3.UP))
	var fr := Transform3D(basis, p + o * d * 0.5)
	for bb in [b, glass, lit]:
		bb.frame = fr
	b.box(Vector3(d, h, w), Vector3(-d * 0.5, h * 0.5, 0), col)
	for fl in range(1, floors):
		b.box(Vector3(d + 0.1, 0.12, w + 0.1), Vector3(-d * 0.5, float(fl) * 2.9 + 0.3, 0), col.darkened(0.15))
	if rng.randf() < 0.6:
		var rh := rng.randf_range(1.6, 2.4)
		b.prism(Vector3(d + 0.6, rh, w + 0.6), Vector3(-d * 0.5, h + rh * 0.5, 0), TERRACOTTA.darkened(rng.randf() * 0.22))
	else:
		b.box(Vector3(d + 0.2, 0.5, w + 0.2), Vector3(-d * 0.5, h + 0.25, 0), col.darkened(0.2))
		b.cyl(0.6, 0.6, 1.4, Vector3(-d * 0.6, h + 1.2, w * 0.2), Color(0.9, 0.9, 0.9), Vector3(PI / 2, 0, 0), 8)
		for k in rng.randi_range(1, 3):
			_dish(b, Vector3(-rng.randf_range(0.8, d - 0.8), h + 0.5, rng.randf_range(-w * 0.4, w * 0.4)), 0.45)
	var cols_n := int(w / 2.2)
	for fl in floors:
		var fy := float(fl) * 2.9 + 1.6
		var bal := fl > 0 and rng.randf() < 0.5
		for k in cols_n:
			var zb := -w * 0.5 + (float(k) + 0.5) * w / float(cols_n)
			(lit if rng.randf() < 0.3 else glass).box(Vector3(0.1, 1.2, 0.95), Vector3(0.02, fy, zb), Color(0.22, 0.27, 0.32))
			if bal and k % 2 == 0:
				b.box(Vector3(0.9, 0.12, 1.9), Vector3(0.45, fy - 1.15, zb), col.darkened(0.1))
				b.box(Vector3(0.06, 0.8, 1.9), Vector3(0.88, fy - 0.7, zb), Color(0.25, 0.26, 0.3))
				if rng.randf() < 0.35:
					var cc: Color = CLOTH_COLS[rng.randi() % CLOTH_COLS.size()]
					b.box(Vector3(0.03, 0.55, 1.4), Vector3(0.9, fy - 0.25, zb), cc, Vector3.ZERO, 0.6)
	if rng.randf() < 0.15:
		var ftop := fr * Vector3(0.1, h + 3.0, 0)
		b.frame = Transform3D.IDENTITY
		b.cyl(0.05, 0.06, 3.0, ftop + Vector3(0, -1.5, 0), Color(0.85, 0.85, 0.88))
		_add_flag(ftop, 2.0, Vector3(0, rng.randf() * TAU, 0))
	for bb in [b, glass, lit]:
		bb.frame = Transform3D.IDENTITY


## Klasik Osmanlı camisi: kare harim, sekizgen kasnak, kurşun kaplı ana kubbe, yarım kubbeler,
## son cemaat yeri kubbecikleri, kalem uçlu minareler ve şerefe ışıkları (gece).
func _mosque(b, lit, c: Vector3, s: float, two_minarets: bool) -> void:
	var stone := Color(0.88, 0.85, 0.78)
	var lead := Color(0.5, 0.55, 0.6)
	var gold := Color(0.95, 0.75, 0.25)
	# Avlu duvarı
	b.box(Vector3(46, 3.2, 1.0) * s, c + Vector3(0, 1.6, 22) * s, stone.darkened(0.1))
	b.box(Vector3(1.0, 3.2, 36) * s, c + Vector3(-23, 1.6, 4) * s, stone.darkened(0.1))
	b.box(Vector3(1.0, 3.2, 36) * s, c + Vector3(23, 1.6, 4) * s, stone.darkened(0.1))
	# Harim
	b.box(Vector3(24, 10, 22) * s, c + Vector3(0, 5, 0) * s, stone)
	b.box(Vector3(24.6, 0.6, 22.6) * s, c + Vector3(0, 10.2, 0) * s, stone.darkened(0.08))
	# Kasnak + ana kubbe + alem
	b.cyl(8.6 * s, 9.0 * s, 3.2 * s, c + Vector3(0, 12.0, 0) * s, stone, Vector3.ZERO, 16)
	b.dome(Vector3(8.4, 7.6, 8.4) * s, c + Vector3(0, 13.5, 0) * s, lead, 18, 6)
	b.cyl(0.35 * s, 0.45 * s, 2.2 * s, c + Vector3(0, 22.1, 0) * s, gold, Vector3.ZERO, 6)
	b.sphere(0.6 * s, c + Vector3(0, 23.4, 0) * s, gold, 6, 4)
	# Kasnak pencereleri (koyu)
	for k in 16:
		var a := float(k) * TAU / 16.0
		b.box(Vector3(0.3, 1.6, 1.0) * s, c + Vector3(cos(a) * 8.85, 12.2, sin(a) * 8.85) * s, Color(0.25, 0.28, 0.32), Vector3(0, -a, 0))
	# Köşe kuleleri ve yarım kubbeler
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var kp := c + Vector3(sx * 10.5, 0, sz * 9.5) * s
			b.cyl(1.0 * s, 1.2 * s, 3.0 * s, kp + Vector3(0, 11.5, 0) * s, stone, Vector3.ZERO, 8)
			b.cyl(0.05 * s, 1.15 * s, 2.4 * s, kp + Vector3(0, 14.2, 0) * s, lead, Vector3.ZERO, 8)
		b.dome(Vector3(4.8, 4.2, 4.8) * s, c + Vector3(sx * 8.4, 10.4, 0) * s, lead, 12, 4)
	b.dome(Vector3(4.8, 4.2, 4.8) * s, c + Vector3(0, 10.4, 8.0) * s, lead, 12, 4)
	# Son cemaat yeri (revak + 5 kubbecik)
	b.box(Vector3(24, 6.4, 5.0) * s, c + Vector3(0, 3.2, 13.5) * s, stone.darkened(0.03))
	for k in 5:
		var px := (-9.6 + float(k) * 4.8) * s
		b.dome(Vector3(2.2, 2.0, 2.2) * s, c + Vector3(px / s, 6.4, 13.5) * s, lead, 10, 3)
		b.box(Vector3(3.0, 4.2, 0.3) * s, c + Vector3(px / s, 2.4, 16.05) * s, Color(0.3, 0.3, 0.34))
	# Minareler
	var mxs := [-14.5, 14.5] if two_minarets else [14.5]
	for mx in mxs:
		var mp := c + Vector3(mx, 0, 10.0) * s
		b.box(Vector3(3.0, 7.0, 3.0) * s, mp + Vector3(0, 3.5, 0) * s, stone)
		b.cyl(1.25 * s, 1.5 * s, 3.0 * s, mp + Vector3(0, 8.5, 0) * s, stone, Vector3.ZERO, 12)
		b.cyl(1.05 * s, 1.25 * s, 30.0 * s, mp + Vector3(0, 25.0, 0) * s, stone.lightened(0.05), Vector3.ZERO, 12)
		for sy in [27.0, 35.0]:
			b.cyl(1.9 * s, 1.15 * s, 1.1 * s, mp + Vector3(0, sy, 0) * s, stone.darkened(0.06), Vector3.ZERO, 12)
			b.cyl(1.95 * s, 1.95 * s, 0.6 * s, mp + Vector3(0, sy + 0.85, 0) * s, stone.darkened(0.12), Vector3.ZERO, 12)
			for k in 12:
				var a := float(k) * TAU / 12.0
				lit.sphere(0.22 * s, mp + Vector3(cos(a) * 2.0, sy + 1.3, sin(a) * 2.0) * s, Color(0.9, 0.85, 0.7), 4, 2)
		b.cyl(1.05 * s, 1.05 * s, 3.0 * s, mp + Vector3(0, 38.0, 0) * s, stone.lightened(0.05), Vector3.ZERO, 12)
		b.cyl(0.02 * s, 1.2 * s, 7.5 * s, mp + Vector3(0, 43.25, 0) * s, lead, Vector3.ZERO, 12)
		b.cyl(0.12 * s, 0.12 * s, 1.6 * s, mp + Vector3(0, 47.6, 0) * s, gold, Vector3.ZERO, 5)
		b.sphere(0.3 * s, mp + Vector3(0, 48.1, 0) * s, gold, 5, 3)
	# Mahya ışıkları (iki minare arası) — gece "HOŞ GELDİN" havası
	if two_minarets:
		var a := c + Vector3(-14.5, 34.0, 10.0) * s
		var e := c + Vector3(14.5, 34.0, 10.0) * s
		for k in 40:
			var t := float(k) / 39.0
			var pp := a.lerp(e, t) + Vector3.DOWN * 3.0 * s * 4.0 * t * (1.0 - t)
			lit.sphere(0.16 * s, pp, Color(0.9, 0.85, 0.7), 4, 2)
	# Selviler
	for k in 6:
		var tp := c + Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(16, 20)) * s
		var g := Color(0.16, 0.36, 0.2)
		b.cyl(0.9 * s, 1.3 * s, 5.0 * s, tp + Vector3(0, 3.0, 0) * s, g, Vector3.ZERO, 7)
		b.cyl(0.05 * s, 0.9 * s, 5.0 * s, tp + Vector3(0, 8.0, 0) * s, g.lightened(0.05), Vector3.ZERO, 7)


func _hill_h(x: float, z: float, nz: FastNoiseLite) -> float:
	var r := Vector2(x, z).length()
	var k := smoothstep(112.0, 175.0, r)
	var n := nz.get_noise_2d(x, z) * 0.5 + 0.5
	return k * (12.0 + n * 46.0) - 2.0 + (1.0 - k) * 0.0


## Halka şeklinde, düz gölgeli, evlerle kaplı tepeler (İstanbul yamaçları).
func _hills(b) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = 1923
	nz.frequency = 0.012
	nz.fractal_octaves = 3
	var rings := [108.0, 125.0, 145.0, 170.0, 200.0, 240.0, 300.0]
	var segs := 72
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var grid := []
	for ri in rings.size():
		var row := []
		for si in segs:
			var a := float(si) / float(segs) * TAU
			var rr: float = rings[ri] * (1.0 + sin(a * 3.0 + float(ri)) * 0.03)
			var x := cos(a) * rr
			var z := sin(a) * rr
			row.append(Vector3(x, _hill_h(x, z, nz), z))
		grid.append(row)
	for ri in rings.size() - 1:
		for si in segs:
			var p00: Vector3 = grid[ri][si]
			var p01: Vector3 = grid[ri][(si + 1) % segs]
			var p10: Vector3 = grid[ri + 1][si]
			var p11: Vector3 = grid[ri + 1][(si + 1) % segs]
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				var v0: Vector3 = tri[0]; var v1: Vector3 = tri[1]; var v2: Vector3 = tri[2]
				var n := (v2 - v0).cross(v1 - v0).normalized()
				if n.y < 0.0:
					n = -n
					var tmp := v1; v1 = v2; v2 = tmp
				var hy := (v0.y + v1.y + v2.y) / 3.0
				var gk := clampf(hy / 50.0, 0.0, 1.0)
				var c := Color(0.42, 0.5, 0.3).lerp(Color(0.58, 0.54, 0.42), gk).darkened(float((si * 7 + ri * 3) % 5) * 0.02)
				verts.append_array([v0, v1, v2])
				norms.append_array([n, n, n])
				cols.append_array([Color(c.r, c.g, c.b, 0), Color(c.r, c.g, c.b, 0), Color(c.r, c.g, c.b, 0)])
	b.verts.append_array(verts)
	b.norms.append_array(norms)
	b.cols.append_array(cols)
	# Yamaçlardaki evler ve ağaç kümeleri
	var house_cols := [Color(0.95, 0.9, 0.8), Color(0.92, 0.78, 0.62), Color(0.85, 0.88, 0.9), Color(0.95, 0.85, 0.6), Color(0.88, 0.7, 0.66)]
	for i in 520:
		var a := rng.randf() * TAU
		var r := rng.randf_range(118.0, 215.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := _hill_h(x, z, nz)
		if rng.randf() < 0.3:
			var g := Color(0.22, 0.4, 0.22).darkened(rng.randf() * 0.2)
			b.ellipsoid(Vector3(2.6, 2.2, 2.6) * rng.randf_range(0.7, 1.4), Vector3(x, y + 1.2, z), g, Vector3.ZERO, 6, 3)
			continue
		var w := rng.randf_range(3.5, 6.0)
		var hh := float(rng.randi_range(1, 3)) * 3.0
		var hc: Color = house_cols[rng.randi() % house_cols.size()]
		b.box(Vector3(w, hh + 2.0, w * 0.8), Vector3(x, y + hh * 0.5 - 1.0, z), hc, Vector3(0, a, 0))
		b.prism(Vector3(w + 0.4, 1.5, w * 0.8 + 0.4), Vector3(x, y + hh + 0.75, z), TERRACOTTA.darkened(rng.randf() * 0.25), Vector3(0, a, 0))
	# Tepe üstünde kocaman bayrak direği
	var fx := 40.0; var fz := 160.0
	var fy := _hill_h(fx, fz, nz)
	b.cyl(0.25, 0.4, 22.0, Vector3(fx, fy + 11.0, fz), Color(0.85, 0.85, 0.88))
	_add_flag(Vector3(fx, fy + 21.5, fz), 12.0, Vector3(0, PI * 0.8, 0))


## Oyuncuların pazar dışına taşmaması için görünmez sınır (NPC'ler ve Ford Transit kinematik olduğu için kapılardan rahat geçer).
func _build_boundaries() -> void:
	LP.solid(self, Vector3(-HALF_X, 2.5, 0), Vector3(0.8, 5.0, HALF_Z * 2.0 + 4.0))
	LP.solid(self, Vector3(HALF_X, 2.5, 0), Vector3(0.8, 5.0, HALF_Z * 2.0 + 4.0))
	LP.solid(self, Vector3(0, 2.5, -HALF_Z), Vector3(HALF_X * 2.0 + 4.0, 5.0, 0.8))
	LP.solid(self, Vector3(0, 2.5, HALF_Z), Vector3(HALF_X * 2.0 + 4.0, 5.0, 0.8))
