extends Node3D
## Pazar mekanı: dinamik gün ışığı (Sabah→Akşam), AgX + glow, hareketli bulutlar, fıskiyeli çeşme,
## cadde üstü flamalar/ampuller, Toptancı Kamyonu (Hal) ve Akdeniz tarzı low-poly çevre.

const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const VFX := preload("res://vfx.gd")

const HALF := 22.0 # pazar alanının yarı genişliği (m)
# Ana cadde boyunca 8 oyuncu tezgahı konumu: [konum, yaw] (ön yüz +Z caddeye bakar)
const PLAYER_STALL_SPOTS := [
	[Vector3(-5.8, 0, -9.0), PI / 2],
	[Vector3(5.8, 0, -9.0), -PI / 2],
	[Vector3(-5.8, 0, 9.0), PI / 2],
	[Vector3(5.8, 0, 9.0), -PI / 2],
	[Vector3(-5.8, 0, -15.0), PI / 2],
	[Vector3(5.8, 0, -15.0), -PI / 2],
	[Vector3(-5.8, 0, 15.0), PI / 2],
	[Vector3(5.8, 0, 15.0), -PI / 2],
]
const TRUCK_POS := Vector3(-11.8, 0.0, 0.0)
const AWNINGS := [
	Color(0.86, 0.24, 0.19), Color(0.95, 0.74, 0.22), Color(0.22, 0.56, 0.78),
	Color(0.36, 0.66, 0.34), Color(0.74, 0.36, 0.62), Color(0.95, 0.54, 0.18),
]
const WOOD := Color(0.54, 0.36, 0.21)
const STONE := Color(0.75, 0.69, 0.58)
const TERRACOTTA := Color(0.78, 0.41, 0.26)

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep_col : source_color = vec3(0.12, 0.45, 0.72);
uniform vec3 foam_col : source_color = vec3(0.78, 0.94, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float w1 = sin(r * 22.0 - TIME * 4.4) * 0.5 + 0.5;
	float w2 = sin((p.x * 9.0 + p.y * 7.0) + TIME * 2.6) * 0.5 + 0.5;
	float foam = smoothstep(0.78, 0.98, r) * 0.45 + smoothstep(0.28, 0.05, r) * (0.45 + 0.35 * w1);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_col, foam_col, clamp(foam + w1 * w2 * 0.14 + fres * 0.35, 0.0, 1.0));
	ROUGHNESS = 0.09;
	SPECULAR = 0.88;
}
"""

var interactive := false # oyun açıkken ana cadde tezgahları oyunculara ayrılır + Toptancı Kamyonu etkileşimlidir
var rng := RandomNumberGenerator.new()

var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _env: Environment
var _lantern_lights: Array[OmniLight3D] = []
var _lantern_mats: Array[StandardMaterial3D] = []
var _bulb_mats: Array[StandardMaterial3D] = []
var _headlight_mats: Array[StandardMaterial3D] = []
var _clouds: Array = [] # [Node3D, speed, base_y, phase]
var _cloud_mats: Array[StandardMaterial3D] = []
var _buntings: Array[Node3D] = []
var _truck_labels: Dictionary = {} # item_id -> Label3D
var _truck_board_lbl: Label3D
var _day_progress := 0.36 # menüde sıcak öğleden sonra ışığı
var _anim_t := 0.0


func _ready() -> void:
	rng.seed = 1453
	_env_setup()
	_ground()
	_fountain(Vector3.ZERO)
	_build_clouds()
	_build_buntings()
	if not interactive:
		for spot in PLAYER_STALL_SPOTS:
			_decor_stall(spot[0], spot[1])
	# Doğu meydan dekor tezgahları + batı arkası dekor
	for z in [-4.5, 4.5]:
		_decor_stall(Vector3(14.5, 0, z), -PI / 2)
	_build_wholesale_truck()
	_walls()
	_build_skyline()
	_build_greenery_and_props()
	for z in [-18.0, -12.0, -6.0, 6.0, 12.0, 18.0]:
		_lantern(Vector3(-3.3, 0, z))
		_lantern(Vector3(3.3, 0, z))
	set_day_progress(_day_progress)


func _process(dt: float) -> void:
	_anim_t += dt
	# Bulutların gökyüzünde yavaşça süzülmesi
	for c in _clouds:
		var n: Node3D = c[0]
		n.position.x += float(c[1]) * dt
		if n.position.x > 62.0:
			n.position.x = -62.0
		n.position.y = float(c[2]) + sin(_anim_t * 0.35 + float(c[3])) * 0.25
	# Cadde üstü bayrakların hafif rüzgar salınımı
	for i in _buntings.size():
		_buntings[i].rotation.x = sin(_anim_t * 1.9 + float(i) * 0.9) * 0.055
	# Akşam fenerlerinde sıcak mum titremesi
	var night_k := clampf((_day_progress - 0.62) / 0.28, 0.0, 1.0)
	if night_k > 0.02:
		for i in _lantern_lights.size():
			var flick := 1.0 + sin(_anim_t * 7.5 + float(i) * 1.7) * 0.07
			_lantern_lights[i].light_energy = lerpf(0.25, 1.85, night_k) * flick


## Günün saatine göre (0.0 Sabah 08:00 -> 1.0 Akşam Pazarı 21:30) ışık, gökyüzü, sis ve fenerleri günceller.
func set_day_progress(p: float) -> void:
	_day_progress = clampf(p, 0.0, 1.0)
	if _sun == null or _sky_mat == null or _env == null:
		return
	# Güneş açısı: sabah doğudan (-24°), öğle tepede (-66°), akşam batıda (-12°)
	var sun_elev := sin(clampf(_day_progress, 0.0, 0.96) * PI / 0.96)
	var pitch_deg := lerpf(-10.0, -68.0, sun_elev)
	var yaw_deg := lerpf(-115.0, 65.0, _day_progress)
	_sun.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)

	# Renk anahtarları: Sabah (0.0) -> Öğle (0.38) -> Gün Batımı (0.76) -> Akşam (1.0)
	var sky_top: Color
	var sky_hor: Color
	var sun_col: Color
	var fog_col: Color
	var cloud_col: Color
	var sun_e: float
	var amb_e: float

	if _day_progress < 0.38:
		var k := _day_progress / 0.38
		sky_top = Color(0.24, 0.48, 0.86).lerp(Color(0.14, 0.44, 0.88), k)
		sky_hor = Color(0.96, 0.78, 0.64).lerp(Color(0.72, 0.85, 0.96), k)
		sun_col = Color(1.0, 0.84, 0.64).lerp(Color(1.0, 0.96, 0.86), k)
		fog_col = Color(0.96, 0.82, 0.68).lerp(Color(0.88, 0.86, 0.78), k)
		cloud_col = Color(1.0, 0.92, 0.86).lerp(Color(0.98, 0.98, 0.99), k)
		sun_e = lerpf(1.05, 1.38, k)
		amb_e = lerpf(0.78, 0.92, k)
	elif _day_progress < 0.78:
		var k := (_day_progress - 0.38) / 0.40
		sky_top = Color(0.14, 0.44, 0.88).lerp(Color(0.24, 0.25, 0.56), k)
		sky_hor = Color(0.72, 0.85, 0.96).lerp(Color(0.98, 0.52, 0.28), k)
		sun_col = Color(1.0, 0.96, 0.86).lerp(Color(1.0, 0.58, 0.26), k)
		fog_col = Color(0.88, 0.86, 0.78).lerp(Color(0.94, 0.58, 0.38), k)
		cloud_col = Color(0.98, 0.98, 0.99).lerp(Color(1.0, 0.68, 0.46), k)
		sun_e = lerpf(1.38, 1.05, k)
		amb_e = lerpf(0.92, 0.68, k)
	else:
		var k := (_day_progress - 0.78) / 0.22
		sky_top = Color(0.24, 0.25, 0.56).lerp(Color(0.05, 0.08, 0.20), k)
		sky_hor = Color(0.98, 0.52, 0.28).lerp(Color(0.28, 0.22, 0.36), k)
		sun_col = Color(1.0, 0.58, 0.26).lerp(Color(0.55, 0.62, 0.92), k)
		fog_col = Color(0.94, 0.58, 0.38).lerp(Color(0.18, 0.16, 0.26), k)
		cloud_col = Color(1.0, 0.68, 0.46).lerp(Color(0.32, 0.3, 0.46), k)
		sun_e = lerpf(1.05, 0.36, k)
		amb_e = lerpf(0.68, 0.44, k)

	_sky_mat.sky_top_color = sky_top
	_sky_mat.sky_horizon_color = sky_hor
	_sky_mat.ground_horizon_color = fog_col
	_sun.light_color = sun_col
	_sun.light_energy = sun_e
	_env.ambient_light_energy = amb_e
	_env.fog_light_color = fog_col
	_env.fog_density = lerpf(0.0018, 0.0038, clampf((_day_progress - 0.55) / 0.45, 0.0, 1.0))

	for cm in _cloud_mats:
		cm.albedo_color = cloud_col

	# Fenerler, cadde ampulleri ve kamyon farları gün batımında parlar
	var night_k := clampf((_day_progress - 0.60) / 0.28, 0.0, 1.0)
	for lm in _lantern_mats:
		lm.emission_energy_multiplier = lerpf(0.6, 3.2, night_k)
	for bm in _bulb_mats:
		bm.emission_energy_multiplier = lerpf(0.18, 2.8, night_k)
	for hm in _headlight_mats:
		hm.emission_energy_multiplier = lerpf(0.2, 3.6, night_k)
	for ll in _lantern_lights:
		ll.light_energy = lerpf(0.22, 1.85, night_k)


func _env_setup() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.16, 0.45, 0.88)
	_sky_mat.sky_horizon_color = Color(0.76, 0.84, 0.94)
	_sky_mat.ground_horizon_color = Color(0.86, 0.74, 0.58)
	_sky_mat.ground_bottom_color = Color(0.38, 0.30, 0.22)
	_sky_mat.sun_angle_max = 22.0
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.88
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.04
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.04
	_env.glow_enabled = true
	_env.glow_intensity = 0.42
	_env.glow_bloom = 0.14
	_env.glow_hdr_threshold = 1.05
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.95, 0.84, 0.68)
	_env.fog_density = 0.0018
	_env.fog_sky_affect = 0.08
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 1.65
	_env.ssao_light_affect = 0.35

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -35, 0)
	_sun.light_color = Color(1.0, 0.94, 0.82)
	_sun.light_energy = 1.32
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 68.0
	_sun.shadow_bias = 0.04
	add_child(_sun)


func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2 + 64, HALF * 2 + 64)
	g.mesh = pm
	g.material_override = LP.mat(Color(0.84, 0.72, 0.53), 0.94)
	add_child(g)
	LP.solid(self, Vector3(0, -0.5, 0), Vector3(HALF * 2 + 64, 1, HALF * 2 + 64))

	# Ana cadde sıcak Akdeniz taş döşemesi + kaldırım bordürleri
	for x in range(-3, 3):
		for z in range(-11, 11):
			var c := STONE.darkened(rng.randf_range(0.0, 0.13))
			if (x + z) % 3 == 0:
				c = c.lerp(TERRACOTTA, 0.14)
			LP.add(self, LP.box(Vector3(0.94, 0.032, 1.94)), Vector3(x * 1.0 + 0.5, 0.012, z * 2.0 + 1.0), c, Vector3.ZERO, 0.92)
	# Cadde kenar bordür taşları
	for sx in [-3.12, 3.12]:
		for z in [-16.0, -10.5, 10.5, 16.0]:
			LP.add(self, LP.box(Vector3(0.22, 0.09, 5.2)), Vector3(sx, 0.045, z), STONE.darkened(0.18))

	# Merkez meydan taş ve mozaik çemberi (çeşme + Toptancı yolu)
	for x in range(-6, 6):
		for z in range(-4, 4):
			var p := Vector3(x * 1.95 + 0.95, 0.016, z * 1.95 + 0.95)
			var c := STONE.darkened(rng.randf_range(0.02, 0.11))
			if absf(p.x) < 4.5 and absf(p.z) < 4.5 and (x + z) % 2 == 0:
				c = Color(0.82, 0.74, 0.60)
			LP.add(self, LP.box(Vector3(1.89, 0.032, 1.89)), p, c, Vector3.ZERO, 0.9)
	# Çeşme etrafı dekoratif terakota mozaik halkası
	LP.add(self, LP.cyl(3.45, 3.55, 0.025, 12), Vector3(0, 0.028, 0), TERRACOTTA.darkened(0.12))
	LP.add(self, LP.cyl(2.95, 3.0, 0.032, 12), Vector3(0, 0.032, 0), STONE.lightened(0.06))


func _fountain(p: Vector3) -> void:
	var f := Node3D.new()
	f.position = p
	add_child(f)
	# Basamaklı oymalı sekizgen taş havuz
	LP.add(f, LP.cyl(2.8, 2.95, 0.18, 8), Vector3(0, 0.09, 0), STONE.darkened(0.14))
	LP.add(f, LP.cyl(2.45, 2.6, 0.56, 8), Vector3(0, 0.42, 0), STONE.darkened(0.06))
	LP.add(f, LP.torus(2.26, 2.54, 8, 5), Vector3(0, 0.68, 0), STONE.lightened(0.08))
	# Hareketli dalgalı su yüzeyi (shader)
	var water := MeshInstance3D.new()
	var w_cyl := CylinderMesh.new()
	w_cyl.top_radius = 2.26; w_cyl.bottom_radius = 2.26; w_cyl.height = 0.05; w_cyl.radial_segments = 16
	water.mesh = w_cyl
	water.position = Vector3(0, 0.58, 0)
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	water.material_override = sm
	f.add_child(water)
	# Orta sütun, çanaklar ve pirinç tepe süsü
	LP.add(f, LP.cyl(0.32, 0.48, 1.65, 8), Vector3(0, 1.25, 0), STONE)
	LP.add(f, LP.cyl(1.05, 0.42, 0.32, 8), Vector3(0, 1.98, 0), STONE.darkened(0.05))
	LP.add(f, LP.cyl(0.88, 0.88, 0.04, 8), Vector3(0, 2.13, 0), Color(0.25, 0.62, 0.86), Vector3.ZERO, 0.12)
	LP.add(f, LP.cyl(0.18, 0.24, 0.55, 6), Vector3(0, 2.38, 0), STONE.lightened(0.04))
	LP.add(f, LP.sphere(0.16, 6, 4), Vector3(0, 2.7, 0), Color(0.86, 0.68, 0.24), Vector3.ZERO, 0.3, 0.75)
	# Sürekli fışkıran su damlacıkları
	var spray := VFX.build_fountain_particles()
	spray.position = Vector3(0, 2.75, 0)
	f.add_child(spray)
	# 3D su şırıltısı sesi
	var fa := Sfx.make_fountain_audio()
	fa.position = Vector3(0, 1.5, 0)
	f.add_child(fa)
	# Çarpıştırıcı
	var b := StaticBody3D.new()
	b.position = p + Vector3(0, 0.5, 0)
	var cs := CollisionShape3D.new()
	var csh := CylinderShape3D.new()
	csh.radius = 2.72; csh.height = 1.1
	cs.shape = csh
	b.add_child(cs)
	add_child(b)


func _build_clouds() -> void:
	var cloud_root := Node3D.new()
	add_child(cloud_root)
	for i in 14:
		var c := Node3D.new()
		var by := rng.randf_range(16.0, 25.0)
		c.position = Vector3(rng.randf_range(-56.0, 56.0), by, rng.randf_range(-52.0, 52.0))
		c.rotation.y = rng.randf() * TAU
		var mat := LP.mat(Color(0.98, 0.98, 0.99), 0.95)
		_cloud_mats.append(mat)
		var puffs := rng.randi_range(3, 5)
		for j in puffs:
			var mi := MeshInstance3D.new()
			var r := rng.randf_range(1.6, 3.0)
			mi.mesh = LP.ellipsoid(r * 1.35, r * 0.62, r * 0.95, 7, 4)
			mi.material_override = mat
			mi.position = Vector3((j - puffs * 0.5) * 2.1, rng.randf_range(-0.35, 0.5), rng.randf_range(-0.9, 0.9))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.add_child(mi)
		cloud_root.add_child(c)
		_clouds.append([c, rng.randf_range(0.55, 1.45), by, rng.randf() * TAU])


## Cadde üstü renkli pazar flamaları ve akşam parlayan ipli ampuller (doğrudan fener direklerine bağlı).
func _build_buntings() -> void:
	for z in [-18.0, -12.0, -6.0, 6.0, 12.0, 18.0]:
		var holder := Node3D.new()
		holder.position = Vector3(0.0, 3.36, z)
		add_child(holder)
		_buntings.append(holder)
		var span := 6.6 # tam olarak x=-3.3 ile x=+3.3 fener direkleri arasına bağlanır
		var segs := 8
		for i in segs:
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			var x0 := lerpf(-span * 0.5, span * 0.5, t0)
			var x1 := lerpf(-span * 0.5, span * 0.5, t1)
			var sag0 := -sin(t0 * PI) * 0.52
			var sag1 := -sin(t1 * PI) * 0.52
			var mid := Vector3((x0 + x1) * 0.5, (sag0 + sag1) * 0.5, 0.0)
			var seg_len := Vector2(x1 - x0, sag1 - sag0).length()
			var ang := atan2(sag1 - sag0, x1 - x0)
			LP.add(holder, LP.box(Vector3(seg_len, 0.024, 0.024)), mid, Color(0.28, 0.22, 0.18), Vector3(0, 0, ang))
			var col: Color = AWNINGS[(i + absi(int(z))) % AWNINGS.size()]
			LP.add(holder, LP.prism(Vector3(0.42, 0.38, 0.03)), mid + Vector3(0, -0.20, 0), col, Vector3(0, 0, PI))
			if i % 2 == 1:
				var bulb := LP.add(holder, LP.sphere(0.068, 6, 4), mid + Vector3(0, -0.07, 0), Color(1.0, 0.9, 0.62), Vector3.ZERO, 0.2)
				var bm := bulb.material_override as StandardMaterial3D
				bm.emission_enabled = true
				bm.emission = Color(1.0, 0.78, 0.36)
				bm.emission_energy_multiplier = 0.4
				_bulb_mats.append(bm)


## Surların dışında sıcak Akdeniz kasabası evleri, saat kulesi ve yumuşak tepeler.
func _build_skyline() -> void:
	var plaster_cols := [
		Color(0.92, 0.84, 0.70), Color(0.89, 0.77, 0.62), Color(0.86, 0.73, 0.60),
		Color(0.94, 0.88, 0.78), Color(0.84, 0.68, 0.54),
	]
	var roof_cols := [TERRACOTTA, TERRACOTTA.darkened(0.14), Color(0.72, 0.34, 0.22)]
	# Dört yönde sur dışına yerleşmiş kasaba evleri
	for side in 4:
		var yaw := side * PI / 2
		var grp := Node3D.new()
		grp.rotation.y = yaw
		add_child(grp)
		for k in range(-3, 4):
			if k == 0:
				continue # kapı aksı açık kalsın
			var hx: float = float(k) * 7.2 + rng.randf_range(-1.1, 1.1)
			var hz: float = -(HALF + rng.randf_range(5.5, 11.5))
			var w := rng.randf_range(4.2, 6.2)
			var d := rng.randf_range(3.8, 5.4)
			var h := rng.randf_range(4.8, 8.2)
			var pc: Color = plaster_cols[rng.randi() % plaster_cols.size()]
			var rc: Color = roof_cols[rng.randi() % roof_cols.size()]
			LP.add(grp, LP.box(Vector3(w, h, d)), Vector3(hx, h * 0.5, hz), pc)
			LP.add(grp, LP.prism(Vector3(w + 0.5, 1.8, d + 0.5)), Vector3(hx, h + 0.9, hz), rc)
			# Pencere detayı
			LP.add(grp, LP.box(Vector3(0.75, 0.95, 0.12)), Vector3(hx - w * 0.22, h * 0.68, hz + d * 0.5 + 0.04), WOOD.darkened(0.22))
			LP.add(grp, LP.box(Vector3(0.75, 0.95, 0.12)), Vector3(hx + w * 0.22, h * 0.68, hz + d * 0.5 + 0.04), WOOD.darkened(0.22))
	# Kuzeydoğu köşesinde ikonik pazar saat/gözetleme kulesi
	var twr := Node3D.new()
	twr.position = Vector3(26.5, 0.0, -28.0)
	add_child(twr)
	LP.add(twr, LP.box(Vector3(4.2, 13.5, 4.2)), Vector3(0, 6.75, 0), STONE.lightened(0.05))
	LP.add(twr, LP.box(Vector3(4.7, 0.5, 4.7)), Vector3(0, 13.6, 0), TERRACOTTA.darkened(0.1))
	LP.add(twr, LP.cyl(0.1, 3.2, 3.6, 4), Vector3(0, 15.6, 0), TERRACOTTA, Vector3(0, PI / 4, 0))
	LP.add(twr, LP.cyl(0.95, 0.95, 0.12, 10), Vector3(0, 11.4, 2.12), Color(0.98, 0.95, 0.85), Vector3(PI / 2, 0, 0))
	LP.add(twr, LP.cyl(0.95, 0.95, 0.12, 10), Vector3(-2.12, 11.4, 0), Color(0.98, 0.95, 0.85), Vector3(0, 0, PI / 2))
	# Uzak yumuşak Akdeniz tepeleri (ufku çerçeveler)
	for i in 12:
		var a := float(i) * TAU / 12.0 + 0.15
		var dist := rng.randf_range(52.0, 66.0)
		var rx := rng.randf_range(16.0, 26.0)
		var ry := rng.randf_range(7.0, 15.0)
		var hill_c := Color(0.46, 0.56, 0.36).lerp(Color(0.68, 0.58, 0.42), rng.randf_range(0.15, 0.65))
		var hm := LP.add(self, LP.ellipsoid(rx, ry, rx * 0.85, 9, 5), Vector3(cos(a) * dist, ry * 0.25 - 1.5, sin(a) * dist), hill_c, Vector3(0, a, 0), 0.96)
		hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Batı meydanında tüm 7 ürünü ve günlük fırsatı sunan etkileşimli Toptancı Kamyonu (Hal).
func _build_wholesale_truck() -> void:
	_truck_labels.clear()
	var truck := Node3D.new()
	truck.name = "WholesaleTruck"
	truck.position = TRUCK_POS
	add_child(truck)

	# Ahşap platform zemin
	LP.add(truck, LP.box(Vector3(4.2, 0.08, 7.6)), Vector3(0.4, 0.04, 0.0), WOOD.darkened(0.32))

	# Kamyon gövdesi (kuzey ucu kabin, güney/orta kısım uzun ahşap kasa; doğu tarafına satış açılır)
	var cab_col := Color(0.18, 0.54, 0.64) # klasik turkuaz Türk hal kamyoneti
	LP.add(truck, LP.box(Vector3(2.1, 1.35, 1.9)), Vector3(-0.75, 1.15, -2.35), cab_col, Vector3.ZERO, 0.45, 0.15)
	LP.add(truck, LP.box(Vector3(1.96, 0.72, 1.15)), Vector3(-0.75, 2.08, -2.1), cab_col.lightened(0.08), Vector3.ZERO, 0.45, 0.15)
	# Ön cam ve yan camlar
	LP.add(truck, LP.box(Vector3(1.8, 0.56, 0.06)), Vector3(-0.75, 2.08, -2.69), Color(0.68, 0.86, 0.95), Vector3.ZERO, 0.12, 0.2)
	LP.add(truck, LP.box(Vector3(0.06, 0.52, 0.95)), Vector3(0.25, 2.08, -2.1), Color(0.68, 0.86, 0.95), Vector3.ZERO, 0.12, 0.2)
	# Ön tampon ve akşam yanan farlar
	LP.add(truck, LP.box(Vector3(2.2, 0.24, 0.24)), Vector3(-0.75, 0.58, -3.32), Color(0.24, 0.24, 0.26), Vector3.ZERO, 0.5, 0.4)
	for hx in [-1.45, -0.05]:
		var hl := LP.add(truck, LP.box(Vector3(0.32, 0.22, 0.08)), Vector3(hx, 0.92, -3.32), Color(1.0, 0.95, 0.75), Vector3.ZERO, 0.2)
		var hm := hl.material_override as StandardMaterial3D
		hm.emission_enabled = true
		hm.emission = Color(1.0, 0.9, 0.6)
		hm.emission_energy_multiplier = 0.25
		_headlight_mats.append(hm)
	# Ahşap kasa gövdesi & gölgelik tenteli çatı
	LP.add(truck, LP.box(Vector3(2.25, 0.45, 4.7)), Vector3(-0.75, 0.78, 1.0), WOOD.darkened(0.18))
	LP.add(truck, LP.box(Vector3(0.14, 1.1, 4.7)), Vector3(-1.82, 1.52, 1.0), WOOD) # arka yan duvar
	LP.add(truck, LP.box(Vector3(2.25, 0.95, 0.14)), Vector3(-0.75, 1.48, 3.3), WOOD) # arka kapak
	for px in [-1.78, 0.3]:
		for pz in [-1.25, 3.25]:
			LP.add(truck, LP.cyl(0.05, 0.05, 1.8, 6), Vector3(px, 1.85, pz), Color(0.3, 0.28, 0.26))
	for i in 6:
		var tc := Color(0.95, 0.62, 0.14) if i % 2 == 0 else Color(0.97, 0.94, 0.86)
		LP.add(truck, LP.box(Vector3(2.75, 0.06, 0.8)), Vector3(-0.62, 2.78, -0.98 + i * 0.8), tc, Vector3(0, 0, -0.14))
	# 4 tekerlek
	for wx in [-1.72, 0.22]:
		for wz in [-2.35, 1.85]:
			LP.add(truck, LP.cyl(0.46, 0.46, 0.28, 10), Vector3(wx, 0.46, wz), Color(0.16, 0.16, 0.18), Vector3(0, 0, PI / 2))
			LP.add(truck, LP.cyl(0.22, 0.22, 0.30, 8), Vector3(wx, 0.46, wz), Color(0.75, 0.75, 0.78), Vector3(0, 0, PI / 2), 0.35, 0.6)
	LP.solid(truck, Vector3(-0.75, 1.2, 0.0), Vector3(2.3, 2.4, 6.7))

	# Üst tabela: TOPTANCI HALİ + akşam yanan kasa ışığı
	LP.add(truck, LP.box(Vector3(0.08, 0.72, 4.4)), Vector3(0.76, 2.98, 1.0), Color(0.14, 0.2, 0.14))
	_truck_board_lbl = Label3D.new()
	_truck_board_lbl.text = "🚚 TOPTANCI HALİ  •  7 ÇEŞİT TAZE KASA"
	_truck_board_lbl.position = Vector3(0.82, 2.98, 1.0)
	_truck_board_lbl.rotation.y = PI / 2
	_truck_board_lbl.font_size = 34
	_truck_board_lbl.outline_size = 8
	_truck_board_lbl.modulate = Color(1.0, 0.9, 0.45)
	_truck_board_lbl.visible = interactive
	truck.add_child(_truck_board_lbl)
	var truck_light := OmniLight3D.new()
	truck_light.position = Vector3(1.1, 2.35, 1.0)
	truck_light.light_color = Color(1.0, 0.82, 0.48)
	truck_light.light_energy = 0.6
	truck_light.omni_range = 7.5
	truck.add_child(truck_light)
	_lantern_lights.append(truck_light)

	# Kamyonun doğu tarafında tüm 7 ürünün etkileşimli toptan satış kasaları (2 sıra: 4 temel + 3 özel!)
	var all_items := Produce.ITEM_ORDER
	for i in all_items.size():
		var item_id: String = all_items[i]
		var info: Dictionary = Produce.ITEMS[item_id]
		var is_exotic := i >= 4
		var cz: float = (-1.2 + float(i) * 0.98) if not is_exotic else (-0.8 + float(i - 4) * 1.15)
		var cx: float = 1.28 if not is_exotic else 0.52
		var cy: float = 0.0 if not is_exotic else 0.95
		var spot := Node3D.new()
		spot.position = Vector3(cx, cy, cz)
		truck.add_child(spot)
		LP.add(spot, LP.box(Vector3(0.62, 0.30, 0.56)), Vector3(0, 0.16, 0), WOOD.lightened(0.08))
		LP.add(spot, LP.box(Vector3(0.66, 0.04, 0.60)), Vector3(0, 0.31, 0), WOOD.darkened(0.2))
		for j in 6:
			var ox := -0.14 + float(j % 2) * 0.28
			var oz := -0.15 + float(int(j / 2)) * 0.15
			Produce.build_mesh(spot, item_id, Vector3(ox, 0.35, oz), 0.072)
		var lbl := Label3D.new()
		lbl.text = "%s\n%d TL" % [info["name"], int(info["crate_cost"])]
		lbl.position = Vector3(0.1, 0.66, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 24
		lbl.outline_size = 7
		lbl.modulate = Color(1.0, 0.95, 0.78) if not is_exotic else Color(0.75, 1.0, 0.82)
		lbl.visible = interactive
		spot.add_child(lbl)
		_truck_labels[item_id] = lbl

		if interactive:
			var area := Area3D.new()
			area.name = "Wholesale_%s" % item_id
			area.collision_layer = 4
			area.collision_mask = 0
			area.set_meta("kind", "wholesale_crate")
			area.set_meta("item_id", item_id)
			area.set_meta("hl_size", Vector3(0.68, 0.42, 0.62))
			area.position = Vector3(0, 0.34, 0)
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.74, 0.74, 0.72)
			cs.shape = sh
			area.add_child(cs)
			spot.add_child(area)


## Toptancı fiyatlarını ve indirim/olay etiketlerini günceller.
func update_wholesale_board(prices: Dictionary, deal_item: String, event_item: String) -> void:
	for item_id in _truck_labels:
		var lbl: Label3D = _truck_labels[item_id]
		var nm: String = Produce.ITEMS[item_id]["name"]
		var cost: int = int(prices.get(item_id, Produce.ITEMS[item_id]["crate_cost"]))
		if item_id == deal_item:
			lbl.text = "🔥 FIRSAT!\n%s\n%d TL" % [nm, cost]
			lbl.modulate = Color(0.42, 1.0, 0.52)
		elif item_id == event_item:
			lbl.text = "⭐ TALEP!\n%s\n%d TL" % [nm, cost]
			lbl.modulate = Color(1.0, 0.85, 0.25)
		else:
			lbl.text = "%s\n%d TL" % [nm, cost]
			lbl.modulate = Color(1.0, 0.95, 0.82)
	if _truck_board_lbl and Produce.ITEMS.has(deal_item):
		_truck_board_lbl.text = "🚚 TOPTANCI HALİ  •  🔥 FIRSAT: %s (%d TL)" % [
			Produce.ITEMS[deal_item]["name"].to_upper(),
			int(prices.get(deal_item, Produce.ITEMS[deal_item]["crate_cost"]))
		]


## Dekoratif tezgah (menü sahnesi + meydan kenarları).
func _decor_stall(p: Vector3, yaw: float) -> void:
	var s := Node3D.new()
	s.position = p
	s.rotation.y = yaw
	add_child(s)
	var awn: Color = AWNINGS[rng.randi() % AWNINGS.size()]
	LP.add(s, LP.box(Vector3(3.2, 0.85, 1.15)), Vector3(0, 0.425, 0.3), WOOD)
	LP.add(s, LP.box(Vector3(3.32, 0.08, 1.26)), Vector3(0, 0.88, 0.3), WOOD.lightened(0.15))
	for x in [-1.5, 1.5]:
		for z in [-0.6, 1.08]:
			LP.add(s, LP.cyl(0.055, 0.065, 2.5, 6), Vector3(x, 1.25, z), WOOD.darkened(0.22))
	for i in 5:
		var c := awn if i % 2 == 0 else Color(0.96, 0.93, 0.86)
		LP.add(s, LP.box(Vector3(0.68, 0.05, 2.15)), Vector3(-1.36 + i * 0.68, 2.56, 0.25), c, Vector3(0.22, 0, 0))
	LP.add(s, LP.box(Vector3(3.45, 0.24, 0.04)), Vector3(0, 2.31, 1.3), awn)
	if rng.randf() < 0.75:
		for i in 3:
			var item_id: String = Produce.ITEM_ORDER[rng.randi() % Produce.ITEM_ORDER.size()]
			var base := Vector3(-1.0 + i * 1.0, 0.96, 0.3)
			LP.add(s, LP.box(Vector3(0.8, 0.12, 0.7)), base, WOOD.darkened(0.3))
			for j in 6:
				var o := Vector3(rng.randf_range(-0.24, 0.24), 0.13 + (0.11 if j > 3 else 0.0), rng.randf_range(-0.18, 0.18))
				Produce.build_mesh(s, item_id, base + o, 0.082)
	else:
		for i in 4:
			var h := rng.randf_range(0.32, 0.56)
			LP.add(s, LP.cyl(0.1, 0.2, h, 7), Vector3(-1.1 + i * 0.73, 0.92 + h / 2, 0.3),
				TERRACOTTA.darkened(rng.randf_range(0.0, 0.25)), Vector3.ZERO, 0.72)
	LP.solid(s, Vector3(0, 0.5, 0.25), Vector3(3.3, 1.0, 1.35))


func _build_greenery_and_props() -> void:
	# Meydan köşelerine şık çiçekli taş saksılar
	for pos in [Vector3(-4.5, 0, -4.5), Vector3(4.5, 0, -4.5), Vector3(-4.5, 0, 4.5), Vector3(4.5, 0, 4.5)]:
		_planter(pos)
	# Çevre ağaçları (zeytin & selvi karışımı)
	for i in 28:
		var p := Vector3(rng.randf_range(-HALF + 2, HALF - 2), 0, rng.randf_range(-HALF + 2, HALF - 2))
		if p.distance_to(TRUCK_POS) < 6.0:
			continue
		if absf(p.x) > 17.2 or (absf(p.z) > 19.2 and absf(p.x) > 4.2):
			if rng.randf() < 0.45:
				_cypress(p)
			else:
				_tree(p)
	# Dekoratif sandık, fıçı ve amforalar
	for i in 16:
		var p := Vector3(rng.randf_range(-HALF + 3, HALF - 3), 0, rng.randf_range(-HALF + 3, HALF - 3))
		if p.length() < 6.5 or absf(p.x) < 4.2 or p.distance_to(TRUCK_POS) < 5.5:
			continue
		if absf(p.x) < 8.5 and (absf(p.z) > 6.5 and absf(p.z) < 17.5):
			continue # oyuncu tezgahı + depo alanı temiz kalsın
		var roll := rng.randf()
		if roll < 0.4:
			_crate(p, rng.randf() * TAU)
		elif roll < 0.75:
			_barrel(p)
		else:
			_amphora(p)


func _planter(p: Vector3) -> void:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	LP.add(n, LP.cyl(0.46, 0.38, 0.42, 8), Vector3(0, 0.21, 0), TERRACOTTA)
	LP.add(n, LP.cyl(0.49, 0.49, 0.06, 8), Vector3(0, 0.41, 0), TERRACOTTA.lightened(0.12))
	LP.add(n, LP.sphere(0.34, 7, 4), Vector3(0, 0.56, 0), Color(0.28, 0.58, 0.26))
	var flower_cols := [Color(0.98, 0.35, 0.42), Color(1.0, 0.82, 0.2), Color(0.95, 0.52, 0.76)]
	var fc: Color = flower_cols[rng.randi() % flower_cols.size()]
	for i in 5:
		var a := i * TAU / 5.0
		LP.add(n, LP.sphere(0.08, 5, 3), Vector3(cos(a) * 0.24, 0.74 + (i % 2) * 0.06, sin(a) * 0.24), fc)
	LP.solid(n, Vector3(0, 0.3, 0), Vector3(0.85, 0.65, 0.85))


func _amphora(p: Vector3) -> void:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	LP.add(n, LP.ellipsoid(0.26, 0.38, 0.26, 8, 5), Vector3(0, 0.38, 0), TERRACOTTA.darkened(0.06), Vector3.ZERO, 0.68)
	LP.add(n, LP.cyl(0.14, 0.11, 0.26, 7), Vector3(0, 0.8, 0), TERRACOTTA)
	LP.solid(n, Vector3(0, 0.45, 0), Vector3(0.54, 0.9, 0.54))


func _crate(p: Vector3, yaw: float) -> void:
	var c := Node3D.new()
	c.position = p
	c.rotation.y = yaw
	add_child(c)
	LP.add(c, LP.box(Vector3(0.7, 0.6, 0.7)), Vector3(0, 0.3, 0), WOOD.lightened(0.1))
	LP.add(c, LP.box(Vector3(0.74, 0.08, 0.74)), Vector3(0, 0.6, 0), WOOD.darkened(0.15))
	LP.solid(c, Vector3(0, 0.3, 0), Vector3(0.7, 0.6, 0.7))


func _barrel(p: Vector3) -> void:
	var b := Node3D.new()
	b.position = p
	add_child(b)
	LP.add(b, LP.cyl(0.32, 0.32, 0.85, 8), Vector3(0, 0.43, 0), WOOD)
	for y in [0.15, 0.7]:
		LP.add(b, LP.cyl(0.34, 0.34, 0.06, 8), Vector3(0, y, 0), Color(0.28, 0.28, 0.32), Vector3.ZERO, 0.5, 0.6)
	LP.solid(b, Vector3(0, 0.43, 0), Vector3(0.64, 0.85, 0.64))


func _tree(p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	t.scale = Vector3.ONE * rng.randf_range(0.85, 1.35)
	add_child(t)
	LP.add(t, LP.cyl(0.16, 0.24, 1.7, 6), Vector3(0, 0.85, 0), WOOD.darkened(0.32))
	var g := Color(0.34, 0.62, 0.28).darkened(rng.randf_range(0.0, 0.22))
	LP.add(t, LP.ellipsoid(1.15, 0.85, 1.15, 7, 4), Vector3(0, 2.25, 0), g)
	LP.add(t, LP.ellipsoid(0.85, 0.72, 0.85, 7, 4), Vector3(0.4, 2.75, -0.2), g.lightened(0.1))
	LP.add(t, LP.ellipsoid(0.7, 0.6, 0.7, 6, 4), Vector3(-0.42, 2.6, 0.3), g.darkened(0.06))
	LP.solid(t, Vector3(0, 1, 0), Vector3(0.44, 2, 0.44))


func _cypress(p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	t.scale = Vector3.ONE * rng.randf_range(0.9, 1.35)
	add_child(t)
	LP.add(t, LP.cyl(0.11, 0.16, 1.2, 5), Vector3(0, 0.6, 0), WOOD.darkened(0.35))
	var g := Color(0.2, 0.46, 0.24).darkened(rng.randf_range(0.0, 0.16))
	LP.add(t, LP.cyl(0.45, 0.62, 2.0, 7), Vector3(0, 1.9, 0), g)
	LP.add(t, LP.cyl(0.02, 0.48, 2.2, 7), Vector3(0, 3.8, 0), g.lightened(0.06))
	LP.solid(t, Vector3(0, 1, 0), Vector3(0.4, 2, 0.4))


func _lantern(p: Vector3) -> void:
	var l := Node3D.new()
	l.position = p
	add_child(l)
	LP.add(l, LP.cyl(0.16, 0.22, 0.35, 6), Vector3(0, 0.18, 0), STONE.darkened(0.2))
	LP.add(l, LP.cyl(0.05, 0.07, 3.0, 6), Vector3(0, 1.65, 0), Color(0.18, 0.17, 0.16), Vector3.ZERO, 0.45, 0.6)
	LP.add(l, LP.cyl(0.02, 0.26, 0.22, 6), Vector3(0, 3.45, 0), Color(0.18, 0.17, 0.16), Vector3.ZERO, 0.45, 0.6)
	var glow := LP.add(l, LP.box(Vector3(0.28, 0.36, 0.28)), Vector3(0, 3.18, 0), Color(1.0, 0.85, 0.48), Vector3.ZERO, 0.2)
	var m := glow.material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.3)
	m.emission_energy_multiplier = 1.6
	_lantern_mats.append(m)
	var light := OmniLight3D.new()
	light.position.y = 3.05
	light.light_color = Color(1.0, 0.76, 0.42)
	light.light_energy = 0.7
	light.omni_range = 8.5
	l.add_child(light)
	_lantern_lights.append(light)
	LP.solid(l, Vector3(0, 1.5, 0), Vector3(0.22, 3, 0.22))


## Çevre suru; dört yönde kemerli taş kapılar, bayraklar ve ahşap pencere nişleri.
func _walls() -> void:
	for side in 4:
		var yaw := side * PI / 2
		var wall := Node3D.new()
		wall.rotation.y = yaw
		add_child(wall)
		for seg in [-1, 1]:
			var wl := HALF - 2.6
			var x: float = seg * (2.6 + wl / 2)
			LP.add(wall, LP.box(Vector3(wl, 3.2, 0.85)), Vector3(x, 1.6, -HALF), STONE.darkened(0.13))
			LP.add(wall, LP.box(Vector3(wl, 0.24, 0.96)), Vector3(x, 3.24, -HALF), TERRACOTTA.darkened(0.15))
			LP.solid(wall, Vector3(x, 1.6, -HALF), Vector3(wl, 3.2, 0.85))
			for i in int(wl / 1.7):
				LP.add(wall, LP.box(Vector3(0.7, 0.48, 0.9)), Vector3(x - wl / 2 + 0.6 + i * 1.7, 3.52, -HALF), STONE.darkened(0.18))
			# Duvar üstü sıcak Akdeniz ahşap kepenkli kemer nişleri
			for n_idx in 2:
				var nx: float = x + (n_idx * 2 - 1) * 4.2
				LP.add(wall, LP.box(Vector3(1.1, 1.35, 0.14)), Vector3(nx, 1.9, -HALF + 0.44), WOOD.darkened(0.18))
				LP.add(wall, LP.box(Vector3(1.3, 0.16, 0.34)), Vector3(nx, 1.18, -HALF + 0.52), TERRACOTTA)
				LP.add(wall, LP.sphere(0.18, 5, 3), Vector3(nx - 0.25, 1.32, -HALF + 0.55), Color(0.95, 0.36, 0.38))
				LP.add(wall, LP.sphere(0.16, 5, 3), Vector3(nx + 0.24, 1.32, -HALF + 0.55), Color(0.98, 0.78, 0.24))
		for gx in [-2.6, 2.6]:
			LP.add(wall, LP.box(Vector3(1.5, 4.7, 1.5)), Vector3(gx, 2.35, -HALF), STONE.darkened(0.2))
			LP.add(wall, LP.cyl(0.05, 1.15, 0.95, 4), Vector3(gx, 5.15, -HALF), TERRACOTTA, Vector3(0, PI / 4, 0))
			LP.solid(wall, Vector3(gx, 2.35, -HALF), Vector3(1.5, 4.7, 1.5))
		LP.add(wall, LP.box(Vector3(6.6, 0.75, 1.1)), Vector3(0, 4.15, -HALF), STONE.darkened(0.22))
		LP.add(wall, LP.box(Vector3(4.2, 0.92, 0.06)), Vector3(0, 3.45, -HALF + 0.58), AWNINGS[side])
	# Kapıdan dışarı kaçılmasın: görünmez dış sınır
	for side in 4:
		var d := Vector3(0, 0, -(HALF + 6)).rotated(Vector3.UP, side * PI / 2)
		LP.solid(self, d + Vector3(0, 3, 0), Vector3(60, 6, 1), side * PI / 2)
