extends CharacterBody3D
## Oyuncu: yuvarlak hatlı karakter (models/character.glb). Gövde, kafa, eller, ayaklar ayrı parçalar; eklem yok.
## Birinci şahıs: fare kafayı çevirir, gövde biraz sonra yürüme yönüne döner. W her zaman bakılan yöne yürür.
## Kendi oyuncumuzda gövde ve kafa sadece gölge olarak çizilir: aşağı bakınca eller ve ayaklar görünür.

const MODEL := preload("res://models/character.glb")
const StallScript := preload("res://stall.gd")
signal money_earned(amount: int, total: int)
const WALK := 3.6
const RUN := 6.8
const JUMP := 5.2
const GRAVITY := 14.0
const SENS := 0.0025
const HEAD_LIMIT := 1.3 # kafa gövdeye göre en fazla bu kadar döner (rad, ~75°)
const EYE_Y := 1.16 # kamera yüksekliği: göz hizası
const EYE_FWD := 0.12 # kamera kafa merkezinden bu kadar önde
# Proximity sesli sohbet (PEAK tarzı 3D uzaklık sönümlemesi + kesintisiz jitter buffer)
const VOICE_BUS := "VoiceRecord"
const VOICE_RATE := 24000 # 24 kHz mono 16-bit PCM (48 kHz'nin tam yarısı, net ses)
const VOICE_CHUNK := 480 # 20 ms paket (960 bayt, düşük gecikme)
const VOICE_GEN_SEC := 0.25 # AudioStreamGenerator iç tamponu (6000 örnek)
const VOICE_PREBUF := 1440 # 60 ms jitter ön-tamponu (yalnızca konuşma başlangıcında)
const VOICE_MAX_BUF := 4800 # 200 ms üst sınır (gecikme birikmesini önler)
const VOICE_DB_MIN := -46.0 # bu eşiğin altı sessizlik
const VOICE_DB_MAX := -12.0 # tam ağız açıklığı (dB)
const VOICE_UNIT_SIZE := 3.5 # bu mesafeye kadar tam ses (m)
const VOICE_MAX_DIST := 22.0 # bu mesafede ses tamamen kesilir (m)
# Oyuncu renkleri (peer id'ye göre): saç ve tişört
const HAIRS := [Color(0.2, 0.12, 0.07), Color(0.08, 0.06, 0.05), Color(0.75, 0.55, 0.25), Color(0.55, 0.22, 0.1),
	Color(0.4, 0.28, 0.18), Color(0.85, 0.8, 0.7)]
const SHIRTS := [Color(0.85, 0.2, 0.18), Color(0.2, 0.5, 0.9), Color(0.98, 0.75, 0.15), Color(0.3, 0.75, 0.35),
	Color(0.65, 0.35, 0.85), Color(1.0, 0.5, 0.7), Color(0.15, 0.75, 0.75), Color(1.0, 0.55, 0.15)]

var spawn_pos := Vector3.ZERO
var npc := false # menü figüranı: ağ ve kontrol yok, main.gd yürütür
var color_id := -1 # figüranlar için renk (-1: peer id'den)

var rig: Node3D # gövde yönü; gövde, eller, ayaklar burada
var head: Node3D # kafa ayrı döner: gövdeden önce fareyi izler
var parts := {} # ad -> sarmalayıcı Node3D
var rest := {} # ad -> modeldeki dinlenme konumu
var cam_root: Node3D
var cam: Camera3D
var _ray: RayCast3D
var _held_anchor: Node3D
var _held_visual: Node3D
var _fp_crate_anchor: Node3D
var _fp_crate_visual: Node3D
var money := 0
var held_crate := false
var held_item := ""
var held_count := 0
var shout_power := 0.0 # mikrofon bağırması veya B tuşu (0..1.4)
var interact_hint := ""
var _place_cd := 0.0
var _place_held := false
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
var talk_level := 0.0 # 0..1 anlık ses seviyesi (dB'den)
var talk_db := -60.0
var talk_smooth := 0.0 # yumuşatılmış ağız açıklığı
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
var _rx_fade := 0.0 # 0..1 kliksiz fade-in zarfı
var _rx_last_s := 0.0
var _remote_talk := 0.0
var _remote_talk_t := 0.0
var _base_tag := ""

var look_yaw := PI # kamera yönü (0: -Z'ye bakış). Modelin önü +Z: yüz yönü = look_yaw + PI
var look_pitch := 0.0
var body_yaw := 0.0 # modelin yönü
var turning := false # dururken kafa sınırı aşıldı, gövde toparlanıyor
var spd := 0.0
var air := false
var phase := 0.0 # adım döngüsü
var land_t := 0.0 # iniş ezilmesi (sn)
var bob_k := 0.0
var net_pos := Vector3.ZERO


func face_yaw() -> float:
	return look_yaw + PI


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
		for n in ["Body", "Head"]: # kendi gövdemi görmem, gölgesi kalsın
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
		_ray.target_position = Vector3(0, 0, -3.4)
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = false
		_ray.collision_mask = 4
		cam.add_child(_ray)
		# Birinci şahısta elde tutulan kasa (ekranın alt-önünde net görünür, eksildikçe boşalır)
		_fp_crate_anchor = Node3D.new()
		_fp_crate_anchor.position = Vector3(0.0, -0.34, -0.58)
		_fp_crate_anchor.rotation_degrees = Vector3(14.0, 0.0, 0.0)
		cam.add_child(_fp_crate_anchor)
		_setup_voice_capture()
	else:
		_setup_voice_playback()


## glb'deki altı parçayı sarmalayıcılara taşır; saç ve tişört rengini oyuncuya göre boyar.
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
		m.owner = null # glb sahnesinden koparıldı
		m.transform = Transform3D.IDENTITY
		w.add_child(m)
		if n == "Head": # kafa, kendi merkezinde döner
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
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_place_held = false
		return
	if e is InputEventMouseMotion:
		look_yaw = wrapf(look_yaw - e.relative.x * SENS, -PI, PI)
		look_pitch = clampf(look_pitch - e.relative.y * SENS, -1.45, 1.35)
	elif e.is_action_pressed("interact"):
		_do_interact()
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
				_place_cd = 0.24 # ilk tık sonrası basılı tutmada seri dizme gecikmesi
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_do_adjust_price(1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_do_adjust_price(-1)


func _process(dt: float) -> void:
	if npc:
		return
	if is_multiplayer_authority():
		_process_voice_capture(dt)
		_process_interaction(dt)
	else:
		_process_voice_remote(dt)
		_pump_voice_playback()


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
	# Yön her zaman kameradan: kafa nereye bakıyorsa W oraya, gövde nereye dönük olursa olsun
	var dir := (Basis(Vector3.UP, look_yaw) * Vector3(inp.x, 0, inp.y)).normalized()
	var running := Input.is_action_pressed("run") and inp.y < 0.0 # sadece ileri koşulur
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
	# Bağırma gücü: yüksek sesli mikrofon konuşması veya B tuşu (müşterileri tezgaha çeker)
	var manual_shout := 1.0 if (captured and Input.is_action_pressed("shout")) else 0.0
	var mic_shout := clampf((talk_smooth - 0.28) * 1.8, 0.0, 1.35) if not mic_muted else 0.0
	shout_power = lerpf(shout_power, maxf(manual_shout, mic_shout), minf(dt * 10.0, 1.0))
	if Net.online():
		sync_state.rpc(global_position, body_yaw, look_yaw, look_pitch, spd, air, shout_power)


## Kafa sallanması: her adım basışında hafif çöküş ve yana salınım, koşarken daha güçlü; inişte sarsıntı.
func _camera(dt: float) -> void:
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0)
	bob_k = lerpf(bob_k, 0.0 if air else clampf(spd / WALK, 0.0, 1.0), minf(dt * 8.0, 1.0))
	var amp := lerpf(0.032, 0.068, kr) * bob_k
	# Adım fazı ile eşzamanlı: sin(phase)=0 anında ayak basar -> hafif çöküş; cos(phase) sol/sağ salınım
	var bob := Vector3(cos(phase) * amp * 0.55, absf(sin(phase)) * amp - amp * 0.5 - land_t * 0.45, 0)
	var yb := Basis(Vector3.UP, look_yaw)
	cam_root.position = Vector3(0, EYE_Y, 0) + yb * (Vector3(0, 0, -EYE_FWD) + bob)
	cam_root.rotation = Vector3(look_pitch, look_yaw, -cos(phase) * 0.011 * bob_k * (1.0 + kr))
	cam.fov = lerpf(cam.fov, 78.0 + kr * 6.0, minf(dt * 6.0, 1.0)) # koşarken hafif genişler


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


## Önce kafa döner. Yürürken gövde yürüme yönüne, dururken kafa sınırı aşılınca kafanın yönüne döner.
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


## Eklemsiz, hızla senkronlu animasyon. Ayak temas hızı gerçek yürüme/koşma hızına kilitlidir.
func _animate(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var kw := clampf(spd / WALK, 0.0, 1.0) # yürüme ağırlığı
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0) # koşu ağırlığı
	var idle := 1.0 - kw
	var stride_full := lerpf(0.28, 0.42, kr)
	var stride := stride_full * kw
	var lift := lerpf(0.11, 0.20, kr) * kw
	if not air and spd > 0.08:
		# Yerdeki ayağın geriye süpürme hızı = stride_full * omega ≈ spd (kayma yok)
		phase = wrapf(phase + dt * (spd / stride_full) * 0.94, 0.0, TAU)
	land_t = maxf(land_t - dt, 0.0)
	var land := land_t / 0.22
	var breathe := sin(t * 2.2)
	var f := minf(dt * 18.0, 1.0) # hedeflere yumuşak yaklaşma, durum geçişlerinde sıçrama olmaz

	# Ayaklar: -cos(c) öne/arkaya (c=0 arkada, c=PI önde), sin(c)>0 iken havada öne savrulur;
	# sin(c)<0 iken yerde geriye iter ve hızı karakter hızıyla birebir eşleşir.
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

	# Eller: aynı taraftaki ayağa tam ters salınır (+cos(c)); koşarken yukarıda pompalar
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

	# Gövde: adım geçişinde yükselip basışta çöker, ters omuz burulması + yana ağırlık aktarımı
	var body: Node3D = parts["Body"]
	var bp: Vector3 = rest["Body"]
	bp.y += absf(sin(phase)) * lerpf(0.04, 0.075, kr) * kw + breathe * 0.008 * idle - land * 0.07 + (0.04 if air else 0.0)
	body.position = body.position.lerp(bp, f)
	body.rotation = body.rotation.lerp(
		Vector3(0.06 * kw + 0.19 * kr, cos(phase) * lerpf(0.09, 0.15, kr) * kw, sin(phase) * 0.06 * kw), f)
	var sq := 1.0 + breathe * 0.015 * idle - land * 0.12 + (0.05 if air else 0.0)
	var side_sq := 1.0 + (1.0 - sq) * 0.5 # hacim korunsun
	body.scale = body.scale.lerp(Vector3(side_sq, sq, side_sq), f)

	# Kafa: gövdeyle birlikte iner kalkar; yönü fareyi gövdeye göre sınırlı izler, bakışla eğilir
	var hp: Vector3 = rest["Head"]
	hp.y += (body.position.y - rest["Body"].y) * 1.1 + breathe * 0.01 * idle
	head.position = head.position.lerp(hp, f)
	var rel := clampf(wrapf(face_yaw() - rig.rotation.y, -PI, PI), -HEAD_LIMIT, HEAD_LIMIT)
	head.rotation.y = lerp_angle(head.rotation.y, rig.rotation.y + rel, minf(dt * 20.0, 1.0))
	head.rotation.x = lerpf(head.rotation.x, -look_pitch * 0.6, f)
	head.rotation.z = lerpf(head.rotation.z, -sin(phase) * 0.045 * kw, f)


# ---------- Proximity Sesli Sohbet ve Ağız Hareketi ----------

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
		AudioServer.set_bus_mute(bus, true) # kendi sesimiz yankı yapmasın
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
	_voice_player.volume_db = 0.0 # clipping/patlama olmaması için +0 dB temiz kazanç
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
	# 1. derece High-Pass (~90 Hz: DC/nefes uğultusu) + Low-Pass (~7.5 kHz: aliasing/parazit keser)
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
		# Yumuşak limiter + headroom (0.85 tavanı: dijital patlama sıfır)
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
	# Örnek atlamayan sürekli fazlı lineer resampler (önceki tamponun son örneğini korur)
	var step := mix_rate / float(VOICE_RATE)
	while _resamp_pos < float(n):
		var idx := int(floor(_resamp_pos))
		var frac := _resamp_pos - float(idx)
		var s0 := _resamp_prev if idx < 0 else mono[idx]
		var s1 := mono[mini(idx + 1, n - 1)]
		_voice_accum.append(lerpf(s0, s1, frac))
		_resamp_pos += step
	_resamp_pos -= float(n) # negatif olabilir (-1..0), sonraki çağrıda _resamp_prev ile eksiksiz devam eder
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
	# Konuşma başlangıcında yalnızca 1 kez 60 ms ön-tampon biriktir; sonra kesintisiz akıt
	if not _rx_playing:
		if _rx_buf.size() < VOICE_PREBUF:
			return
		_rx_playing = true
		_rx_fade = 0.0
	var take := mini(avail, _rx_buf.size())
	if take > 0:
		var out := PackedVector2Array()
		out.resize(take)
		var fade_step := 1.0 / 120.0 # 5 ms yumuşak fade-in
		for i in take:
			_rx_fade = minf(_rx_fade + fade_step, 1.0)
			var s := _rx_buf[i] * _rx_fade
			_rx_last_s = s
			out[i] = Vector2(s, s)
		_voice_pb.push_buffer(out) # tek C++ çağrısıyla kesintisiz aktarım
		_rx_buf = _rx_buf.slice(take)
		return
	# _rx_buf boş ama AudioStreamGenerator içinde hâlâ çalınan ses olabilir!
	# Yalnızca jeneratör tamponu da neredeyse bittiğinde (< 8 ms kaldıysa) yumuşak fade-out yap.
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


func _animate_mouth(dt: float) -> void:
	if mouth_node == null:
		return
	var rate := 28.0 if talk_level > talk_smooth else 14.0
	talk_smooth = lerpf(talk_smooth, talk_level, minf(dt * rate, 1.0))
	# Desibele göre ağız dikeyde belirgin açılır, hafif genişler ve çeneye doğru iner
	mouth_node.scale = Vector3(1.0 + talk_smooth * 0.35, 1.0 + talk_smooth * 2.5, 1.0 + talk_smooth * 0.4)
	mouth_node.position = mouth_rest + Vector3(0.0, -talk_smooth * 0.016, talk_smooth * 0.004)


## Canlı göz animasyonu: doğal göz kırpma, hafif bakış kaydırma (saccade) ve konuşurken göz parlaması.
func _animate_eyes(dt: float) -> void:
	if eye_l == null or eye_r == null:
		return
	# 1. Doğal göz kırpma (her 2.2 - 5.2 sn, %25 çift kırpma)
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

	# 2. Canlı bakış kaydırma (saccade): donuk sabit bakış yerine ufak doğal göz hareketleri
	if pupil_l and pupil_r:
		_saccade_cd -= dt
		if _saccade_cd <= 0.0:
			_saccade_cd = randf_range(1.1, 3.0)
			if randf() < 0.45:
				_saccade_target = Vector2.ZERO # merkeze dön
			else:
				_saccade_target = Vector2(randf_range(-0.0085, 0.0085), randf_range(-0.005, 0.006))
		_saccade_cur = _saccade_cur.lerp(_saccade_target, minf(dt * 18.0, 1.0))
		var p_off := Vector3(_saccade_cur.x, _saccade_cur.y, 0.0)
		pupil_l.position = p_off
		pupil_r.position = p_off


# ---------- Tezgah, Kasa, Fiyat Etiketi ve Müşteri Satış Etkileşimi ----------

func _my_peer_id() -> int:
	return name.to_int()


func _find_world() -> Node:
	return get_parent().get_parent() if get_parent() else null


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


func _process_interaction(dt: float) -> void:
	# Sol tık basılı tutuluyorsa seri ürün dizme
	if _place_held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_place_cd -= dt
		if _place_cd <= 0.0:
			if _try_place_once():
				_place_cd = 0.17
			else:
				_place_cd = 0.12
	# Bağlamsal etkileşim ipucu
	interact_hint = ""
	var area := _ray_target()
	if area == null:
		if held_crate:
			if held_count > 0:
				interact_hint = "Elde: %s Kasası (%d/10)  •  [Q] Fırlat" % [StallScript.ITEMS[held_item]["name"], held_count]
			else:
				interact_hint = "Elde: Boş Kasa  •  [Q] Uzağa Fırlat"
		return
	var kind: String = str(area.get_meta("kind", ""))
	var my_id := _my_peer_id()
	match kind:
		"crate":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var item_id: String = str(area.get_meta("item_id", ""))
			var st := _find_stall(owner_id)
			if st and owner_id == my_id and StallScript.ITEMS.has(item_id):
				var nm: String = StallScript.ITEMS[item_id]["name"]
				if st.has_supply_crate(item_id):
					interact_hint = "[E] %s Kasası Al (10 ad.)" % nm if not held_crate else "Önce elindeki kasayı [Q] ile fırlat"
				else:
					interact_hint = "[E] Yeni %s Kasası Getir" % nm
		"slot":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var idx: int = int(area.get_meta("slot_idx", -1))
			var st := _find_stall(owner_id)
			if st and owner_id == my_id and idx >= 0 and idx < st.slots.size():
				var sl: Dictionary = st.slots[idx]
				var parts_txt := PackedStringArray()
				if held_crate and held_count > 0 and st.can_place(idx, held_item):
					parts_txt.append("[Sol Tık] %s Diz (%d kaldı)" % [StallScript.ITEMS[held_item]["name"], held_count])
				elif held_crate and held_count == 0:
					parts_txt.append("Kasa boş! [Q] Fırlat")
				elif not held_crate and sl["count"] == 0:
					parts_txt.append("Arkadan [E] ile kasa al")
				if sl["item"] != "" and int(sl["count"]) > 0:
					parts_txt.append("[Tekerlek / Z-X] Fiyat: %d TL" % int(sl["price"]))
				interact_hint = "  •  ".join(parts_txt)
		"customer":
			var c := _find_customer(str(area.get_meta("customer_name", "")))
			if c:
				interact_hint = c.get_next_sell_hint(my_id)


func _do_interact() -> void:
	var area := _ray_target()
	var my_id := _my_peer_id()
	if area == null:
		return
	var kind: String = str(area.get_meta("kind", ""))
	if kind == "crate":
		var owner_id: int = int(area.get_meta("stall_owner", -1))
		var item_id: String = str(area.get_meta("item_id", ""))
		var st := _find_stall(owner_id)
		if st and owner_id == my_id and StallScript.ITEMS.has(item_id):
			if st.has_supply_crate(item_id):
				if not held_crate and st.request_take_crate(item_id):
					set_held_crate(true, item_id, StallScript.CRATE_CAPACITY)
			else:
				st.request_restock_crate(item_id)
	elif kind == "customer":
		var c := _find_customer(str(area.get_meta("customer_name", "")))
		if c and c.get_next_sell_hint(my_id) != "":
			if Net.online():
				c.rpc_request_sell.rpc_id(1, my_id)
			else:
				var res: Dictionary = c.try_sell_one_from(my_id)
				if not res.is_empty():
					award_money(int(res["price"]))


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
	var rb := RigidBody3D.new()
	rb.mass = 1.2
	rb.position = start_p
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0), randf_range(-8.0, 8.0))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.42, 0.20, 0.34)
	cs.shape = sh
	rb.add_child(cs)
	rb.add_child(StallScript.build_held_crate(item_id, count))
	w.add_child(rb)
	# 10 sn sonra etrafta birikmemesi için temizle
	var tw := rb.create_tween()
	tw.tween_interval(9.5)
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
	held_crate = has_crate
	held_item = item_id if has_crate else ""
	held_count = clampi(count, 0, StallScript.CRATE_CAPACITY) if has_crate else 0
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


func award_money(amount: int) -> void:
	if amount <= 0:
		return
	if Net.online():
		rpc_add_money.rpc(amount)
	else:
		rpc_add_money(amount)


@rpc("any_peer", "call_local", "reliable")
func rpc_add_money(amount: int) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return # yalnızca host para verebilir
	money += amount
	money_earned.emit(amount, money)
