extends Node3D
## Toptancı Ford Transit ("GARDAŞLAR SEBZE MEYVE"): Kuzey Kapısından havalı korna çalarak pazara girer,
## tekerlekleri dönerek orta meydana park eder, dörtlülerini yakıp arkasından her çeşitten bir kasa (farklı fiyat / indirimli) satar,
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
# Tek kasa kaynağı toptancı: daha uzun durur, daha çabuk döner
const PARK_DURATION := 80.0
# Oyun başına TEK ziyaret: sabah, oyun başladıktan bu kadar sn sonra gelir
const ARRIVE_DELAY := 45.0
## Ürün emojileri (HUD, dükkan, ipuçları)
const ITEM_EMOJI := {
	"domates": "🍅", "elma": "🍎", "sogan": "🧅", "portakal": "🍊", "salatalik": "🥒", "biber": "🌶️",
	"patlican": "🍆", "muz": "🍌", "karpuz": "🍉", "cilek": "🍓", "limon": "🍋",
}
const CRATE_COLORS := [
	Color(0.88, 0.18, 0.16), Color(0.16, 0.62, 0.26), Color(0.94, 0.72, 0.12),
	Color(0.96, 0.48, 0.08), Color(0.10, 0.46, 0.88), Color(0.18, 0.56, 0.30),
	Color(0.44, 0.18, 0.62), Color(0.96, 0.82, 0.14), Color(0.16, 0.5, 0.22),
	Color(0.86, 0.2, 0.3), Color(0.12, 0.4, 0.78),
]
# Kasa yerleşimi: temel ürünler kamyonun iki yanında (3+3), özel ürünler arka kapağın önünde (5'li yay).
const RACK_LAYOUT := {
	"domates": Vector3(-1.58, 0.0, -0.55), "elma": Vector3(-1.58, 0.0, -1.5), "sogan": Vector3(-1.58, 0.0, -2.45),
	"portakal": Vector3(1.58, 0.0, -0.55), "salatalik": Vector3(1.58, 0.0, -1.5), "biber": Vector3(1.58, 0.0, -2.45),
	"patlican": Vector3(-1.64, 0.0, -3.6), "muz": Vector3(-0.82, 0.0, -3.72), "karpuz": Vector3(0.0, 0.0, -3.78),
	"cilek": Vector3(0.82, 0.0, -3.72), "limon": Vector3(1.64, 0.0, -3.6),
}

var state: int = State.AWAY
var state_timer := ARRIVE_DELAY
var _used := false # ziyaret bitti, bir daha gelmez (sadece host)
var stock := {} # item_id -> [adet, fiyat] (host yetkili, herkese senkron)
var _honked_arrive := false
var _honked_warn := false
var _sync_t := 0.0
var _net_pos := Vector3(0, 0, ENTER_Z)
var _wheel_rot := 0.0
var _blink_t := 0.0
var _horn_cd := 0.0
var _last_horn_idx := -1

## Şoförün seslendirilmiş repliklerinden (VoxCPM2, kamyoncu sesi) her an için 3 çeşit.
const VOICE_LINES := {
	"geldi": [preload("res://audio/voices/toptanci/geldi_1.ogg"), preload("res://audio/voices/toptanci/geldi_2.ogg"),
		preload("res://audio/voices/toptanci/geldi_3.ogg")],
	"uyari": [preload("res://audio/voices/toptanci/uyari_1.ogg"), preload("res://audio/voices/toptanci/uyari_2.ogg"),
		preload("res://audio/voices/toptanci/uyari_3.ogg")],
	"kalkiyor": [preload("res://audio/voices/toptanci/kalkiyor_1.ogg"),
		preload("res://audio/voices/toptanci/kalkiyor_2.ogg"), preload("res://audio/voices/toptanci/kalkiyor_3.ogg")],
}
var _voice_audio: AudioStreamPlayer3D
var _last_voice := {}

const HORN_CALLOUTS: Array[String] = [
	"📣 FİİİUUUV! ISLIK KORNA — TOPTANCI GELDİ!",
	"📣 DÜÜÜT! SALYANGOZ KORNA — TOPTANCI GELDİ!",
	"📣 BOOOONK! HAVALI KORNA — TOPTANCI GELDİ!",
	"📣 DAAA-DAAA! İKİLİ HAVALI KORNA!",
	"📣 DA-DA-DA-DAAA! ARAP KORNA — TOPTANCI GELDİ!",
]

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
var _horn_audio: AudioStreamPlayer3D
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
	_horn_audio = AudioStreamPlayer3D.new()
	_horn_audio.bus = Sfx.BUS_SFX
	_horn_audio.position = Vector3(0, 2.05, 2.35)
	_horn_audio.unit_size = 7.0
	_horn_audio.max_distance = 58.0
	_horn_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_horn_audio.volume_db = 1.5
	add_child(_horn_audio)
	_voice_audio = AudioStreamPlayer3D.new()
	_voice_audio.bus = Sfx.BUS_SFX
	_voice_audio.position = Vector3(0.55, 1.75, 1.9)  # şoför camı
	_voice_audio.unit_size = 6.5
	_voice_audio.max_distance = 48.0
	_voice_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_audio.volume_db = -2.5
	add_child(_voice_audio)
	if DisplayServer.get_name() != "headless":
		_engine_audio.play()
	visible = false
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
	_sign_lbl.position = Vector3(0, 2.95, 0.25)
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
	sh.size = Vector3(2.20, 2.18, 5.96)
	cs.shape = sh
	cs.position = Vector3(0, 1.15, 0.05)
	_solid_body.add_child(cs)
	add_child(_solid_body)


## Park halindeyken kamyonun arkasından ve yanlarından çıkan 7 çeşit plastik hal kasası rafı.
func _build_supply_rack() -> void:
	_rack_root = Node3D.new()
	add_child(_rack_root)
	_crate_areas.clear()
	_crate_labels.clear()

	# Katalogdaki her ürün için bir kasa; düzende tanımlı değilse en arka sıraya eklenir.
	var extra := 0
	for idx in Produce.ITEM_ORDER.size():
		var item_id: String = Produce.ITEM_ORDER[idx]
		var pos: Vector3 = RACK_LAYOUT.get(item_id, Vector3(-1.6 + float(extra) * 0.8, 0.0, -4.7))
		if not RACK_LAYOUT.has(item_id):
			extra += 1
		var info: Dictionary = Produce.ITEMS[item_id]
		var c_col: Color = CRATE_COLORS[idx % CRATE_COLORS.size()]
		var spot := Node3D.new()
		spot.position = pos
		# Arka sıra kamyona doğru yelpaze gibi hafif açılı
		spot.rotation.y = pos.x * 0.12 if pos.z < -3.0 else 0.0
		_rack_root.add_child(spot)
		# Renkli plastik hal kasası (içi dolu, tepeden taşan ürün yığını)
		LP.add(spot, LP.box(Vector3(0.62, 0.28, 0.52)), Vector3(0, 0.15, 0), c_col, Vector3.ZERO, 0.52)
		LP.add(spot, LP.box(Vector3(0.66, 0.05, 0.56)), Vector3(0, 0.29, 0), c_col.darkened(0.22), Vector3.ZERO, 0.5)
		LP.add(spot, LP.box(Vector3(0.22, 0.05, 0.02)), Vector3(0, 0.19, 0.265), c_col.darkened(0.45))
		Produce.build_crate_fill(spot, item_id, Vector3(0, 0.31, 0), 0.54, 0.44, 0.84, 2, idx)
		var lbl := Label3D.new()
		lbl.text = "%s\n%d TL" % [info["name"], int(info["crate_cost"])]
		lbl.position = Vector3(0, 0.72 if (idx % 2 == 0 or pos.z > -3.0) else 0.98, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 22
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
		area.set_meta("hl_size", Vector3(0.68, 0.44, 0.58))
		area.position = Vector3(0, 0.32, 0)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.68, 0.72, 0.6)
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
		var iid := str(a.get_meta("item_id"))
		var n := stock_left(iid)
		a.collision_layer = 4 if (on and n > 0) else 0
		var spot := a.get_parent() as Node3D
		if spot:
			spot.visible = n > 0
		var lbl: Label3D = _crate_labels.get(iid)
		if lbl and n > 0:
			lbl.text = "%s ×%d
%d TL" % [ITEM_EMOJI.get(iid, "📦"), n, price_of(iid)]
			var dp := discount_of(iid)
			if dp > 0:
				lbl.text += "\n%%%d indirim" % dp
				lbl.modulate = Color(0.55, 1.0, 0.5)
			else:
				lbl.modulate = Color(1.0, 0.96, 0.82)


func is_parked() -> bool:
	return state == State.PARKED


func is_present() -> bool:
	return state != State.AWAY


## Eski API (fiyat/fırsat artık kamyonun kendi sınırlı stokundan gelir).
func update_prices(_prices: Dictionary, _deal: String, _event_item: String) -> void:
	pass


func stock_left(item_id: String) -> int:
	return int((stock.get(item_id, [0, 0]) as Array)[0])


func price_of(item_id: String) -> int:
	return int((stock.get(item_id, [0, 0]) as Array)[1])


func discount_of(item_id: String) -> int:
	var a: Array = stock.get(item_id, [0, 0, 0])
	return int(a[2]) if a.size() > 2 else 0


func total_left() -> int:
	var n := 0
	for k in stock:
		n += int((stock[k] as Array)[0])
	return n


## Geliş öncesi geri sayım (sn); 0 = yok / ziyaret bitti.
func countdown_left() -> float:
	return maxf(state_timer, 0.0) if state == State.AWAY else 0.0


## Host: bir kasa düş (ilk gelen alır). Başarılıysa true.
func take_stock(item_id: String) -> bool:
	if stock_left(item_id) <= 0:
		return false
	var d := stock.duplicate(true)
	d[item_id][0] = int(d[item_id][0]) - 1
	if Net.online():
		rpc_sync_stock.rpc(d)
	else:
		rpc_sync_stock(d)
	return true


## Host: her ürün çeşidinden TEK kasa; fiyatlar farklı (ucuz / pahalı), birkaçı "%X indirim" etiketli.
## stock: item_id -> [adet, fiyat, indirim_yüzdesi]
func _gen_stock() -> void:
	var ids: Array = Produce.ITEM_ORDER.duplicate()
	var disc: Array = ids.duplicate()
	disc.shuffle()
	var disc_pct := {}
	for k in 4:
		disc_pct[disc[k]] = [20, 30, 40].pick_random()
	var d := {}
	for iid: String in ids:
		var info: Dictionary = Produce.ITEMS[iid]
		# Temel ürünler ucuz (başlangıç parasıyla alınır), özel ürünler pahalı
		var mult := randf_range(0.45, 0.75) if int(info.get("tier", 0)) == 0 else randf_range(0.95, 1.3)
		var pct: int = int(disc_pct.get(iid, 0))
		d[iid] = [1, maxi(12, roundi(float(info["crate_cost"]) * mult * (1.0 - float(pct) / 100.0))), pct]
	if Net.online():
		rpc_sync_stock.rpc(d)
	else:
		rpc_sync_stock(d)


@rpc("authority", "call_local", "reliable")
func rpc_sync_stock(d: Dictionary) -> void:
	stock = d.duplicate(true)
	_set_rack_active(state == State.PARKED)


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
				_say_voice("geldi", 0.3)
				arrived.emit()
		State.PARKED:
			state_timer -= dt
			if not _honked_warn and state_timer <= 8.0:
				_honked_warn = true
				_fire_horn(true)
				_say_voice("uyari", 1.1)
				departing.emit()
			if state_timer <= 0.0:
				state = State.DEPARTING
				_set_rack_active(false)
				_fire_horn(true)
				_say_voice("kalkiyor", 1.1)
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
				state_timer = 0.0
				_used = true
				if Net.online():
					rpc_state_changed.rpc(state, state_timer)
				else:
					rpc_state_changed(state, state_timer)
		State.AWAY:
			if _used:
				return
			state_timer -= dt
			if state_timer <= 0.0:
				position = Vector3(0.0, 0.0, ENTER_Z)
				_gen_stock()
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
			_sign_lbl.text = "🚚 Toptancı geliyor!"
			_sign_lbl.modulate = Color(1.0, 0.88, 0.32)
		State.PARKED:
			_sign_lbl.text = "🚚 %d kasa  •  ⏱ %d" % [total_left(), ceili(maxf(state_timer, 0.0))]
			_sign_lbl.modulate = Color(0.55, 1.0, 0.58) if state_timer > 10.0 else Color(1.0, 0.52, 0.32)
		State.DEPARTING:
			_sign_lbl.text = "📣 Gidiyor!"
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


func _pick_random_horn_idx() -> int:
	var n := Sfx.TRUCK_HORN_STREAMS.size()
	if n <= 1:
		return 0
	var idx := randi() % n
	if idx == _last_horn_idx:
		idx = (idx + 1 + randi() % (n - 1)) % n
	_last_horn_idx = idx
	return idx


func _fire_horn(short_blast: bool) -> void:
	_horn_cd = 2.4
	var horn_idx := _pick_random_horn_idx()
	if Net.online():
		rpc_play_horn.rpc(short_blast, horn_idx)
	else:
		rpc_play_horn(short_blast, horn_idx)


@rpc("authority", "call_local", "reliable")
func rpc_play_horn(short_blast: bool, horn_idx: int = -1) -> void:
	_horn_cd = 2.4
	var idx := horn_idx if horn_idx >= 0 else _pick_random_horn_idx()
	var horn_pos := global_position + Vector3(0, 2.2, 2.2)
	if DisplayServer.get_name() != "headless" and _horn_audio:
		_horn_audio.stop()
		_horn_audio.stream = Sfx.get_truck_horn_stream(idx)
		_horn_audio.pitch_scale = randf_range(0.985, 1.015)
		_horn_audio.play()
	VFX.spawn_sound_ring(self, horn_pos, 6.2, Color(1.0, 0.78, 0.22))
	var callout := "📣 DÜT DÜÜÜT! TOPTANCI KALKIYOR!" if short_blast else HORN_CALLOUTS[posmod(idx, HORN_CALLOUTS.size())]
	VFX.spawn_floating_text(self, horn_pos + Vector3(0, 0.85, 0), callout, Color(1.0, 0.88, 0.28), 46)


## Host seçer (art arda aynı replik gelmez), herkes aynı repliği kamyonun şoför camından duyar.
func _say_voice(kind: String, delay: float) -> void:
	var n: int = VOICE_LINES[kind].size()
	var idx := randi() % n
	if n > 1 and idx == int(_last_voice.get(kind, -1)):
		idx = (idx + 1 + randi() % (n - 1)) % n
	_last_voice[kind] = idx
	if Net.online():
		rpc_say_voice.rpc(kind, idx, delay)
	else:
		rpc_say_voice(kind, idx, delay)


@rpc("authority", "call_local", "reliable")
func rpc_say_voice(kind: String, idx: int, delay: float) -> void:
	if DisplayServer.get_name() == "headless" or _voice_audio == null or not VOICE_LINES.has(kind):
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(_voice_audio) or not _voice_audio.is_inside_tree():
			return
	var lines: Array = VOICE_LINES[kind]
	_voice_audio.stop()
	_voice_audio.stream = lines[posmod(idx, lines.size())]
	_voice_audio.play()


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
	return {"pos": position, "state": state, "timer": state_timer, "stock": stock.duplicate(true)}


func apply_snapshot(d: Dictionary) -> void:
	position = d.get("pos", Vector3(0, 0, ENTER_Z))
	_net_pos = position
	state = int(d.get("state", State.ENTERING))
	state_timer = float(d.get("timer", 0.0))
	stock = (d.get("stock", {}) as Dictionary).duplicate(true)
	_used = state == State.AWAY and state_timer <= 0.0
	_set_rack_active(state == State.PARKED)
