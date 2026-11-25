extends Node3D
## Pazar Zabıtası AI: ana caddede devriye gezer, tezgahları denetler.
## Fahiş fiyata (-25 TL) ve sokağa atılmış kasalara (-15 TL) düdük çalıp ceza keser;
## temiz ve dürüst esnafa +10 TL ödül verir!

const MODEL := preload("res://models/character.glb")
const LP := preload("res://lowpoly.gd")
const VFX := preload("res://vfx.gd")

const FINE_GOUGE := 25
const FINE_LITTER := 15
const CLEAN_REWARD := 10
const WALK_SPEED := 2.75

var _exit_pos := Vector3(0, 0, 20.5)
var _checked_stalls := {} # owner_id -> bool
var _pause_t := 0.0
var _bubble_text := "👮 ZABITA DENETİMİ!"
var _body_yaw := 0.0
var _phase := 0.0
var _spd := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_spd := 0.0
var _sync_t := 0.0

var rig: Node3D
var head: Node3D
var parts := {}
var rest := {}
var bubble: Label3D


func init_inspector(from_north: bool) -> void:
	name = "Zabita"
	position = Vector3(0.0, 0.0, -20.5 if from_north else 20.5)
	_net_pos = position
	_exit_pos = Vector3(0.0, 0.0, 20.5 if from_north else -20.5)


func _ready() -> void:
	_build_visual()
	bubble = Label3D.new()
	bubble.text = _bubble_text
	bubble.position = Vector3(0, 2.02, 0)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font_size = 36
	bubble.outline_size = 11
	bubble.modulate = Color(0.58, 0.85, 1.0)
	bubble.outline_modulate = Color(0.05, 0.08, 0.18)
	bubble.no_depth_test = true
	add_child(bubble)
	Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, -2.0, 1.0, 36.0)


func _build_visual() -> void:
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
				if mat and mat.resource_name == "Shirt":
					var c := mat.duplicate() as BaseMaterial3D
					c.albedo_color = Color(0.11, 0.22, 0.46) # lacivert zabıta üniforması
					mi.set_surface_override_material(i, c)
	src.free()
	# Zabıta şapkası + altın rozet
	var h := parts["Head"] as Node3D
	LP.add(h, LP.cyl(0.30, 0.25, 0.16, 10), Vector3(0, 0.29, 0), Color(0.09, 0.17, 0.38))
	LP.add(h, LP.box(Vector3(0.30, 0.035, 0.22)), Vector3(0, 0.22, 0.25), Color(0.06, 0.08, 0.14))
	LP.add(h, LP.cyl(0.055, 0.055, 0.03, 6), Vector3(0, 0.28, 0.28), Color(1.0, 0.82, 0.2), Vector3(PI / 2, 0, 0), 0.22, 0.85)
	# Sol elde ceza defteri
	var hl := parts["HandL"] as Node3D
	LP.add(hl, LP.box(Vector3(0.18, 0.24, 0.03)), Vector3(0, 0.02, 0.10), Color(0.45, 0.28, 0.14), Vector3(-0.3, 0, 0))
	LP.add(hl, LP.box(Vector3(0.14, 0.19, 0.035)), Vector3(0, 0.02, 0.105), Color(0.98, 0.96, 0.9), Vector3(-0.3, 0, 0))
	scale = Vector3(1.08, 1.08, 1.08)


func _physics_process(dt: float) -> void:
	var is_host := (not Net.online()) or multiplayer.is_server()
	if is_host:
		_tick_patrol(dt)
		_sync_t += dt
		if Net.online() and _sync_t >= 0.1:
			_sync_t = 0.0
			rpc_sync.rpc(position, _body_yaw, _spd, _bubble_text)
	else:
		position = position.lerp(_net_pos, minf(dt * 12.0, 1.0))
		_body_yaw = lerp_angle(_body_yaw, _net_yaw, minf(dt * 12.0, 1.0))
		_spd = lerpf(_spd, _net_spd, minf(dt * 10.0, 1.0))
	rig.rotation.y = _body_yaw
	head.rotation.y = lerp_angle(head.rotation.y, _body_yaw, minf(dt * 10.0, 1.0))
	_animate_walk(dt)


func _tick_patrol(dt: float) -> void:
	if _pause_t > 0.0:
		_pause_t -= dt
		_spd = 0.0
		return
	var diff := Vector3(_exit_pos.x - position.x, 0.0, _exit_pos.z - position.z)
	var dist := diff.length()
	if dist < 1.2:
		queue_free()
		return
	var dir := diff / dist
	var from_f := Vector2(position.x, position.z)
	if from_f.length() < 3.7:
		var push := (from_f if from_f.length() > 0.05 else Vector2(1, 0)).normalized()
		dir = (dir + Vector3(push.x, 0.0, push.y) * 1.1).normalized()
	position += dir * minf(WALK_SPEED * dt, dist)
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 8.0, 1.0))
	_spd = WALK_SPEED
	_inspect_nearby_stalls()


func _inspect_nearby_stalls() -> void:
	var world := get_parent()
	if world == null:
		return
	var sg := world.get_node_or_null("Stalls")
	var pg := world.get_node_or_null("Players")
	if sg == null or pg == null:
		return
	var all_stalls := sg.get_children()
	var ev := str(world.get_meta("event_item", ""))
	for st in all_stalls:
		var oid: int = st.owner_id
		if _checked_stalls.has(oid):
			continue
		if absf(position.z - st.global_position.z) < 2.1 and global_position.distance_to(st.global_position) < 7.2:
			_checked_stalls[oid] = true
			var owner := pg.get_node_or_null(str(oid))
			if owner == null:
				continue
			# Tezgaha dön ve kısa süre denetle
			var look: Vector3 = st.global_position - global_position
			_body_yaw = atan2(look.x, look.z)
			_pause_t = 2.0
			# 1) Fahiş fiyat denetimi
			var gouge: Dictionary = st.find_price_gouging(all_stalls, ev)
			if not gouge.is_empty():
				owner.apply_fine(FINE_GOUGE, "Fahiş Fiyat Cezası (%d TL)" % int(gouge["price"]))
				_announce("🚨 FAHİŞ FİYAT! -%d TL" % FINE_GOUGE, st.global_position, false)
				return
			# 2) Sokaktaki atılmış kasa denetimi
			for node in get_tree().get_nodes_in_group("thrown_crates"):
				if is_instance_valid(node) and not bool(node.get_meta("fined", false)) and int(node.get_meta("owner_id", -1)) == oid:
					if (node as Node3D).global_position.distance_to(st.global_position) < 8.5:
						node.set_meta("fined", true)
						owner.apply_fine(FINE_LITTER, "Sokağa Kasa Atma Cezası")
						node.queue_free()
						_announce("🚨 SOKAK KİRLİLİĞİ! -%d TL" % FINE_LITTER, st.global_position, false)
						return
			# 3) Temiz & dürüst esnaf ödülü (tezgah doluysa)
			if st.total_stock() >= 3:
				owner.award_money(CLEAN_REWARD, 0, false)
				_announce("👍 TEMİZ ESNAF! +%d TL" % CLEAN_REWARD, st.global_position, true)
			else:
				_bubble_text = "👮 Denetim devam ediyor..."
				if bubble:
					bubble.text = _bubble_text
			return


func _announce(msg: String, stall_pos: Vector3, good: bool) -> void:
	if Net.online():
		rpc_verdict.rpc(msg, stall_pos, good)
	else:
		rpc_verdict(msg, stall_pos, good)


@rpc("authority", "call_local", "reliable")
func rpc_verdict(msg: String, stall_pos: Vector3, good: bool) -> void:
	_bubble_text = msg
	if bubble:
		bubble.text = msg
		bubble.modulate = Color(0.52, 1.0, 0.58) if good else Color(1.0, 0.35, 0.28)
	var fx_pos := stall_pos + Vector3(0, 1.75, 0)
	if good:
		Sfx.play_3d("happy", fx_pos, self, -2.0)
		VFX.burst_mood(self, fx_pos, true)
		VFX.spawn_floating_text(self, fx_pos, msg, Color(0.45, 1.0, 0.55), 42)
	else:
		Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, 0.0, 1.08, 34.0)
		VFX.burst_mood(self, fx_pos, false)
		VFX.spawn_floating_text(self, fx_pos, msg, Color(1.0, 0.32, 0.26), 44)


@rpc("authority", "unreliable_ordered")
func rpc_sync(p: Vector3, yaw: float, s: float, txt: String) -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	if _bubble_text != txt:
		_bubble_text = txt
		if bubble:
			bubble.text = txt


func _animate_walk(dt: float) -> void:
	var kw := clampf(_spd / 2.8, 0.0, 1.0)
	var stride := 0.28 * kw
	var lift := 0.11 * kw
	if _spd > 0.08:
		_phase = wrapf(_phase + dt * (_spd / 0.28) * 0.94, 0.0, TAU)
	var f := minf(dt * 14.0, 1.0)
	for side in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = _phase + (0.0 if side < 0 else PI)
		var fp: Vector3 = rest[fn] + Vector3(0, maxf(0.0, sin(c)) * lift, -cos(c) * stride)
		parts[fn].position = parts[fn].position.lerp(fp, f)
		parts[fn].rotation = parts[fn].rotation.lerp(Vector3(-sin(c) * 0.45 * kw, 0, 0), f)
		var hp: Vector3 = rest[hn] + Vector3(0, maxf(0.0, cos(c)) * 0.04 * kw, cos(c) * 0.24 * kw)
		parts[hn].position = parts[hn].position.lerp(hp, f)
		parts[hn].rotation = parts[hn].rotation.lerp(Vector3(-cos(c) * 0.5 * kw, 0, 0), f)
	var bp: Vector3 = rest["Body"] + Vector3(0, absf(sin(_phase)) * 0.04 * kw, 0)
	parts["Body"].position = parts["Body"].position.lerp(bp, f)
	head.position = head.position.lerp(rest["Head"] + Vector3(0, (parts["Body"].position.y - rest["Body"].y) * 1.1, 0), f)
