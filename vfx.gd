extends RefCounted
## Düşük poligonlu 3D partiküller: altın para, toz, duman, kor, müzik notaları, darbe yıldızları ve ses halkaları.

const LP := preload("res://lowpoly.gd")

static var _soft_mat: StandardMaterial3D


## Duman/buhar için yumuşak kenarlı kamera'ya dönük bulut: radyal geçişli doku + kameraya çok yaklaşınca saydamlaşır
## (köşeli küre topları yerine). Partiküllerin rengini ve saydamlığını color_ramp belirler.
static func soft_puff_mat() -> StandardMaterial3D:
	if _soft_mat:
		return _soft_mat
	var g := ramp([0.0, 0.35, 0.7, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.25
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.12
	m.distance_fade_max_distance = 0.6
	_soft_mat = m
	return m


## Noktaları sırasıyla kurulmuş renk geçişi (add_point + set_color(1) karışıklığı olmadan).
static func ramp(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


static func soft_puff_mesh(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


static func _soften(p: CPUParticles3D, size: float) -> void:
	p.mesh = soft_puff_mesh(size)
	p.material_override = soft_puff_mat()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0


static func _vcol_mat(rough := 0.5, metallic := 0.0, unshaded := false, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metallic
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _spawn_oneshot(parent: Node, world_pos: Vector3, amount: int, lifetime: float,
		mesh: Mesh, mat: Material, color: Color, vel_min: float, vel_max: float,
		spread := 55.0, grav := Vector3(0, -8.5, 0), dir := Vector3.UP,
		scale_min := 0.75, scale_max := 1.25) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = mesh
	p.material_override = mat
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = grav
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(lifetime + 0.35)
	tw.tween_callback(p.queue_free)


static func burst_coins(parent: Node, world_pos: Vector3, count := 10) -> void:
	var coin_mesh := LP.cyl(0.052, 0.052, 0.016, 7)
	var m := _vcol_mat(0.22, 0.85, false, false)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.18)
	m.emission_energy_multiplier = 0.9
	_spawn_oneshot(parent, world_pos, count, 0.85, coin_mesh, m,
		Color(1.0, 0.84, 0.22), 2.2, 4.4, 52.0, Vector3(0, -9.0, 0))


static func burst_dust(parent: Node, world_pos: Vector3, color := Color(0.92, 0.88, 0.80), count := 7) -> void:
	var puff := LP.sphere(0.055, 5, 3)
	var m := _vcol_mat(0.95, 0.0, false, true)
	_spawn_oneshot(parent, world_pos, count, 0.5, puff, m,
		Color(color.r, color.g, color.b, 0.75), 0.7, 1.9, 140.0, Vector3(0, 0.6, 0))


static func burst_mood(parent: Node, world_pos: Vector3, happy: bool) -> void:
	var mesh := LP.box(Vector3(0.06, 0.06, 0.06)) if happy else LP.sphere(0.065, 5, 3)
	var col := Color(0.42, 1.0, 0.55) if happy else Color(0.95, 0.28, 0.22)
	var m := _vcol_mat(0.4, 0.0, happy, false)
	_spawn_oneshot(parent, world_pos, 9 if happy else 7, 0.7, mesh, m,
		col, 1.4, 2.8, 70.0, Vector3(0, 1.4, 0) if happy else Vector3(0, 0.8, 0))


## Sigara veya Küba Purosu duman bulutu (yavaşça yükselen, büyüyerek dağılan yumuşak 3D duman).
static func spawn_smoke_puff(parent: Node, world_pos: Vector3, dir := Vector3.UP, thick := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.35
	p.amount = 18 if thick else 10
	p.lifetime = 2.1 if thick else 1.5
	_soften(p, 0.24 if thick else 0.16)
	p.direction = (dir * 0.55 + Vector3.UP * 0.75).normalized()
	p.spread = 32.0 if thick else 24.0
	p.initial_velocity_min = 0.45 if thick else 0.32
	p.initial_velocity_max = 1.05 if thick else 0.72
	p.gravity = Vector3(0.12, 0.55, 0.08) # duman yukarı süzülür
	p.damping_min = 0.45
	p.damping_max = 0.85
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.45))
	sc.add_point(Vector2(0.45, 1.35 if thick else 1.1))
	sc.add_point(Vector2(1.0, 2.2 if thick else 1.7))
	p.scale_amount_curve = sc
	var base_c := Color(0.76, 0.80, 0.86, 0.62) if thick else Color(0.86, 0.88, 0.92, 0.52)
	p.color_ramp = ramp([0.0, 0.12, 0.55, 1.0], [Color(base_c, 0.0), base_c, Color(base_c, 0.30), Color(base_c, 0.0)])
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.4)
	tw.tween_callback(p.queue_free)


## Sigara/puro korundan sıçrayan minik turuncu kıvılcımlar.
static func spawn_ember_sparks(parent: Node, world_pos: Vector3) -> void:
	var spark := LP.box(Vector3(0.014, 0.014, 0.014))
	var m := _vcol_mat(0.2, 0.0, true, false)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.08)
	m.emission_energy_multiplier = 3.2
	_spawn_oneshot(parent, world_pos, 6, 0.42, spark, m,
		Color(1.0, 0.58, 0.14), 0.35, 0.95, 75.0, Vector3(0, -1.8, 0))


## Ağızdan ileri üflenen hacimli sigara / Küba purosu duman bulutu (ileri savrulur, yavaşlayıp yukarı açılır!).
static func spawn_exhale_cloud(parent: Node, world_pos: Vector3, fwd_dir: Vector3, thick := false) -> void:
	if not _ok(parent):
		return
	var d := fwd_dir.normalized() if fwd_dir.length() > 0.01 else Vector3.FORWARD
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.25
	p.amount = 28 if thick else 18
	p.lifetime = 2.6 if thick else 2.0
	_soften(p, 0.22 if thick else 0.16)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.03
	p.direction = (d + Vector3(0, 0.10, 0)).normalized()
	p.spread = 20.0 if thick else 15.0
	p.initial_velocity_min = 1.15 if thick else 1.05
	p.initial_velocity_max = 2.35 if thick else 1.95
	p.damping_min = 1.45
	p.damping_max = 2.2
	p.gravity = Vector3(0.08, 0.38, 0.06)
	p.scale_amount_curve = _scale_curve(0.35, 1.55 if thick else 1.25, 2.85 if thick else 2.25, 0.42)
	var base_c := Color(0.80, 0.84, 0.90, 0.62) if thick else Color(0.88, 0.90, 0.94, 0.50)
	p.color_ramp = ramp([0.0, 0.10, 0.55, 1.0], [Color(base_c, 0.0), base_c, Color(base_c, base_c.a * 0.48), Color(base_c, 0.0)])
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.45)
	tw.tween_callback(p.queue_free)


## Küba purosu üflerken ağızdan çıkıp büyüyerek süzülen 3D duman halkası!
static func spawn_smoke_ring(parent: Node, world_pos: Vector3, fwd_dir: Vector3) -> void:
	if not _ok(parent):
		return
	var d := fwd_dir.normalized() if fwd_dir.length() > 0.01 else Vector3.FORWARD
	var mi := MeshInstance3D.new()
	mi.mesh = LP.torus(0.042, 0.066, 16, 6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.84, 0.87, 0.92, 0.56)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = world_pos + d * 0.16
	# Torus eksenini üfleme yönüne hizala
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	mi.look_at(mi.global_position + d, up)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.scale = Vector3(0.45, 0.45, 0.45)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "global_position", mi.global_position + d * 1.45 + Vector3(0, 0.52, 0), 1.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(3.4, 2.2, 3.4), 1.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.75).set_delay(0.15)
	tw.chain().tween_callback(mi.queue_free)


## Sigara/puro kül silkme: gri kül parçaları + 2 minik sönmekte olan kor.
static func spawn_ash_drop(parent: Node, world_pos: Vector3) -> void:
	if not _ok(parent):
		return
	var ash_mesh := LP.box(Vector3(0.012, 0.008, 0.012))
	var am := _vcol_mat(0.95, 0.0, false, true)
	_spawn_oneshot(parent, world_pos, 9, 0.72, ash_mesh, am,
		Color(0.55, 0.54, 0.56, 0.92), 0.18, 0.65, 65.0, Vector3(0.08, -3.4, 0.04), Vector3.DOWN, 0.65, 1.35)
	var spark := LP.box(Vector3(0.010, 0.010, 0.010))
	var sm := _vcol_mat(0.2, 0.0, true, false)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.42, 0.06)
	sm.emission_energy_multiplier = 2.8
	_spawn_oneshot(parent, world_pos, 3, 0.36, spark, sm,
		Color(1.0, 0.55, 0.12), 0.15, 0.55, 55.0, Vector3(0, -2.6, 0), Vector3.DOWN, 0.6, 1.0)


## Sıcak Türk çayından yükselen yumuşak buhar dalgası (yudum veya kaşık karıştırma anında).
static func spawn_tea_steam(parent: Node, world_pos: Vector3, burst := false) -> void:
	if not _ok(parent):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.45 if burst else 0.25
	p.amount = 9 if burst else 6
	p.lifetime = 1.45 if burst else 1.15
	_soften(p, 0.10 if burst else 0.08)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.025
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 0.20
	p.initial_velocity_max = 0.48 if burst else 0.34
	p.gravity = Vector3(0.05, 0.28, 0.04)
	p.damping_min = 0.35
	p.damping_max = 0.65
	p.scale_amount_curve = _scale_curve(0.4, 1.5, 2.3, 0.4)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.94, 0.42 if burst else 0.30))
	g.set_color(1, Color(1.0, 0.98, 0.94, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.35)
	tw.tween_callback(p.queue_free)


## Çıtır simit ısırırken dökülen altın kabuk ve susam kırıntıları.
static func spawn_crumbs(parent: Node, world_pos: Vector3) -> void:
	if not _ok(parent):
		return
	var crust := LP.box(Vector3(0.015, 0.011, 0.012))
	var cm := _vcol_mat(0.85, 0.0, false, false)
	_spawn_oneshot(parent, world_pos, 10, 0.62, crust, cm,
		Color(0.84, 0.54, 0.20), 0.35, 1.15, 95.0, Vector3(0, -6.2, 0), Vector3(0, 0.2, 0), 0.6, 1.25)
	var ses := LP.box(Vector3(0.008, 0.006, 0.006))
	_spawn_oneshot(parent, world_pos, 8, 0.55, ses, cm,
		Color(0.96, 0.90, 0.72), 0.25, 0.95, 110.0, Vector3(0, -5.4, 0), Vector3(0, 0.15, 0), 0.6, 1.1)


## Meyve bıçağı darbe efekti (kırmızı kıvılcım + şok).
static func spawn_hit_burst(parent: Node, world_pos: Vector3) -> void:
	var mesh := LP.prism(Vector3(0.08, 0.09, 0.03))
	var m := _vcol_mat(0.3, 0.0, true, false)
	_spawn_oneshot(parent, world_pos, 12, 0.55, mesh, m,
		Color(1.0, 0.24, 0.18), 2.0, 4.2, 110.0, Vector3(0, -6.0, 0))


## Arabesk radyodan yükselen süzülen müzik notaları.
static func spawn_music_note(parent: Node, world_pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var glyphs := ["♪", "♫", "♬"]
	var cols := [Color(1.0, 0.82, 0.28), Color(0.58, 0.92, 1.0), Color(1.0, 0.58, 0.72)]
	var lbl := Label3D.new()
	lbl.text = glyphs[randi() % glyphs.size()]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 42
	lbl.outline_size = 8
	lbl.modulate = cols[randi() % cols.size()]
	lbl.outline_modulate = Color(0.1, 0.05, 0.02)
	parent.add_child(lbl)
	lbl.global_position = world_pos + Vector3(randf_range(-0.18, 0.18), 0.1, randf_range(-0.18, 0.18))
	var tw := lbl.create_tween().set_parallel()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.15, 1.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lbl, "global_position:x", lbl.global_position.x + randf_range(-0.35, 0.35), 1.35)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.35).set_delay(0.35)
	tw.chain().tween_callback(lbl.queue_free)


static func spawn_sound_ring(parent: Node, world_pos: Vector3, max_scale := 3.6, color := Color(1.0, 0.85, 0.32)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = LP.torus(0.46, 0.52, 18, 5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.72)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.scale = Vector3(0.25, 0.25, 0.25)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(max_scale, 0.45, max_scale), 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.72)
	tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.72)
	tw.chain().tween_callback(mi.queue_free)


static func spawn_floating_text(parent: Node, world_pos: Vector3, text: String,
		color := Color(1.0, 0.86, 0.22), font_size := 44) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = font_size
	lbl.outline_size = 11
	lbl.modulate = color
	lbl.outline_modulate = Color(0.12, 0.06, 0.02)
	lbl.no_depth_test = true
	parent.add_child(lbl)
	lbl.global_position = world_pos
	var tw := lbl.create_tween().set_parallel()
	tw.tween_property(lbl, "global_position:y", world_pos.y + 0.95, 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.15).set_delay(0.32)
	tw.chain().tween_callback(lbl.queue_free)


# ---------------------------------------------------------------------------
# v0.6 yardımcıları (diğer sistemler çağırabilir; hepsi parent null/ağaç dışıysa sessizce çıkar)
# ---------------------------------------------------------------------------

static func _ok(parent: Node) -> bool:
	return parent != null and is_instance_valid(parent) and parent.is_inside_tree()


static func _scale_curve(a: float, peak: float, b: float, peak_at := 0.3) -> Curve:
	var sc := Curve.new()
	sc.max_value = maxf(maxf(a, peak), b) + 0.01
	sc.add_point(Vector2(0.0, a))
	sc.add_point(Vector2(peak_at, peak))
	sc.add_point(Vector2(1.0, b))
	return sc


## 💦 Su fısfısı: ince damlacık konisi + yumuşak sis bulutu. dir = püskürtme yönü (dünya).
static func spawn_water_mist(parent: Node, world_pos: Vector3, dir := Vector3.FORWARD) -> void:
	if not _ok(parent):
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var drop := LP.sphere(0.018, 4, 2)
	var dm := _vcol_mat(0.08, 0.0, false, true)
	dm.emission_enabled = true
	dm.emission = Color(0.55, 0.8, 1.0)
	dm.emission_energy_multiplier = 0.35
	_spawn_oneshot(parent, world_pos, 28, 0.55, drop, dm,
		Color(0.78, 0.92, 1.0, 0.85), 3.2, 5.6, 11.0, Vector3(0, -7.5, 0), d, 0.6, 1.2)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = 10
	p.lifetime = 1.0
	p.mesh = LP.sphere(0.07, 6, 3)
	p.material_override = _vcol_mat(0.9, 0.0, true, true)
	p.direction = d
	p.spread = 18.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.damping_min = 2.0
	p.damping_max = 3.2
	p.gravity = Vector3(0, -0.4, 0)
	p.scale_amount_curve = _scale_curve(0.4, 1.4, 2.4)
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.94, 1.0, 0.42))
	g.set_color(1, Color(0.85, 0.94, 1.0, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = world_pos + d * 0.35
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)


## ✨ Parıltı: tazelenen ürünün üstünde yükselen minik yıldızlar.
static func spawn_sparkle(parent: Node, world_pos: Vector3, color := Color(1.0, 0.97, 0.7)) -> void:
	if not _ok(parent):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.55
	p.amount = 12
	p.lifetime = 0.95
	p.mesh = LP.prism(Vector3(0.05, 0.07, 0.012))
	var m := _vcol_mat(0.2, 0.0, true, true)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.6
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.28
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.25, 0)
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.scale_amount_curve = _scale_curve(0.0, 1.6, 0.0, 0.25)
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)


## 🪰 Bayat ürün sinekleri: döngüsel uçuşan sinekler. Node3D döner; çağıran queue_free() etmeli.
static func spawn_flies(parent: Node, world_pos: Vector3, count := 5) -> Node3D:
	var root := Node3D.new()
	root.name = "Flies"
	if not _ok(parent):
		return root
	parent.add_child(root)
	root.global_position = world_pos
	var fly_mesh := LP.sphere(0.014, 4, 2)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.05, 0.06)
	fm.roughness = 0.4
	for i in count:
		var f := MeshInstance3D.new()
		f.mesh = fly_mesh
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(f)
		var pts: Array[Vector3] = []
		for k in 5:
			pts.append(Vector3(randf_range(-0.26, 0.26), randf_range(0.06, 0.36), randf_range(-0.26, 0.26)))
		f.position = pts[0]
		var tw := f.create_tween().set_loops()
		for k in pts.size():
			tw.tween_property(f, "position", pts[(k + 1) % pts.size()], randf_range(0.18, 0.42)).set_trans(Tween.TRANS_SINE)
	return root


## 🤢 Koku dalgası: yeşilimsi kıvrılan buhar (döngüsel). Node3D döner; çağıran queue_free() etmeli.
static func spawn_stink(parent: Node, world_pos: Vector3) -> Node3D:
	var p := CPUParticles3D.new()
	p.name = "Stink"
	p.amount = 7
	p.lifetime = 1.8
	p.mesh = LP.sphere(0.045, 5, 3)
	p.material_override = _vcol_mat(0.9, 0.0, true, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.18
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0, 0.08, 0)
	p.tangential_accel_min = -0.6
	p.tangential_accel_max = 0.6
	p.scale_amount_curve = _scale_curve(0.3, 1.0, 1.9, 0.4)
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.72, 0.25, 0.0))
	g.add_point(0.25, Color(0.55, 0.72, 0.25, 0.34))
	g.set_color(g.get_point_count() - 1, Color(0.45, 0.55, 0.22, 0.0))
	p.color_ramp = g
	if _ok(parent):
		parent.add_child(p)
		p.global_position = world_pos
		p.emitting = true
	return p


## ♨️ Döngüsel buhar (semaver, simit tepsisi, sıcak çay). Node3D döner.
static func spawn_steam(parent: Node, world_pos: Vector3, strength := 1.0) -> Node3D:
	var p := CPUParticles3D.new()
	p.name = "Steam"
	p.amount = int(8 * strength) + 2
	p.lifetime = 2.2
	p.mesh = LP.sphere(0.05, 5, 3)
	p.material_override = _vcol_mat(0.9, 0.0, false, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.05, 0.12, 0.02)
	p.damping_min = 0.1
	p.damping_max = 0.3
	p.scale_amount_curve = _scale_curve(0.35, 1.2, 2.6, 0.35)
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.95, 0.97, 0.0))
	g.add_point(0.15, Color(0.95, 0.95, 0.97, 0.32))
	g.set_color(g.get_point_count() - 1, Color(0.95, 0.95, 0.97, 0.0))
	p.color_ramp = g
	if _ok(parent):
		parent.add_child(p)
		p.global_position = world_pos
		p.emitting = true
	return p


## 🎉 Kombo patlaması: n büyüdükçe daha çok renkli konfeti + altın halka (+ n>=5 ise para yağmuru).
static func spawn_combo_burst(parent: Node, world_pos: Vector3, n := 3) -> void:
	if not _ok(parent):
		return
	var k := clampi(n, 1, 12)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 14 + k * 5
	p.lifetime = 1.25
	p.mesh = LP.box(Vector3(0.05, 0.004, 0.032))
	p.material_override = _vcol_mat(0.5, 0.0, false, false)
	(p.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	p.direction = Vector3.UP
	p.spread = 48.0
	p.initial_velocity_min = 2.6 + float(k) * 0.12
	p.initial_velocity_max = 4.6 + float(k) * 0.2
	p.gravity = Vector3(0, -5.0, 0)
	p.damping_min = 1.2
	p.damping_max = 2.4
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.particle_flag_rotate_y = true
	var ig := Gradient.new()
	ig.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var confetti_cols := [Color(0.95, 0.2, 0.2), Color(1.0, 0.82, 0.15), Color(0.2, 0.75, 0.35),
		Color(0.2, 0.55, 1.0), Color(0.9, 0.35, 0.85), Color(1.0, 1.0, 1.0)]
	ig.set_color(0, confetti_cols[0])
	ig.set_offset(1, 1.0)
	ig.set_color(1, confetti_cols[confetti_cols.size() - 1])
	for i in range(1, confetti_cols.size() - 1):
		ig.add_point(float(i) / float(confetti_cols.size()), confetti_cols[i])
	p.color_initial_ramp = ig
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)
	spawn_sound_ring(parent, world_pos, 2.4 + float(k) * 0.25, Color(1.0, 0.8, 0.25))
	if k >= 5:
		burst_coins(parent, world_pos + Vector3(0, 0.2, 0), 6 + k)


## 💧 Su sıçraması (su birikintisine basınca).
static func spawn_splash(parent: Node, world_pos: Vector3) -> void:
	if not _ok(parent):
		return
	var drop := LP.sphere(0.02, 4, 2)
	var m := _vcol_mat(0.1, 0.0, false, true)
	_spawn_oneshot(parent, world_pos, 12, 0.45, drop, m, Color(0.75, 0.85, 0.95, 0.8),
		1.2, 2.4, 38.0, Vector3(0, -9.0, 0), Vector3.UP, 0.6, 1.1)
	spawn_sound_ring(parent, world_pos + Vector3(0, 0.02, 0), 1.3, Color(0.75, 0.88, 1.0))


## 🪶 Süzülerek düşen birkaç güvercin tüyü.
static func spawn_feathers(parent: Node, world_pos: Vector3, count := 5) -> void:
	if not _ok(parent):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = count
	p.lifetime = 2.4
	p.mesh = LP.box(Vector3(0.05, 0.003, 0.022))
	var m := _vcol_mat(0.9, 0.0, false, true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -0.55, 0)
	p.damping_min = 1.0
	p.damping_max = 1.6
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	p.particle_flag_rotate_y = true
	var g := Gradient.new()
	g.set_color(0, Color(0.78, 0.8, 0.84, 1.0))
	g.add_point(0.8, Color(0.78, 0.8, 0.84, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.78, 0.8, 0.84, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)


## 🌧️ Yağmur: kameranın etrafında düşen GPU damlaları + yerde sıçrama halkaları.
## Dönen Node3D'yi her kare kameranın x/z konumuna taşıyın (y=0). Damlalar dünya uzayındadır.
## set_rain_amount(node, 0..1) ile yoğunluk ayarlanır.
static func spawn_rain(parent: Node, amount := 2400) -> Node3D:
	var root := Node3D.new()
	root.name = "Rain"
	# --- Damlalar
	var drops := GPUParticles3D.new()
	drops.name = "Drops"
	drops.amount = amount
	drops.lifetime = 1.05
	drops.preprocess = 1.0
	drops.local_coords = false
	drops.position = Vector3(0, 15.0, 0)
	drops.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 26, 40))
	drops.collision_base_size = 0.02
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(17.0, 1.0, 17.0)
	pm.direction = Vector3(0.06, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 17.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.particle_flag_align_y = true
	pm.scale_min = 0.75
	pm.scale_max = 1.25
	drops.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.62)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.78, 0.84, 0.92, 0.32)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.billboard_keep_scale = true
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = dm
	drops.draw_pass_1 = q
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(drops)
	# --- Yer sıçramaları
	var spl := GPUParticles3D.new()
	spl.name = "Splashes"
	spl.amount = int(amount / 12)
	spl.lifetime = 0.32
	spl.local_coords = false
	spl.position = Vector3(0, 0.03, 0)
	spl.visibility_aabb = AABB(Vector3(-16, -1, -16), Vector3(32, 3, 32))
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(13.0, 0.0, 13.0)
	sm.gravity = Vector3.ZERO
	sm.initial_velocity_min = 0.0
	sm.initial_velocity_max = 0.0
	var sc := CurveTexture.new()
	sc.curve = _scale_curve(0.25, 1.0, 1.35, 0.5)
	sm.scale_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.55))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	sm.color_ramp = rt
	spl.process_material = sm
	var ring := LP.torus(0.035, 0.06, 10, 3)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.vertex_color_use_as_albedo = true
	rm.albedo_color = Color(0.85, 0.9, 1.0, 0.7)
	ring.surface_set_material(0, rm)
	spl.draw_pass_1 = ring
	spl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spl)
	if _ok(parent):
		parent.add_child(root)
	return root


static func set_rain_amount(rain: Node, k: float) -> void:
	if rain == null or not is_instance_valid(rain):
		return
	var on := k > 0.01
	for n in ["Drops", "Splashes"]:
		var p := rain.get_node_or_null(n) as GPUParticles3D
		if p:
			p.amount_ratio = clampf(k, 0.0, 1.0)
			p.emitting = on
	if rain is Node3D:
		(rain as Node3D).visible = on
