extends Node3D
## Kapkaççı çocuk (kapüşonlu): hedef tezgaha sinsice yaklaşır, 2-4 sn "👀" diye etrafı kollar (adil uyarı!),
## tezgahtan bir ürün aşırır ve çıkış kapısına doğru depar atar. Oyuncu [E] ile yakalayabilir (3.2 m),
## Zabıta da yakındaysa peşine düşer. Host otoriter; istemcilere konum unreliable rpc ile gider.

signal caught(catcher_id: int, item_id: String)

const MODEL := preload("res://models/char_kapkac.glb")
const MODEL_BALD := preload("res://models/char_hirsiz.glb") # tas kafa, siyah şişme mont, spor ayakkabı
const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const VFX := preload("res://vfx.gd")
const StallScript := preload("res://stall.gd")

enum TState { SNEAK, LURK, FLEE, CAUGHT }

const SNEAK_SPEED := 2.0
const FLEE_SPEED := 5.3 # oyuncu koşusu 7.0: koşarsan yetişirsin
const CATCH_RANGE := 4.2
const BOUNTY := 30
const REP_RESTORE := 0.2
const MAX_LIFE := 75.0
const PART_NAMES := ["Body", "Head", "HandL", "HandR", "FootL", "FootR"]

const HOODIES := [Color(0.16, 0.16, 0.19), Color(0.42, 0.12, 0.14), Color(0.18, 0.26, 0.2), Color(0.3, 0.3, 0.34),
	Color(0.14, 0.2, 0.36)]
const SNEAK_LINES := ["🎵 Fiyuuu fiyuuu...", "🙄 Hiiç, bakıyorum...", "😇 Ben bir şey yapmadım!", "🎵 Lalala..."]
const LURK_LINES := ["👀 ...", "👀 Kimse bakmıyor mu?", "👀 Şu tezgah tam bana göre...", "👀 Hıımm..."]
const FLEE_LINES := ["🏃 Hehe, kaçtııım!", "🏃 Yakalayamazsın!", "🏃 Bay bay abi!", "🏃 Tüüüüüüh!"]
const EMPTY_LINES := ["😒 Tüh, tezgah boşmuş!", "😒 Bir şey yok ki burada!"]
const CAUGHT_LINES := ["😵 Yakalandım abi!", "😵 Tamam abi tamam, geri veriyorum!", "😵 Bir daha yapmam abi!"]
const ZABITA_LINES := ["😵 Zabıta abi bırak!", "😵 Tamam tamam, teslim!"]

var thief_state: int = TState.SNEAK
var target_owner_id := 0
var exit_pos := Vector3(0, 0, -21.2)
var carried_item := ""
var color_seed := 0

var _approach_pos := Vector3.ZERO
var _lurk_t := 3.0
var _stun_t := 0.0
var _life := 0.0
var _rng := RandomNumberGenerator.new()
var _caught := false
var _line := ""

var rig: Node3D
var parts := {}
var rest := {}
var _carry_root: Node3D
var _bubble_pivot: Node3D
var bubble: Label3D
var _emote_lbl: Label3D
var _emote_tw: Tween
var _area: Area3D
var _body_yaw := 0.0
var _phase := 0.0
var _spd := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_spd := 0.0
var _sync_t := 0.0
var _step_cd := 0.0


func init_thief(tname: String, seed_val: int, start_p: Vector3, exit_p: Vector3, target_owner: int) -> void:
	name = tname
	color_seed = seed_val
	position = start_p
	_net_pos = start_p
	exit_pos = exit_p
	target_owner_id = target_owner
	_rng.seed = hash(tname) ^ seed_val
	_lurk_t = _rng.randf_range(2.0, 4.0)
	var d := exit_p - start_p
	_body_yaw = atan2(-d.x, -d.z)
	_net_yaw = _body_yaw


func is_carrying() -> bool:
	return carried_item != ""


func is_fleeing() -> bool:
	return thief_state == TState.FLEE


func is_catchable() -> bool:
	return not _caught


func _ready() -> void:
	_build_visual()
	_build_bubble_and_area()
	_set_line(SNEAK_LINES[absi(hash(name)) % SNEAK_LINES.size()])


func _build_visual() -> void:
	rig = Node3D.new()
	add_child(rig)
	# Yarısı kapüşonlu velet, yarısı tas kafa şişme montlu hırsız
	var bald := absi(color_seed / 2) % 2 == 1
	var src := (MODEL_BALD if bald else MODEL).instantiate()
	var hoodie: Color = HOODIES[absi(color_seed) % HOODIES.size()]
	var skin: Color = [Color(0.96, 0.78, 0.62), Color(0.86, 0.66, 0.5), Color(0.74, 0.54, 0.4)][absi(color_seed / 3) % 3]
	var cols := {"Shirt": hoodie, "Pants": Color(0.2, 0.22, 0.28), "Skin": skin, "Lid": skin.darkened(0.06),
		"SkinLid": skin.darkened(0.03), "Shoe": Color(0.9, 0.9, 0.92)}
	if bald:
		# siyah mont ve spor ayakkabı modelin kendi renginde kalır
		cols.erase("Shirt")
		cols.erase("Shoe")
		cols["Stubble"] = skin.darkened(0.14)
		cols["Fade"] = skin.darkened(0.3)
	for n in PART_NAMES:
		var m: Node3D = src.find_child(n, true, false)
		var w := Node3D.new()
		w.name = n
		rest[n] = m.position
		m.get_parent().remove_child(m)
		m.owner = null
		m.transform = Transform3D.IDENTITY
		w.add_child(m)
		rig.add_child(w)
		w.position = rest[n]
		parts[n] = w
		var meshes: Array = w.find_children("*", "MeshInstance3D", true, false)
		if m is MeshInstance3D:
			meshes.append(m)
		for mi: MeshInstance3D in meshes:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if mat and cols.has(mat.resource_name):
					var c := mat.duplicate() as BaseMaterial3D
					c.albedo_color = cols[mat.resource_name]
					mi.set_surface_override_material(i, c)
	src.free()
	# Kapüşon (Shirt = hoodie rengi), ipler, çatık kaşlar ve çiller modelde (char_kapkac.glb)
	# Sırttaki çuval (kanguru cebi modelde)
	var b := parts["Body"] as Node3D
	LP.add(b, LP.ellipsoid(0.17, 0.2, 0.12, 7, 4), Vector3(0, 0.08, -0.27), Color(0.68, 0.56, 0.38))
	_carry_root = Node3D.new()
	_carry_root.position = Vector3(0, 0.12, 0.06)
	(parts["HandR"] as Node3D).add_child(_carry_root)
	scale = Vector3(0.92, 0.92, 0.92) if bald else Vector3(0.84, 0.84, 0.84)


func _build_bubble_and_area() -> void:
	_bubble_pivot = Node3D.new()
	_bubble_pivot.position = Vector3(0, 2.0, 0)
	add_child(_bubble_pivot)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font_size = 46
	bubble.pixel_size = 0.0038
	bubble.outline_size = 14
	bubble.modulate = Color(1.0, 0.95, 0.85)
	bubble.outline_modulate = Color(0.1, 0.06, 0.04)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble_pivot.add_child(bubble)
	_emote_lbl = Label3D.new()
	_emote_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_lbl.font_size = 96
	_emote_lbl.pixel_size = 0.0045
	_emote_lbl.outline_size = 16
	_emote_lbl.outline_modulate = Color(0.1, 0.06, 0.04)
	_emote_lbl.position = Vector3(0, 0.42, 0)
	_emote_lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_emote_lbl.hide()
	_bubble_pivot.add_child(_emote_lbl)

	_area = Area3D.new()
	_area.name = "ThiefArea"
	_area.collision_layer = 4
	_area.collision_mask = 0
	_area.set_meta("kind", "thief")
	_area.set_meta("thief_name", name)
	_area.set_meta("hl_size", Vector3(0.8, 1.4, 0.8))
	_area.position = Vector3(0, 0.75, 0)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.5
	sh.height = 1.5
	cs.shape = sh
	_area.add_child(cs)
	add_child(_area)


func _set_line(t: String) -> void:
	_line = t
	if bubble:
		bubble.text = t


func _pop_emote(e: String, hold := 1.4) -> void:
	if _emote_lbl == null:
		return
	_emote_lbl.text = e
	_emote_lbl.show()
	_emote_lbl.modulate.a = 1.0
	_emote_lbl.outline_modulate.a = 1.0
	if _emote_tw and _emote_tw.is_valid():
		_emote_tw.kill()
	_emote_lbl.scale = Vector3(0.2, 0.2, 0.2)
	_emote_tw = create_tween()
	_emote_tw.tween_property(_emote_lbl, "scale", Vector3(1.3, 1.3, 1.3), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tw.tween_property(_emote_lbl, "scale", Vector3.ONE, 0.12)
	if hold > 0.0:
		_emote_tw.tween_interval(hold)
		_emote_tw.tween_property(_emote_lbl, "modulate:a", 0.0, 0.3)
		_emote_tw.parallel().tween_property(_emote_lbl, "outline_modulate:a", 0.0, 0.3)
		_emote_tw.tween_callback(_emote_lbl.hide)


func _world() -> Node:
	var n: Node = get_parent()
	while n:
		if n.name == "World":
			return n
		n = n.get_parent()
	return get_parent().get_parent() if get_parent() else null


func _find_stall() -> Node3D:
	var w := _world()
	var sg := w.get_node_or_null("Stalls") if w else null
	return sg.get_node_or_null("Stall_%d" % target_owner_id) as Node3D if sg else null


func _find_player(pid: int) -> Node3D:
	var w := _world()
	var pg := w.get_node_or_null("Players") if w else null
	return pg.get_node_or_null(str(pid)) as Node3D if pg else null


func _is_host() -> bool:
	return (not Net.online()) or multiplayer.is_server()


func _process(_dt: float) -> void:
	if _bubble_pivot == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(_bubble_pivot.global_position)
		var s := clampf(d / 6.5, 1.0, 2.3)
		_bubble_pivot.scale = Vector3(s, s, s)
		_bubble_pivot.visible = d < 40.0


func _physics_process(dt: float) -> void:
	if _is_host():
		_tick_ai(dt)
		_sync_t += dt
		if Net.online() and _sync_t >= 0.1 and is_inside_tree():
			_sync_t = 0.0
			rpc_sync.rpc(position, _body_yaw, _spd, thief_state)
	else:
		position = position.lerp(_net_pos, minf(dt * 12.0, 1.0))
		_body_yaw = lerp_angle(_body_yaw, _net_yaw, minf(dt * 12.0, 1.0))
		_spd = lerpf(_spd, _net_spd, minf(dt * 10.0, 1.0))
		if _stun_t > 0.0:
			_stun_t = maxf(_stun_t - dt, 0.0)
	if thief_state == TState.FLEE and _spd > 3.5:
		_step_cd -= dt
		if _step_cd <= 0.0:
			_step_cd = 0.27
			Sfx.play_step("asphalt", global_position, false, 0.9)
	_animate(dt)


func _tick_ai(dt: float) -> void:
	_life += dt
	match thief_state:
		TState.SNEAK:
			var st := _find_stall()
			if st == null:
				_start_flee(false)
				return
			if _approach_pos == Vector3.ZERO:
				var side := 1.15 if _rng.randf() < 0.5 else -1.15
				_approach_pos = st.customer_spot(side) if st.has_method("customer_spot") else st.global_position
			if _move_to(_approach_pos, SNEAK_SPEED, dt) < 0.35 or _life > MAX_LIFE * 0.5:
				_set_state(TState.LURK)
				var look := st.global_position - global_position
				_body_yaw = atan2(look.x, look.z)
		TState.LURK:
			_spd = 0.0
			_lurk_t -= dt
			if _lurk_t <= 0.0:
				_do_steal()
		TState.FLEE:
			if _move_to(exit_pos, FLEE_SPEED, dt) < 1.3 or _life > MAX_LIFE:
				queue_free()
		TState.CAUGHT:
			_stun_t -= dt
			if _stun_t > 0.0:
				_spd = 0.0
			elif _move_to(exit_pos, 3.6, dt) < 1.3 or _life > MAX_LIFE + 20.0:
				queue_free()


func _move_to(p: Vector3, speed: float, dt: float) -> float:
	var diff := Vector3(p.x - position.x, 0.0, p.z - position.z)
	var dist := diff.length()
	if dist < 0.05:
		_spd = 0.0
		return dist
	var dir := diff / dist
	if thief_state == TState.FLEE:
		# zikzaklı kaçış
		var perp := Vector3(dir.z, 0, -dir.x)
		dir = (dir + perp * sin(_life * 3.1) * 0.28).normalized()
	dir = StallScript.world_steer_all(self, position, dir, dist - 0.2)
	position = StallScript.world_keepout_all(self, position + dir * minf(speed * dt, dist))
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 10.0, 1.0))
	_spd = speed
	return dist


func _set_state(s: int) -> void:
	thief_state = s
	_on_state_visual(s)


## Durum değişiminde yerel görsel (host + istemci).
func _on_state_visual(s: int) -> void:
	match s:
		TState.LURK:
			_set_line(LURK_LINES[absi(hash(name) + 1) % LURK_LINES.size()])
			_pop_emote("👀", 0.0) # adil uyarı: çalmadan önce 2-4 sn baş üstünde kalır
		TState.FLEE:
			if carried_item != "":
				_set_line(FLEE_LINES[absi(hash(name) + 2) % FLEE_LINES.size()])
			else:
				_set_line(EMPTY_LINES[absi(hash(name)) % EMPTY_LINES.size()])
				if _emote_lbl:
					_emote_lbl.hide()


func _do_steal() -> void:
	var st := _find_stall()
	var item := ""
	if st and global_position.distance_to(st.global_position) <= 4.5:
		if st.has_method("steal_one"):
			item = str(st.steal_one())
		else:
			# stall.gd yeni API'si yoksa: stoktan bir tane aşır (geri iade edilemez)
			for k in Produce.ITEM_ORDER:
				if st.has_item(k):
					if st.consume_for_sale(k) > 0:
						item = k
					break
	if Net.online():
		rpc_on_steal.rpc(item)
	else:
		rpc_on_steal(item)


## Geç katılan istemciye hırsızın durumunu ve taşıdığı ürünü uygular.
func apply_snapshot(d: Dictionary) -> void:
	var st_v := int(d.get("state", TState.SNEAK))
	var item_id := str(d.get("carried", ""))
	thief_state = st_v
	carried_item = item_id
	if item_id != "" and _carry_root:
		for c in _carry_root.get_children():
			c.queue_free()
		if Produce.ITEMS.has(item_id):
			Produce.build_mesh(_carry_root, item_id, Vector3.ZERO, 0.11)
	_on_state_visual(st_v)


@rpc("authority", "call_local", "reliable")
func rpc_on_steal(item_id: String) -> void:
	carried_item = item_id
	if item_id != "":
		_pop_emote("❗", 1.2)
		Sfx.play_3d("steal", global_position + Vector3(0, 1.0, 0), self, 0.0)
		Sfx.play_3d("kid_laugh", global_position + Vector3(0, 1.2, 0), self, -3.0)
		var nm: String = Produce.ITEMS[item_id]["name"] if Produce.ITEMS.has(item_id) else item_id
		VFX.spawn_floating_text(self, global_position + Vector3(0, 2.4, 0), "🕵️ -1 %s ÇALINDI!" % nm, Color(1.0, 0.4, 0.3), 46)
		if _carry_root:
			for c in _carry_root.get_children():
				c.queue_free()
			if Produce.ITEMS.has(item_id):
				Produce.build_mesh(_carry_root, item_id, Vector3.ZERO, 0.11)
	_start_flee_visual()
	if _is_host():
		thief_state = TState.FLEE
		_spd = FLEE_SPEED


func _start_flee(_had: bool) -> void:
	if Net.online():
		rpc_on_steal.rpc("")
	else:
		rpc_on_steal("")


func _start_flee_visual() -> void:
	thief_state = TState.FLEE
	_on_state_visual(TState.FLEE)
	Sfx.play_3d("whoosh_big", global_position + Vector3(0, 1.0, 0), self, -2.0)
	VFX.burst_dust(self, global_position + Vector3(0, 0.1, 0), Color(0.85, 0.8, 0.72), 9)


## Oyuncu [E] ile yakalamak ister. Yalnızca host işler; yakalayan 3.2 m içinde olmalı.
@rpc("any_peer", "call_local", "reliable")
func rpc_request_catch(catcher_id: int) -> void:
	if not _is_host() or _caught:
		return
	if Net.online():
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != 1 and sender != catcher_id:
			return
	var p := _find_player(catcher_id)
	if p == null:
		return
	var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	if d > CATCH_RANGE:
		return
	var item := _resolve_catch()
	# Ödül: müşteri satışlarıyla aynı para yolu, is_sale=false (satış/kombo sayacını şişirmez)
	award_non_sale(p, BOUNTY)
	if p.has_method("on_thief_caught"):
		p.on_thief_caught(item)
	caught.emit(catcher_id, item)
	if Net.online():
		rpc_on_caught.rpc(catcher_id, item != "", false)
	else:
		rpc_on_caught(catcher_id, item != "", false)


## Satış sayılmayan ödeme: yeni player.gd'de award_money(amount, tip, haggle, is_sale=false);
## eski imzada bahşiş olarak verilir.
static func award_non_sale(p: Node, amount: int) -> void:
	if p == null or not p.has_method("award_money"):
		return
	if p.get_method_argument_count("award_money") >= 4:
		p.award_money(amount, 0, false, false)
	else:
		p.award_money(0, amount, false)


## Zabıta kovalayıp yakaladığında (host). Ödül yok, mal tezgaha döner.
func zabita_catch() -> void:
	if not _is_host() or _caught:
		return
	var item := _resolve_catch()
	caught.emit(0, item)
	if Net.online():
		rpc_on_caught.rpc(0, item != "", true)
	else:
		rpc_on_caught(0, item != "", true)


func _resolve_catch() -> String:
	_caught = true
	var item := carried_item
	if item != "":
		var st := _find_stall()
		if st:
			if st.has_method("restore_one"):
				st.restore_one(item)
			if st.has_method("add_reputation"):
				st.add_reputation(REP_RESTORE)
	return item


@rpc("authority", "call_local", "reliable")
func rpc_on_caught(catcher_id: int, had_item: bool, by_zabita: bool) -> void:
	_caught = true
	thief_state = TState.CAUGHT
	_stun_t = 1.8
	carried_item = ""
	var main_node := get_parent()
	while main_node and not main_node.has_method("on_thief_caught_by"):
		main_node = main_node.get_parent()
	if main_node:
		main_node.on_thief_caught_by(catcher_id)
	if _area:
		_area.collision_layer = 0
	if _carry_root:
		for c in _carry_root.get_children():
			c.queue_free()
	var lines := ZABITA_LINES if by_zabita else CAUGHT_LINES
	_set_line(lines[absi(hash(name)) % lines.size()])
	_pop_emote("😵", 1.6)
	var pos := global_position + Vector3(0, 1.6, 0)
	Sfx.play_3d("catch", pos, self, 0.0)
	VFX.burst_mood(self, pos, false)
	VFX.burst_dust(self, global_position + Vector3(0, 0.2, 0), Color(0.9, 0.86, 0.78), 10)
	if had_item:
		VFX.spawn_floating_text(self, pos + Vector3(0, 0.5, 0), "✅ Mal geri döndü! +⭐", Color(0.5, 1.0, 0.6), 42)
	if catcher_id != 0:
		VFX.burst_coins(self, pos, 14)
		VFX.spawn_floating_text(self, pos + Vector3(0, 0.95, 0), "🏆 +%d TL ÖDÜL!" % BOUNTY, Color(1.0, 0.86, 0.22), 50)
		Sfx.play_3d("coin", pos, self, -1.0)


@rpc("authority", "unreliable_ordered")
func rpc_sync(p: Vector3, yaw: float, s: float, ts: int) -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	if ts != thief_state and not _caught:
		thief_state = ts
		if ts == TState.LURK:
			_on_state_visual(ts)


func _animate(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + float(absi(color_seed) % 50)
	var f := minf(dt * 14.0, 1.0)
	var running := thief_state == TState.FLEE or (thief_state == TState.CAUGHT and _spd > 0.5)
	var sneaking := thief_state == TState.SNEAK
	var kw := clampf(_spd / 2.0, 0.0, 1.6)
	if _spd > 0.08:
		var stride_len := 0.34 if running else 0.3
		_phase = wrapf(_phase + dt * (_spd / stride_len) * (1.0 if running else 1.4), 0.0, TAU)
	var stride := (0.36 if running else 0.24) * minf(kw, 1.0)
	var lift := (0.18 if running else 0.1) * minf(kw, 1.0)
	var lean := 0.0
	var crouch := 0.0
	var head_yaw := 0.0
	if sneaking:
		lean = 0.22
		crouch = 0.08
		head_yaw = sin(t * 2.4) * 0.6
	elif running:
		lean = 0.32
	elif thief_state == TState.LURK:
		head_yaw = sin(t * 3.2) * 0.9 # sağa sola kolaçan
		crouch = 0.04
	for side: float in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = _phase + (0.0 if side < 0 else PI)
		var fp: Vector3 = rest[fn] + Vector3(0, maxf(0.0, sin(c)) * lift, -cos(c) * stride)
		parts[fn].position = parts[fn].position.lerp(fp, f)
		parts[fn].rotation = parts[fn].rotation.lerp(Vector3(-sin(c) * 0.55 * minf(kw, 1.0), 0, 0), f)
		var hp: Vector3 = rest[hn] + Vector3(0, maxf(0.0, cos(c)) * 0.06 * kw, cos(c) * (0.32 if running else 0.16) * minf(kw, 1.0))
		var hr := Vector3(-cos(c) * 0.7 * minf(kw, 1.0), 0, 0)
		if thief_state == TState.CAUGHT and _stun_t > 0.0:
			hp = Vector3(rest[hn].x * 0.9, 1.22 + sin(t * 18.0) * 0.03, 0.05) # eller yukarı!
			hr = Vector3(0, 0, side * -0.4)
		elif thief_state == TState.LURK:
			hp = Vector3(side * 0.12, 0.62 + sin(t * 10.0 + side) * 0.02, 0.26) # elleri ovuşturur
		elif hn == "HandR" and carried_item != "":
			hp = Vector3(rest[hn].x, 0.95 + sin(c) * 0.04, 0.12) # ganimet havada!
		parts[hn].position = parts[hn].position.lerp(hp, f)
		parts[hn].rotation = parts[hn].rotation.lerp(hr, f)
	var bob := absf(sin(_phase)) * (0.06 if running else 0.03) * minf(kw, 1.0)
	parts["Body"].position = parts["Body"].position.lerp(rest["Body"] + Vector3(0, bob - crouch, 0), f)
	var hd := parts["Head"] as Node3D
	hd.position = hd.position.lerp(rest["Head"] + Vector3(0, bob - crouch * 1.4, lean * 0.4), f)
	hd.rotation = hd.rotation.lerp(Vector3(-lean * 0.4, head_yaw, 0), f)
	rig.rotation = Vector3(lerpf(rig.rotation.x, lean, f), _body_yaw, lerpf(rig.rotation.z, sin(_phase) * 0.06 * minf(kw, 1.0), f))
