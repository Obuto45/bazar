extends RefCounted
## Düşük poligonlu 3D partikül ve görsel geri bildirim yardımcıları.

const LP := preload("res://lowpoly.gd")


static func _vcol_mat(rough := 0.5, metallic := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metallic
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _spawn_oneshot(parent: Node, world_pos: Vector3, amount: int, lifetime: float,
		mesh: Mesh, mat: Material, color: Color, vel_min: float, vel_max: float,
		spread := 55.0, grav := Vector3(0, -8.5, 0), dir := Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.88
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = mesh
	p.material_override = mat
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = grav
	p.angular_velocity_min = -240.0
	p.angular_velocity_max = 240.0
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.25
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


## Satış anında saçılan altın para kıvılcımları.
static func burst_coins(parent: Node, world_pos: Vector3, count := 10) -> void:
	var coin_mesh := LP.cyl(0.052, 0.052, 0.016, 7)
	var m := _vcol_mat(0.22, 0.85, false)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.18)
	m.emission_energy_multiplier = 0.9
	_spawn_oneshot(parent, world_pos, count, 0.85, coin_mesh, m,
		Color(1.0, 0.84, 0.22), 2.2, 4.4, 52.0, Vector3(0, -9.0, 0))


## Kasa bırakma / ürün yerleştirme yumuşak toz bulutu.
static func burst_dust(parent: Node, world_pos: Vector3, color := Color(0.95, 0.9, 0.78), count := 7) -> void:
	var puff := LP.sphere(0.055, 5, 3)
	var m := _vcol_mat(0.95, 0.0, false)
	_spawn_oneshot(parent, world_pos, count, 0.5, puff, m,
		color, 0.7, 1.9, 140.0, Vector3(0, 0.6, 0))


## Müşteri memnuniyeti (yeşil/altın yıldız) veya kızgınlık/ceza (kırmızı duman).
static func burst_mood(parent: Node, world_pos: Vector3, happy: bool) -> void:
	var mesh := LP.box(Vector3(0.06, 0.06, 0.06)) if happy else LP.sphere(0.065, 5, 3)
	var col := Color(0.42, 1.0, 0.55) if happy else Color(0.95, 0.28, 0.22)
	var m := _vcol_mat(0.4, 0.0, happy)
	_spawn_oneshot(parent, world_pos, 9 if happy else 7, 0.7, mesh, m,
		col, 1.4, 2.8, 70.0, Vector3(0, 1.4, 0) if happy else Vector3(0, 0.8, 0))


## Bağırırken veya tezgah zili çalarken yayılan 3D ses halkası.
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
	m.no_depth_test = false
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.scale = Vector3(0.25, 0.25, 0.25)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(max_scale, 0.45, max_scale), 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.72)
	tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.72)
	tw.chain().tween_callback(mi.queue_free)


## Havaya süzülen 3D bilgilendirme / para / ceza yazısı.
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


## Çeşme tepesinden fışkıran sürekli su damlacıkları.
static func build_fountain_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.05
	p.mesh = LP.sphere(0.048, 5, 3)
	var m := _vcol_mat(0.15, 0.0, false)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 34.0
	p.initial_velocity_min = 2.1
	p.initial_velocity_max = 3.1
	p.gravity = Vector3(0, -6.8, 0)
	p.scale_amount_min = 0.65
	p.scale_amount_max = 1.25
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.94, 1.0, 0.9))
	grad.set_color(1, Color(0.38, 0.74, 0.96, 0.15))
	p.color_ramp = grad
	return p
