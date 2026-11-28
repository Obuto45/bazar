extends Node3D
## Pazar Zabıtası AI: normal devriyede fahiş fiyat (-25 TL) ve sokak kirliliğine (-15 TL) ceza keser;
## bir pazarcı diğerine veya rakip tezgaha zarar verirse ACİL MÜDAHALE moduna geçip koşarak gelir,
## gözünün önünde ceza tutanağı yazıp keser ve zarar verdiği nesneye el koyar!

const MODEL := preload("res://models/char_zabita.glb")
const LP := preload("res://lowpoly.gd")
const VFX := preload("res://vfx.gd")
const StallScript := preload("res://stall.gd")

enum Mode { PATROL, CHASE, TICKET, CHASE_THIEF }

const FINE_GOUGE := 25
const FINE_LITTER := 15
const FINE_DRUNK := 25
const FINE_ASSAULT := 50
const CLEAN_REWARD := 10
const WALK_SPEED := 2.75
const CHASE_SPEED := 6.8
const THIEF_SIGHT := 16.0
const TICKET_WRITE_SEC := 1.45
const TICKET_TOTAL_SEC := 2.40
const WEAPON_LABELS := {
	"bicak": "BIÇAĞA",
	"sopa": "SOPAYA",
	"bira": "BİRAYA",
	"sigara": "SİGARAYA",
	"puro": "PUROYA",
}
const CONFISCATE_FALLBACK := ["bicak", "sopa", "bira", "sigara", "puro"]
const PATROL_LINES := ["👮 Fiyat etiketleri yerinde mi?", "👮 Teraziler kontrol edilecek!", "👮 Kaldırım işgali yasak!",
	"👮 Fişinizi kesmeyi unutmayın!", "👮 Pazar düzenli olacak!", "👮 Bağırmak serbest, kazık yasak!",
	"👮 Kasalar yere atılmayacak!", "👮 Hayırlı işler esnaf!", "👮 Çürük mal satan yandı!"]

var mode: int = Mode.PATROL
var chase_peer_id := 0
var chase_weapon := "bicak"
var chase_fine := FINE_ASSAULT
var chase_reason := "Saldırı Cezası!"
var _chase_timeout := 0.0
var _ticket_t := 0.0
var _ticket_delivered := false
var _ticket_target_pos := Vector3.ZERO
var _patrol_ticket_t := 0.0
var _exit_pos := Vector3(0, 0, 21.5)
var _checked_stalls := {}
var _pause_t := 0.0
var _bubble_text := "👮 ZABITA DENETİMİ!"
var _body_yaw := 0.0
var _phase := 0.0
var _spd := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_spd := 0.0
var _sync_t := 0.0
var _chase_thief: Node3D
var _thief_scan_t := 0.0
var _line_t := 3.0
var _line_idx := 0
var _verdict_hold := 0.0
var _whistle_t := 0.0
var _whistle: Node3D
var _pen: Node3D
var _clipboard: Node3D
var _step_cd := 0.0

var rig: Node3D
var head: Node3D
var parts := {}
var rest := {}
var bubble: Label3D


func init_inspector(from_north: bool, target_attacker := 0, weapon := "bicak", fine := FINE_ASSAULT, reason := "Saldırı Cezası!") -> void:
	name = "Zabita"
	position = Vector3(1.8 if from_north else -1.8, 0.0, -21.0 if from_north else 21.0)
	_net_pos = position
	_exit_pos = Vector3(0.0, 0.0, 21.5 if from_north else -21.5)
	if target_attacker > 0:
		mode = Mode.CHASE
		chase_peer_id = target_attacker
		chase_weapon = weapon
		chase_fine = fine
		chase_reason = reason
		_chase_timeout = 26.0
		_bubble_text = "🚨 ZABITA! %s! DUR!" % reason.to_upper()


func start_chase(target_attacker: int, weapon := "bicak", fine := FINE_ASSAULT, reason := "Saldırı Cezası!") -> void:
	mode = Mode.CHASE
	chase_peer_id = target_attacker
	chase_weapon = weapon
	chase_fine = fine
	chase_reason = reason
	_chase_timeout = 26.0
	_ticket_t = 0.0
	_ticket_delivered = false
	_pause_t = 0.0
	_verdict_hold = 0.0
	_bubble_text = "🚨 ZABITA! %s! DUR!" % reason.to_upper()
	if bubble:
		bubble.text = _bubble_text
		bubble.modulate = Color(1.0, 0.35, 0.28)
	_whistle_t = 1.15
	Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, 1.0, 1.12, 42.0)


func _ready() -> void:
	_build_visual()
	bubble = Label3D.new()
	bubble.text = _bubble_text
	bubble.position = Vector3(0, 2.02, 0)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font_size = 44
	bubble.pixel_size = 0.0042
	bubble.outline_size = 14
	bubble.modulate = Color(1.0, 0.35, 0.28) if mode == Mode.CHASE else Color(0.58, 0.85, 1.0)
	bubble.outline_modulate = Color(0.05, 0.08, 0.18)
	bubble.no_depth_test = true
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubble)
	_whistle_t = 1.0
	Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, 0.0, 1.05, 40.0)


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
				var recol := {"Shirt": Color(0.11, 0.2, 0.42), "Pants": Color(0.08, 0.12, 0.24), "Hair": Color(0.08, 0.06, 0.05),
					"Shoe": Color(0.06, 0.06, 0.07)}
				if mat and recol.has(mat.resource_name):
					var c := mat.duplicate() as BaseMaterial3D
					c.albedo_color = recol[mat.resource_name]
					mi.set_surface_override_material(i, c)
	src.free()
	# Resmi zabıta şapkası, apoletler, kemer ve altın toka modelde (char_zabita.glb)
	# Gövde: sırtta ZABITA yazısı
	var b := parts["Body"] as Node3D
	var back := Label3D.new()
	back.text = "ZABITA"
	back.font_size = 40
	back.pixel_size = 0.0042
	back.outline_size = 6
	back.modulate = Color(1.0, 0.95, 0.75)
	back.outline_modulate = Color(0.05, 0.08, 0.18)
	back.position = Vector3(0, 0.02, -0.25)
	back.rotation = Vector3(0, PI, 0)
	back.double_sided = false
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(back)
	# Düdük (sağ elde, çalarken ağza gider) + Ceza Kalemi (tutanak yazarken görünür)
	var hr := parts["HandR"] as Node3D
	_whistle = Node3D.new()
	_whistle.position = Vector3(0, 0.05, 0.08)
	hr.add_child(_whistle)
	LP.add(_whistle, LP.cyl(0.025, 0.03, 0.08, 6), Vector3.ZERO, Color(0.85, 0.85, 0.88), Vector3(PI / 2, 0, 0), 0.25, 0.8)
	_pen = Node3D.new()
	_pen.position = Vector3(0.0, 0.03, 0.09)
	_pen.rotation = Vector3(-0.65, 0.2, 0.0)
	hr.add_child(_pen)
	LP.add(_pen, LP.cyl(0.011, 0.012, 0.16, 6), Vector3.ZERO, Color(0.10, 0.24, 0.62), Vector3(PI / 2, 0, 0), 0.3, 0.3)
	LP.add(_pen, LP.cyl(0.013, 0.013, 0.025, 6), Vector3(0, 0, -0.055), Color(0.92, 0.76, 0.24), Vector3(PI / 2, 0, 0), 0.25, 0.75)
	LP.add(_pen, LP.cyl(0.003, 0.011, 0.038, 6), Vector3(0, 0, 0.095), Color(0.86, 0.88, 0.90), Vector3(PI / 2, 0, 0), 0.2, 0.85)
	_pen.hide()
	# Ceza panosu + sarı makbuz sayfası (sol elde)
	var hl := parts["HandL"] as Node3D
	_clipboard = Node3D.new()
	_clipboard.position = Vector3(0, 0.02, 0.10)
	_clipboard.rotation = Vector3(-0.3, 0, 0)
	hl.add_child(_clipboard)
	LP.add(_clipboard, LP.box(Vector3(0.20, 0.26, 0.028)), Vector3.ZERO, Color(0.45, 0.28, 0.14))
	LP.add(_clipboard, LP.box(Vector3(0.16, 0.21, 0.010)), Vector3(0, -0.008, 0.017), Color(1.0, 0.94, 0.56))
	LP.add(_clipboard, LP.box(Vector3(0.08, 0.03, 0.022)), Vector3(0, 0.108, 0.018), Color(0.76, 0.78, 0.82), Vector3.ZERO, 0.25, 0.8)
	scale = Vector3(1.08, 1.08, 1.08)


func _physics_process(dt: float) -> void:
	var is_host := (not Net.online()) or multiplayer.is_server()
	if is_host:
		if mode == Mode.CHASE:
			_tick_chase(dt)
		elif mode == Mode.TICKET:
			_tick_ticket(dt)
		elif mode == Mode.CHASE_THIEF:
			_tick_chase_thief(dt)
		else:
			_tick_patrol(dt)
			_scan_for_thieves(dt)
			_tick_patrol_lines(dt)
		_sync_t += dt
		if Net.online() and _sync_t >= 0.09:
			_sync_t = 0.0
			Net.rpc_ready(rpc_sync, [position, _body_yaw, _spd, _bubble_text, mode])
	else:
		position = position.lerp(_net_pos, minf(dt * 12.0, 1.0))
		_body_yaw = lerp_angle(_body_yaw, _net_yaw, minf(dt * 12.0, 1.0))
		_spd = lerpf(_spd, _net_spd, minf(dt * 10.0, 1.0))
		if mode == Mode.TICKET:
			_ticket_t += dt
	if _spd > 3.6:
		_step_cd -= dt
		if _step_cd <= 0.0:
			_step_cd = 0.28
			Sfx.play_step("asphalt", global_position, false, 0.85)
	rig.rotation.y = _body_yaw
	head.rotation.y = lerp_angle(head.rotation.y, _body_yaw, minf(dt * 10.0, 1.0))
	_animate_walk(dt)


func _process(_dt: float) -> void:
	# Uzaktan okunur balon: kameraya uzaklıkla büyür
	if bubble == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(bubble.global_position)
		var s := clampf(d / 7.0, 1.0, 2.3) / maxf(scale.x, 0.5)
		bubble.scale = Vector3(s, s, s)


func _set_bubble(t: String) -> void:
	_bubble_text = t
	if bubble:
		bubble.text = t


## Devriyede ara ara replik (host; rpc_sync ile istemcilere gider).
func _tick_patrol_lines(dt: float) -> void:
	if _verdict_hold > 0.0:
		_verdict_hold -= dt
		return
	_line_t -= dt
	if _line_t <= 0.0:
		_line_t = randf_range(4.0, 6.5)
		_line_idx = (_line_idx + 1 + randi() % 3) % PATROL_LINES.size()
		_set_bubble(PATROL_LINES[_line_idx])
		if bubble:
			bubble.modulate = Color(0.58, 0.85, 1.0)


## Yakındaki kaçan kapkaççıyı görürse düdük çalıp peşine düşer.
func _scan_for_thieves(dt: float) -> void:
	_thief_scan_t -= dt
	if _thief_scan_t > 0.0:
		return
	_thief_scan_t = 0.4
	var tg := get_parent().get_node_or_null("Thieves") if get_parent() else null
	if tg == null:
		return
	for th in tg.get_children():
		if not (th is Node3D) or not th.has_method("is_carrying") or not th.is_carrying():
			continue
		if th.has_method("is_catchable") and not th.is_catchable():
			continue
		if (th as Node3D).global_position.distance_to(global_position) < THIEF_SIGHT:
			_chase_thief = th
			mode = Mode.CHASE_THIEF
			_chase_timeout = 12.0
			_pause_t = 0.0
			_verdict_hold = 0.0
			if Net.online():
				rpc_thief_alarm.rpc()
			else:
				rpc_thief_alarm()
			return


@rpc("authority", "call_local", "reliable")
func rpc_thief_alarm() -> void:
	_set_bubble("🚨 DUR! KAPKAÇÇI! YAKALAYIN!")
	if bubble:
		bubble.modulate = Color(1.0, 0.35, 0.28)
	_whistle_t = 1.2
	Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, 1.0, 1.15, 44.0)


func _tick_chase_thief(dt: float) -> void:
	_chase_timeout -= dt
	var th := _chase_thief
	if th == null or not is_instance_valid(th) or not th.is_inside_tree() or _chase_timeout <= 0.0 \
			or (th.has_method("is_catchable") and not th.is_catchable()):
		_chase_thief = null
		mode = Mode.PATROL
		_set_bubble("👮 Kaçtı... Bir dahakine!")
		_verdict_hold = 2.5
		return
	var diff := Vector3(th.global_position.x - position.x, 0.0, th.global_position.z - position.z)
	var dist := diff.length()
	if dist < 1.5:
		var had: bool = th.is_carrying()
		if th.has_method("zabita_catch"):
			th.zabita_catch()
		_chase_thief = null
		mode = Mode.PATROL
		_pause_t = 2.0
		_verdict_hold = 3.0
		_announce("👮 KAPKAÇÇI YAKALANDI! %s" % ("Mal sahibine döndü!" if had else ""), th.global_position - Vector3(0, 0.6, 0), true)
		return
	var dir := diff / maxf(dist, 0.001)
	dir = StallScript.world_steer_all(self, position, dir, dist - 0.2)
	position = StallScript.world_keepout_all(self, position + dir * minf(CHASE_SPEED * dt, dist))
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 10.0, 1.0))
	_spd = CHASE_SPEED


func _tick_chase(dt: float) -> void:
	_chase_timeout -= dt
	var world := get_parent()
	var pg := world.get_node_or_null("Players") if world else null
	var target := pg.get_node_or_null(str(chase_peer_id)) as Node3D if pg else null
	if target == null or _chase_timeout <= 0.0:
		mode = Mode.PATROL
		chase_peer_id = 0
		_set_bubble("👮 Denetim devam ediyor...")
		if bubble:
			bubble.modulate = Color(0.58, 0.85, 1.0)
		return
	var diff := Vector3(target.global_position.x - position.x, 0.0, target.global_position.z - position.z)
	var dist := diff.length()
	if dist < 2.2:
		# Saldırgan yakalandı! Önce yüz yüze tutanak yazma animasyonu, sonra ceza + nesneye el koyma!
		var yaw := atan2(diff.x, diff.z) if dist > 0.05 else _body_yaw
		_body_yaw = yaw
		if Net.online():
			rpc_start_ticket.rpc(target.global_position, chase_weapon, chase_fine, chase_reason)
		else:
			rpc_start_ticket(target.global_position, chase_weapon, chase_fine, chase_reason)
		return
	var dir := diff / dist
	var run_spd := CHASE_SPEED + (0.55 if dist > 8.0 else 0.0)
	dir = StallScript.world_steer_all(self, position, dir, dist - 0.2)
	position = StallScript.world_keepout_all(self, position + dir * minf(run_spd * dt, dist))
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 10.0, 1.0))
	_spd = run_spd


@rpc("authority", "call_local", "reliable")
func rpc_start_ticket(target_pos: Vector3, weapon: String, fine: int, reason: String) -> void:
	mode = Mode.TICKET
	chase_weapon = weapon
	chase_fine = fine
	chase_reason = reason
	_ticket_t = 0.0
	_ticket_delivered = false
	_ticket_target_pos = target_pos
	_spd = 0.0
	_whistle_t = 0.0
	_verdict_hold = 3.5
	_set_bubble("✍️ TUTANAK YAZILIYOR... HİÇ KIPIRDAMA!")
	if bubble:
		bubble.modulate = Color(1.0, 0.78, 0.25)
	Sfx.play_3d("ticket_write", global_position + Vector3(0, 1.25, 0), self, -0.5, 1.0, 30.0)


func _tick_ticket(dt: float) -> void:
	_ticket_t += dt
	var world := get_parent()
	var pg := world.get_node_or_null("Players") if world else null
	var target := pg.get_node_or_null(str(chase_peer_id)) as Node3D if pg else null
	if target:
		_ticket_target_pos = target.global_position
		var diff := Vector3(target.global_position.x - position.x, 0.0, target.global_position.z - position.z)
		var dist := diff.length()
		if dist > 0.1:
			_body_yaw = lerp_angle(_body_yaw, atan2(diff.x, diff.z), minf(dt * 10.0, 1.0))
		# Suçlu tutanak bitmeden uzağa kaçarsa tekrar kovalamacaya geç (uzaktan telepatik ceza kesme!)
		if not _ticket_delivered and dist > 4.6:
			mode = Mode.CHASE
			_ticket_t = 0.0
			_set_bubble("🚨 KAÇMA! DUR!")
			if bubble:
				bubble.modulate = Color(1.0, 0.35, 0.28)
			return
		# Suçlu yazarken hafifçe uzaklaşırsa zabıta adım atıp takip eder
		if dist > 2.6 and dist <= 4.6:
			var dir := StallScript.world_steer_all(self, position, diff / dist, dist - 0.2)
			position = StallScript.world_keepout_all(self, position + dir * minf(WALK_SPEED * 1.25 * dt, dist - 2.1))
			_spd = WALK_SPEED * 1.25
		else:
			_spd = 0.0
	else:
		_spd = 0.0

	if not _ticket_delivered and _ticket_t >= TICKET_WRITE_SEC:
		_ticket_delivered = true
		var taken := ""
		if target:
			target.apply_fine(chase_fine, chase_reason)
			if target.has_method("confiscate_item_synced"):
				if target.has_method("has_inventory_item") and target.has_inventory_item(chase_weapon):
					target.confiscate_item_synced(chase_weapon)
					taken = chase_weapon
				else:
					var eq := str(target.equipped_item_id()) if target.has_method("equipped_item_id") else ""
					if eq in CONFISCATE_FALLBACK:
						target.confiscate_item_synced(eq)
						taken = eq
					else:
						for w_id: String in CONFISCATE_FALLBACK:
							if target.has_method("has_inventory_item") and target.has_inventory_item(w_id):
								target.confiscate_item_synced(w_id)
								taken = w_id
								break
		var item_txt := (" & %s EL KONULDU!" % str(WEAPON_LABELS.get(taken, "EŞYAYA"))) if taken != "" else "!"
		var msg := "🚨 CEZA KESİLDİ! -%d TL%s" % [chase_fine, item_txt]
		if Net.online():
			rpc_ticket_deliver.rpc(_ticket_target_pos, msg)
		else:
			rpc_ticket_deliver(_ticket_target_pos, msg)

	if _ticket_t >= TICKET_TOTAL_SEC:
		if Net.online():
			rpc_end_ticket.rpc()
		else:
			rpc_end_ticket()


@rpc("authority", "call_local", "reliable")
func rpc_ticket_deliver(target_pos: Vector3, msg: String) -> void:
	_ticket_delivered = true
	_verdict_hold = 3.2
	_set_bubble(msg)
	if bubble:
		bubble.modulate = Color(1.0, 0.32, 0.24)
	Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, 0.5, 1.10, 40.0)
	var world := get_parent()
	if world:
		var from_p := global_position + Vector3(0, 1.05, 0) + Vector3(sin(_body_yaw), 0.0, cos(_body_yaw)) * 0.42
		VFX.spawn_ticket_slip(world, from_p, target_pos + Vector3(0, 1.15, 0))
	var fx_pos := target_pos + Vector3(0, 1.85, 0)
	VFX.burst_mood(self, fx_pos, false)
	VFX.spawn_floating_text(self, fx_pos, msg, Color(1.0, 0.34, 0.24), 46)


@rpc("authority", "call_local", "reliable")
func rpc_end_ticket() -> void:
	mode = Mode.PATROL
	chase_peer_id = 0
	_ticket_t = 0.0
	_ticket_delivered = false
	_pause_t = 0.75


func _tick_patrol(dt: float) -> void:
	if _pause_t > 0.0:
		_pause_t -= dt
		_spd = 0.0
		return
	var diff := Vector3(_exit_pos.x - position.x, 0.0, _exit_pos.z - position.z)
	var dist := diff.length()
	if dist < 1.3:
		queue_free()
		return
	var dir := diff / dist
	dir = StallScript.world_steer_all(self, position, dir, dist - 0.2)
	position = StallScript.world_keepout_all(self, position + dir * minf(WALK_SPEED * dt, dist))
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
		if absf(position.z - st.global_position.z) < 2.2 and global_position.distance_to(st.global_position) < 7.8:
			_checked_stalls[oid] = true
			var owner := pg.get_node_or_null(str(oid))
			if owner == null:
				continue
			var look: Vector3 = st.global_position - global_position
			_body_yaw = atan2(look.x, look.z)
			_pause_t = 2.0
			if int(owner.get("drunk_level") if owner.get("drunk_level") != null else 0) >= 2 or bool(owner.get("beer_fainted")):
				owner.apply_fine(FINE_DRUNK, "Kamu Düzenini Bozma Cezası")
				_announce("🚨 SARHOŞ ESNAF! -%d TL" % FINE_DRUNK, st.global_position, false)
				return
			var gouge: Dictionary = st.find_price_gouging(all_stalls, ev)
			if not gouge.is_empty():
				owner.apply_fine(FINE_GOUGE, "Fahiş Fiyat Cezası (%d TL)" % int(gouge["price"]))
				_announce("🚨 FAHİŞ FİYAT! -%d TL" % FINE_GOUGE, st.global_position, false)
				return
			for node in get_tree().get_nodes_in_group("thrown_crates"):
				if is_instance_valid(node) and not bool(node.get_meta("fined", false)) and int(node.get_meta("owner_id", -1)) == oid:
					if (node as Node3D).global_position.distance_to(st.global_position) < 8.5:
						node.set_meta("fined", true)
						owner.apply_fine(FINE_LITTER, "Sokağa Kasa Atma Cezası")
						node.queue_free()
						_announce("🚨 SOKAK KİRLİLİĞİ! -%d TL" % FINE_LITTER, st.global_position, false)
						return
			if st.total_stock() >= 3:
				# Satış sayılmayan ödül (yeni imzada is_sale=false; kombo/satış sayacını etkilemez)
				if owner.get_method_argument_count("award_money") >= 4:
					owner.award_money(CLEAN_REWARD, 0, false, false)
				else:
					owner.award_money(0, CLEAN_REWARD, false)
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
	_verdict_hold = 3.0
	_whistle_t = 0.0 if good else 0.9
	if bubble:
		bubble.text = msg
		bubble.modulate = Color(0.52, 1.0, 0.58) if good else Color(1.0, 0.35, 0.28)
	var fx_pos := stall_pos + Vector3(0, 1.75, 0)
	if good:
		Sfx.play_3d("happy", fx_pos, self, -2.0)
		VFX.burst_mood(self, fx_pos, true)
		VFX.spawn_floating_text(self, fx_pos, msg, Color(0.45, 1.0, 0.55), 42)
	else:
		_patrol_ticket_t = 1.45
		Sfx.play_3d("ticket_write", global_position + Vector3(0, 1.3, 0), self, -2.0, 1.05, 26.0)
		Sfx.play_3d("whistle", global_position + Vector3(0, 1.4, 0), self, 0.0, 1.08, 38.0)
		var tw_slip := create_tween()
		tw_slip.tween_interval(0.75)
		tw_slip.tween_callback(func():
			var w := get_parent()
			if w and is_inside_tree():
				var from_p := global_position + Vector3(0, 1.05, 0) + Vector3(sin(_body_yaw), 0.0, cos(_body_yaw)) * 0.42
				VFX.spawn_ticket_slip(w, from_p, stall_pos + Vector3(0, 1.1, 0)))
		VFX.burst_mood(self, fx_pos, false)
		VFX.spawn_floating_text(self, fx_pos, msg, Color(1.0, 0.32, 0.26), 44)


@rpc("authority", "unreliable_ordered")
func rpc_sync(p: Vector3, yaw: float, s: float, txt: String, m := -1) -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	if m >= 0 and m != mode:
		mode = m
		if bubble:
			bubble.modulate = Color(1.0, 0.35, 0.28) if mode in [Mode.CHASE, Mode.CHASE_THIEF] else (Color(1.0, 0.78, 0.25) if mode == Mode.TICKET else Color(0.58, 0.85, 1.0))
	if _bubble_text != txt:
		_bubble_text = txt
		if bubble:
			bubble.text = txt


func _animate_walk(dt: float) -> void:
	if _whistle_t > 0.0:
		_whistle_t = maxf(_whistle_t - dt, 0.0)
	if _patrol_ticket_t > 0.0:
		_patrol_ticket_t = maxf(_patrol_ticket_t - dt, 0.0)
	var writing := mode == Mode.TICKET or _patrol_ticket_t > 0.0
	if _pen:
		_pen.visible = writing
	if _whistle:
		_whistle.visible = not writing
	var kw := clampf(_spd / 2.8, 0.0, 1.6)
	var stride := 0.28 * minf(kw, 1.35)
	var lift := 0.11 * minf(kw, 1.35)
	if _spd > 0.08:
		_phase = wrapf(_phase + dt * (_spd / 0.28) * 0.94, 0.0, TAU)
	var f := minf(dt * 14.0, 1.0)
	for side: float in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = _phase + (0.0 if side < 0 else PI)
		var fp: Vector3 = rest[fn] + Vector3(0, maxf(0.0, sin(c)) * lift, -cos(c) * stride)
		parts[fn].position = parts[fn].position.lerp(fp, f)
		parts[fn].rotation = parts[fn].rotation.lerp(Vector3(-sin(c) * 0.48 * minf(kw, 1.2), 0, 0), f)
		var hp: Vector3 = rest[hn] + Vector3(0, maxf(0.0, cos(c)) * 0.05 * kw, cos(c) * 0.26 * minf(kw, 1.3))
		var hrot := Vector3(-cos(c) * 0.55 * minf(kw, 1.3), 0, 0)
		if writing:
			var wt := _ticket_t if mode == Mode.TICKET else (1.45 - _patrol_ticket_t)
			var delivering := mode == Mode.TICKET and wt >= TICKET_WRITE_SEC
			if not delivering:
				# Aşama 1: Sol el panoyu göğüs hizasına kaldırır, sağ el kalemle hızlı hızlı tutanak yazar!
				if hn == "HandL":
					hp = Vector3(0.14, 0.72, 0.36)
					hrot = Vector3(-0.32, -0.42, 0.12)
				else:
					var scrib := sin(wt * 26.0)
					var line_y := fmod(wt * 0.32, 0.09)
					hp = Vector3(0.02 + scrib * 0.055, 0.78 - line_y + cos(wt * 52.0) * 0.015, 0.38)
					hrot = Vector3(-0.62 + scrib * 0.14, 0.42, -0.22)
			else:
				# Aşama 2: Makbuzu suçluya doğru fırlatır / zarar verdiği eşyaya el koyma hamlesi!
				var du := clampf((wt - TICKET_WRITE_SEC) / maxf(TICKET_TOTAL_SEC - TICKET_WRITE_SEC, 0.1), 0.0, 1.0)
				if hn == "HandL":
					hp = Vector3(0.30, 0.62, 0.22)
					hrot = Vector3(-0.18, -0.12, 0.05)
				else:
					hp = Vector3(-0.08, 0.84 + sin(du * PI) * 0.11, 0.54)
					hrot = Vector3(-1.12, 0.0, sin(du * PI * 4.0) * 0.24)
		elif hn == "HandR" and _whistle_t > 0.0:
			hp = Vector3(-0.08, 0.98, 0.3) # düdüğü ağzına götürür
		parts[hn].position = parts[hn].position.lerp(hp, f)
		parts[hn].rotation = parts[hn].rotation.lerp(hrot, f)
	var bp: Vector3 = rest["Body"] + Vector3(0, absf(sin(_phase)) * 0.04 * minf(kw, 1.2), 0)
	parts["Body"].position = parts["Body"].position.lerp(bp, f)
	head.position = head.position.lerp(rest["Head"] + Vector3(0, (parts["Body"].position.y - rest["Body"].y) * 1.1, 0), f)
	var target_head_x := 0.0
	if writing:
		var wt2 := _ticket_t if mode == Mode.TICKET else (1.45 - _patrol_ticket_t)
		target_head_x = (0.24 + sin(wt2 * 7.5) * 0.06) if not (mode == Mode.TICKET and wt2 >= TICKET_WRITE_SEC) else -0.05
	head.rotation.x = lerpf(head.rotation.x, target_head_x, f)
