extends Node3D
## Toptancı Ford Transit ("GARDAŞLAR SEBZE MEYVE"): Kuzey Kapısından havalı korna çalarak pazara girer,
## tekerlekleri dönerek orta meydana park eder, dörtlülerini yakıp arkasından 7 çeşit taze kasa tedarik eder,
## süresi dolunca korna çalıp Güney Kapısından çıkar ve yeni fiyatlarla geri gelir!

const TRUCK_MODEL := preload("res://models/ford_transit/ford_transit_complete.glb")
const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const VFX := preload("res://vfx.gd")

signal arrived()
signal departing()
signal restock_needed()

enum State { AWAY, ENTERING, PARKED, DEPARTING }

const PARK_Z := -0.6
const ENTER_Z := -28.0
const EXIT_Z := 29.0
const DRIVE_SPEED := 5.6
const PARK_DURATION := 56.0
const AWAY_DURATION := 28.0
const CRATE_COLORS := [
	Color(0.88, 0.18, 0.16), Color(0.16, 0.62, 0.26), Color(0.94, 0.72, 0.12),
	Color(0.96, 0.48, 0.08), Color(0.44, 0.18, 0.62), Color(0.96, 0.82, 0.14), Color(0.10, 0.46, 0.88),
]

var state: int = State.ENTERING
var state_timer := 0.0
var _honked_arrive := false
var _honked_warn := false
var _sync_t := 0.0
var _net_pos := Vector3(0, 0, ENTER_Z)
var _wheel_rot := 0.0
var _blink_t := 0.0
var _horn_cd := 0.0

var _model_root: Node3D
var _wheels: Array[Node3D] = []
var _amber_mat: StandardMaterial3D
var _headlight_mat: StandardMaterial3D
var _solid_body: StaticBody3D
var _rack_root: Node3D
var _crate_areas: Array[Area3D] = []
var _crate_labels: Dictionary = {} # item_id -> Label3D
var _sign_lbl: Label3D
var _engine_audio: AudioStreamPlayer3D
var _prices: Dictionary = {}
var _deal_item := "domates"
var _event_item := ""


func _ready() -> void:
	name = "Wholesaler"
	position = Vector3(0.0, 0.0, ENTER_Z)
	_net_pos = position
	_build_truck()
	_build_supply_rack()
	_build_cab_horn_areas()
	_engine_audio = Sfx.make_truck_engine_player()
	_engine_audio.position = Vector3(0, 1.0, 2.0)
	add_child(_engine_audio)
	if DisplayServer.get_name() != "headless":
		_engine_audio.play()
	_set_rack_active(false)


func _build_truck() -> void:
	_model_root = TRUCK_MODEL.instantiate()
	add_child(_model_root)
	# 4 tekerleği yakala (sürüşte dönerler)
	for wn in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := _model_root.find_child(wn, true, false) as Node3D
		if w:
			_wheels.append(w)
	# Dörtlü sinyal (AmberIndicator) ve far (HeadlightGlass) malzemelerini kopyala
	var body := _model_root.find_child("FordTransitBody", true, false) as MeshInstance3D
	if body and body.mesh:
		for i in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			if m.resource_name == "AmberIndicator":
				_amber_mat = m.duplicate() as StandardMaterial3D
				body.set_surface_override_material(i, _amber_mat)
			elif m.resource_name == "HeadlightGlass":
				_headlight_mat = m.duplicate() as StandardMaterial3D
				_headlight_mat.emission_enabled = true
				_headlight_mat.emission = Color(1.0, 0.94, 0.72)
				_headlight_mat.emission_energy_multiplier = 1.6
				body.set_surface_override_material(i, _headlight_mat)
	# Far ışığı + tezgah üstü durum tabelası
	var hl := SpotLight3D.new()
	hl.position = Vector3(0, 1.1, 3.15)
	hl.rotation_degrees = Vector3(-12, 180, 0)
	hl.light_color = Color(1.0, 0.94, 0.78)
	hl.light_energy = 2.6
	hl.spot_range = 16.0
	hl.spot_angle = 42.0
	add_child(hl)

	_sign_lbl = Label3D.new()
	_sign_lbl.text = "🚚 GARDAŞLAR TOPTANCI GELİYOR!"
	_sign_lbl.position = Vector3(0, 3.72, -0.4)
	_sign_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign_lbl.font_size = 42
	_sign_lbl.outline_size = 11
	_sign_lbl.modulate = Color(1.0, 0.9, 0.35)
	_sign_lbl.outline_modulate = Color(0.1, 0.06, 0.02)
	_sign_lbl.no_depth_test = true
	add_child(_sign_lbl)

	# Katı çarpıştırıcı (park halindeyken oyuncular kamyondan geçmez)
	_solid_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.25, 2.55, 5.9)
	cs.shape = sh
	cs.position = Vector3(0, 1.35, 0.05)
	_solid_body.add_child(cs)
	add_child(_solid_body)


## Park halindeyken kamyonun arkasından ve yanlarından çıkan 7 çeşit plastik hal kasası rafı.
func _build_supply_rack() -> void:
	_rack_root = Node3D.new()
	add_child(_rack_root)
	_crate_areas.clear()
	_crate_labels.clear()

	# 4 temel ürün sol/sağ arka köşelerde, 3 özel ürün (patlıcan, muz, karpuz) tam arka kapağın önünde!
	var layout := [
		["domates", Vector3(-1.55, 0.0, -1.0)],
		["elma", Vector3(-1.55, 0.0, -2.05)],
		["sogan", Vector3(1.55, 0.0, -1.0)],
		["portakal", Vector3(1.55, 0.0, -2.05)],
		["patlican", Vector3(-0.95, 0.0, -3.55)],
		["muz", Vector3(0.0, 0.0, -3.55)],
		["karpuz", Vector3(0.95, 0.0, -3.55)],
	]
	for idx in layout.size():
		var item_id: String = layout[idx][0]
		var pos: Vector3 = layout[idx][1]
		var info: Dictionary = Produce.ITEMS[item_id]
		var c_col: Color = CRATE_COLORS[idx % CRATE_COLORS.size()]
		var spot := Node3D.new()
		spot.position = pos
		_rack_root.add_child(spot)
		# Renkli plastik hal kasası
		LP.add(spot, LP.box(Vector3(0.66, 0.30, 0.56)), Vector3(0, 0.16, 0), c_col, Vector3.ZERO, 0.52)
		LP.add(spot, LP.box(Vector3(0.70, 0.05, 0.60)), Vector3(0, 0.31, 0), c_col.darkened(0.22), Vector3.ZERO, 0.5)
		for j in 6:
			var ox := -0.16 + float(j % 3) * 0.16
			var oz := -0.10 + float(int(j / 3)) * 0.20
			Produce.build_mesh(spot, item_id, Vector3(ox, 0.36, oz), 0.072)
		var lbl := Label3D.new()
		lbl.text = "%s\n%d TL" % [info["name"], int(info["crate_cost"])]
		lbl.position = Vector3(0, 0.68, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 24
		lbl.outline_size = 7
		lbl.modulate = Color(1.0, 0.96, 0.82)
		spot.add_child(lbl)
		_crate_labels[item_id] = lbl

		var area := Area3D.new()
		area.name = "TransitCrate_%s" % item_id
		area.collision_layer = 4
		area.collision_mask = 0
		area.set_meta("kind", "wholesale_crate")
		area.set_meta("item_id", item_id)
		area.set_meta("hl_size", Vector3(0.72, 0.44, 0.62))
		area.position = Vector3(0, 0.32, 0)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.76, 0.72, 0.68)
		cs.shape = sh
		area.add_child(cs)
		spot.add_child(area)
		_crate_areas.append(area)


## Kamyon kabin kapılarında şoföre selam / havalı korna çaldırma alanı!
func _build_cab_horn_areas() -> void:
	for sx in [-1.3, 1.3]:
		var area := Area3D.new()
		area.name = "CabHorn_%d" % int(signf(sx))
		area.collision_layer = 4
		area.collision_mask = 0
		area.set_meta("kind", "truck_horn")
		area.set_meta("hl_size", Vector3(0.6, 1.0, 1.2))
		area.position = Vector3(sx, 1.2, 1.8)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.8, 1.2, 1.4)
		cs.shape = sh
		area.add_child(cs)
		add_child(area)


func _set_rack_active(on: bool) -> void:
	if _rack_root:
		_rack_root.visible = on
	for a in _crate_areas:
		a.collision_layer = 4 if on else 0


func is_parked() -> bool:
	return state == State.PARKED


func is_present() -> bool:
	return state != State.AWAY


func update_prices(prices: Dictionary, deal: String, event_item: String) -> void:
	_prices = prices.duplicate()
	_deal_item = deal
	_event_item = event_item
	for item_id in _crate_labels:
		var lbl: Label3D = _crate_labels[item_id]
		var nm: String = Produce.ITEMS[item_id]["name"]
		var base := int(prices.get(item_id, Produce.ITEMS[item_id]["crate_cost"]))
		var cost := maxi(16, roundi(float(base) * (0.78 if item_id != deal else 0.90)))
		if item_id == deal:
			lbl.text = "🔥 FIRSAT!\n%s\n%d TL" % [nm, cost]
			lbl.modulate = Color(0.45, 1.0, 0.52)
		elif item_id == event_item:
			lbl.text = "⭐ TALEP!\n%s\n%d TL" % [nm, cost]
			lbl.modulate = Color(1.0, 0.85, 0.25)
		else:
			lbl.text = "%s\n%d TL" % [nm, cost]
			lbl.modulate = Color(1.0, 0.96, 0.82)


func _physics_process(dt: float) -> void:
	if _horn_cd > 0.0:
		_horn_cd = maxf(_horn_cd - dt, 0.0)
	var prev_z := position.z
	var is_host := (not Net.online()) or multiplayer.is_server()
	if is_host:
		_tick_host(dt)
		_sync_t += dt
		if Net.online() and _sync_t >= 0.08:
			_sync_t = 0.0
			rpc_sync_truck.rpc(position, state, state_timer)
	else:
		position = position.lerp(_net_pos, minf(dt * 12.0, 1.0))

	# Tekerlekleri ilerleme mesafesine göre fiziksel döndür (+Z yönü -> +X rotasyon)
	var dz := position.z - prev_z
	if absf(dz) > 0.0005:
		_wheel_rot = wrapf(_wheel_rot + dz / 0.37, 0.0, TAU)
		for w in _wheels:
			w.rotation.x = _wheel_rot

	# Park halindeyken dörtlü flaşörler yanıp sönsün!
	if _amber_mat:
		if state == State.PARKED:
			_blink_t += dt
			var on := fmod(_blink_t, 0.9) < 0.45
			_amber_mat.emission_enabled = on
			_amber_mat.emission = Color(1.0, 0.55, 0.05)
			_amber_mat.emission_energy_multiplier = 3.2 if on else 0.0
		else:
			_amber_mat.emission_enabled = false

	# Motor sesi ve görünürlük
	visible = state != State.AWAY
	if _solid_body:
		_solid_body.collision_layer = 1 if state != State.AWAY else 0
	if _engine_audio:
		if state == State.AWAY:
			_engine_audio.volume_db = -80.0
		elif state == State.PARKED:
			_engine_audio.volume_db = -17.0
			_engine_audio.pitch_scale = 0.88
		else:
			_engine_audio.volume_db = -10.5
			_engine_audio.pitch_scale = 1.18

	_update_sign()


func _tick_host(dt: float) -> void:
	match state:
		State.ENTERING:
			var dist := PARK_Z - position.z
			var spd := clampf(dist * 0.85, 1.4, DRIVE_SPEED)
			position.z += minf(spd * dt, maxf(dist, 0.0))
			if not _honked_arrive and position.z >= -16.5:
				_honked_arrive = true
				_fire_horn(false)
			if position.z >= PARK_Z - 0.05:
				position.z = PARK_Z
				state = State.PARKED
				state_timer = PARK_DURATION
				_honked_warn = false
				_set_rack_active(true)
				if Net.online():
					rpc_state_changed.rpc(state, state_timer)
				else:
					rpc_state_changed(state, state_timer)
				arrived.emit()
		State.PARKED:
			state_timer -= dt
			if not _honked_warn and state_timer <= 8.0:
				_honked_warn = true
				_fire_horn(true)
				departing.emit()
			if state_timer <= 0.0:
				state = State.DEPARTING
				_set_rack_active(false)
				_fire_horn(true)
				if Net.online():
					rpc_state_changed.rpc(state, 0.0)
				else:
					rpc_state_changed(state, 0.0)
		State.DEPARTING:
			var dist_out := EXIT_Z - position.z
			var accel := clampf((position.z - PARK_Z) * 0.7 + 1.6, 1.6, DRIVE_SPEED + 1.2)
			position.z += minf(accel * dt, maxf(dist_out, 0.0))
			if position.z >= EXIT_Z - 0.1:
				state = State.AWAY
				state_timer = AWAY_DURATION
				if Net.online():
					rpc_state_changed.rpc(state, state_timer)
				else:
					rpc_state_changed(state, state_timer)
		State.AWAY:
			state_timer -= dt
			if state_timer <= 0.0:
				position = Vector3(0.0, 0.0, ENTER_Z)
				state = State.ENTERING
				_honked_arrive = false
				restock_needed.emit()
				if Net.online():
					rpc_state_changed.rpc(state, 0.0)
				else:
					rpc_state_changed(state, 0.0)


func _update_sign() -> void:
	if _sign_lbl == null:
		return
	match state:
		State.ENTERING:
			_sign_lbl.text = "🚚 GARDAŞLAR TOPTANCI GELİYOR!"
			_sign_lbl.modulate = Color(1.0, 0.88, 0.32)
		State.PARKED:
			var deal_nm := str(Produce.ITEMS.get(_deal_item, {"name": "Domates"})["name"]).to_upper()
			_sign_lbl.text = "🚚 GARDAŞLAR HAL  •  🔥 FIRSAT: %s  •  %d sn" % [deal_nm, ceili(maxf(state_timer, 0.0))]
			_sign_lbl.modulate = Color(0.55, 1.0, 0.58) if state_timer > 10.0 else Color(1.0, 0.52, 0.32)
		State.DEPARTING:
			_sign_lbl.text = "📣 TOPTANCI KALKIYOR! GÖRÜŞÜRÜZ!"
			_sign_lbl.modulate = Color(1.0, 0.68, 0.32)
		State.AWAY:
			_sign_lbl.text = ""


func request_honk() -> void:
	if _horn_cd > 0.0:
		return
	if Net.online():
		rpc_request_honk.rpc_id(1)
	else:
		_fire_horn(false)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_honk() -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if _horn_cd <= 0.0:
		_fire_horn(false)


func _fire_horn(short_blast: bool) -> void:
	_horn_cd = 2.0
	if Net.online():
		rpc_play_horn.rpc(short_blast)
	else:
		rpc_play_horn(short_blast)


@rpc("authority", "call_local", "reliable")
func rpc_play_horn(short_blast: bool) -> void:
	_horn_cd = 2.0
	var horn_pos := global_position + Vector3(0, 2.2, 2.2)
	Sfx.play_3d("air_horn_short" if short_blast else "air_horn", horn_pos, self, 2.5, 1.0, 52.0)
	VFX.spawn_sound_ring(self, horn_pos, 6.2, Color(1.0, 0.78, 0.22))
	VFX.spawn_floating_text(self, horn_pos + Vector3(0, 0.85, 0),
		"📣 DÜT DÜÜÜT!" if short_blast else "📣 DAAA-DA-DA-DAAA! TOPTANCI GELDİ!", Color(1.0, 0.88, 0.28), 46)


@rpc("authority", "call_local", "reliable")
func rpc_state_changed(new_state: int, t: float) -> void:
	state = new_state
	state_timer = t
	_set_rack_active(state == State.PARKED)
	if state == State.PARKED:
		VFX.burst_dust(self, global_position + Vector3(0, 0.25, -3.5), Color(0.88, 0.86, 0.80), 8)


@rpc("authority", "unreliable_ordered")
func rpc_sync_truck(p: Vector3, st: int, t: float) -> void:
	_net_pos = p
	if state != st:
		state = st
		_set_rack_active(state == State.PARKED)
	state_timer = t


func export_snapshot() -> Dictionary:
	return {"pos": position, "state": state, "timer": state_timer}


func apply_snapshot(d: Dictionary) -> void:
	position = d.get("pos", Vector3(0, 0, ENTER_Z))
	_net_pos = position
	state = int(d.get("state", State.ENTERING))
	state_timer = float(d.get("timer", 0.0))
	_set_rack_active(state == State.PARKED)
