extends RefCounted
## Düşük poligonlu 3D partiküller: altın para, toz, duman, kor, müzik notaları, darbe yıldızları ve ses halkaları.

const LP := preload("res://lowpoly.gd")


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
	p.mesh = LP.sphere(0.075 if thick else 0.048, 6, 4)
	var m := _vcol_mat(0.95, 0.0, false, true)
	p.material_override = m
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
	var grad := Gradient.new()
	var base_c := Color(0.76, 0.80, 0.86, 0.62) if thick else Color(0.86, 0.88, 0.92, 0.52)
	grad.set_color(0, base_c)
	grad.add_point(0.55, Color(base_c.r, base_c.g, base_c.b, 0.30))
	grad.set_color(1, Color(base_c.r, base_c.g, base_c.b, 0.0))
	p.color_ramp = grad
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
