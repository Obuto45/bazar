extends CharacterBody3D
## Oyuncu: kişisel envanter (1-6; meyve kasaları ASLA envantere girmez), sigara/puro yanma + duman,
## el megafonu (+dB bağırma), meyve bıçağı saldırısı, Arabesk radyo, azaltılmış sarsıntı ve koşma efekti.

const MODEL := preload("res://models/char_pazarci.glb")
const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const StallScript := preload("res://stall.gd")
const Items := preload("res://items.gd")
const VFX := preload("res://vfx.gd")

signal money_earned(amount: int, total: int, tip: int)
signal money_spent(amount: int, total: int, reason: String)
signal open_shop()
signal inventory_changed()
signal combo_changed(n: int)

const STARTING_MONEY := 120
const INV_SIZE := 8
const MAX_BUFF := 60.0
const WALK := 3.6
const RUN := 7.0
const JUMP := 5.2
const GRAVITY := 14.0
const SENS := 0.0025
const HEAD_LIMIT := 1.3
const EYE_Y := 1.16
const EYE_FWD := 0.12
const COYOTE_SEC := 0.12
const JUMP_BUFFER_SEC := 0.14
const FALL_GRAVITY_MULT := 1.35
# Satış kombosu: 6 sn içinde art arda satışlar; 3. satıştan itibaren adım başı +%10 (en çok +%50)
const COMBO_WINDOW := 6.0
const COMBO_START := 3
const COMBO_STEP := 0.10
const COMBO_MAX_BONUS := 0.50
const SPRAY_RANGE := 3.0
const INTERACT_REACH := 3.7
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
# Bağırma eşikleri (Megafon eldeyken +12 dB / 1.85x!)
const SHOUT_DB_MIN := -36.0
const SHOUT_DB_MAX := -10.0
const SHOUT_KEY_POWER := 0.72
const SHOUT_ON := 0.45
const SHOUT_CALLS := ["Taze %s! %d TL!", "Gel gel! %s %d lira!", "Seç al! %s sadece %d TL!", "Bal gibi %s! %d TL!"]
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
var _fp_item_anchor: Node3D
var _fp_item_visual: Node3D
var _tp_item_anchor: Node3D
var _tp_item_visual: Node3D
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
var combo := 0
var best_combo_today := 0
var _combo_t := 0.0
static var _coin_mesh: Mesh
static var _coin_mat: Material

# Kişisel Envanter (1..8 — meyve kasaları ASLA buraya girmez!)
var inventory: Array[Dictionary] = [] # {"id": String, "uses": int, "puffs": int} veya {}
var active_slot := -1 # -1 = boş el, 0..7 = seçili envanter yuvası
var _remote_item_id := ""
var _remote_burn := 0.0
var _use_anim := 0.0
var _action_kind := ""
var _action_item := ""
var _action_t := 0.0
var _action_dur := 0.0
var _action_stage := 0
var _tp_action := ""
var _tp_t := 0.0
var _tp_dur := 0.0
var _equip_t := 0.0
var _sway_off := Vector2.ZERO
var _fp_base_pos := Vector3(0.24, -0.20, -0.38)
var _fp_base_rot := Vector3.ZERO
var _cam_fov_mod := 0.0
var _cam_pitch_mod := 0.0
var _mega_raise := 0.0
var _radio_freq_idx := 0
var _knife_cd := 0.0
var _puff_cd := 0.0
var _sec_cd := 0.0
var _mega_burst := 0.0
var _stun_t := 0.0
var _spray_cd := 0.0
var _catch_cd := 0.0
var _coyote := 0.0
var _jump_buf := 0.0
var _strafe_roll := 0.0
var _shape: ShapeCast3D
var _hand_radio_playing := false
var _hand_radio_audio: AudioStreamPlayer3D
var _radio_note_cd := 0.0

# Elde fiziksel taşınan meyve kasası (envanterden tamamen bağımsız!)
var held_crate := false
var held_item := ""
var held_count := 0

var shout_power := 0.0
var sprint_k := 0.0 # 0..1 koşma efekti yoğunluğu (HUD hız çizgileri için)
var _shout_lbl: Label3D
var _shout_ring_cd := 0.0
var _was_shouting := false
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
var tea_buff := 0.0 # çay: bağırma +%25 (yudum başı +15sn, en çok 60sn)
var simit_buff := 0.0 # simit: %15 hızlı yürüyüş (ısırık başı +18sn, en çok 60sn)
var smoke_buff := 0.0 # sigara/puro: %25 hızlı yürüyüş/koşu (nefes başı +12sn / puro +16sn, en çok 30sn)
var air := false
var phase := 0.0
var land_t := 0.0
var bob_k := 0.0
var net_pos := Vector3.ZERO


func face_yaw() -> float:
	return look_yaw + PI


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * 0.55, 0.0, 0.7) # azaltılmış yumuşak sarsıntı


func _ready() -> void:
	var id := color_id if color_id >= 0 else name.to_int()
	position = spawn_pos
	net_pos = spawn_pos
	body_yaw = face_yaw()
	_init_inventory()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32; cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	add_child(col)
	_build_model(HAIRS[(id / 8 + id) % HAIRS.size()], SHIRTS[id % SHIRTS.size()])
	_hand_radio_audio = Sfx.make_radio_player()
	_hand_radio_audio.position = Vector3(0, 1.0, 0)
	add_child(_hand_radio_audio)

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
		_ray.target_position = Vector3(0, 0, -INTERACT_REACH)
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = false
		_ray.collision_mask = 4
		cam.add_child(_ray)
		# Affedici etkileşim: ışın ıskalarsa ince bir küre taraması en yakın hedefi yakalar (zil, hırsız, müşteri)
		_shape = ShapeCast3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.17
		_shape.shape = sph
		_shape.target_position = Vector3(0, 0, -(INTERACT_REACH - 0.25))
		_shape.collide_with_areas = true
		_shape.collide_with_bodies = false
		_shape.collision_mask = 4
		_shape.max_results = 6
		cam.add_child(_shape)
		_fp_crate_anchor = Node3D.new()
		_fp_crate_anchor.position = Vector3(0.0, -0.4, -0.62)
		_fp_crate_anchor.rotation_degrees = Vector3(20.0, 0.0, 0.0)
		cam.add_child(_fp_crate_anchor)
		_fp_item_anchor = Node3D.new()
		_fp_item_anchor.position = Vector3(0.24, -0.20, -0.38)
		cam.add_child(_fp_item_anchor)
		_build_highlight_box()
		_setup_voice_capture()
		_refresh_equipped_visual()
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


func _init_inventory() -> void:
	inventory.clear()
	for i in INV_SIZE:
		inventory.append({})
	# Her pazarcı başlangıçta 1 paket (5 dal) Sigara ve 1 bardak sıcak İnce Belli Çay ile başlar!
	inventory[0] = {"id": "sigara", "uses": 5, "puffs": 0}
	inventory[1] = {"id": "cay", "uses": 1, "puffs": 0}
	active_slot = -1


func equipped_item_id() -> String:
	if held_crate:
		return ""
	if not is_multiplayer_authority():
		return _remote_item_id
	if active_slot >= 0 and active_slot < inventory.size():
		return str(inventory[active_slot].get("id", ""))
	return ""


func is_holding_item(item_id: String) -> bool:
	return equipped_item_id() == item_id


func has_inventory_item(item_id: String) -> bool:
	for sl in inventory:
		if str(sl.get("id", "")) == item_id and int(sl.get("uses", 0)) > 0:
			return true
	return false


func has_prestige_aura() -> bool:
	return is_holding_item("puro")


## Efektif bağırma gücü: normal mikrofon/B + El Megafonu (1.85x) + Tezgah Hoparlörü (1.35x).
func get_effective_shout() -> float:
	var sp := maxf(shout_power, 1.15 if _mega_burst > 0.0 else 0.0)
	if is_holding_item("megafon"):
		sp *= 1.85
	var st := _find_stall(_my_peer_id())
	if st and st.has_upgrade("megaphone"):
		sp *= 1.35
	return sp


func select_slot(idx: int) -> void:
	var prev_slot := active_slot
	if idx < 0 or idx >= INV_SIZE:
		active_slot = -1
	elif active_slot == idx:
		active_slot = -1 # aynı tuşa basınca cebine koy
	elif not inventory[idx].is_empty():
		active_slot = idx
		Sfx.play("ui_click", -10.0)
	else:
		active_slot = -1
	if active_slot != prev_slot:
		_action_kind = ""
		_action_t = 0.0
		_action_dur = 0.0
		_action_stage = 0
		_equip_t = 1.0 if active_slot >= 0 else 0.0
	if not is_holding_item("radyo") and _hand_radio_playing:
		_set_hand_radio_synced(false)
	_sync_equipped_to_peers()
	_refresh_equipped_visual()
	inventory_changed.emit()


func _sync_equipped_to_peers() -> void:
	var iid := equipped_item_id()
	var br := _current_burn_ratio()
	if Net.online():
		rpc_sync_equipped.rpc(iid, br)


@rpc("authority", "reliable")
func rpc_sync_equipped(item_id: String, burn_r: float) -> void:
	_remote_item_id = item_id
	_remote_burn = burn_r
	_refresh_equipped_visual()


func _current_burn_ratio() -> float:
	if not is_multiplayer_authority():
		return _remote_burn
	if active_slot >= 0 and active_slot < inventory.size() and not inventory[active_slot].is_empty():
		var iid := str(inventory[active_slot].get("id", ""))
		if Items.CATALOG.has(iid):
			var max_p: int = int(Items.CATALOG[iid]["puffs_per_use"])
			return float(int(inventory[active_slot].get("puffs", 0))) / float(maxi(max_p, 1))
	return 0.0


func _refresh_equipped_visual() -> void:
	if _fp_item_visual:
		_fp_item_visual.queue_free()
		_fp_item_visual = null
	if _tp_item_visual:
		_tp_item_visual.queue_free()
		_tp_item_visual = null
	var iid := equipped_item_id()
	if iid == "" or not Items.CATALOG.has(iid):
		return
	var br := _current_burn_ratio()
	if is_multiplayer_authority() and _fp_item_anchor:
		_fp_item_visual = Items.build_item_model(iid, br)
		_fp_item_anchor.add_child(_fp_item_visual)
		# Eşyaya özel doğal 1. şahıs tutuş açısı
		match iid:
			"sigara", "puro":
				_fp_base_pos = Vector3(0.22, -0.17, -0.34)
				_fp_base_rot = Vector3(12, 24, -10)
			"cay":
				_fp_base_pos = Vector3(0.24, -0.165, -0.37)
				_fp_base_rot = Vector3(4, -10, 0)
			"simit":
				_fp_base_pos = Vector3(0.23, -0.20, -0.37)
				_fp_base_rot = Vector3(10, -24, 12)
			"megafon":
				_fp_base_pos = Vector3(0.26, -0.20, -0.44)
				_fp_base_rot = Vector3(6, 12, 0)
			"bicak":
				_fp_base_pos = Vector3(0.28, -0.22, -0.42)
				_fp_base_rot = Vector3(14, 10, -14)
			"radyo":
				_fp_base_pos = Vector3(0.26, -0.26, -0.48)
				_fp_base_rot = Vector3(8, -22, 0)
			"spray":
				_fp_base_pos = Vector3(0.24, -0.24, -0.42)
				_fp_base_rot = Vector3(6, 10, -4)
			_:
				_fp_base_pos = Vector3(0.24, -0.20, -0.38)
				_fp_base_rot = Vector3.ZERO
		_fp_item_anchor.position = _fp_base_pos
		_fp_item_anchor.rotation_degrees = _fp_base_rot
	elif _tp_item_anchor:
		_tp_item_visual = Items.build_item_model(iid, br)
		_tp_item_anchor.add_child(_tp_item_visual)


func add_inventory_item_synced(item_id: String) -> void:
	if Net.online():
		rpc_add_inventory_item.rpc(item_id)
	else:
		rpc_add_inventory_item(item_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_add_inventory_item(item_id: String) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	if not Items.CATALOG.has(item_id):
		return
	var info: Dictionary = Items.CATALOG[item_id]
	var add_uses: int = int(info["uses"])
	# Aynı tüketilebilir eşya varsa adetini ekle (sigara/puro/çay/simit/fısfıs)
	for i in inventory.size():
		if str(inventory[i].get("id", "")) == item_id:
			if bool(info["consumable"]):
				inventory[i]["uses"] = int(inventory[i]["uses"]) + add_uses
			if is_multiplayer_authority():
				if item_id in ["cay", "simit"] and not held_crate:
					active_slot = i
					_equip_t = 1.0
					_sync_equipped_to_peers()
					_refresh_equipped_visual()
				inventory_changed.emit()
			return
	# Boş yuvaya koy
	for i in inventory.size():
		if inventory[i].is_empty():
			inventory[i] = {"id": item_id, "uses": add_uses, "puffs": 0}
			if is_multiplayer_authority():
				active_slot = i
				_equip_t = 1.0
				_sync_equipped_to_peers()
				_refresh_equipped_visual()
				inventory_changed.emit()
			return


func confiscate_item_synced(item_id: String) -> void:
	if Net.online():
		rpc_confiscate_item.rpc(item_id)
	else:
		rpc_confiscate_item(item_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_confiscate_item(item_id: String) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	for i in inventory.size():
		if str(inventory[i].get("id", "")) == item_id:
			inventory[i] = {}
			if active_slot == i:
				active_slot = -1
	if is_multiplayer_authority():
		_sync_equipped_to_peers()
		_refresh_equipped_visual()
		inventory_changed.emit()


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
	var edge_x := LP.box(Vector3(1.0, t, t))
	var edge_y := LP.box(Vector3(t, 1.0, t))
	var edge_z := LP.box(Vector3(t, t, 1.0))
	for a: float in [-0.5, 0.5]:
		for b: float in [-0.5, 0.5]:
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
	_tp_item_anchor = Node3D.new()
	_tp_item_anchor.position = Vector3(0.0, 0.04, 0.14)
	_tp_item_anchor.rotation_degrees = Vector3(0, 180, 0)
	(parts["HandR"] as Node3D).add_child(_tp_item_anchor)
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
	if e.is_action_pressed("open_shop") or e.is_action_pressed("upgrade_shop"):
		open_shop.emit()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_place_held = false
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode >= KEY_1 and e.physical_keycode < KEY_1 + INV_SIZE:
			select_slot(e.physical_keycode - KEY_1)
			return
		elif e.physical_keycode == KEY_0:
			select_slot(-1)
			return
	if e is InputEventMouseMotion:
		look_yaw = wrapf(look_yaw - e.relative.x * SENS, -PI, PI)
		look_pitch = clampf(look_pitch - e.relative.y * SENS, -1.45, 1.35)
		_sway_off.x = clampf(_sway_off.x - e.relative.x * 0.00055, -0.045, 0.045)
		_sway_off.y = clampf(_sway_off.y + e.relative.y * 0.00045, -0.035, 0.035)
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
			if held_crate:
				_place_held = e.pressed
				if e.pressed:
					_try_place_once()
					var st := _find_stall(_my_peer_id())
					_place_cd = 0.16 if (st and st.has_upgrade("big_crate")) else 0.24
			elif e.pressed:
				_use_active_item()
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and not held_crate:
			_use_secondary_item()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_do_wheel(1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_do_wheel(-1)


## Tekerlek: tezgah radyosuna bakıyorsan şarkı, rafa bakıyorsan fiyat, elde radyo varsa şarkı değiştirir.
func _do_wheel(dir: int) -> void:
	var area := _ray_target()
	var kind := str(area.get_meta("kind", "")) if area else ""
	if kind == "stall_radio":
		var owner_id: int = int(area.get_meta("stall_owner", -1))
		var st := _find_stall(owner_id)
		if st and owner_id == _my_peer_id() and st.has_radio:
			_radio_toast(st.step_radio_synced(dir))
			return
	if kind == "slot":
		_do_adjust_price(dir)
		return
	if equipped_item_id() == "radyo" and _sec_cd <= 0.0:
		_sec_cd = 0.18
		_step_hand_radio(dir)


func _step_hand_radio(dir: int) -> void:
	if _hand_radio_audio == null:
		return
	var idx := Sfx.radio_step_idx(_hand_radio_audio, dir)
	if Net.online():
		rpc_hand_radio_track.rpc(idx)
	else:
		rpc_hand_radio_track(idx)
	_radio_toast(Sfx.radio_title(idx))
	_start_action("radio_tune", "radyo", 0.40)


@rpc("authority", "call_local", "reliable")
func rpc_hand_radio_track(idx: int) -> void:
	Sfx.radio_set(_hand_radio_audio, idx)


func _radio_toast(title: String) -> void:
	Sfx.play("ui_click", -10.0, 1.1)
	var main := _find_main()
	if main and main.has_method("show_toast"):
		main.show_toast("📻 " + title, Color(1.0, 0.82, 0.5))


## Kişisel envanter eşyasını kullan (Sol Tık: çek/üfle, çay yudumla, simit ısır, megafon, bıçak, radyo, fısfıs).
func _use_active_item() -> void:
	var iid := equipped_item_id()
	if iid == "":
		return
	match iid:
		"sigara", "puro":
			if _puff_cd > 0.0 or _action_kind != "":
				return
			_puff_cd = 1.95
			_start_action("smoke_drag", iid, 1.85)

		"cay":
			if _puff_cd > 0.0 or _action_kind != "":
				return
			_puff_cd = 1.50
			_start_action("tea_sip", iid, 1.45)

		"simit":
			if _puff_cd > 0.0 or _action_kind != "":
				return
			_puff_cd = 1.20
			_start_action("simit_bite", iid, 1.15)

		"megafon":
			if _action_kind == "mega_blast":
				return
			_mega_burst = 2.4
			_start_action("mega_blast", iid, 0.72)
			var pos := global_position + Vector3(0, 1.3, 0)
			_trigger_item_fx_synced("mega", iid, pos, Vector3.UP)

		"bicak":
			if _knife_cd > 0.0:
				return
			_knife_cd = 0.60
			_start_action("knife_slash", iid, 0.48)
			var pos := global_position + Vector3(0, 1.1, 0)
			var fwd := -cam.global_transform.basis.z if cam else Vector3(0, 0, -1)
			_trigger_item_fx_synced("knife", iid, pos, fwd)
			_check_knife_hit(fwd)

		"radyo":
			_set_hand_radio_synced(not _hand_radio_playing)
			Sfx.play("ui_click", -8.0, 1.15 if _hand_radio_playing else 0.85)
			_start_action("radio_toggle", iid, 0.34)

		"spray":
			if _spray_cd > 0.0:
				return
			var st := _find_stall(_my_peer_id())
			var nozzle := _get_smoke_tip_world()
			var fwd := -cam.global_transform.basis.z if cam else Vector3(0, 0, -1)
			if st == null or _flat_dist(global_position, st.global_position) > SPRAY_RANGE:
				_spray_cd = 0.6
				VFX.spawn_floating_text(_find_world(), nozzle + fwd * 0.6 + Vector3(0, 0.15, 0), "💦 Tezgahına yaklaş!", Color(0.6, 0.9, 1.0), 26)
				Sfx.play("ui_click", -10.0, 0.7)
				return
			_spray_cd = 0.85
			_start_action("spray_pump", iid, 0.56)
			var sl := inventory[active_slot]
			sl["uses"] = int(sl.get("uses", 1)) - 1
			if int(sl["uses"]) <= 0:
				inventory[active_slot] = {}
				active_slot = -1
			var to_st: Vector3 = (st.global_position + Vector3(0, 0.75, 0)) - nozzle
			var dir := (fwd * 0.5 + to_st.normalized() * 0.5).normalized()
			_trigger_item_fx_synced("spray", iid, nozzle, dir)
			st.request_spray(_my_peer_id())
			add_trauma(0.05)
			_sync_equipped_to_peers()
			_refresh_equipped_visual()
			inventory_changed.emit()


## İkincil eşya hareketi (Sağ Tık: kül silk, çay karıştır, simit kokla, bıçak çevir, megafon sireni, şişe çalkala, radyo frekansı).
func _use_secondary_item() -> void:
	var iid := equipped_item_id()
	if iid == "" or _sec_cd > 0.0 or _action_kind != "":
		return
	var tip_pos := _get_smoke_tip_world()
	var fwd := -cam.global_transform.basis.z if cam else Vector3(0, 0, -1)
	match iid:
		"sigara", "puro":
			_sec_cd = 0.55
			_start_action("ash_flick", iid, 0.42)
			_trigger_item_fx_synced("ash_flick", iid, tip_pos, fwd)
		"cay":
			_sec_cd = 0.98
			_start_action("tea_stir", iid, 0.92)
			_trigger_item_fx_synced("tea_stir", iid, tip_pos, Vector3.UP)
		"simit":
			_sec_cd = 0.85
			_start_action("simit_sniff", iid, 0.78)
			_trigger_item_fx_synced("simit_sniff", iid, tip_pos, fwd)
		"bicak":
			_sec_cd = 0.65
			_start_action("knife_spin", iid, 0.56)
			_trigger_item_fx_synced("knife_spin", iid, global_position + Vector3(0, 1.15, 0), fwd)
		"megafon":
			_sec_cd = 1.05
			_mega_burst = maxf(_mega_burst, 1.25)
			_start_action("mega_chirp", iid, 0.48)
			_trigger_item_fx_synced("mega_chirp", iid, global_position + Vector3(0, 1.3, 0), fwd)
		"spray":
			_sec_cd = 0.62
			_start_action("spray_shake", iid, 0.54)
			_trigger_item_fx_synced("spray_shake", iid, tip_pos, fwd)
		"radyo":
			_sec_cd = 0.48
			_radio_freq_idx = (_radio_freq_idx + 1) % 4
			if _hand_radio_audio:
				var idx := Sfx.radio_step_idx(_hand_radio_audio, 1) # frekans değişince sıradaki şarkı
				if Net.online():
					rpc_hand_radio_track.rpc(idx)
				else:
					rpc_hand_radio_track(idx)
				_radio_toast(Sfx.radio_title(idx))
			if _fp_item_visual:
				var dial := _fp_item_visual.find_child("Dial", true, false) as MeshInstance3D
				if dial and dial.material_override is StandardMaterial3D:
					var cols: Array[Color] = [Color(1.0, 0.72, 0.22), Color(0.35, 0.95, 0.65), Color(0.45, 0.80, 1.0), Color(1.0, 0.45, 0.55)]
					(dial.material_override as StandardMaterial3D).emission = cols[_radio_freq_idx]
			_start_action("radio_tune", iid, 0.40)
			_trigger_item_fx_synced("radio_tune", iid, global_position + Vector3(0, 1.1, 0), fwd)


func _start_action(kind: String, iid: String, dur: float) -> void:
	_action_kind = kind
	_action_item = iid
	_action_t = 0.0
	_action_dur = dur
	_action_stage = 0
	_use_anim = 1.0


func _get_mouth_world() -> Vector3:
	if is_multiplayer_authority() and cam:
		var fwd := -cam.global_transform.basis.z
		var up := cam.global_transform.basis.y
		return cam.global_position + fwd * 0.24 - up * 0.09
	if head:
		return head.global_position + (-head.global_transform.basis.z) * 0.20 + Vector3(0, -0.05, 0)
	return global_position + Vector3(0, 1.12, 0)


func _finish_consumable_step(iid: String, toast_when_empty: String) -> void:
	if active_slot < 0 or active_slot >= inventory.size():
		return
	var sl := inventory[active_slot]
	if str(sl.get("id", "")) != iid:
		return
	var max_p: int = int(Items.CATALOG[iid]["puffs_per_use"])
	if int(sl.get("puffs", 0)) >= max_p:
		sl["uses"] = int(sl.get("uses", 1)) - 1
		sl["puffs"] = 0
		if int(sl["uses"]) <= 0:
			inventory[active_slot] = {}
			active_slot = -1
			var main := _find_main()
			if toast_when_empty != "" and main and main.has_method("show_toast"):
				main.show_toast(toast_when_empty, Color(1.0, 0.88, 0.52))
	_sync_equipped_to_peers()
	_refresh_equipped_visual()
	inventory_changed.emit()


## Çok aşamalı 1. şahıs eşya aksiyon zaman çizelgesi (çekiş -> üfleme, yudumlama -> seviye düşüşü, ısırık -> kırıntı).
func _tick_item_action(dt: float) -> void:
	if _action_kind == "" or _action_dur <= 0.0:
		return
	_action_t += dt
	var u := clampf(_action_t / _action_dur, 0.0, 1.0)
	var fwd := -cam.global_transform.basis.z if cam else Vector3(0, 0, -1)

	match _action_kind:
		"smoke_drag":
			if _action_stage == 0 and u >= 0.24:
				_action_stage = 1
				var tip_p := _get_smoke_tip_world()
				_trigger_item_fx_synced("smoke_inhale", _action_item, tip_p, fwd)
			elif _action_stage == 1 and u >= 0.56:
				_action_stage = 2
				var mouth_p := _get_mouth_world()
				_trigger_item_fx_synced("smoke_exhale", _action_item, mouth_p, fwd)
				var is_puro := _action_item == "puro"
				smoke_buff = minf(smoke_buff + (16.0 if is_puro else 12.0), 30.0)
				if active_slot >= 0 and active_slot < inventory.size() and str(inventory[active_slot].get("id", "")) == _action_item:
					inventory[active_slot]["puffs"] = int(inventory[active_slot].get("puffs", 0)) + 1
					inventory_changed.emit()

		"tea_sip":
			if _action_stage == 0 and u >= 0.32:
				_action_stage = 1
				var tip_p := _get_smoke_tip_world()
				_trigger_item_fx_synced("tea_sip", _action_item, tip_p, Vector3.UP)
				tea_buff = minf(tea_buff + 15.0, MAX_BUFF)
				if active_slot >= 0 and active_slot < inventory.size() and str(inventory[active_slot].get("id", "")) == "cay":
					inventory[active_slot]["puffs"] = int(inventory[active_slot].get("puffs", 0)) + 1
					inventory_changed.emit()
					# Çay seviyesini bardak içinde anında yumuşakça indir!
					if _fp_item_visual:
						var liq := _fp_item_visual.find_child("TeaLiquid", true, false) as Node3D
						if liq:
							var max_p: int = int(Items.CATALOG["cay"]["puffs_per_use"])
							var cur_p: int = int(inventory[active_slot].get("puffs", 0))
							var target_fill := 0.04 if cur_p >= max_p else clampf(1.0 - (float(cur_p) / float(max_p)) * 0.88, 0.16, 1.0)
							liq.create_tween().tween_property(liq, "scale:y", target_fill, 0.34).set_trans(Tween.TRANS_SINE)

		"simit_bite":
			if _action_stage == 0 and u >= 0.30:
				_action_stage = 1
				var mouth_p := _get_mouth_world() + fwd * 0.08
				_trigger_item_fx_synced("simit_bite", _action_item, mouth_p, fwd)
				simit_buff = minf(simit_buff + 18.0, MAX_BUFF)
				add_trauma(0.06)
				if active_slot >= 0 and active_slot < inventory.size() and str(inventory[active_slot].get("id", "")) == "simit":
					inventory[active_slot]["puffs"] = int(inventory[active_slot].get("puffs", 0)) + 1
					inventory_changed.emit()
					var max_p: int = int(Items.CATALOG["simit"]["puffs_per_use"])
					if int(inventory[active_slot].get("puffs", 0)) < max_p:
						_sync_equipped_to_peers()
						_refresh_equipped_visual()

	if _action_t >= _action_dur:
		var done_kind := _action_kind
		var done_item := _action_item
		_action_kind = ""
		_action_t = 0.0
		_action_dur = 0.0
		_action_stage = 0
		match done_kind:
			"smoke_drag":
				var msg := "🪵 Puro bitti, ne keyifti!" if done_item == "puro" else "🚬 Sigara bitti."
				_finish_consumable_step(done_item, msg)
			"tea_sip":
				_finish_consumable_step("cay", "🍵 Ohh mis gibi tavşan kanı çay bitti!")
			"simit_bite":
				_finish_consumable_step("simit", "🥯 Çıtır simit bitti, enerji doldu!")


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_smoke_tip_world() -> Vector3:
	if _fp_item_visual:
		var tip := _fp_item_visual.find_child("SmokeTip", true, false) as Node3D
		if tip:
			return tip.global_position
	return (cam.global_position + (-cam.global_transform.basis.z) * 0.42) if cam else (global_position + Vector3(0, 1.15, 0))


func _check_knife_hit(fwd: Vector3) -> void:
	var pg := get_parent()
	var main := _find_main()
	if pg == null or main == null:
		return
	var best_id := -1
	var best_d := 2.6
	for p in pg.get_children():
		if p == self or p.npc:
			continue
		var diff: Vector3 = p.global_position - global_position
		var d := diff.length()
		if d < best_d and Vector3(diff.x, 0, diff.z).normalized().dot(Vector3(fwd.x, 0, fwd.z).normalized()) > 0.32:
			best_d = d
			best_id = p.name.to_int()
	if best_id > 0:
		main.request_knife_attack(best_id)


func _set_hand_radio_synced(on: bool) -> void:
	if Net.online():
		rpc_set_hand_radio.rpc(on)
	else:
		rpc_set_hand_radio(on)


@rpc("authority", "call_local", "reliable")
func rpc_set_hand_radio(on: bool) -> void:
	_hand_radio_playing = on
	if _hand_radio_audio:
		if on and DisplayServer.get_name() != "headless":
			if not _hand_radio_audio.playing:
				_hand_radio_audio.play()
		elif _hand_radio_audio.playing:
			_hand_radio_audio.stop()


func _trigger_item_fx_synced(action: String, iid: String, pos: Vector3, dir: Vector3) -> void:
	if Net.online():
		rpc_item_fx.rpc(action, iid, pos, dir)
	else:
		rpc_item_fx(action, iid, pos, dir)


@rpc("authority", "call_local", "reliable")
func rpc_item_fx(action: String, iid: String, pos: Vector3, dir: Vector3) -> void:
	var w := _find_world()
	match action:
		"smoke":
			var thick := iid == "puro"
			Sfx.play_3d("puff", pos, w, -3.5, 0.92 if thick else 1.05, 14.0)
			VFX.spawn_smoke_puff(w, pos, dir, thick)
			VFX.spawn_ember_sparks(w, pos)
		"smoke_inhale":
			var thick := iid == "puro"
			Sfx.play_3d("smoke_inhale", pos, w, -4.5, 0.90 if thick else 1.04, 12.0)
			VFX.spawn_ember_sparks(w, pos)
			_tp_action = "smoke_inhale"; _tp_t = 0.0; _tp_dur = 0.65
		"smoke_exhale":
			var thick := iid == "puro"
			Sfx.play_3d("smoke_exhale", pos, w, -3.2, 0.88 if thick else 1.04, 14.0)
			VFX.spawn_exhale_cloud(w, pos, dir, thick)
			if thick:
				VFX.spawn_smoke_ring(w, pos, dir)
			_tp_action = "smoke_exhale"; _tp_t = 0.0; _tp_dur = 0.75
		"ash_flick":
			Sfx.play_3d("ash_flick", pos, w, -5.5, 1.0, 10.0)
			VFX.spawn_ash_drop(w, pos)
			_tp_action = "ash_flick"; _tp_t = 0.0; _tp_dur = 0.42
		"tea_sip":
			Sfx.play_3d("tea_sip", pos, w, -3.5, 1.0, 12.0)
			VFX.spawn_tea_steam(w, pos, true)
			_tp_action = "tea_sip"; _tp_t = 0.0; _tp_dur = 1.05
		"tea_stir":
			Sfx.play_3d("tea_stir", pos, w, -4.0, 1.0, 14.0)
			VFX.spawn_tea_steam(w, pos, false)
			_tp_action = "tea_stir"; _tp_t = 0.0; _tp_dur = 0.92
		"simit_bite":
			Sfx.play_3d("bite_crunch", pos, w, -3.0, 1.0, 12.0)
			VFX.spawn_crumbs(w, pos)
			_tp_action = "simit_bite"; _tp_t = 0.0; _tp_dur = 0.85
		"simit_sniff":
			Sfx.play_3d("smoke_inhale", pos, w, -9.0, 1.38, 10.0)
			_tp_action = "simit_sniff"; _tp_t = 0.0; _tp_dur = 0.75
		"mega":
			Sfx.play_3d("megaphone_pop", pos, w, 0.0, 1.0, 36.0)
			VFX.spawn_sound_ring(w, pos, 6.2, Color(1.0, 0.72, 0.18))
			VFX.spawn_floating_text(w, pos + Vector3(0, 0.65, 0), "📢 GEL VATANDAŞ GELL!", Color(1.0, 0.86, 0.25), 46)
			_tp_action = "mega"; _tp_t = 0.0; _tp_dur = 0.72
		"mega_chirp":
			Sfx.play_3d("mega_chirp", pos, w, -1.5, 1.0, 32.0)
			VFX.spawn_sound_ring(w, pos, 4.6, Color(1.0, 0.82, 0.28))
			_tp_action = "mega"; _tp_t = 0.0; _tp_dur = 0.48
		"knife":
			Sfx.play_3d("knife_swing", pos, w, -2.0, 1.0, 16.0)
			_tp_action = "knife_slash"; _tp_t = 0.0; _tp_dur = 0.48
		"knife_spin":
			Sfx.play_3d("knife_spin", pos, w, -3.5, 1.0, 14.0)
			_tp_action = "knife_spin"; _tp_t = 0.0; _tp_dur = 0.56
		"spray":
			Sfx.play_3d("spray", pos, w, -3.0, 1.0, 14.0)
			VFX.spawn_water_mist(w, pos, dir)
			_tp_action = "spray_pump"; _tp_t = 0.0; _tp_dur = 0.55
		"spray_shake":
			Sfx.play_3d("bottle_shake", pos, w, -4.5, 1.0, 12.0)
			_tp_action = "spray_shake"; _tp_t = 0.0; _tp_dur = 0.54
		"radio_tune":
			Sfx.play_3d("radio_tune", pos, w, -5.0, 1.0, 12.0)
			_tp_action = "radio_tune"; _tp_t = 0.0; _tp_dur = 0.40
		"catch":
			Sfx.play_3d("crate_throw", pos, w, -6.0, 1.3, 12.0)


## Su fısfısı buğusu: yarı saydam mavi damlacık konisi, yavaşlayarak genişler ve söner.
static func _spawn_mist(parent: Node, world_pos: Vector3, dir: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.55
	p.amount = 26
	p.lifetime = 0.75
	p.mesh = LP.sphere(0.022, 5, 3)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.direction = dir
	p.spread = 13.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -1.6, 0)
	p.damping_min = 2.0
	p.damping_max = 3.4
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 1.7))
	p.scale_amount_curve = sc
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.98, 1.0, 0.85))
	grad.add_point(0.5, Color(0.62, 0.84, 1.0, 0.45))
	grad.set_color(1, Color(0.6, 0.82, 1.0, 0.0))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)


func apply_knife_hit_synced(knock_dir: Vector3) -> void:
	if Net.online():
		rpc_on_knife_hit.rpc(knock_dir)
	else:
		rpc_on_knife_hit(knock_dir)


@rpc("any_peer", "call_local", "reliable")
func rpc_on_knife_hit(knock_dir: Vector3) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	var w := _find_world()
	Sfx.play_3d("knife_hit", global_position + Vector3(0, 1.1, 0), w, 0.0, 1.0, 26.0)
	VFX.spawn_hit_burst(w, global_position + Vector3(0, 1.1, 0))
	VFX.spawn_floating_text(w, global_position + Vector3(0, 1.85, 0), "💢 SALDIRIYA UĞRADIN!", Color(1.0, 0.28, 0.22), 44)
	if is_multiplayer_authority():
		_stun_t = 1.2
		velocity = knock_dir * 6.5 + Vector3.UP * 2.5
		add_trauma(0.55)
		if held_crate:
			_do_throw_crate()


func _process(dt: float) -> void:
	if npc:
		return
	if _puff_cd > 0.0:
		_puff_cd = maxf(_puff_cd - dt, 0.0)
	if _sec_cd > 0.0:
		_sec_cd = maxf(_sec_cd - dt, 0.0)
	if _knife_cd > 0.0:
		_knife_cd = maxf(_knife_cd - dt, 0.0)
	if _mega_burst > 0.0:
		_mega_burst = maxf(_mega_burst - dt, 0.0)
	if _stun_t > 0.0:
		_stun_t = maxf(_stun_t - dt, 0.0)
	if _spray_cd > 0.0:
		_spray_cd = maxf(_spray_cd - dt, 0.0)
	if _catch_cd > 0.0:
		_catch_cd = maxf(_catch_cd - dt, 0.0)
	if _combo_t > 0.0:
		_combo_t = maxf(_combo_t - dt, 0.0)
		if _combo_t <= 0.0 and combo > 0:
			combo = 0
			combo_changed.emit(0)
	if _tp_action != "":
		_tp_t += dt
		if _tp_t >= _tp_dur:
			_tp_action = ""
			_tp_t = 0.0
			_tp_dur = 0.0

	if is_multiplayer_authority():
		_tick_item_action(dt)

	# Elde çalan Arabesk Radyo notaları
	if _hand_radio_playing:
		_radio_note_cd -= dt
		if _radio_note_cd <= 0.0:
			_radio_note_cd = 1.15
			VFX.spawn_music_note(_find_world(), global_position + Vector3(0, 1.25, 0))

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
	var eff := get_effective_shout()
	var is_sh := eff >= SHOUT_ON
	if is_sh and not _was_shouting and is_holding_item("megafon"):
		Sfx.play_3d("megaphone_pop", global_position + Vector3(0, 1.2, 0), _find_world(), -2.0, 1.0, 28.0)
	_was_shouting = is_sh
	if is_sh and _shout_ring_cd <= 0.0:
		_shout_ring_cd = 0.50 if is_holding_item("megafon") else 0.60
		var has_mega := is_holding_item("megafon")
		var rad := clampf(2.8 + eff * 1.9, 3.0, 6.8)
		var col := Color(1.0, 0.65, 0.14) if has_mega else Color(1.0, 0.90, 0.45)
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
	tea_buff = maxf(tea_buff - dt, 0.0)
	simit_buff = maxf(simit_buff - dt, 0.0)
	smoke_buff = maxf(smoke_buff - dt, 0.0)
	var inp := Vector2.ZERO
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and _stun_t <= 0.0:
		inp = Input.get_vector("left", "right", "fwd", "back")
	var dir := (Basis(Vector3.UP, look_yaw) * Vector3(inp.x, 0, inp.y)).normalized()
	var running := Input.is_action_pressed("run") and inp.y < 0.0 and _stun_t <= 0.0
	# Hız bonusları birikmez, büyüğü geçer: sigara/puro %25, simit %15
	var speed_k := 1.25 if smoke_buff > 0.0 else (1.15 if simit_buff > 0.0 else 1.0)
	var target := dir * (RUN if running else WALK) * speed_k
	var accel := (14.0 if target != Vector3.ZERO else 18.0) if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * dt * WALK)
	velocity.z = move_toward(velocity.z, target.z, accel * dt * WALK)
	var was_air := air
	# Coyote süresi + zıplama tamponu: kenardan düşerken ya da yere değmeden hemen önce basılan zıplama da sayılır
	if is_on_floor():
		_coyote = COYOTE_SEC
	else:
		_coyote = maxf(_coyote - dt, 0.0)
	if captured and _stun_t <= 0.0 and Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER_SEC
	else:
		_jump_buf = maxf(_jump_buf - dt, 0.0)
	if _jump_buf > 0.0 and _coyote > 0.0 and velocity.y <= 0.5:
		velocity.y = JUMP
		_jump_buf = 0.0
		_coyote = 0.0
	elif not is_on_floor():
		# Düşerken biraz daha ağır yerçekimi + erken bırakılan zıplama kısalır: daha tok, kontrollü zıplayış
		var g := GRAVITY * (FALL_GRAVITY_MULT if velocity.y < 0.0 else 1.0)
		if velocity.y > 0.0 and not (captured and Input.is_action_pressed("jump")):
			g *= 1.6
		velocity.y -= g * dt
	var fall_v := -velocity.y
	move_and_slide()
	if global_position.y < -10.0:
		global_position = spawn_pos
		velocity = Vector3.ZERO
	spd = Vector2(velocity.x, velocity.z).length()
	air = not is_on_floor()
	# Koşma efekti yoğunluğu (HUD hız çizgileri ve FOV artışı için)
	var target_sprint := clampf((spd - WALK - 0.35) / (RUN - WALK), 0.0, 1.0) if (running and not air) else 0.0
	sprint_k = lerpf(sprint_k, target_sprint, minf(dt * 9.0, 1.0))
	# Yanal kayışta hafif kamera yatışı
	var side_v := (Basis(Vector3.UP, look_yaw).inverse() * velocity).x
	_strafe_roll = lerpf(_strafe_roll, clampf(-side_v * 0.006, -0.025, 0.025), minf(dt * 8.0, 1.0))
	if was_air and not air:
		var impact := clampf(fall_v / 9.0, 0.35, 1.4)
		land_t = 0.14 * impact
		add_trauma(0.06 + 0.08 * impact)
		Sfx.play("step", -13.0 + impact * 3.0, 0.9 - impact * 0.08)
		VFX.burst_dust(_find_world(), global_position + Vector3(0, 0.08, 0), Color(0.84, 0.80, 0.72), int(3 + impact * 3.0))
	# Bağırma: El Megafonu takılıysa mikrofon dB +12 dB güçlenir!
	var db_boost := 12.0 if is_holding_item("megafon") else 0.0
	var manual_shout := SHOUT_KEY_POWER if (captured and Input.is_action_pressed("shout")) else 0.0
	var mic_shout := 0.0 if mic_muted else \
		clampf(((talk_db + db_boost) - SHOUT_DB_MIN) / (SHOUT_DB_MAX - SHOUT_DB_MIN), 0.0, 1.0) * 1.45
	var burst := 1.05 if _mega_burst > 0.0 else 0.0
	# Çay: senkronlanan shout_power'a uygulanır ki host da görsün
	var tea_k := 1.25 if tea_buff > 0.0 else 1.0
	shout_power = lerpf(shout_power, maxf(maxf(manual_shout, mic_shout), burst) * tea_k, minf(dt * 14.0, 1.0))
	if Net.online():
		sync_state.rpc(global_position, body_yaw, look_yaw, look_pitch, spd, air, shout_power)


## Azaltılmış yumuşak ekran sarsılması + canlı koşma FOV efekti + 1. şahıs eşya animasyonları!
func _camera(dt: float) -> void:
	var kr := clampf((spd - WALK) / (RUN - WALK), 0.0, 1.0)
	bob_k = lerpf(bob_k, 0.0 if air else clampf(spd / WALK, 0.0, 1.0), minf(dt * 8.0, 1.0))
	# Ekran sarsılması ~%65 azaltıldı: kaymak gibi akıcı yürüyüş ve koşu!
	var amp := lerpf(0.010, 0.022, kr) * bob_k
	var bob := Vector3(cos(phase) * amp * 0.45, absf(sin(phase)) * amp - amp * 0.5 - land_t * 0.18, 0)

	var shake_off := Vector3.ZERO
	var shake_roll := 0.0
	if _trauma > 0.0:
		_trauma = maxf(_trauma - dt * 2.4, 0.0)
		var sh := _trauma * _trauma
		_shake_t += dt * 30.0
		shake_off = Vector3(sin(_shake_t * 1.7) * 0.015 * sh, sin(_shake_t * 2.3) * 0.012 * sh, 0.0)
		shake_roll = sin(_shake_t * 1.2) * 0.014 * sh

	var yb := Basis(Vector3.UP, look_yaw)
	cam_root.position = Vector3(0, EYE_Y, 0) + yb * (Vector3(0, 0, -EYE_FWD) + bob + shake_off)
	cam_root.rotation = Vector3(clampf(look_pitch + _cam_pitch_mod, -1.45, 1.35), look_yaw, -cos(phase) * 0.004 * bob_k * (1.0 + kr) + shake_roll + _strafe_roll)
	# Belirgin koşma FOV açılması (78° -> 89°!) + nefes çekme/üfleme mikro odaklanması
	var smoke_fov := 3.5 if smoke_buff > 0.0 else 0.0 # sigara hızı: hafif FOV açılması
	cam.fov = lerpf(cam.fov, 78.0 + sprint_k * 11.5 + smoke_fov + _cam_fov_mod, minf(dt * 7.5, 1.0))

	if _fp_crate_anchor:
		_place_kick = lerpf(_place_kick, 0.0, minf(dt * 14.0, 1.0))
		var sway_x := cos(phase) * 0.010 * bob_k
		var sway_y := absf(sin(phase)) * 0.010 * bob_k
		_fp_crate_anchor.position = Vector3(sway_x, -0.4 - sway_y + _place_kick * 0.04, -0.62 - _place_kick * 0.09)
		_fp_crate_anchor.rotation_degrees = Vector3(20.0 - _place_kick * 16.0, 0.0, -sway_x * 45.0)

	# 1. şahıs profesyonel eşya animasyonları: çekme yayı, fare atalet salınımı, yürüyüş/nefes ve çok aşamalı kullanım!
	_sway_off = _sway_off.lerp(Vector2.ZERO, minf(dt * 11.0, 1.0))
	_equip_t = maxf(_equip_t - dt * 4.2, 0.0)
	var target_fov_mod := 0.0
	var target_pitch_mod := 0.0
	var iid := equipped_item_id()
	var want_mega := 1.0 if (iid == "megafon" and (shout_power >= SHOUT_ON or _mega_burst > 0.0)) else 0.0
	_mega_raise = lerpf(_mega_raise, want_mega, minf(dt * 10.0, 1.0))

	if _fp_item_anchor and _fp_item_visual:
		var now_t := Time.get_ticks_msec() * 0.001
		# Doğal çekme yayı (draw-in), yürüyüş sekiz-çizimi, nefes alma ve koşarken indirme
		var eq_e := _equip_t * _equip_t
		var walk_x := cos(phase) * 0.011 * bob_k
		var walk_y := absf(sin(phase)) * 0.012 * bob_k
		var idle_y := sin(now_t * 2.1) * 0.004 * (1.0 - bob_k * 0.6)
		var sprint_pos := Vector3(0.03, -0.055, 0.03) * sprint_k
		var sprint_rot := Vector3(-12.0, 14.0, -10.0) * sprint_k
		var draw_pos := Vector3(0.02, -0.22, 0.08) * eq_e
		var draw_rot := Vector3(-28.0, 10.0, -14.0) * eq_e
		var sway_pos := Vector3(_sway_off.x, _sway_off.y, 0.0)
		var sway_rot := Vector3(_sway_off.y * 160.0, _sway_off.x * 220.0, -_sway_off.x * 130.0)

		_fp_item_anchor.position = _fp_base_pos + Vector3(walk_x, -walk_y + idle_y, 0.0) + sprint_pos + draw_pos + sway_pos
		_fp_item_anchor.rotation_degrees = _fp_base_rot + sprint_rot + draw_rot + sway_rot

		var a_pos := Vector3.ZERO
		var a_rot := Vector3.ZERO
		var ember_boost := 0.0
		var u := clampf(_action_t / _action_dur, 0.0, 1.0) if (_action_kind != "" and _action_dur > 0.0) else 0.0

		match _action_kind:
			"smoke_drag":
				# 3 aşamalı sigara/puro animasyonu: ağza götür -> derin çek (kor parlar!) -> indir & ileri duman üfle!
				var lift := 0.0
				if u < 0.24:
					lift = smoothstep(0.0, 0.24, u)
				elif u < 0.56:
					lift = 1.0
					var inh := sin(((u - 0.24) / 0.32) * PI)
					ember_boost = 5.8 * inh
					target_fov_mod = -2.4 * inh
				else:
					var exh := smoothstep(0.56, 1.0, u)
					lift = 1.0 - exh
					var rel := sin(((u - 0.56) / 0.44) * PI)
					target_fov_mod = 1.3 * rel
					ember_boost = (1.0 - exh) * 1.4
				a_pos = Vector3(-0.19, 0.095, 0.165) * lift
				a_rot = Vector3(12.0, -34.0, -16.0) * lift

			"ash_flick":
				# Keskin bilek vuruşuyla kül silkme!
				var f1 := sin(u * PI)
				var snap := sin(clampf((u - 0.28) / 0.36, 0.0, 1.0) * PI)
				a_pos = Vector3(-0.04 * f1, -0.03 * f1 - 0.045 * snap, -0.02 * f1)
				a_rot = Vector3(-28.0 * snap - 8.0 * f1, -12.0 * f1, -14.0 * snap)

			"tea_sip":
				# İnce belli çayı ağza kaldır -> eğip sıcak yudumla -> yavaşça geri indir!
				var lift := 0.0
				var tilt := 0.0
				if u < 0.30:
					lift = smoothstep(0.0, 0.30, u)
					tilt = lift * 0.45
				elif u < 0.68:
					lift = 1.0
					var sip_k := sin(((u - 0.30) / 0.38) * PI)
					tilt = 0.45 + 0.55 * sip_k
					target_pitch_mod = 0.11 * sip_k
				else:
					var dn := smoothstep(0.68, 1.0, u)
					lift = 1.0 - dn
					tilt = 0.45 * lift
				# Bardak ağız hizasında, ekranın alt-ortasında kalır; yudumda baş hafif geriye yatar
				a_pos = Vector3(-0.15, 0.045, 0.085) * lift
				a_rot = Vector3(-48.0 * tilt, -12.0 * lift, 8.0 * lift)

			"tea_stir":
				# Bardağı hafif ortaya yaklaştır ve içindeki kaşığı dairesel şıngırdat!
				var env := sin(u * PI)
				a_pos = Vector3(-0.075 * env, 0.03 * env, 0.04 * env)
				a_rot = Vector3(4.0 * env + sin(u * TAU * 4.0) * 2.5 * env, 0.0, cos(u * TAU * 4.0) * 2.5 * env)
				var sp_piv := _fp_item_visual.find_child("SpoonPivot", true, false) as Node3D
				if sp_piv:
					sp_piv.rotation.y += dt * 19.5 * maxf(env, 0.25)

			"simit_bite":
				# Çıtır simidi ağza götür -> ısır -> 2 hafif çiğneme salınımıyla indir!
				var lift := 0.0
				var chew := 0.0
				if u < 0.28:
					lift = smoothstep(0.0, 0.28, u)
				elif u < 0.44:
					lift = 1.0 + sin(((u - 0.28) / 0.16) * PI) * 0.08
					target_pitch_mod = -0.025 * sin(((u - 0.28) / 0.16) * PI)
				elif u < 0.78:
					var mid := (u - 0.44) / 0.34
					lift = lerpf(1.0, 0.35, mid)
					chew = sin(mid * TAU * 2.0) * 0.015
				else:
					lift = lerpf(0.35, 0.0, smoothstep(0.78, 1.0, u))
				a_pos = Vector3(-0.17 * lift, 0.125 * lift + chew, 0.155 * lift)
				a_rot = Vector3(-24.0 * lift, 22.0 * lift, -18.0 * lift)

			"simit_sniff":
				var env := sin(u * PI)
				a_pos = Vector3(-0.12 * env, 0.075 * env, 0.11 * env)
				a_rot = Vector3(8.0 * env, 36.0 * sin(u * TAU) * env, -12.0 * env)

			"knife_slash":
				# 3 aşamalı bıçak savurma: geri çek -> çapraz hızlı kes -> toparla!
				if u < 0.22:
					var w_k := smoothstep(0.0, 0.22, u)
					a_pos = Vector3(0.08, 0.09, 0.06) * w_k
					a_rot = Vector3(26.0, -18.0, 22.0) * w_k
				elif u < 0.52:
					var s_k := smoothstep(0.22, 0.52, u)
					a_pos = Vector3(0.08, 0.09, 0.06).lerp(Vector3(-0.34, -0.09, -0.24), s_k)
					a_rot = Vector3(26.0, -18.0, 22.0).lerp(Vector3(-56.0, 68.0, -52.0), s_k)
				else:
					var r_k := smoothstep(0.52, 1.0, u)
					a_pos = Vector3(-0.34, -0.09, -0.24).lerp(Vector3.ZERO, r_k)
					a_rot = Vector3(-56.0, 68.0, -52.0).lerp(Vector3.ZERO, r_k)

			"knife_spin":
				# Pazarcı usulü 360° bıçak çevirme şovu!
				var env := sin(u * PI)
				a_pos = Vector3(-0.07 * env, 0.06 * env, -0.03 * env)
				a_rot = Vector3(-360.0 * smoothstep(0.0, 1.0, u), 18.0 * env, -20.0 * env)

			"mega_blast", "mega_chirp":
				var env := sin(u * PI)
				var vib := sin(now_t * 62.0) * 0.005 * env
				a_pos = Vector3(-0.11 * env + vib, 0.075 * env, 0.04 * env)
				a_rot = Vector3(6.0 * env, -12.0 * env, vib * 400.0)

			"spray_pump":
				# Çift tetik sıkma + şişe geri tepmesi!
				var p1 := sin(clampf(u / 0.45, 0.0, 1.0) * PI)
				var p2 := sin(clampf((u - 0.45) / 0.55, 0.0, 1.0) * PI)
				var sq := maxf(p1, p2 * 0.85)
				a_pos = Vector3(-0.05 * sq, 0.045 * sq, -0.095 * sq)
				a_rot = Vector3(11.0 * sq, 0.0, -4.0 * sq)
				var trig := _fp_item_visual.find_child("Trigger", true, false) as Node3D
				if trig:
					trig.rotation.x = -0.35 + sq * 0.52

			"spray_shake":
				var env := sin(u * PI)
				var sh := sin(u * TAU * 3.5) * env
				a_pos = Vector3(-0.03 * env, 0.055 * sh, 0.0)
				a_rot = Vector3(18.0 * sh, -10.0 * env, 14.0 * sh)

			"radio_toggle":
				var env := sin(u * PI)
				a_pos = Vector3(-0.03 * env, 0.04 * env, 0.02 * env)
				a_rot = Vector3(-8.0 * env, 12.0 * env, 0.0)

			"radio_tune":
				var env := sin(u * PI)
				a_pos = Vector3(-0.05 * env, 0.035 * env, 0.05 * env)
				a_rot = Vector3(-12.0 * env, 24.0 * env, 5.0 * sin(u * TAU * 2.0) * env)

		# Eşya pasif canlılıkları: sigara/puro kor titremesi, megafon bağırırken ağza kalkması, radyo ritim zıplaması
		if iid in ["sigara", "puro"]:
			var emb := _fp_item_visual.find_child("Ember", true, false) as MeshInstance3D
			if emb and emb.material_override is StandardMaterial3D:
				var base_e := 3.0 if iid == "puro" else 2.4
				var flick := sin(now_t * 5.3) * 0.35 + sin(now_t * 13.7) * 0.22
				(emb.material_override as StandardMaterial3D).emission_energy_multiplier = maxf(1.2, base_e + flick + ember_boost)
		elif iid == "megafon" and _mega_raise > 0.01:
			var vib_m := sin(now_t * 54.0) * 0.004 * _mega_raise * clampf(shout_power, 0.3, 1.4)
			a_pos += Vector3(-0.14, 0.09, 0.07) * _mega_raise + Vector3(vib_m, vib_m * 0.6, 0.0)
			a_rot += Vector3(4.0, -14.0, 0.0) * _mega_raise
		elif iid == "radyo" and _hand_radio_playing:
			var beat := pow(absf(sin(now_t * 5.2)), 2.2)
			a_pos.y += beat * 0.008
			a_rot.z += sin(now_t * 2.6) * 2.2
			var dial := _fp_item_visual.find_child("Dial", true, false) as MeshInstance3D
			if dial and dial.material_override is StandardMaterial3D:
				(dial.material_override as StandardMaterial3D).emission_energy_multiplier = 1.2 + beat * 1.1

		_fp_item_visual.position = a_pos
		_fp_item_visual.rotation_degrees = a_rot

	_cam_fov_mod = lerpf(_cam_fov_mod, target_fov_mod, minf(dt * 8.0, 1.0))
	_cam_pitch_mod = lerpf(_cam_pitch_mod, target_pitch_mod, minf(dt * 8.0, 1.0))


@rpc("authority", "unreliable_ordered")
func sync_state(p: Vector3, by: float, ly: float, lp: float, s: float, a: bool, sp := 0.0) -> void:
	net_pos = p
	body_yaw = by
	look_yaw = ly
	look_pitch = lp
	if not a and air:
		land_t = 0.14
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
		if not npc and is_multiplayer_authority() and spd > 0.65:
			var cur_half := 0 if phase < PI else 1
			if cur_half != _prev_step_half:
				_prev_step_half = cur_half
				Sfx.play("step", -14.0 + kr * 4.5, 0.96 + kr * 0.16 + float(cur_half) * 0.07)
	land_t = maxf(land_t - dt, 0.0)
	var land := land_t / 0.14
	var breathe := sin(t * 2.2)
	var f := minf(dt * 18.0, 1.0)

	for side: float in [-1.0, 1.0]:
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

	var eq_tp := equipped_item_id()
	var tp_u := clampf(_tp_t / _tp_dur, 0.0, 1.0) if (_tp_action != "" and _tp_dur > 0.0) else 0.0
	var tp_env := sin(tp_u * PI)
	var head_tilt_tp := 0.0

	for side: float in [-1.0, 1.0]:
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
			p.y += kr * 0.12 + maxf(0.0, cos(c)) * 0.05 * kw + breathe * 0.015 * idle - land * 0.06
			p.x += side * (0.02 * sin(t * 1.3 + side) * idle + 0.015 * kw)
			r.x = -cos(c) * lerpf(0.55, 1.0, kr) * kw
		# 3. şahıs elde eşya tutuş & senkronize kullanım animasyonları!
		if side < 0 and eq_tp != "":
			match eq_tp:
				"cay":
					p = rest[n] + Vector3(0.04, 0.12 + breathe * 0.01, 0.18)
					r = Vector3(-0.12, 0.0, 0.0)
				"sigara", "puro":
					p = rest[n] + Vector3(0.02, 0.14 + breathe * 0.01, 0.14)
					r = Vector3(-0.25, 0.25, 0.0)
				"simit":
					p = rest[n] + Vector3(0.04, 0.13 + breathe * 0.01, 0.17)
					r = Vector3(-0.2, 0.0, 0.0)
				"megafon":
					var sh_k := 1.0 if (shout_power >= SHOUT_ON or _mega_burst > 0.0) else 0.25
					p = rest[n] + Vector3(0.14 * sh_k, 0.26 * sh_k + 0.08, 0.24 * sh_k + 0.08)
					r = Vector3(-0.5 * sh_k, 0.2 * sh_k, 0.0)
			match _tp_action:
				"smoke_inhale":
					p = rest[n] + Vector3(0.18 * tp_env, 0.34 * tp_env + 0.10, 0.26 * tp_env + 0.08)
					r = Vector3(-0.75 * tp_env, 0.4 * tp_env, 0.0)
					head_tilt_tp = -0.10 * tp_env
				"smoke_exhale":
					p = rest[n] + Vector3(0.04, 0.14, 0.14)
					head_tilt_tp = 0.14 * tp_env
				"tea_sip":
					p = rest[n] + Vector3(0.18 * tp_env, 0.36 * tp_env + 0.10, 0.25 * tp_env + 0.10)
					r = Vector3(-0.65 * tp_env, 0.0, 0.0)
					head_tilt_tp = -0.22 * tp_env
				"tea_stir":
					p = rest[n] + Vector3(0.10 * tp_env, 0.16, 0.22)
				"simit_bite":
					p = rest[n] + Vector3(0.18 * tp_env, 0.34 * tp_env + 0.10, 0.25 * tp_env + 0.10)
					head_tilt_tp = 0.12 * sin(tp_u * TAU * 2.0) * tp_env
				"knife_slash":
					p += Vector3(-0.25 * tp_env, 0.16 * tp_env, 0.32 * tp_env)
					r += Vector3(-1.35 * tp_env, 0.65 * tp_env, 0.0)
				"knife_spin":
					p += Vector3(0.0, 0.18 * tp_env, 0.15 * tp_env)
					r.x -= TAU * tp_u
				"spray_pump":
					p += Vector3(0.0, 0.18 * tp_env, 0.26 * tp_env)
				"spray_shake":
					p += Vector3(0.0, 0.14 + sin(tp_u * TAU * 3.0) * 0.10 * tp_env, 0.16)
		elif side > 0 and _tp_action == "tea_stir":
			# Sol el 3. şahısta çay kaşığını dairesel karıştırır!
			p = rest[n] + Vector3(-0.14 * tp_env + cos(tp_u * TAU * 4.0) * 0.04, 0.26 * tp_env, 0.24 * tp_env + sin(tp_u * TAU * 4.0) * 0.04)
		var w: Node3D = parts[n]
		w.position = w.position.lerp(p, f)
		w.rotation = w.rotation.lerp(r, f)

	var body: Node3D = parts["Body"]
	var bp: Vector3 = rest["Body"]
	bp.y += absf(sin(phase)) * lerpf(0.04, 0.075, kr) * kw + breathe * 0.008 * idle - land * 0.05 + (0.04 if air else 0.0)
	body.position = body.position.lerp(bp, f)
	body.rotation = body.rotation.lerp(
		Vector3(0.06 * kw + 0.19 * kr, cos(phase) * lerpf(0.09, 0.15, kr) * kw, sin(phase) * 0.06 * kw), f)
	var sq := 1.0 + breathe * 0.015 * idle - land * 0.08 + (0.05 if air else 0.0)
	var side_sq := 1.0 + (1.0 - sq) * 0.5
	body.scale = body.scale.lerp(Vector3(side_sq, sq, side_sq), f)

	var hp: Vector3 = rest["Head"]
	hp.y += (body.position.y - rest["Body"].y) * 1.1 + breathe * 0.01 * idle
	head.position = head.position.lerp(hp, f)
	var rel := clampf(wrapf(face_yaw() - rig.rotation.y, -PI, PI), -HEAD_LIMIT, HEAD_LIMIT)
	head.rotation.y = lerp_angle(head.rotation.y, rig.rotation.y + rel, minf(dt * 20.0, 1.0))
	head.rotation.x = lerpf(head.rotation.x, -look_pitch * 0.6 + head_tilt_tp, f)
	head.rotation.z = lerpf(head.rotation.z, -sin(phase) * 0.045 * kw, f)


# ---------- Proximity Sesli Sohbet ----------

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
	var eff := get_effective_shout()
	var on := eff >= SHOUT_ON
	if on and not _shout_lbl.visible:
		_shout_lbl.text = _pick_shout_call()
	_shout_lbl.visible = on
	_shout_lbl.scale = Vector3.ONE * (0.88 + clampf(eff, 0.0, 2.0) * 0.25)


func _pick_shout_call() -> String:
	var st := _find_stall(_my_peer_id())
	var stocked: Array = []
	if st:
		for sl: Dictionary in st.slots:
			if sl["item"] != "" and int(sl["count"]) > 0:
				stocked.append(sl)
	if stocked.is_empty():
		return "📢 Gel vatandaş gel!"
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


# ---------- Etkileşim, Hedef Vurgusu ve Ekonomi ----------

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
	if _ray and _ray.is_colliding():
		var a := _ray.get_collider() as Area3D
		if a:
			return a
	# Affedici yedek: küre taramasında kameraya en yakın hedef
	if _shape and _shape.is_colliding() and cam:
		var best: Area3D = null
		var best_d := INF
		for i in _shape.get_collision_count():
			var c := _shape.get_collider(i) as Area3D
			if c == null:
				continue
			var d := cam.global_position.distance_to(_shape.get_collision_point(i))
			if d < best_d:
				best_d = d
				best = c
		return best
	return null


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
	if _place_held and held_crate and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
		else:
			var eq := equipped_item_id()
			match eq:
				"sigara":
					interact_hint = "🚬 Sigara  •  [Sol Tık] Nefes Çek"
				"puro":
					interact_hint = "🪵 Küba Purosu  •  [Sol Tık] Nefes Çek (+Prestij)"
				"megafon":
					interact_hint = "📢 El Megafonu (+12 dB)  •  [B / Mikrofon / Sol Tık] Bağır!"
				"bicak":
					interact_hint = "🔪 Meyve Bıçağı  •  [Sol Tık] Savur (Zabıta Dikkat!)"
				"radyo":
					interact_hint = "📻 Arabesk Radyo (%s)  •  [Sol Tık] Aç/Kapat  •  Tezgaha bakıp [E] Koy" % ("ÇALIYOR" if _hand_radio_playing else "KAPALI")
				"spray":
					var uses := int(inventory[active_slot].get("uses", 0)) if active_slot >= 0 else 0
					interact_hint = "💦 Su Fısfısı (%d fıs)  •  Tezgahının yanında [Sol Tık] Tazele" % uses
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
					interact_hint = "[E] Yedek %s Kasası — %d TL (%d ad.)" % [nm, cost, cap]
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
					interact_hint = "[E] Ford Transit'ten %s Kasası Al — %d TL (%d ad.)" % [nm, cost, cap]
		"truck_horn":
			show_hl = true
			interact_hint = "[E] Toptancıya Selam Ver — Havalı Korna Çaldır! 📣"
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
				elif is_holding_item("radyo") and not st.has_radio:
					parts_txt.append("[E] Radyoyu Tezgaha Koy")
				elif not held_crate and sl["count"] == 0:
					parts_txt.append("Ford Transit Toptancıdan [E] kasa al")
				if sl["item"] != "" and int(sl["count"]) > 0:
					var badge := _price_badge(sl["item"], int(sl["price"]))
					parts_txt.append("[Tekerlek / Z-X] %d TL (%s)" % [int(sl["price"]), badge])
					parts_txt.append(_freshness_hint(float(sl.get("fresh", 1.0))))
				interact_hint = "  •  ".join(parts_txt)
		"thief":
			show_hl = true
			interact_hint = "[E] Kapkaççıyı yakala!" if _catch_cd <= 0.0 else "🏃 Kapkaççı kaçıyor!"
		"stall_radio":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id and my_st and my_st.has_radio:
				show_hl = true
				interact_hint = "📻 Tezgah Radyosu (%s)  •  [E] Aç/Kapat  •  [Tekerlek] Şarkı  •  [R] Eline Al" % ("ÇALIYOR" if my_st.radio_playing else "KAPALI")
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
				interact_hint = "[E / P] Pazarcı Dükkanı (Sigara, Puro, Megafon, Bıçak, Radyo & Tezgah)"
		"customer":
			var c := _find_customer(str(area.get_meta("customer_name", "")))
			if c:
				var h: String = c.get_next_sell_hint(my_id)
				if h != "":
					show_hl = true
					interact_hint = h
		"vendor":
			show_hl = true
			interact_hint = str(area.get_meta("offer", "[E] Satın al"))
	_update_highlight(area, show_hl)


## Yuvadaki ürünün tazelik satırı: "Tazelik %62 — 💦 fısfısla".
func _freshness_hint(f: float) -> String:
	var txt := "Tazelik %%%d" % roundi(f * 100.0)
	if f < StallScript.ROTTEN:
		txt = "🪰 " + txt + " ÇÜRÜYOR!"
	elif f >= 0.85:
		txt = "✨ " + txt
	if f < 0.75:
		if is_holding_item("spray"):
			txt += " — 💦 [Sol Tık] fısfısla"
		elif has_inventory_item("spray"):
			txt += " — 💦 fısfısla"
		else:
			txt += " — 💦 Fısfıs al [P]"
	return txt


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
		"truck_horn":
			var w := _find_world()
			var tr := w.get_node_or_null("Wholesaler") if w else null
			if tr and tr.has_method("request_honk"):
				tr.request_honk()
		"slot":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var st := _find_stall(owner_id)
			if st and owner_id == my_id and is_holding_item("radyo") and not st.has_radio:
				_set_hand_radio_synced(false)
				st.set_radio_synced(true, true)
				inventory[active_slot] = {}
				active_slot = -1
				_sync_equipped_to_peers()
				_refresh_equipped_visual()
				inventory_changed.emit()
		"stall_radio":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			var st := _find_stall(owner_id)
			if st and owner_id == my_id and st.has_radio:
				st.set_radio_synced(true, not st.radio_playing)
		"bell":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id:
				_do_ring_bell()
		"upgrade_board":
			var owner_id: int = int(area.get_meta("stall_owner", -1))
			if owner_id == my_id:
				open_shop.emit()
		"customer":
			_do_sell_to_customer(false)
		"thief":
			_do_catch_thief(area)
		"vendor":
			_do_buy_from_vendor(area, main)


## Çaycı/simitçiden satın alma: parayı düş, ince belli çayı veya sıcak simidi doğrudan eline/envanterine ver!
func _do_buy_from_vendor(area: Area3D, main: Node) -> void:
	var price := int(area.get_meta("price", 5))
	var is_tea := str(area.get_meta("vendor", "")) == "cay"
	var item_id := "cay" if is_tea else "simit"
	if money < price:
		if main and main.has_method("show_toast"):
			main.show_toast("Cebinde %d TL yok abi!" % price, Color(1.0, 0.5, 0.4))
		return
	spend_money(price, "Çay" if is_tea else "Simit")
	var can_store := has_inventory_item(item_id)
	if not can_store:
		for sl in inventory:
			if sl.is_empty():
				can_store = true
				break
	if can_store:
		add_inventory_item_synced(item_id)
		Sfx.play("tea" if is_tea else "happy", -6.0)
		if main and main.has_method("show_toast"):
			main.show_toast("🍵 Tavşan kanı çay elinde! Sol tıkla yudumla, sağ tıkla karıştır!" if is_tea else "🥯 Sıcak simit elinde! Sol tıkla ısır, sağ tıkla kokla!", Color(1.0, 0.86, 0.5))
	else:
		# Tüm 8 yuva doluysa para boşa gitmesin: doğrudan etkisini ver
		if is_tea:
			tea_buff = minf(tea_buff + 40.0, MAX_BUFF)
		else:
			simit_buff = minf(simit_buff + 40.0, MAX_BUFF)
		Sfx.play("tea_sip" if is_tea else "bite_crunch", -5.0)
		if main and main.has_method("show_toast"):
			main.show_toast("🍵 Çay keyfi: +40 sn bağırma +%25!" if is_tea else "🥯 Simit enerjisi: +40 sn %15 hızlı!", Color(1.0, 0.86, 0.5))
	var amb := area.get_parent().get_parent() if area.get_parent() else null
	if amb and amb.has_method("vendor_purchase"):
		amb.vendor_purchase(area)


## Kapkaççı yakalama: hırsız düğümünü bulup host'a istek gönderir (doğrulama thief.gd'de).
func _do_catch_thief(area: Area3D) -> void:
	if _catch_cd > 0.0:
		return
	var th: Node = area
	while th and not th.has_method("rpc_request_catch"):
		th = th.get_parent()
	if th == null:
		var w := _find_world()
		var tg := w.get_node_or_null("Thieves") if w else null
		var tname := str(area.get_meta("thief_name", ""))
		th = tg.get_node_or_null(tname) if (tg and tname != "") else null
	if th == null or not th.has_method("rpc_request_catch"):
		return
	_catch_cd = 0.5
	_use_anim = 1.0
	add_trauma(0.12)
	var fwd := -cam.global_transform.basis.z if cam else Vector3(0, 0, -1)
	_trigger_item_fx_synced("catch", "", global_position + Vector3(0, 1.1, 0) + fwd * 0.5, fwd)
	var my_id := _my_peer_id()
	if Net.online():
		th.rpc_request_catch.rpc_id(1, my_id)
	else:
		th.rpc_request_catch(my_id)


func _do_ring_bell() -> void:
	var st := _find_stall(_my_peer_id())
	if st and st.has_upgrade("bell") and global_position.distance_to(st.global_position) < 4.5:
		st.request_ring_bell()


func _do_sell_to_customer(insist: bool) -> void:
	var area := _ray_target()
	if area == null:
		return
	var kind := str(area.get_meta("kind", ""))
	if insist and kind == "stall_radio":
		# R ile tezgaha konan radyoyu geri envantere al
		var owner_id: int = int(area.get_meta("stall_owner", -1))
		var st := _find_stall(owner_id)
		if st and owner_id == _my_peer_id() and st.has_radio:
			st.set_radio_synced(false, false)
			add_inventory_item_synced("radyo")
		return
	if kind != "customer":
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
	add_trauma(0.14)
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
	rb.add_child(StallScript.build_held_crate(item_id, count, _my_crate_capacity()))
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
			_fp_crate_visual = StallScript.build_held_crate(held_item, held_count, _my_crate_capacity())
			_fp_crate_anchor.add_child(_fp_crate_visual)
		elif _held_anchor:
			_held_visual = StallScript.build_held_crate(held_item, held_count, _my_crate_capacity())
			_held_anchor.add_child(_held_visual)
	# Kasa taşırken eldeki kişisel eşya geçici gizlenir, kasa bırakılınca geri görünür (envantere kasa ASLA girmez!)
	_refresh_equipped_visual()


func _my_crate_capacity() -> int:
	var st := _find_stall(_my_peer_id())
	return int(st.crate_capacity()) if st else StallScript.CRATE_CAPACITY


## Para ödülü (host/solo çağırır). is_sale=false: müşteri satışı olmayan ödüller (zabıta ödülü, hırsız ödülü, görev)
## komboyu ve satılan adet sayacını etkilemez.
func award_money(amount: int, tip := 0, was_haggle := false, is_sale := true) -> void:
	if amount <= 0 and tip <= 0:
		return
	var bonus := 0
	var combo_n := -1
	if is_sale and amount > 0:
		combo_n = (combo + 1) if _combo_t > 0.0 else 1
		bonus = roundi(float(amount) * combo_bonus_ratio(combo_n))
	if Net.online():
		rpc_add_money.rpc(amount, tip, was_haggle, bonus, combo_n)
	else:
		rpc_add_money(amount, tip, was_haggle, bonus, combo_n)


## Kombo n için satış primi oranı: 3. ardışık satıştan itibaren adım başı +%10, en çok +%50.
static func combo_bonus_ratio(n: int) -> float:
	if n < COMBO_START:
		return 0.0
	return minf(float(n - COMBO_START + 1) * COMBO_STEP, COMBO_MAX_BONUS)


@rpc("any_peer", "call_local", "reliable")
func rpc_add_money(amount: int, tip := 0, was_haggle := false, bonus := 0, combo_n := 0) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	bonus = maxi(bonus, 0)
	var total_gain := amount + tip + bonus
	money += total_gain
	daily_revenue += total_gain
	daily_tips += tip
	# combo_n: >=1 satış, 0 = eski çağrı (satış say), -1 = satış dışı ödül
	if amount > 0 and combo_n >= 0:
		daily_sold += 1
	if was_haggle:
		daily_haggles += 1
	if combo_n >= 1:
		combo = combo_n
		_combo_t = COMBO_WINDOW
		best_combo_today = maxi(best_combo_today, combo)
		combo_changed.emit(combo)
		if combo >= COMBO_START:
			_combo_feedback(combo, bonus)
	money_earned.emit(total_gain, money, tip)
	if amount > 0 and is_multiplayer_authority() and not npc and cam:
		_spawn_coin_fly(clampi(1 + amount / 7, 2, 7))


## Kombo geri bildirimi: herkese görünen alev yazısı + ses; satıcının kendi ekranında küçük sarsıntı.
func _combo_feedback(n: int, bonus: int) -> void:
	var w := _find_world()
	var pct := roundi(combo_bonus_ratio(n) * 100.0)
	var hot := clampf(float(n - COMBO_START) / 4.0, 0.0, 1.0)
	var col := Color(1.0, 0.82, 0.2).lerp(Color(1.0, 0.32, 0.12), hot)
	var txt := "🔥 KOMBO x%d  +%%%d" % [n, pct]
	if bonus > 0:
		txt += "  (+%d TL)" % bonus
	VFX.spawn_floating_text(w, global_position + Vector3(0, 2.15, 0), txt, col, 40 + mini(n, 8) * 2)
	Sfx.play_3d("combo", global_position + Vector3(0, 1.4, 0), w, -3.0, 1.0 + hot * 0.25, 20.0)
	if is_multiplayer_authority() and not npc:
		add_trauma(0.10 + 0.05 * hot)


## Satışta paralar tezgahtaki yığından fırlayıp kameraya (cebe) uçar; her biri varışta ince bir şıngırtı.
func _spawn_coin_fly(n: int) -> void:
	var w := _find_world()
	if w == null or not w.is_inside_tree() or cam == null:
		return
	var st := _find_stall(_my_peer_id())
	var fwd := -cam.global_transform.basis.z
	var src := cam.global_position + fwd * 1.2 + Vector3(0, -0.35, 0)
	if st and Time.get_ticks_msec() - int(st.last_sale_ms) < 1600:
		src = st.last_sale_pos + Vector3(0, 0.12, 0)
	if _coin_mesh == null:
		_coin_mesh = LP.cyl(0.032, 0.032, 0.009, 8)
		_coin_mat = LP.mat(Color(1.0, 0.8, 0.22), 0.25, 0.85, Color(1.0, 0.72, 0.15), 0.8)
	for i in n:
		var coin := MeshInstance3D.new()
		coin.mesh = _coin_mesh
		coin.material_override = _coin_mat
		coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(coin)
		var p0 := src + Vector3(randf_range(-0.12, 0.12), randf_range(0.0, 0.1), randf_range(-0.12, 0.12))
		coin.global_position = p0
		coin.rotation = Vector3(randf_range(0, TAU), 0, randf_range(0, TAU))
		var lift := Vector3(randf_range(-0.45, 0.45), randf_range(0.55, 0.9), randf_range(-0.45, 0.45))
		var spin := randf_range(10.0, 18.0)
		var idx := i
		coin.scale = Vector3.ZERO
		var tw := coin.create_tween()
		tw.tween_interval(float(i) * 0.055)
		tw.tween_property(coin, "scale", Vector3.ONE, 0.06)
		tw.tween_method(func(t: float) -> void:
			if not is_instance_valid(coin) or not is_instance_valid(cam):
				return
			var tgt := cam.global_position + cam.global_transform.basis * Vector3(0.18, -0.26, -0.42)
			var p1 := p0 + lift
			var u := 1.0 - t
			coin.global_position = u * u * p0 + 2.0 * u * t * p1 + t * t * tgt
			coin.rotation.x += spin * 0.016
			coin.scale = Vector3.ONE * lerpf(1.0, 0.45, t * t)
		, 0.0, 1.0, 0.48).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Sfx.play("coin", -15.0, 1.15 + float(idx) * 0.07, 0.02)
			if is_instance_valid(coin):
				coin.queue_free()
		)


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
			add_trauma(0.32)
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
	best_combo_today = 0
	_combo_t = 0.0
	if combo != 0:
		combo = 0
		combo_changed.emit(0)


func net_profit() -> int:
	return daily_revenue - daily_spent - daily_fines


func export_snapshot() -> Dictionary:
	return {
		"id": _my_peer_id(), "pos": global_position, "money": money,
		"daily_revenue": daily_revenue, "daily_spent": daily_spent,
		"daily_fines": daily_fines, "daily_tips": daily_tips,
		"daily_sold": daily_sold, "daily_haggles": daily_haggles,
		"held_crate": held_crate, "held_item": held_item, "held_count": held_count,
		"equipped": equipped_item_id(), "hand_radio": _hand_radio_playing,
		"combo": combo, "combo_t": _combo_t, "best_combo_today": best_combo_today,
	}


func apply_snapshot(d: Dictionary) -> void:
	money = int(d.get("money", STARTING_MONEY))
	daily_revenue = int(d.get("daily_revenue", 0))
	daily_spent = int(d.get("daily_spent", 0))
	daily_fines = int(d.get("daily_fines", 0))
	daily_tips = int(d.get("daily_tips", 0))
	daily_sold = int(d.get("daily_sold", 0))
	daily_haggles = int(d.get("daily_haggles", 0))
	best_combo_today = maxi(int(d.get("best_combo_today", 0)), 0)
	_combo_t = clampf(float(d.get("combo_t", 0.0)), 0.0, COMBO_WINDOW)
	combo = maxi(int(d.get("combo", 0)), 0) if _combo_t > 0.0 else 0
	combo_changed.emit(combo)
	_remote_item_id = str(d.get("equipped", ""))
	_apply_held_crate(bool(d.get("held_crate", false)), str(d.get("held_item", "")), int(d.get("held_count", 0)))
	rpc_set_hand_radio(bool(d.get("hand_radio", false)))
