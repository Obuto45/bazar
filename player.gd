extends CharacterBody3D
## Oyuncu: yuvarlak hatlı karakter (models/character.glb). Gövde, kafa, eller, ayaklar ayrı parçalar; eklem yok.
## Birinci şahıs: fare kafayı çevirir, gövde biraz sonra yürüme yönüne döner. W her zaman bakılan yöne yürür.
## Kendi oyuncumuzda gövde ve kafa sadece gölge olarak çizilir: aşağı bakınca eller ve ayaklar görünür.

const MODEL := preload("res://models/character.glb")
const WALK := 3.6
const RUN := 6.8
const JUMP := 5.2
const GRAVITY := 14.0
const SENS := 0.0025
const HEAD_LIMIT := 1.3 # kafa gövdeye göre en fazla bu kadar döner (rad, ~75°)
const EYE_Y := 1.16 # kamera yüksekliği: göz hizası
const EYE_FWD := 0.12 # kamera kafa merkezinden bu kadar önde
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
var tag: Label3D

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
	tag.text = Net.display_name(id)
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


## glb'deki altı parçayı sarmalayıcılara taşır; saç ve tişört rengini oyuncuya göre boyar.
func _build_model(hair: Color, shirt: Color) -> void:
	var src := MODEL.instantiate()
	rig = Node3D.new()
	add_child(rig)
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
	src.free()


func _unhandled_input(e: InputEvent) -> void:
	if npc or not is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		look_yaw = wrapf(look_yaw - e.relative.x * SENS, -PI, PI)
		look_pitch = clampf(look_pitch - e.relative.y * SENS, -1.45, 1.35)


func _physics_process(dt: float) -> void:
	if npc:
		pass
	elif is_multiplayer_authority():
		_local(dt)
	else:
		position = position.lerp(net_pos, minf(dt * 15.0, 1.0))
	_turn_body(dt)
	_animate(dt)
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
	sync_state.rpc(global_position, body_yaw, look_yaw, look_pitch, spd, air)


## Kafa sallanması: her adımda hafif çöküş ve yana salınım, koşarken daha güçlü; inişte sarsıntı.
func _camera(dt: float) -> void:
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0)
	bob_k = lerpf(bob_k, 0.0 if air else clampf(spd / WALK, 0.0, 1.0), minf(dt * 8.0, 1.0))
	var amp := lerpf(0.035, 0.075, kr) * bob_k
	var bob := Vector3(sin(phase) * amp * 0.6, -absf(cos(phase)) * amp - land_t * 0.45, 0)
	var yb := Basis(Vector3.UP, look_yaw)
	cam_root.position = Vector3(0, EYE_Y, 0) + yb * (Vector3(0, 0, -EYE_FWD) + bob)
	cam_root.rotation = Vector3(look_pitch, look_yaw, -sin(phase) * 0.012 * bob_k * (1.0 + kr))
	cam.fov = lerpf(cam.fov, 78.0 + kr * 6.0, minf(dt * 6.0, 1.0)) # koşarken hafif genişler


@rpc("authority", "unreliable_ordered")
func sync_state(p: Vector3, by: float, ly: float, lp: float, s: float, a: bool) -> void:
	net_pos = p
	body_yaw = by
	look_yaw = ly
	look_pitch = lp
	if not a and air:
		land_t = 0.22
	spd = s
	air = a


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


## Eklemsiz, el yapımı animasyon. Hızla idle -> yürüme -> koşu arasında yumuşak geçer.
func _animate(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var kw := clampf(spd / WALK, 0.0, 1.0) # yürüme ağırlığı
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0) # koşu ağırlığı
	var idle := 1.0 - kw
	if not air:
		phase += dt * spd * 1.75 # adım sıklığı hıza bağlı: ayak kayması olmaz
	land_t = maxf(land_t - dt, 0.0)
	var land := land_t / 0.22
	var breathe := sin(t * 2.2)
	var f := minf(dt * 16.0, 1.0) # hedeflere yumuşak yaklaşma, durum geçişlerinde sıçrama olmaz
	var stride := lerpf(0.2, 0.34, kr) * kw
	var lift := lerpf(0.1, 0.18, kr) * kw

	# Ayaklar: öne giderken kalkar ve burun yukarı bakar; havada toplanır, inişte açılır
	for side in [-1.0, 1.0]:
		var n := "FootR" if side < 0 else "FootL"
		var c: float = phase + (0.0 if side < 0 else PI)
		var p: Vector3 = rest[n]
		var r := Vector3.ZERO
		if air:
			p += Vector3(0, 0.14, 0.06 * side)
			r.x = -0.5
		else:
			p.z += sin(c) * stride
			p.y += maxf(0.0, cos(c)) * lift
			p.x += side * 0.03 * land
			r.x = -cos(c) * 0.45 * kw
		var w: Node3D = parts[n]
		w.position = w.position.lerp(p, f)
		w.rotation = w.rotation.lerp(r, f)

	# Eller: aynı taraftaki ayağa ters sallanır; koşarken yukarıda pompalar, dururken nefesle süzülür
	for side in [-1.0, 1.0]:
		var n := "HandR" if side < 0 else "HandL"
		var c: float = phase + (0.0 if side < 0 else PI)
		var p: Vector3 = rest[n]
		var r := Vector3.ZERO
		if air:
			p += Vector3(side * 0.12, 0.42, 0.05)
			r = Vector3(-0.4, 0, side * 0.6)
		else:
			p.z += -sin(c) * lerpf(0.2, 0.32, kr) * kw + kr * 0.06
			p.y += kr * 0.12 + absf(sin(c)) * 0.04 * kw + breathe * 0.015 * idle - land * 0.08
			p.x += side * 0.02 * sin(t * 1.3 + side) * idle
			r.x = sin(c) * lerpf(0.5, 0.9, kr) * kw
		var w: Node3D = parts[n]
		w.position = w.position.lerp(p, f)
		w.rotation = w.rotation.lerp(r, f)

	# Gövde: adımda inip kalkar, yana yalpalar, koşarken öne eğilir; nefes ve iniş ezilmesi
	var body: Node3D = parts["Body"]
	var bp: Vector3 = rest["Body"]
	bp.y += absf(cos(phase)) * lerpf(0.035, 0.06, kr) * kw + breathe * 0.008 * idle - land * 0.07 + (0.04 if air else 0.0)
	body.position = body.position.lerp(bp, f)
	body.rotation = body.rotation.lerp(Vector3(0.05 * kw + 0.18 * kr, 0, sin(phase) * 0.07 * kw), f)
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
	head.rotation.z = lerpf(head.rotation.z, sin(phase) * 0.05 * kw, f)
