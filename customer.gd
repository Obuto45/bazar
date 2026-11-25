extends Node3D
## Yapay zeka pazar müşterisi (NPC): caddede yürür, fiyat orantısı + oyuncu bağırması + çeşitliliğe göre
## tezgah seçer, konuşma balonunda istediği ürünleri gösterir, E ile tek tek ürün alır ve üstünde +TL çıkarır.

const MODEL := preload("res://models/character.glb")
const StallScript := preload("res://stall.gd")
const HAIRS := [Color(0.2, 0.12, 0.07), Color(0.08, 0.06, 0.05), Color(0.75, 0.55, 0.25), Color(0.55, 0.22, 0.1),
	Color(0.4, 0.28, 0.18), Color(0.85, 0.8, 0.7)]
const SHIRTS := [Color(0.82, 0.28, 0.24), Color(0.24, 0.52, 0.82), Color(0.92, 0.72, 0.2), Color(0.32, 0.7, 0.36),
	Color(0.62, 0.36, 0.78), Color(0.92, 0.48, 0.65), Color(0.18, 0.68, 0.68), Color(0.92, 0.54, 0.18)]

enum State { STROLL, APPROACH, WAIT_BUY, LEAVE }

var state: int = State.STROLL
var color_seed := 0
var wants: Dictionary = {} # item_id -> kalan adet (1..3 ürün çeşidi, toplam 1..4 adet)
var target_owner_id := 0 # seçilen tezgahın sahibi peer_id
var target_pos := Vector3.ZERO
var exit_pos := Vector3(0, 0, 20)
var walk_speed := 2.35
var wait_timer := 0.0
var eval_timer := 0.0
var mood_text := ""

var rig: Node3D
var head: Node3D
var parts := {}
var rest := {}
var bubble: Label3D
var _body_yaw := 0.0
var _phase := 0.0
var _spd := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_spd := 0.0
var _sync_t := 0.0


func init_customer(p_name: String, p_seed: int, start_pos: Vector3, p_exit: Vector3, p_wants: Dictionary) -> void:
	name = p_name
	color_seed = p_seed
	position = start_pos
	_net_pos = start_pos
	exit_pos = p_exit
	target_pos = p_exit
	wants = p_wants.duplicate()


func _ready() -> void:
	_build_visual()
	_build_bubble_and_area()
	_refresh_bubble()


func _build_visual() -> void:
	var src := MODEL.instantiate()
	rig = Node3D.new()
	add_child(rig)
	head = Node3D.new()
	add_child(head)
	var hair_col: Color = HAIRS[absi(color_seed) % HAIRS.size()]
	var shirt_col: Color = SHIRTS[absi(color_seed * 3 + 1) % SHIRTS.size()]
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
					c.albedo_color = hair_col if mat.resource_name == "Hair" else shirt_col
					mi.set_surface_override_material(i, c)
	src.free()
	var sc := 0.93 + float(absi(color_seed) % 5) * 0.03
	scale = Vector3(sc, sc, sc)


func _build_bubble_and_area() -> void:
	bubble = Label3D.new()
	bubble.position = Vector3(0, 1.82, 0)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font_size = 34
	bubble.outline_size = 10
	bubble.modulate = Color(1.0, 0.98, 0.9)
	bubble.outline_modulate = Color(0.1, 0.06, 0.04)
	add_child(bubble)
	# Satış etkileşimi için RayCast alanı (layer 4)
	var area := Area3D.new()
	area.name = "CustomerArea"
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("kind", "customer")
	area.set_meta("customer_name", name)
	area.position = Vector3(0, 0.85, 0)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45; sh.height = 1.65
	cs.shape = sh
	area.add_child(cs)
	add_child(area)


func _refresh_bubble() -> void:
	if bubble == null:
		return
	if mood_text != "":
		bubble.text = mood_text
		bubble.modulate = Color(0.65, 1.0, 0.65)
		return
	var segs := PackedStringArray()
	for k in wants:
		var cnt: int = int(wants[k])
		if cnt > 0 and StallScript.ITEMS.has(k):
			segs.append("%dx %s" % [cnt, StallScript.ITEMS[k]["name"]])
	if segs.is_empty():
		bubble.text = ""
		return
	if state == State.WAIT_BUY:
		bubble.text = "🛒 " + ", ".join(segs)
		bubble.modulate = Color(1.0, 0.88, 0.38)
	else:
		bubble.text = "💬 " + ", ".join(segs)
		bubble.modulate = Color(1.0, 0.98, 0.92)


func _physics_process(dt: float) -> void:
	var is_host := (not Net.online()) or multiplayer.is_server()
	if is_host:
		_tick_ai(dt)
		_sync_t += dt
		if Net.online() and _sync_t >= 0.1:
			_sync_t = 0.0
			rpc_sync_state.rpc(position, _body_yaw, _spd, state, target_owner_id, wants, mood_text)
	else:
		position = position.lerp(_net_pos, minf(dt * 12.0, 1.0))
		_body_yaw = lerp_angle(_body_yaw, _net_yaw, minf(dt * 12.0, 1.0))
		_spd = lerpf(_spd, _net_spd, minf(dt * 10.0, 1.0))
	rig.rotation.y = _body_yaw
	head.rotation.y = lerp_angle(head.rotation.y, _body_yaw, minf(dt * 10.0, 1.0))
	_animate_walk(dt)


func _tick_ai(dt: float) -> void:
	match state:
		State.STROLL:
			_move_toward_target(dt, walk_speed)
			eval_timer -= dt
			if eval_timer <= 0.0:
				eval_timer = 0.45
				_evaluate_stalls()
			if Vector2(position.x - exit_pos.x, position.z - exit_pos.z).length() < 1.2:
				queue_free()
		State.APPROACH:
			var st := _find_stall(target_owner_id)
			if st == null or not _stall_has_any_want(st):
				state = State.STROLL
				target_owner_id = 0
				target_pos = exit_pos
				_refresh_bubble()
				return
			_move_toward_target(dt, walk_speed * 1.1)
			if Vector2(position.x - target_pos.x, position.z - target_pos.z).length() < 0.35:
				state = State.WAIT_BUY
				_spd = 0.0
				wait_timer = 26.0
				# Tezgaha dön
				var look_dir: Vector3 = (st as Node3D).global_position - global_position
				_body_yaw = atan2(look_dir.x, look_dir.z)
				_refresh_bubble()
		State.WAIT_BUY:
			_spd = 0.0
			wait_timer -= dt
			var st := _find_stall(target_owner_id)
			if st == null or not _stall_has_any_want(st) or _total_wants() <= 0 or wait_timer <= 0.0:
				if _total_wants() <= 0:
					mood_text = "😊 Teşekkürler!"
				elif wait_timer <= 0.0:
					mood_text = "😕 Çok bekledim..."
				state = State.LEAVE
				target_owner_id = 0
				target_pos = exit_pos
				_refresh_bubble()
		State.LEAVE:
			_move_toward_target(dt, walk_speed * 1.05)
			if Vector2(position.x - exit_pos.x, position.z - exit_pos.z).length() < 1.2:
				queue_free()


func _move_toward_target(dt: float, speed: float) -> void:
	var diff := Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	var dist := diff.length()
	if dist < 0.05:
		_spd = 0.0
		return
	var dir := diff / dist
	# Çeşme etrafından (merkez r=3.1m) yumuşakça kaçın
	var from_fountain := Vector2(position.x, position.z)
	if from_fountain.length() < 3.4:
		var push := from_fountain.normalized()
		dir = (dir + Vector3(push.x, 0.0, push.y) * 0.9).normalized()
	position += dir * minf(speed * dt, dist)
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 8.0, 1.0))
	_spd = speed


## Çok faktörlü cazibe: göreceli fiyat orantısı + oyuncu bağırması (desibel/yakınlık) + çeşitlilik + kuyruk.
func _evaluate_stalls() -> void:
	var stalls := _all_stalls()
	if stalls.is_empty():
		return
	var best_stall = null
	var best_score := 0.0
	for st in stalls:
		var dist := global_position.distance_to(st.global_position)
		if dist > 15.0:
			continue
		var matched := 0
		var price_sum := 0.0
		for k in wants:
			if int(wants[k]) > 0 and st.has_item(k):
				matched += 1
				price_sum += StallScript.relative_price_score(k, st.get_item_price(k), stalls)
		if matched == 0:
			continue
		var avg_price_score := price_sum / float(matched)
		if avg_price_score < 0.12:
			continue # fahiş fiyata hiç uğramaz
		# Oyuncunun bağırma gücü (mikrofon desibeli veya B tuşu) — tezgahına yakınsa geçerli
		var shout_score := 0.0
		var owner := _find_player(st.owner_id)
		if owner and owner.global_position.distance_to(st.global_position) < 4.5:
			var sp: float = owner.shout_power
			shout_score = clampf(sp / (1.0 + dist * 0.12), 0.0, 1.2)
		# Çeşitlilik ve yakınlık bonusu
		var variety := clampf(float(matched) / float(maxi(wants.size(), 1)), 0.0, 1.0)
		var proximity := clampf(1.0 - dist / 15.0, 0.0, 1.0)
		var busy := _count_customers_at(st.owner_id)
		# Çok faktörlü ağırlıklı cazibe: fiyat (%50) + bağırma (%32) + çeşit/yakınlık (%18)
		# Fiyat çok kötüyse yüksek bağırma tek başına kurtarmaz (avg_price_score çarpanı)
		var score := avg_price_score * 0.50 + shout_score * 0.32 * clampf(avg_price_score, 0.35, 1.15) \
			+ (variety * 0.6 + proximity * 0.4) * 0.18 - float(busy) * 0.25
		if score > best_score:
			best_score = score
			best_stall = st
	# Cazibe oranına göre tezgaha yönelme olasılığı (bağırma + ucuz fiyat çekimi belirgin artırır)
	if best_stall and best_score > 0.36 and randf() < clampf(best_score * 0.72, 0.15, 0.92):
		target_owner_id = best_stall.owner_id
		var busy_n := _count_customers_at(target_owner_id)
		var side_off := (busy_n % 3 - 1) * 0.65
		target_pos = best_stall.customer_spot(side_off)
		state = State.APPROACH
		_refresh_bubble()


## Oyuncu E tuşuna basıp 1 ürün satmaya çalışır. Başarılıysa satılan (item_id, price) döner.
func try_sell_one_from(seller_id: int) -> Dictionary:
	if state != State.WAIT_BUY or target_owner_id != seller_id:
		return {}
	var st := _find_stall(seller_id)
	if st == null:
		return {}
	for k in wants:
		if int(wants[k]) > 0 and st.has_item(k):
			var price: int = st.consume_for_sale(k)
			if price > 0:
				wants[k] = int(wants[k]) - 1
				if int(wants[k]) <= 0:
					wants.erase(k)
				wait_timer = 22.0
				var done := _total_wants() <= 0 or not _stall_has_any_want(st)
				if done:
					mood_text = "😊 Teşekkürler!"
					state = State.LEAVE
					target_owner_id = 0
					target_pos = exit_pos
				_refresh_bubble()
				if Net.online():
					rpc_on_sold.rpc(price, wants, state, mood_text)
				else:
					_spawn_floating_money(price)
				return {"item": k, "price": price}
	return {}


@rpc("any_peer", "call_local", "reliable")
func rpc_request_sell(seller_id: int) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	var res := try_sell_one_from(seller_id)
	if not res.is_empty():
		var p := _find_player(seller_id)
		if p:
			p.award_money(int(res["price"]))


@rpc("authority", "call_local", "reliable")
func rpc_on_sold(price: int, new_wants: Dictionary, new_state: int, new_mood: String) -> void:
	wants = new_wants
	state = new_state
	mood_text = new_mood
	_refresh_bubble()
	_spawn_floating_money(price)


@rpc("authority", "unreliable_ordered")
func rpc_sync_state(p: Vector3, yaw: float, s: float, st: int, own: int, w: Dictionary, mood: String) -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	if state != st or wants != w or mood_text != mood:
		state = st
		target_owner_id = own
		wants = w
		mood_text = mood
		_refresh_bubble()


## Satış anında müşterinin üstünde yukarı süzülen altın "+10 TL" yazısı.
func _spawn_floating_money(amount: int) -> void:
	var lbl := Label3D.new()
	lbl.text = "+%d TL" % amount
	lbl.position = Vector3(0, 2.15, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 46
	lbl.outline_size = 12
	lbl.modulate = Color(1.0, 0.86, 0.22)
	lbl.outline_modulate = Color(0.15, 0.08, 0.02)
	add_child(lbl)
	var tw := create_tween().set_parallel()
	tw.tween_property(lbl, "position:y", 2.95, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.05).set_delay(0.25)
	tw.chain().tween_callback(lbl.queue_free)


func get_next_sell_hint(seller_id: int) -> String:
	if state != State.WAIT_BUY or target_owner_id != seller_id:
		return ""
	var st := _find_stall(seller_id)
	if st == null:
		return ""
	for k in wants:
		if int(wants[k]) > 0 and st.has_item(k):
			var p: int = st.get_item_price(k)
			return "[E] Sat: %s (%d TL)  •  Kalan: %d" % [StallScript.ITEMS[k]["name"], p, _total_wants()]
	return ""


func _total_wants() -> int:
	var t := 0
	for k in wants:
		t += int(wants[k])
	return t


func _stall_has_any_want(st) -> bool:
	for k in wants:
		if int(wants[k]) > 0 and st.has_item(k):
			return true
	return false


func _all_stalls() -> Array:
	var world := get_parent().get_parent() if get_parent() else null
	var sg := world.get_node_or_null("Stalls") if world else null
	return sg.get_children() if sg else []


func _find_stall(owner_id: int) -> Node3D:
	var world := get_parent().get_parent() if get_parent() else null
	var sg := world.get_node_or_null("Stalls") if world else null
	return sg.get_node_or_null("Stall_%d" % owner_id) as Node3D if sg else null


func _find_player(pid: int) -> Node3D:
	var world := get_parent().get_parent() if get_parent() else null
	var pg := world.get_node_or_null("Players") if world else null
	return pg.get_node_or_null(str(pid)) as Node3D if pg else null


func _count_customers_at(owner_id: int) -> int:
	var n := 0
	if get_parent():
		for c in get_parent().get_children():
			if c != self and c.target_owner_id == owner_id and c.state in [State.APPROACH, State.WAIT_BUY]:
				n += 1
	return n


func _animate_walk(dt: float) -> void:
	var kw := clampf(_spd / 2.6, 0.0, 1.0)
	var stride := 0.25 * kw
	var lift := 0.10 * kw
	if _spd > 0.08:
		_phase = wrapf(_phase + dt * (_spd / 0.25) * 0.94, 0.0, TAU)
	var f := minf(dt * 14.0, 1.0)
	for side in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = _phase + (0.0 if side < 0 else PI)
		var fp: Vector3 = rest[fn] + Vector3(0, maxf(0.0, sin(c)) * lift, -cos(c) * stride)
		parts[fn].position = parts[fn].position.lerp(fp, f)
		parts[fn].rotation = parts[fn].rotation.lerp(Vector3(-sin(c) * 0.4 * kw, 0, 0), f)
		var hp: Vector3 = rest[hn] + Vector3(0, maxf(0.0, cos(c)) * 0.04 * kw, cos(c) * 0.22 * kw)
		parts[hn].position = parts[hn].position.lerp(hp, f)
		parts[hn].rotation = parts[hn].rotation.lerp(Vector3(-cos(c) * 0.5 * kw, 0, 0), f)
	var bp: Vector3 = rest["Body"] + Vector3(0, absf(sin(_phase)) * 0.035 * kw, 0)
	parts["Body"].position = parts["Body"].position.lerp(bp, f)
	head.position = head.position.lerp(rest["Head"] + Vector3(0, (parts["Body"].position.y - rest["Body"].y) * 1.1, 0), f)
