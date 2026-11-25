extends CharacterBody3D
## Oyuncu: low-poly gövde + kafa, boşlukta süzülen eller ve ayaklar (eklem yok).
## Sahibi kendi makinesinde hareket ettirir, konumu diğerlerine yayınlar.

const LP := preload("res://lowpoly.gd")
const WALK := 4.2
const RUN := 7.5
const JUMP := 5.2
const GRAVITY := 14.0
const SENS := 0.0028
# Gömlek renkleri: peer id'ye göre seçilir, herkes aynı rengi görür.
const SHIRTS := [Color(0.85, 0.3, 0.25), Color(0.25, 0.55, 0.85), Color(0.95, 0.7, 0.2), Color(0.35, 0.7, 0.4),
	Color(0.6, 0.4, 0.8), Color(0.95, 0.5, 0.65), Color(0.2, 0.7, 0.7), Color(0.9, 0.55, 0.25)]
const SKINS := [Color(0.96, 0.8, 0.66), Color(0.85, 0.64, 0.48), Color(0.65, 0.45, 0.32), Color(0.45, 0.3, 0.22)]

var spawn_pos := Vector3.ZERO
var npc := false # menü sahnesindeki figüran: ağ ve kontrol yok, konumunu main.gd verir
var color_id := -1 # figüranlar için renk seçimi (-1: peer id'den)
var rig: Node3D # görsel kök: yürüme yönüne döner
var body: Node3D
var head: Node3D
var hands: Array[Node3D] = []
var feet: Array[Node3D] = []
var cam_yaw: Node3D
var cam_pitch: Node3D
var cam: Camera3D
var tag: Label3D
var phase := 0.0 # yürüme döngüsü
var spd := 0.0 # yatay hız (animasyon için, uzaktakilerde ağdan gelir)
var air := false
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var sync_wait := 1.0 # shortcut: diğerleri düğümümü kurana dek sync atma; yavaş ağda hâlâ birkaç "node not found" olabilir, gerekirse host onaylı "hazır" RPC'sine geç


func _ready() -> void:
	var id := color_id if color_id >= 0 else name.to_int()
	position = spawn_pos
	net_pos = spawn_pos
	net_yaw = PI # başta kameranın baktığı yöne (-Z) dönük
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35; cap.height = 1.5
	col.shape = cap
	col.position.y = 0.75
	add_child(col)
	_build_body(SHIRTS[id % SHIRTS.size()], SKINS[(id / 7) % SKINS.size()])
	rig.rotation.y = net_yaw
	tag = Label3D.new()
	tag.text = Net.display_name(id)
	tag.position.y = 2.05
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	tag.no_depth_test = true
	add_child(tag)
	if npc:
		tag.hide()
	elif is_multiplayer_authority():
		tag.hide() # kendi adımı görmeyeyim
		cam_yaw = Node3D.new()
		cam_yaw.position.y = 1.4
		add_child(cam_yaw)
		cam_yaw.top_level = true # gövde dönünce kamera dönmesin
		cam_pitch = Node3D.new()
		cam_pitch.rotation.x = -0.35
		cam_yaw.add_child(cam_pitch)
		var arm := SpringArm3D.new()
		arm.spring_length = 4.5
		arm.margin = 0.2
		arm.add_excluded_object(get_rid())
		cam_pitch.add_child(arm)
		cam = Camera3D.new()
		cam.fov = 70
		arm.add_child(cam)
		cam.current = true


## Gövde kafa el ayak ayrı parçalar; aralarında bağlantı yok, hepsi rig'e göre süzülür.
func _build_body(shirt: Color, skin: Color) -> void:
	rig = Node3D.new()
	add_child(rig)
	body = Node3D.new()
	body.position.y = 0.95
	rig.add_child(body)
	LP.add(body, LP.cyl(0.26, 0.36, 0.7, 6), Vector3.ZERO, shirt) # aşağı doğru genişleyen gövde
	LP.add(body, LP.cyl(0.37, 0.37, 0.08, 6), Vector3(0, -0.3, 0), shirt.darkened(0.35)) # kemer
	head = Node3D.new()
	head.position.y = 1.62
	rig.add_child(head)
	LP.add(head, LP.sphere(0.27, 7, 4), Vector3.ZERO, skin)
	LP.add(head, LP.box(Vector3(0.06, 0.09, 0.03)), Vector3(-0.09, 0.03, 0.25), Color(0.1, 0.1, 0.12)) # gözler
	LP.add(head, LP.box(Vector3(0.06, 0.09, 0.03)), Vector3(0.09, 0.03, 0.25), Color(0.1, 0.1, 0.12))
	LP.add(head, LP.prism(Vector3(0.08, 0.1, 0.08)), Vector3(0, -0.04, 0.28), skin.darkened(0.1), Vector3(PI / 2, 0, 0)) # burun
	LP.add(head, LP.cyl(0.18, 0.28, 0.12, 6), Vector3(0, 0.2, 0), shirt.darkened(0.25)) # şapka
	for s in [-1, 1]:
		var h := Node3D.new()
		h.position = Vector3(0.5 * s, 0.95, 0.05)
		rig.add_child(h)
		LP.add(h, LP.sphere(0.11, 6, 3), Vector3.ZERO, skin)
		hands.append(h)
		var f := Node3D.new()
		f.position = Vector3(0.17 * s, 0.1, 0.0)
		rig.add_child(f)
		LP.add(f, LP.box(Vector3(0.2, 0.14, 0.32)), Vector3(0, 0, 0.04), Color(0.3, 0.2, 0.13))
		feet.append(f)


func _unhandled_input(e: InputEvent) -> void:
	if npc or not is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		cam_yaw.rotation.y -= e.relative.x * SENS
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - e.relative.y * SENS, -1.2, 0.5)


func _physics_process(dt: float) -> void:
	if npc:
		pass
	elif is_multiplayer_authority():
		_local(dt)
	else:
		position = position.lerp(net_pos, minf(dt * 15.0, 1.0))
		rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, minf(dt * 12.0, 1.0))
	_animate(dt)


func _local(dt: float) -> void:
	cam_yaw.global_position = global_position + Vector3(0, 1.4, 0)
	var inp := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		inp = Input.get_vector("left", "right", "fwd", "back")
	var dir := (cam_yaw.basis * Vector3(inp.x, 0, inp.y)).normalized()
	var target := (RUN if Input.is_action_pressed("run") else WALK) * dir
	var accel := 12.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, target.x, accel * dt * maxf(target.length(), WALK))
	velocity.z = move_toward(velocity.z, target.z, accel * dt * maxf(target.length(), WALK))
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	if global_position.y < -10.0: # haritadan düştüyse
		global_position = spawn_pos
		velocity = Vector3.ZERO
	spd = Vector2(velocity.x, velocity.z).length()
	air = not is_on_floor()
	if spd > 0.3:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(velocity.x, velocity.z), minf(dt * 12.0, 1.0))
	sync_wait -= dt
	if sync_wait <= 0.0:
		sync_state.rpc(global_position, rig.rotation.y, spd, air)


@rpc("authority", "unreliable_ordered")
func sync_state(p: Vector3, yaw: float, s: float, a: bool) -> void:
	net_pos = p
	net_yaw = yaw
	spd = s
	air = a


## Eklemsiz animasyon: ayaklar ileri geri adım atar, eller ters sallanır, gövde zıplar.
func _animate(dt: float) -> void:
	var k := clampf(spd / WALK, 0.0, 1.6)
	phase += dt * (2.0 + spd * 2.1)
	var sw := sin(phase)
	var t := Time.get_ticks_msec() * 0.001
	var breathe := sin(t * 2.0) * 0.015
	for i in 2:
		var side := -1.0 if i == 0 else 1.0 # hands/feet sırası: sol, sağ
		var f := feet[i]
		var h := hands[i]
		if air: # havada: eller yukarı, ayaklar toplanır
			f.position = f.position.lerp(Vector3(0.17 * side, 0.2, -0.12 * side), minf(dt * 10.0, 1.0))
			f.rotation.x = 0.0
			h.position = h.position.lerp(Vector3(0.6 * side, 1.4, 0.1), minf(dt * 10.0, 1.0))
			continue
		var step := sw * side
		f.position = Vector3(0.17 * side, 0.08 + maxf(0.0, step) * 0.18 * k, step * 0.32 * k)
		f.rotation.x = -step * 0.4 * k
		h.position = Vector3(0.5 * side, 0.95 + breathe + absf(step) * 0.05 * k, 0.05 - step * 0.35 * k)
	body.position.y = 0.95 + breathe + absf(cos(phase)) * 0.06 * k
	body.rotation.x = 0.08 * k # koşarken öne eğil
	head.position.y = 1.62 + breathe * 1.5 + absf(cos(phase)) * 0.07 * k
	head.rotation.z = sin(t * 0.9) * 0.04 * (1.0 - minf(k, 1.0))
