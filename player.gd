extends CharacterBody3D
## Oyuncu: yuvarlak hatlı karakter (models/character.glb), 1. şahıs hareket + ayak sesleri + kamera sarsıntısı,
## 3D hedef vurgusu, proximity sesli sohbet, bağırma dalgaları, toptancı/depo kasa alımı, satış ve yükseltmeler.

const MODEL := preload("res://models/character.glb")
const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const StallScript := preload("res://stall.gd")
const VFX := preload("res://vfx.gd")

signal money_earned(amount: int, total: int, tip: int)
signal money_spent(amount: int, total: int, reason: String)
signal open_upgrade_shop()

const STARTING_MONEY := 120
const WALK := 3.6
const RUN := 6.8
const JUMP := 5.2
const GRAVITY := 14.0
const SENS := 0.0025
const HEAD_LIMIT := 1.3
const EYE_Y := 1.16
const EYE_FWD := 0.12
# Proximity sesli sohbet
const VOICE_BUS := "VoiceRecord"
const VOICE_RATE := 24000
const VOICE_CHUNK := 480
const VOICE_GEN_SEC := 0.25
const VOICE_PREBUF := 1440
const VOICE_MAX_BUF := 4800
const VOICE_DB_MIN := -46.0
const VOICE_DB_MAX := -12.0
const VOICE_UNIT_SIZE := 3.5
const VOICE_MAX_DIST := 22.0
# Bağırma eşikleri
const SHOUT_DB_MIN := -36.0
const SHOUT_DB_MAX := -10.0
const SHOUT_KEY_POWER := 0.62
const SHOUT_ON := 0.55
const SHOUT_CALLS := ["Taze %s! %d TL!", "Gel gel! %s %d lira!", "Kaçırma! %s sadece %d TL!", "Bal gibi %s! %d TL!"]
const HAIRS := [Color(0.2, 0.12, 0.07), Color(0.08, 0.06, 0.05), Color(0.75, 0.55, 0.25), Color(0.55, 0.22, 0.1),
	Color(0.4, 0.28, 0.18), Color(0.85, 0.8, 0.7)]
const SHIRTS := [Color(0.85, 0.2, 0.18), Color(0.2, 0.5, 0.9), Color(0.98, 0.75, 0.15), Color(0.3, 0.75, 0.35),
	Color(0.65, 0.35, 0.85), Color(1.0, 0.5, 0.7), Color(0.15, 0.75, 0.75), Color(1.0, 0.55, 0.15)]

var spawn_pos := Vector3.ZERO
var npc := false
var color_id := -1

var rig: Node3D
var head: Node3D
var parts := {}
var rest := {}
var cam_root: Node3D
var cam: Camera3D
var _ray: RayCast3D
var _held_anchor: Node3D
var _held_visual: Node3D
var _fp_crate_anchor: Node3D
var _fp_crate_visual: Node3D
var _hl_box: Node3D
var _hl_mat: StandardMaterial3D

# Ekonomi ve günlük istatistikler
var money := STARTING_MONEY
var daily_revenue := 0
var daily_spent := 0
var daily_fines := 0
var daily_tips := 0
var daily_sold := 0
var daily_haggles := 0

var held_crate := false
var held_item := ""
var held_count := 0
var shout_power := 0.0
var _shout_lbl: Label3D
var _shout_ring_cd := 0.0
var interact_hint := ""
var has_target := false
var _place_cd := 0.0
var _place_held := false
var _place_kick := 0.0
var _trauma := 0.0
var _shake_t := 0.0
var _prev_step_half := 0

var tag: Label3D
var mouth_node: Node3D
var mouth_rest := Vector3.ZERO
var eye_l: Node3D
var eye_r: Node3D
var pupil_l: Node3D
var pupil_r: Node3D
var _blink_cd := 2.4
var _blink_t := 0.0
var _saccade_cd := 1.6
var _saccade_target := Vector2.ZERO
var _saccade_cur := Vector2.ZERO

var mic_muted := false
var talk_level := 0.0
var talk_db := -60.0
var talk_smooth := 0.0
var _voice_cap: AudioEffectCapture
var _voice_accum: PackedFloat32Array = PackedFloat32Array()
var _voice_hold := 0.0
var _resamp_pos := 0.0
var _resamp_prev := 0.0
var _hp_prev_in := 0.0
var _hp_prev_out := 0.0
var _lp_prev := 0.0
var _voice_player: AudioStreamPlayer3D
var _voice_pb: AudioStreamGeneratorPlayback
var _voice_gen_cap := 0
var _rx_buf: PackedFloat32Array = PackedFloat32Array()
var _rx_playing := false
var _rx_fade := 0.0
var _rx_last_s := 0.0
var _remote_talk := 0.0
var _remote_talk_t := 0.0
var _base_tag := ""

var look_yaw := PI
var look_pitch := 0.0
var body_yaw := 0.0
var turning := false
var spd := 0.0
var air := false
var phase := 0.0
var land_t := 0.0
var bob_k := 0.0
var net_pos := Vector3.ZERO


func face_yaw() -> float:
	return look_yaw + PI


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _ready() -> void:
	var id := color_id if color_id >= 0 else name.to_int()
	position = spawn_pos
	net_pos = spawn_pos
	body_yaw = face_yaw()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32; cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	add_child(col)
	_build_model(HAIRS[(id / 8 + id) % HAIRS.size()], SHIRTS[id % SHIRTS.size()])
	tag = Label3D.new()
	_base_tag = Net.display_name(id)
	tag.text = _base_tag
	tag.position.y = 1.65
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	tag.no_depth_test = true
	add_child(tag)
	if npc:
		tag.hide()
	elif is_multiplayer_authority():
		tag.hide()
		for n in ["Body", "Head"]:
			for mi in parts[n].find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		cam_root = Node3D.new()
		add_child(cam_root)
		cam = Camera3D.new()
		cam.fov = 78
		cam.near = 0.04
		cam_root.add_child(cam)
		cam.current = true
		_ray = RayCast3D.new()
		_ray.target_position = Vector3(0, 0, -3.7)
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = false
		_ray.collision_mask = 4
		cam.add_child(_ray)
		_fp_crate_anchor = Node3D.new()
		_fp_crate_anchor.position = Vector3(0.0, -0.34, -0.58)
		_fp_crate_anchor.rotation_degrees = Vector3(14.0, 0.0, 0.0)
		cam.add_child(_fp_crate_anchor)
		_build_highlight_box()
		_setup_voice_capture()
	else:
		_setup_voice_playback()
		_shout_lbl = Label3D.new()
		_shout_lbl.position.y = 2.02
		_shout_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_shout_lbl.font_size = 44
		_shout_lbl.outline_size = 12
		_shout_lbl.modulate = Color(1.0, 0.85, 0.25)
		_shout_lbl.outline_modulate = Color(0.25, 0.08, 0.02)
		_shout_lbl.no_depth_test = true
		_shout_lbl.hide()
		add_child(_shout_lbl)


## Bakılan yuva / kasa / zil / müşteri çevresinde parlayan altın 3D seçim çerçevesi.
func _build_highlight_box() -> void:
	_hl_box = Node3D.new()
	_hl_box.top_level = true
	_hl_mat = StandardMaterial3D.new()
	_hl_mat.albedo_color = Color(1.0, 0.88, 0.35, 0.9)
	_hl_mat.emission_enabled = true
	_hl_mat.emission = Color(1.0, 0.82, 0.28)
	_hl_mat.emission_energy_multiplier = 2.0
	_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var t := 0.022
	# Birim küpün 12 kenarı (scale ile hedef kutuya oturur)
	var edge_x := LP.box(Vector3(1.0, t, t))
	var edge_y := LP.box(Vector3(t, 1.0, t))
	var edge_z := LP.box(Vector3(t, t, 1.0))
	for a in [-0.5, 0.5]:
		for b in [-0.5, 0.5]:
			for pair in [[edge_x, Vector3(0, a, b)], [edge_y, Vector3(a, 0, b)], [edge_z, Vector3(a, b, 0)]]:
				var mi := MeshInstance3D.new()
				mi.mesh = pair[0]
				mi.position = pair[1]
				mi.material_override = _hl_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_hl_box.add_child(mi)
	_hl_box.hide()
	add_child(_hl_box)


func _build_model(hair: Color, shirt: Color) -> void:
	var src := MODEL.instantiate()
	rig = Node3D.new()
	add_child(rig)
	_held_anchor = Node3D.new()
	_held_anchor.position = Vector3(0.0, 0.54, 0.38)
	rig.add_child(_held_anchor)
	head = Node3D.new()
	add_child(head)
	for n in ["Body", "Head", "HandL", "HandR", "FootL", "FootR"]:
		var m: Node3D = src.find_child(n, true, false)
		var w := Node3D.new()
		w.name = n
		rest[n] = m.position
		m.get_parent().remove_child(m)
		m.owner = null
		m.transform = Transform3D.IDENTITY
		w.add_child(m)
		if n == "Head":
			head.add_child(w)
			head.position = rest[n]
		else:
			rig.add_child(w)
			w.position = rest[n]
		parts[n] = w
		var meshes: Array = w.find_children("*", "MeshInstance3D", true, false)
		if m is MeshInstance3D:
			meshes.append(m)
		for mi: MeshInstance3D in meshes:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if mat and mat.resource_name in ["Hair", "Shirt"]:
					var c := mat.duplicate() as BaseMaterial3D
					c.albedo_color = hair if mat.resource_name == "Hair" else shirt
					mi.set_surface_override_material(i, c)
	mouth_node = parts["Head"].find_child("Mouth", true, false)
	if mouth_node:
		mouth_rest = mouth_node.position
	eye_l = parts["Head"].find_child("EyeL", true, false)
	eye_r = parts["Head"].find_child("EyeR", true, false)
	pupil_l = parts["Head"].find_child("PupilL", true, false)
	pupil_r = parts["Head"].find_child("PupilR", true, false)
	_blink_cd = randf_range(1.2, 4.5)
	_saccade_cd = randf_range(0.8, 2.6)
	src.free()


func _unhandled_input(e: InputEvent) -> void:
	if npc or not is_multiplayer_authority():
		return
	if e.is_action_pressed("mic_mute"):
		mic_muted = not mic_muted
		if mic_muted:
			talk_level = 0.0
			talk_db = -60.0
			_voice_accum.clear()
		return
	if e.is_action_pressed("upgrade_shop"):
		open_upgrade_shop.emit()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_place_held = false
		return
	if e is InputEventMouseMotion:
		look_yaw = wrapf(look_yaw - e.relative.x * SENS, -PI, PI)
		look_pitch = clampf(look_pitch - e.relative.y * SENS, -1.45, 1.35)
	elif e.is_action_pressed("interact"):
		_do_interact()
	elif e.is_action_pressed("ring_bell"):
		_do_ring_bell()
	elif e.is_action_pressed("refuse_offer"):
		_do_sell_to_customer(true)
	elif e.is_action_pressed("throw_crate"):
		_do_throw_crate()
	elif e.is_action_pressed("price_down"):
		_do_adjust_price(-1)
	elif e.is_action_pressed("price_up"):
		_do_adjust_price(1)
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_place_held = e.pressed
			if e.pressed:
				_try_place_once()
				var st := _find_stall(_my_peer_id())
				_place_cd = 0.16 if (st and st.has_upgrade("big_crate")) else 0.24
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_do_adjust_price(1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_do_adjust_price(-1)


func _process(dt: float) -> void:
	if npc:
		return
	_tick_shout_rings(dt)
	if is_multiplayer_authority():
		_process_voice_capture(dt)
		_process_interaction(dt)
	else:
		_process_voice_remote(dt)
		_pump_voice_playback()


func _tick_shout_rings(dt: float) -> void:
	if _shout_ring_cd > 0.0:
		_shout_ring_cd = maxf(_shout_ring_cd - dt, 0.0)
	if shout_power >= SHOUT_ON and _shout_ring_cd <= 0.0:
		_shout_ring_cd = 0.58
		var st := _find_stall(_my_peer_id())
		var has_mega: bool = st != null and st.has_upgrade("megaphone")
		var rad := (3.2 + shout_power * 1.6) * (1.4 if has_mega else 1.0)
		var col := Color(1.0, 0.78, 0.2) if has_mega else Color(1.0, 0.92, 0.55)
		VFX.spawn_sound_ring(_find_world(), global_position + Vector3(0, 1.25, 0), rad, col)


func _physics_process(dt: float) -> void:
	if npc:
		pass
	elif is_multiplayer_authority():
		_local(dt)
	else:
		position = position.lerp(net_pos, minf(dt * 15.0, 1.0))
	_turn_body(dt)
	_animate(dt)
	_animate_mouth(dt)
	_animate_eyes(dt)
	if cam_root:
		_camera(dt)


func _local(dt: float) -> void:
	var inp := Vector2.ZERO
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured:
		inp = Input.get_vector("left", "right", "fwd", "back")
	var dir := (Basis(Vector3.UP, look_yaw) * Vector3(inp.x, 0, inp.y)).normalized()
	var running := Input.is_action_pressed("run") and inp.y < 0.0
	var target := dir * (RUN if running else WALK)
	var accel := (14.0 if target != Vector3.ZERO else 18.0) if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * dt * WALK)
	velocity.z = move_toward(velocity.z, target.z, accel * dt * WALK)
	var was_air := air
	if is_on_floor():
		if captured and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	if global_position.y < -10.0:
		global_position = spawn_pos
		velocity = Vector3.ZERO
	spd = Vector2(velocity.x, velocity.z).length()
	air = not is_on_floor()
	if was_air and not air:
		land_t = 0.22
		add_trauma(0.18)
		Sfx.play("step", -10.0, 0.85)
		VFX.burst_dust(_find_world(), global_position + Vector3(0, 0.08, 0), Color(0.88, 0.78, 0.62), 5)
	var manual_shout := SHOUT_KEY_POWER if (captured and Input.is_action_pressed("shout")) else 0.0
	var mic_shout := 0.0 if mic_muted else \
		clampf((talk_db - SHOUT_DB_MIN) / (SHOUT_DB_MAX - SHOUT_DB_MIN), 0.0, 1.0) * 1.35
	shout_power = lerpf(shout_power, maxf(manual_shout, mic_shout), minf(dt * 10.0, 1.0))
	if Net.online():
		sync_state.rpc(global_position, body_yaw, look_yaw, look_pitch, spd, air, shout_power)


func _camera(dt: float) -> void:
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0)
	bob_k = lerpf(bob_k, 0.0 if air else clampf(spd / WALK, 0.0, 1.0), minf(dt * 8.0, 1.0))
	var amp := lerpf(0.032, 0.068, kr) * bob_k
	var bob := Vector3(cos(phase) * amp * 0.55, absf(sin(phase)) * amp - amp * 0.5 - land_t * 0.45, 0)

	# Trauma tabanlı yumuşak kamera sarsıntısı
	var shake_off := Vector3.ZERO
	var shake_roll := 0.0
	if _trauma > 0.0:
		_trauma = maxf(_trauma - dt * 1.8, 0.0)
		var sh := _trauma * _trauma
		_shake_t += dt * 32.0
		shake_off = Vector3(sin(_shake_t * 1.7) * 0.045 * sh, sin(_shake_t * 2.3) * 0.035 * sh, 0.0)
		shake_roll = sin(_shake_t * 1.2) * 0.04 * sh

	var yb := Basis(Vector3.UP, look_yaw)
	cam_root.position = Vector3(0, EYE_Y, 0) + yb * (Vector3(0, 0, -EYE_FWD) + bob + shake_off)
	cam_root.rotation = Vector3(look_pitch, look_yaw, -cos(phase) * 0.011 * bob_k * (1.0 + kr) + shake_roll)
	cam.fov = lerpf(cam.fov, 78.0 + kr * 6.0, minf(dt * 6.0, 1.0))

	# Birinci şahıs kasa salınımı ve dizme hareketi
	if _fp_crate_anchor:
		_place_kick = lerpf(_place_kick, 0.0, minf(dt * 14.0, 1.0))
		var sway_x := cos(phase) * 0.014 * bob_k
		var sway_y := absf(sin(phase)) * 0.014 * bob_k
		_fp_crate_anchor.position = Vector3(sway_x, -0.34 - sway_y + _place_kick * 0.04, -0.58 - _place_kick * 0.09)
		_fp_crate_anchor.rotation_degrees = Vector3(14.0 - _place_kick * 16.0, 0.0, -sway_x * 65.0)


@rpc("authority", "unreliable_ordered")
func sync_state(p: Vector3, by: float, ly: float, lp: float, s: float, a: bool, sp := 0.0) -> void:
	net_pos = p
	body_yaw = by
	look_yaw = ly
	look_pitch = lp
	if not a and air:
		land_t = 0.22
	spd = s
	air = a
	shout_power = sp


func _turn_body(dt: float) -> void:
	if npc or not is_multiplayer_authority():
		rig.rotation.y = lerp_angle(rig.rotation.y, body_yaw, minf(dt * 14.0, 1.0))
		return
	if spd > 0.4:
		body_yaw = lerp_angle(body_yaw, atan2(velocity.x, velocity.z), minf(dt * 9.0, 1.0))
		turning = false
	else:
		var diff := wrapf(face_yaw() - body_yaw, -PI, PI)
		if absf(diff) > HEAD_LIMIT * 0.85:
			turning = true
		if turning:
			body_yaw = lerp_angle(body_yaw, face_yaw(), minf(dt * 7.0, 1.0))
			turning = absf(diff) > 0.15
	rig.rotation.y = body_yaw


func _animate(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var kw := clampf(spd / WALK, 0.0, 1.0)
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0)
	var idle := 1.0 - kw
	var stride_full := lerpf(0.28, 0.42, kr)
	var stride := stride_full * kw
	var lift := lerpf(0.11, 0.20, kr) * kw
	if not air and spd > 0.08:
		phase = wrapf(phase + dt * (spd / stride_full) * 0.94, 0.0, TAU)
		# Adım fazıyla tam senkron ayak sesi
		if not npc and is_multiplayer_authority() and spd > 0.65:
			var cur_half := 0 if phase < PI else 1
			if cur_half != _prev_step_half:
				_prev_step_half = cur_half
				Sfx.play("step", -14.0 + kr * 3.5, 0.96 + float(cur_half) * 0.08)
	land_t = maxf(land_t - dt, 0.0)
	var land := land_t / 0.22
	var breathe := sin(t * 2.2)
	var f := minf(dt * 18.0, 1.0)

	for side in [-1.0, 1.0]:
		var n := "FootR" if side < 0 else "FootL"
		var c: float = phase + (0.0 if side < 0 else PI)
		var p: Vector3 = rest[n]
		var r := Vector3.ZERO
		if air:
			p += Vector3(0, 0.14, 0.06 * side)
			r.x = -0.5
		else:
			p.z += -cos(c) * stride
			p.y += maxf(0.0, sin(c)) * lift
			p.x += side * 0.03 * land
			r.x = -sin(c) * lerpf(0.42, 0.65, kr) * kw
		var w: Node3D = parts[n]
		w.position = w.position.lerp(p, f)
		w.rotation = w.rotation.lerp(r, f)

	for side in [-1.0, 1.0]:
		var n := "HandR" if side < 0 else "HandL"
		var c: float = phase + (0.0 if side < 0 else PI)
		var p: Vector3 = rest[n]
		var r := Vector3.ZERO
		if air:
			p += Vector3(side * 0.12, 0.42, 0.05)
			r = Vector3(-0.4, 0, side * 0.6)
		else:
			var hand_stride := lerpf(0.24, 0.38, kr) * kw
			p.z += cos(c) * hand_stride + kr * 0.07
			p.y += kr * 0.12 + maxf(0.0, cos(c)) * 0.05 * kw + breathe * 0.015 * idle - land * 0.08
			p.x += side * (0.02 * sin(t * 1.3 + side) * idle + 0.015 * kw)
			r.x = -cos(c) * lerpf(0.55, 1.0, kr) * kw
		var w: Node3D = parts[n]
		w.position = w.position.lerp(p, f)
		w.rotation = w.rotation.lerp(r, f)

	var body: Node3D = parts["Body"]
	var bp: Vector3 = rest["Body"]
	bp.y += absf(sin(phase)) * lerpf(0.04, 0.075, kr) * kw + breathe * 0.008 * idle - land * 0.07 + (0.04 if air else 0.0)
	body.position = body.position.lerp(bp, f)
	body.rotation = body.rotation.lerp(
		Vector3(0.06 * kw + 0.19 * kr, cos(phase) * lerpf(0.09, 0.15, kr) * kw, sin(phase) * 0.06 * kw), f)
	var sq := 1.0 + breathe * 0.015 * idle - land * 0.12 + (0.05 if air else 0.0)
	var side_sq := 1.0 + (1.0 - sq) * 0.5
	body.scale = body.scale.lerp(Vector3(side_sq, sq, side_sq), f)

	var hp: Vector3 = rest["Head"]
	hp.y += (body.position.y - rest["Body"].y) * 1.1 + breathe * 0.01 * idle
	head.position = head.position.lerp(hp, f)
	var rel := clampf(wrapf(face_yaw() - rig.rotation.y, -PI, PI), -HEAD_LIMIT, HEAD_LIMIT)
	head.rotation.y = lerp_angle(head.rotation.y, rig.rotation.y + rel, minf(dt * 20.0, 1.0))
	head.rotation.x = lerpf(head.rotation.x, -look_pitch * 0.6, f)
	head.rotation.z = lerpf(head.rotation.z, -sin(phase) * 0.045 * kw, f)


# ---------- Proximity Sesli Sohbet ve Ağız/Göz Animasyonu ----------

func set_display_name(n: String) -> void:
	_base_tag = n
	_refresh_tag()


func _refresh_tag() -> void:
	if tag:
		tag.text = ("🔊 " + _base_tag) if (not is_multiplayer_authority() and talk_smooth > 0.08) else _base_tag


func _setup_voice_capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var bus := AudioServer.get_bus_index(VOICE_BUS)
	if bus == -1:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, VOICE_BUS)
		AudioServer.set_bus_mute(bus, true)
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new(), 0)
	for i in AudioServer.get_bus_effect_count(bus):
		var ef := AudioServer.get_bus_effect(bus, i)
		if ef is AudioEffectCapture:
			_voice_cap = ef
			break
	var mic := AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = VOICE_BUS
	mic.autoplay = true
	add_child(mic)


func _setup_voice_playback() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VOICE_RATE
	gen.buffer_length = VOICE_GEN_SEC
	_voice_player = AudioStreamPlayer3D.new()
	_voice_player.stream = gen
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_player.unit_size = VOICE_UNIT_SIZE
	_voice_player.max_distance = VOICE_MAX_DIST
	_voice_player.panning_strength = 1.15
	_voice_player.volume_db = 0.0
	_voice_player.max_db = 2.0
	head.add_child(_voice_player)
	_voice_player.play()
	_voice_pb = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _voice_pb:
		_voice_gen_cap = _voice_pb.get_frames_available()


func _process_voice_capture(dt: float) -> void:
	if _voice_cap == null:
		return
	var avail := _voice_cap.get_frames_available()
	if avail <= 0:
		_voice_hold = maxf(_voice_hold - dt, 0.0)
		if _voice_hold <= 0.0:
			talk_level = lerpf(talk_level, 0.0, minf(dt * 12.0, 1.0))
			talk_db = lerpf(talk_db, -60.0, minf(dt * 10.0, 1.0))
		return
	var frames := _voice_cap.get_buffer(avail)
	if mic_muted:
		talk_level = 0.0
		talk_db = -60.0
		_voice_accum.clear()
		_resamp_pos = 0.0
		return
	var mix_rate := maxf(AudioServer.get_mix_rate(), 16000.0)
	var hp_a := 1.0 / (1.0 + TAU * 90.0 / mix_rate)
	var lp_a := clampf(TAU * 7500.0 / (mix_rate + TAU * 7500.0), 0.05, 1.0)
	var n := frames.size()
	var mono := PackedFloat32Array()
	mono.resize(n)
	var sum_sq := 0.0
	for i in n:
		var v := frames[i]
		var x := 0.5 * (v.x + v.y)
		var hp := hp_a * (_hp_prev_out + x - _hp_prev_in)
		_hp_prev_in = x
		_hp_prev_out = hp
		_lp_prev += lp_a * (hp - _lp_prev)
		var y := 0.85 * tanh(_lp_prev * 1.05)
		mono[i] = y
		sum_sq += y * y
	var rms := sqrt(sum_sq / float(n))
	var db := linear_to_db(maxf(rms, 0.00001))
	talk_db = db
	var lvl := clampf((db - VOICE_DB_MIN) / (VOICE_DB_MAX - VOICE_DB_MIN), 0.0, 1.0)
	talk_level = lvl
	if lvl > 0.02:
		_voice_hold = 0.28
	else:
		_voice_hold = maxf(_voice_hold - dt, 0.0)
	if _voice_hold <= 0.0:
		_voice_accum.clear()
		_resamp_pos = 0.0
		_resamp_prev = mono[n - 1]
		return
	var step := mix_rate / float(VOICE_RATE)
	while _resamp_pos < float(n):
		var idx := int(floor(_resamp_pos))
		var frac := _resamp_pos - float(idx)
		var s0 := _resamp_prev if idx < 0 else mono[idx]
		var s1 := mono[mini(idx + 1, n - 1)]
		_voice_accum.append(lerpf(s0, s1, frac))
		_resamp_pos += step
	_resamp_pos -= float(n)
	_resamp_prev = mono[n - 1]
	while _voice_accum.size() >= VOICE_CHUNK:
		var pcm := PackedByteArray()
		pcm.resize(VOICE_CHUNK * 2)
		for i in VOICE_CHUNK:
			pcm.encode_s16(i * 2, clampi(int(_voice_accum[i] * 32767.0), -32768, 32767))
		_voice_accum = _voice_accum.slice(VOICE_CHUNK)
		if Net.online():
			voice_packet.rpc(pcm, lvl)


@rpc("authority", "unreliable_ordered")
func voice_packet(pcm: PackedByteArray, lvl: float) -> void:
	if npc or is_multiplayer_authority():
		return
	_remote_talk = clampf(lvl, 0.0, 1.0)
	_remote_talk_t = 0.26
	var samples := pcm.size() / 2
	if samples <= 0:
		return
	var start := _rx_buf.size()
	_rx_buf.resize(start + samples)
	for i in samples:
		_rx_buf[start + i] = float(pcm.decode_s16(i * 2)) / 32767.0
	if _rx_buf.size() > VOICE_MAX_BUF:
		_rx_buf = _rx_buf.slice(_rx_buf.size() - VOICE_MAX_BUF)


func _pump_voice_playback() -> void:
	if _voice_pb == null and _voice_player:
		_voice_player.play()
		_voice_pb = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _voice_pb:
			_voice_gen_cap = _voice_pb.get_frames_available()
	if _voice_pb == null:
		return
	var avail := _voice_pb.get_frames_available()
	if avail <= 0:
		return
	if _voice_gen_cap < avail:
		_voice_gen_cap = avail
	if not _rx_playing:
		if _rx_buf.size() < VOICE_PREBUF:
			return
		_rx_playing = true
		_rx_fade = 0.0
	var take := mini(avail, _rx_buf.size())
	if take > 0:
		var out := PackedVector2Array()
		out.resize(take)
		var fade_step := 1.0 / 120.0
		for i in take:
			_rx_fade = minf(_rx_fade + fade_step, 1.0)
			var s := _rx_buf[i] * _rx_fade
			_rx_last_s = s
			out[i] = Vector2(s, s)
		_voice_pb.push_buffer(out)
		_rx_buf = _rx_buf.slice(take)
		return
	var queued_in_gen := _voice_gen_cap - avail
	if queued_in_gen <= 192:
		var tail := mini(avail, 120)
		if tail > 0 and absf(_rx_last_s) > 0.0005:
			var out := PackedVector2Array()
			out.resize(tail)
			for i in tail:
				var k := 1.0 - float(i + 1) / float(tail + 1)
				var s := _rx_last_s * k
				out[i] = Vector2(s, s)
			_voice_pb.push_buffer(out)
		_rx_last_s = 0.0
		_rx_playing = false


func _process_voice_remote(dt: float) -> void:
	_remote_talk_t = maxf(_remote_talk_t - dt, 0.0)
	talk_level = _remote_talk if _remote_talk_t > 0.0 else 0.0
	_refresh_tag()
	_update_shout_bubble()


func _update_shout_bubble() -> void:
	if _shout_lbl == null:
		return
	var on := shout_power >= SHOUT_ON
	if on and not _shout_lbl.visible:
		_shout_lbl.text = _pick_shout_call()
	_shout_lbl.visible = on
	_shout_lbl.scale = Vector3.ONE * (0.85 + clampf(shout_power, 0.0, 1.35) * 0.3)


func _pick_shout_call() -> String:
	var st := _find_stall(_my_peer_id())
	var stocked: Array = []
	if st:
		for sl: Dictionary in st.slots:
			if sl["item"] != "" and int(sl["count"]) > 0:
				stocked.append(sl)
	if stocked.is_empty():
		return "📢 Gel gel! Buraya!"
	var pick: Dictionary = stocked.pick_random()
	return "📢 " + str(SHOUT_CALLS.pick_random()) % [Produce.ITEMS[pick["item"]]["name"], int(pick["price"])]


func _animate_mouth(dt: float) -> void:
	if mouth_node == null:
		return
	var rate := 28.0 if talk_level > talk_smooth else 14.0
	talk_smooth = lerpf(talk_smooth, talk_level, minf(dt * rate, 1.0))
	var open := maxf(talk_smooth, clampf(shout_power, 0.0, 1.0))
	mouth_node.scale = Vector3(1.0 + open * 0.35, 1.0 + open * 2.5, 1.0 + open * 0.4)
	mouth_node.position = mouth_rest + Vector3(0.0, -open * 0.016, open * 0.004)


func _animate_eyes(dt: float) -> void:
	if eye_l == null or eye_r == null:
		return
	if _blink_t > 0.0:
		_blink_t = maxf(_blink_t - dt, 0.0)
	else:
		_blink_cd -= dt
		if _blink_cd <= 0.0:
			_blink_t = 0.15
			_blink_cd = 0.26 if randf() < 0.25 else randf_range(2.2, 5.2)
	var blink_k := sin((_blink_t / 0.15) * PI) if _blink_t > 0.0 else 0.0
	var talk_pop := 1.0 + talk_smooth * 0.07
	var sy := lerpf(talk_pop, 0.08, blink_k)
	var sx := talk_pop + (1.0 - minf(sy, 1.0)) * 0.12
	eye_l.scale = Vector3(sx, sy, 1.0)
	eye_r.scale = Vector3(sx, sy, 1.0)
	if pupil_l and pupil_r:
		_saccade_cd -= dt
		if _saccade_cd <= 0.0:
			_saccade_cd = randf_range(1.1, 3.0)
			if randf() < 0.45:
				_saccade_target = Vector2.ZERO
			else:
				_saccade_target = Vector2(randf_range(-0.0085, 0.0085), randf_range(-0.005, 0.006))
		_saccade_cur = _saccade_cur.lerp(_saccade_target, minf(dt * 18.0, 1.0))
		var p_off := Vector3(_saccade_cur.x, _saccade_cur.y, 0.0)
		pupil_l.position = p_off
		pupil_r.position = p_off


# ---------- Etkileşim, Hedef Vurgusu, Toptancı, Satış ve Ekonomi ----------

func _my_peer_id() -> int:
	return name.to_int()


func _find_world() -> Node:
	return get_parent().get_parent() if get_parent() else null


func _find_main() -> Node:
	var w := _find_world()
	return w.get_parent() if w else null


func _find_stall(owner_id: int) -> Node:
	var w := _find_world()
	var sg := w.get_node_or_null("Stalls") if w else null
	return sg.get_node_or_null("Stall_%d" % owner_id) if sg else null


func _find_customer(cname: String) -> Node:
	var w := _find_world()
	var cg := w.get_node_or_null("Customers") if w else null
	return cg.get_node_or_null(cname) if cg else null


func _ray_target() -> Area3D:
	if _ray == null or not _ray.is_colliding():
		return null
	return _ray.get_collider() as Area3D


func _update_highlight(area: Area3D, show_hl: bool) -> void:
	has_target = show_hl
	if _hl_box == null:
		return
	if not show_hl or area == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_hl_box.hide()
		return
	_hl_box.show()
	_hl_box.global_transform = Transform3D(area.global_transform.basis.orthonormalized(), area.global_position)
	var sz: Vector3 = area.get_meta("hl_size", Vector3(0.7, 0.5, 0.7))
	var pulse := 1.02 + sin(Time.get_ticks_msec() * 0.01) * 0.025
	_hl_box.scale = sz * pulse


func _process_interaction(dt: float) -> void:
	var my_st := _find_stall(_my_peer_id())
	if _place_held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_place_cd -= dt
		if _place_cd <= 0.0:
			var fast: bool = my_st != null and my_st.has_upgrade("big_crate")
			if _try_place_once():
				_place_cd = 0.10 if fast else 0.17
			else:
				_place_cd = 0.11

	interact_hint = ""
	var area := _ray_target()
	var show_hl := false
	if area == null:
		_update_highlight(null, false)
		if held_crate:
			var cap: int = my_st.crate_capacity() if my_st else StallScript.CRATE_CAPACITY
			if held_count > 0:
				interact_hint = "Elde: %s Kasası (%d/%d)  •  [Q] Fırlat" % [Produce.ITEMS[held_item]["name"], held_count, cap]
			else:
				interact_hint = "Elde: Boş Kasa  •  [Q] Uzağa Fırlat"
		return

	var kind: String = str(area.get_meta("kind", ""))
	var my_id := _my_peer_id()
	var main := _find_main()
	match kind:
		"crate":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var item_id: String = str(area.get_meta("item_id", ""))
			if owner_id == my_id and Produce.ITEMS.has(item_id):
				show_hl = true
				var nm: String = Produce.ITEMS[item_id]["name"]
				var cost: int = main.get_crate_cost(my_id, item_id, false) if main else int(Produce.ITEMS[item_id]["crate_cost"])
				var cap: int = my_st.crate_capacity() if my_st else StallScript.CRATE_CAPACITY
				if held_crate:
					interact_hint = "Önce elindeki kasayı [Q] ile fırlat"
				elif cost == 0:
					interact_hint = "[E] %s Kasası Al — ACİL VERESİYE (0 TL, %d ad.)" % [nm, cap]
				else:
					interact_hint = "[E] %s Kasası Satın Al — %d TL (%d ad.)" % [nm, cost, cap]
		"wholesale_crate":
			var item_id: String = str(area.get_meta("item_id", ""))
			if Produce.ITEMS.has(item_id):
				show_hl = true
				var nm: String = Produce.ITEMS[item_id]["name"]
				var cost: int = main.get_crate_cost(my_id, item_id, true) if main else int(Produce.ITEMS[item_id]["crate_cost"])
				var cap: int = my_st.crate_capacity() if my_st else StallScript.CRATE_CAPACITY
				if held_crate:
					interact_hint = "Önce elindeki kasayı [Q] ile fırlat"
				else:
					interact_hint = "[E] Toptancıdan %s Kasası Al — %d TL (%d ad.)" % [nm, cost, cap]
		"slot":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var idx: int = int(area.get_meta("slot_idx", -1))
			var st := _find_stall(owner_id)
			if st and owner_id == my_id and idx >= 0 and idx < st.slots.size():
				show_hl = true
				var sl: Dictionary = st.slots[idx]
				var parts_txt := PackedStringArray()
				if held_crate and held_count > 0 and st.can_place(idx, held_item):
					parts_txt.append("[Sol Tık] %s Diz (%d kaldı)" % [Produce.ITEMS[held_item]["name"], held_count])
				elif held_crate and held_count == 0:
					parts_txt.append("Kasa boş! [Q] Fırlat")
				elif not held_crate and sl["count"] == 0:
					parts_txt.append("Arka depodan veya Toptancıdan [E] ile kasa al")
				if sl["item"] != "" and int(sl["count"]) > 0:
					var badge := _price_badge(sl["item"], int(sl["price"]))
					parts_txt.append("[Tekerlek / Z-X] %d TL (%s)" % [int(sl["price"]), badge])
				interact_hint = "  •  ".join(parts_txt)
		"bell":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id and my_st and my_st.has_upgrade("bell"):
				show_hl = true
				if my_st.bell_cd > 0.0:
					interact_hint = "🔔 Tezgah Zili hazırlanıyor (%.0f sn)" % ceilf(my_st.bell_cd)
				else:
					interact_hint = "[E / F] Pirinç Zili Çal! (10 sn güçlü müşteri çekimi)"
		"upgrade_board":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id:
				show_hl = true
				interact_hint = "[E / U] Tezgah Geliştirmeleri (Megafon, Işıklar, Geniş Kasa, Zil)"
		"customer":
			var c := _find_customer(str(area.get_meta("customer_name", "")))
			if c:
				var h: String = c.get_next_sell_hint(my_id)
				if h != "":
					show_hl = true
					interact_hint = h
	_update_highlight(area, show_hl)


func _price_badge(item_id: String, price: int) -> String:
	var w := _find_world()
	var sg := w.get_node_or_null("Stalls") if w else null
	var all_stalls := sg.get_children() if sg else []
	var ev := str(w.get_meta("event_item", "")) if w else ""
	var fp := StallScript.fair_price(item_id, all_stalls, ev)
	var r := float(price) / maxf(fp, 1.0)
	if float(price) > StallScript.gouge_ceiling(item_id, ev):
		return "⚠️ Zabıta Riski!"
	if r < 0.88:
		return "Ucuz"
	if r <= 1.15:
		return "Normal"
	return "Pahalı"


func _do_interact() -> void:
	var area := _ray_target()
	var my_id := _my_peer_id()
	if area == null:
		return
	var kind: String = str(area.get_meta("kind", ""))
	var main := _find_main()
	match kind:
		"crate":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var item_id: String = str(area.get_meta("item_id", ""))
			if owner_id == my_id and not held_crate and main:
				main.request_buy_crate(item_id, false)
		"wholesale_crate":
			var item_id: String = str(area.get_meta("item_id", ""))
			if not held_crate and main:
				main.request_buy_crate(item_id, true)
		"bell":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id:
				_do_ring_bell()
		"upgrade_board":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id:
				open_upgrade_shop.emit()
		"customer":
			_do_sell_to_customer(false)


func _do_ring_bell() -> void:
	var st := _find_stall(_my_peer_id())
	if st and st.has_upgrade("bell") and global_position.distance_to(st.global_position) < 4.5:
		st.request_ring_bell()


func _do_sell_to_customer(insist: bool) -> void:
	var area := _ray_target()
	if area == null or str(area.get_meta("kind", "")) != "customer":
		return
	var my_id := _my_peer_id()
	var c := _find_customer(str(area.get_meta("customer_name", "")))
	if c and c.get_next_sell_hint(my_id) != "":
		if Net.online():
			c.rpc_request_sell.rpc_id(1, my_id, insist)
		else:
			var res: Dictionary = c.try_sell_one_from(my_id, insist)
			if not res.is_empty():
				award_money(int(res["price"]), int(res.get("tip", 0)), bool(res.get("haggle", false)))


func _try_place_once() -> bool:
	if not held_crate or held_count <= 0 or held_item == "":
		return false
	var area := _ray_target()
	if area == null or str(area.get_meta("kind", "")) != "slot":
		return false
	var owner_id: int = int(area.get_meta("stall_owner", -1))
	if owner_id != _my_peer_id():
		return false
	var idx: int = int(area.get_meta("slot_idx", -1))
	var st := _find_stall(owner_id)
	if st == null:
		return false
	var from_p := _fp_crate_anchor.global_position if _fp_crate_anchor else _held_anchor.global_position
	if st.request_place(idx, held_item, from_p):
		_place_kick = 1.0
		set_held_crate(true, held_item, held_count - 1)
		return true
	return false


func _do_throw_crate() -> void:
	if not held_crate:
		return
	var fwd := -cam.global_transform.basis.z if cam else Vector3(0, 0, -1)
	var start_p := (_fp_crate_anchor.global_position if _fp_crate_anchor else global_position + Vector3(0, 0.9, 0)) + fwd * 0.25
	var vel := fwd * 9.5 + Vector3.UP * 3.4 + velocity * 0.35
	var item_id := held_item
	var cnt := held_count
	add_trauma(0.22)
	set_held_crate(false, "", 0)
	if Net.online():
		rpc_throw_crate.rpc(item_id, cnt, start_p, vel)
	else:
		rpc_throw_crate(item_id, cnt, start_p, vel)


@rpc("authority", "call_local", "reliable")
func rpc_throw_crate(item_id: String, count: int, start_p: Vector3, vel: Vector3) -> void:
	var w := _find_world()
	if w == null:
		return
	Sfx.play_3d("crate_throw", start_p, w, -3.0)
	var rb := RigidBody3D.new()
	rb.mass = 1.2
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	rb.position = start_p
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0), randf_range(-8.0, 8.0))
	rb.add_to_group("thrown_crates")
	rb.set_meta("owner_id", _my_peer_id())
	rb.set_meta("hit_done", false)
	rb.body_entered.connect(func(_b):
		if is_instance_valid(rb) and not bool(rb.get_meta("hit_done", false)):
			rb.set_meta("hit_done", true)
			Sfx.play_3d("crate_hit", rb.global_position, w, -3.0)
			VFX.burst_dust(w, rb.global_position, Color(0.85, 0.76, 0.62), 6)
	)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.42, 0.20, 0.34)
	cs.shape = sh
	rb.add_child(cs)
	rb.add_child(StallScript.build_held_crate(item_id, count))
	w.add_child(rb)
	var tw := rb.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(rb, "scale", Vector3.ONE * 0.01, 0.5)
	tw.tween_callback(rb.queue_free)


func _do_adjust_price(delta: int) -> void:
	var area := _ray_target()
	if area == null or str(area.get_meta("kind", "")) != "slot":
		return
	var owner_id: int = int(area.get_meta("stall_owner", -1))
	if owner_id != _my_peer_id():
		return
	var idx: int = int(area.get_meta("slot_idx", -1))
	var st := _find_stall(owner_id)
	if st:
		st.request_adjust_price(idx, delta)


func set_held_crate(has_crate: bool, item_id: String, count: int) -> void:
	if Net.online():
		rpc_set_held_crate.rpc(has_crate, item_id, count)
	else:
		rpc_set_held_crate(has_crate, item_id, count)


@rpc("authority", "call_local", "reliable")
func rpc_set_held_crate(has_crate: bool, item_id: String, count: int) -> void:
	_apply_held_crate(has_crate, item_id, count)


## Sunucu kasa satın alımını onayladığında oyuncuya kasa verir.
func give_crate_synced(item_id: String, capacity: int) -> void:
	if Net.online():
		rpc_give_crate.rpc(item_id, capacity)
	else:
		rpc_give_crate(item_id, capacity)


@rpc("any_peer", "call_local", "reliable")
func rpc_give_crate(item_id: String, capacity: int) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	_apply_held_crate(true, item_id, capacity)
	Sfx.play_3d("crate_pick", global_position + Vector3(0, 0.9, 0), self, -3.0)
	if is_multiplayer_authority() and _fp_crate_anchor:
		_place_kick = -0.65


func _apply_held_crate(has_crate: bool, item_id: String, count: int) -> void:
	held_crate = has_crate
	held_item = item_id if has_crate else ""
	held_count = clampi(count, 0, 14) if has_crate else 0
	if _held_visual:
		_held_visual.queue_free()
		_held_visual = null
	if _fp_crate_visual:
		_fp_crate_visual.queue_free()
		_fp_crate_visual = null
	if has_crate:
		if is_multiplayer_authority() and _fp_crate_anchor:
			_fp_crate_visual = StallScript.build_held_crate(held_item, held_count)
			_fp_crate_anchor.add_child(_fp_crate_visual)
		elif _held_anchor:
			_held_visual = StallScript.build_held_crate(held_item, held_count)
			_held_anchor.add_child(_held_visual)


func award_money(amount: int, tip := 0, was_haggle := false) -> void:
	if amount <= 0 and tip <= 0:
		return
	if Net.online():
		rpc_add_money.rpc(amount, tip, was_haggle)
	else:
		rpc_add_money(amount, tip, was_haggle)


@rpc("any_peer", "call_local", "reliable")
func rpc_add_money(amount: int, tip := 0, was_haggle := false) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	var total_gain := amount + tip
	money += total_gain
	daily_revenue += total_gain
	daily_tips += tip
	if amount > 0:
		daily_sold += 1
	if was_haggle:
		daily_haggles += 1
	money_earned.emit(total_gain, money, tip)


func spend_money(amount: int, reason := "Kasa") -> void:
	if amount <= 0:
		return
	if Net.online():
		rpc_spend_money.rpc(amount, reason, false)
	else:
		rpc_spend_money(amount, reason, false)


func apply_fine(amount: int, reason := "Zabıta Cezası") -> void:
	var actual := mini(amount, money)
	if Net.online():
		rpc_spend_money.rpc(actual, reason, true)
	else:
		rpc_spend_money(actual, reason, true)


@rpc("any_peer", "call_local", "reliable")
func rpc_spend_money(amount: int, reason: String, is_fine: bool) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	money = maxi(money - amount, 0)
	if is_fine:
		daily_fines += amount
		if is_multiplayer_authority():
			add_trauma(0.42)
	else:
		daily_spent += amount
	money_spent.emit(amount, money, reason)


func reset_daily_stats_synced() -> void:
	if Net.online():
		rpc_reset_daily_stats.rpc()
	else:
		rpc_reset_daily_stats()


@rpc("any_peer", "call_local", "reliable")
func rpc_reset_daily_stats() -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	daily_revenue = 0
	daily_spent = 0
	daily_fines = 0
	daily_tips = 0
	daily_sold = 0
	daily_haggles = 0


func net_profit() -> int:
	return daily_revenue - daily_spent - daily_fines


func export_snapshot() -> Dictionary:
	return {
		"id": _my_peer_id(),
		"pos": global_position,
		"money": money,
		"daily_revenue": daily_revenue,
		"daily_spent": daily_spent,
		"daily_fines": daily_fines,
		"daily_tips": daily_tips,
		"daily_sold": daily_sold,
		"daily_haggles": daily_haggles,
		"held_crate": held_crate,
		"held_item": held_item,
		"held_count": held_count,
	}


func apply_snapshot(d: Dictionary) -> void:
	money = int(d.get("money", STARTING_MONEY))
	daily_revenue = int(d.get("daily_revenue", 0))
	daily_spent = int(d.get("daily_spent", 0))
	daily_fines = int(d.get("daily_fines", 0))
	daily_tips = int(d.get("daily_tips", 0))
	daily_sold = int(d.get("daily_sold", 0))
	daily_haggles = int(d.get("daily_haggles", 0))
	_apply_held_crate(bool(d.get("held_crate", false)), str(d.get("held_item", "")), int(d.get("held_count", 0)))
