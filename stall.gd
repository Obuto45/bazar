extends Node3D
## Oyuncu tezgahı: dokulu ahşap/branda, 4 ürün yuvası, çift taraflı renkli fiyat etiketleri,
## pirinç terazi, arka yedek kasalar, tezgaha konulan Arabesk Radyo ve 3D yükseltmeler.

const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const Items := preload("res://items.gd")
const VFX := preload("res://vfx.gd")

const ITEMS := Produce.ITEMS
const ITEM_ORDER := Produce.ITEM_ORDER
const BASIC_ORDER := Produce.BASIC_ORDER
const WOOD := Color(0.55, 0.37, 0.22)
const STEEL := Color(0.50, 0.52, 0.55)
const BRASS := Color(0.88, 0.70, 0.22)
const AWNINGS := [
	Color(0.14, 0.44, 0.80), Color(0.84, 0.22, 0.18), Color(0.18, 0.54, 0.30), Color(0.92, 0.56, 0.14),
	Color(0.62, 0.30, 0.76), Color(0.90, 0.38, 0.54), Color(0.14, 0.62, 0.66), Color(0.82, 0.66, 0.16),
]
const UPGRADES := {
	"megaphone": {
		"name": "Tezgah Hoparlörü",
		"cost": 80,
		"desc": "Tezgaha hoparlör takar: bağırma gücü +%35 artar, el megafonuyla birleşir.",
	},
	"lights": {
		"name": "Süslü Tente & Işıklar",
		"cost": 100,
		"desc": "Tezgahın ışıl ışıl parlar; pasif müşteri cazibesi +%22 artar.",
	},
	"big_crate": {
		"name": "Geniş Kasa & Hızlı Dizim",
		"cost": 120,
		"desc": "Yuva kapasitesi 16, kasa 14 adede çıkar; %40 daha hızlı dizilir.",
	},
	"bell": {
		"name": "Pirinç Tezgah Zili",
		"cost": 90,
		"desc": "Tezgaha zil ekler: [E] veya [F] ile çal, 10 sn güçlü müşteri çek!",
	},
}
const UPGRADE_ORDER := ["megaphone", "lights", "big_crate", "bell"]
const SLOT_XS := [-1.2, -0.4, 0.4, 1.2]
const MAX_SLOT_COUNT := 10
const CRATE_CAPACITY := 10
const GOUGE_RATIO := 1.75

var owner_id := 0
var owner_name := ""
var spot_idx := 0
var awning_color := Color(0.14, 0.44, 0.80)
var slots: Array[Dictionary] = []
var crate_available: Dictionary = {}
var upgrades: Dictionary = {"megaphone": false, "lights": false, "big_crate": false, "bell": false}
var bell_boost := 0.0
var bell_cd := 0.0

# Tezgaha bırakılan Arabesk Radyo
var has_radio := false
var radio_playing := false
var _radio_node: Node3D
var _radio_area: Area3D
var _radio_audio: AudioStreamPlayer3D
var _radio_note_cd := 0.0

var _crate_visuals: Dictionary = {}
var _crate_labels: Dictionary = {}
var _slot_visuals: Array[Node3D] = []
var _slot_labels: Array[Label3D] = []
var _slot_back_labels: Array[Label3D] = []
var _slot_tag_mats: Array[StandardMaterial3D] = []
var _sign_label: Label3D
var _scale_beam: Node3D
var _upgrade_visuals: Dictionary = {}
var _bell_area: Area3D
var _bell_mesh: Node3D
var _light_bulbs: Array[StandardMaterial3D] = []
var _anim_t := 0.0


func setup(p_owner_id: int, p_owner_name: String, color_idx: int, p_spot_idx := 0) -> void:
	owner_id = p_owner_id
	owner_name = p_owner_name
	spot_idx = p_spot_idx
	awning_color = AWNINGS[absi(color_idx) % AWNINGS.size()]
	name = "Stall_%d" % owner_id


func _ready() -> void:
	slots.clear()
	for i in 4:
		slots.append({"item": "", "count": 0, "price": 10})
	_build_geometry()
	_build_slots()
	_build_supply_crates()
	_build_scale()
	_build_upgrade_board()
	_build_upgrade_attachments()
	_build_radio_slot()
	for k in upgrades:
		if bool(upgrades[k]):
			_show_upgrade_visual(k)


func _process(dt: float) -> void:
	_anim_t += dt
	if bell_boost > 0.0:
		bell_boost = maxf(bell_boost - dt, 0.0)
	if bell_cd > 0.0:
		bell_cd = maxf(bell_cd - dt, 0.0)
	if not _light_bulbs.is_empty() and has_upgrade("lights"):
		for i in _light_bulbs.size():
			_light_bulbs[i].emission_energy_multiplier = 2.0 + sin(_anim_t * 4.5 + float(i) * 1.1) * 0.45
	if has_radio and radio_playing:
		_radio_note_cd -= dt
		if _radio_note_cd <= 0.0:
			_radio_note_cd = 1.15
			if _radio_node:
				VFX.spawn_music_note(self, _radio_node.global_position + Vector3(0, 0.28, 0))


func max_slot_count() -> int:
	return 16 if has_upgrade("big_crate") else MAX_SLOT_COUNT


func crate_capacity() -> int:
	return 14 if has_upgrade("big_crate") else CRATE_CAPACITY


func has_upgrade(key: String) -> bool:
	return bool(upgrades.get(key, false))


func _build_geometry() -> void:
	var wood_m := LP.mat_tex(WOOD, LP.tex_wood(), 0.86, Vector3(2.0, 1.0, 1.0))
	var top_m := LP.mat_tex(WOOD.lightened(0.14), LP.tex_wood(), 0.84, Vector3(2.0, 1.0, 1.0))
	var tarp_a := LP.mat_tex(awning_color, LP.tex_tarp(), 0.72, Vector3(2.0, 2.0, 1.0))
	var tarp_w := LP.mat_tex(Color(0.96, 0.94, 0.88), LP.tex_tarp(), 0.74, Vector3(2.0, 2.0, 1.0))

	LP.add_mat(self, LP.box(Vector3(3.4, 0.52, 0.92)), Vector3(0, 0.26, 0.25), wood_m)
	LP.add(self, LP.box(Vector3(3.46, 0.08, 0.96)), Vector3(0, 0.06, 0.25), WOOD.darkened(0.24))
	LP.add_mat(self, LP.box(Vector3(3.54, 0.06, 1.04)), Vector3(0, 0.545, 0.25), top_m)
	for sx in [-1.25, -0.42, 0.42, 1.25]:
		LP.add(self, LP.box(Vector3(0.06, 0.48, 0.03)), Vector3(sx, 0.27, 0.72), WOOD.darkened(0.18))
	LP.solid(self, Vector3(0, 0.285, 0.25), Vector3(3.54, 0.57, 1.04))

	# Galvaniz çelik pazarcı direkleri
	for x in [-1.62, 1.62]:
		for z in [-0.75, 0.85]:
			LP.add(self, LP.cyl(0.042, 0.048, 2.28, 6), Vector3(x, 1.14, z), STEEL, Vector3.ZERO, 0.42, 0.7)
		LP.add(self, LP.box(Vector3(0.05, 0.05, 1.62)), Vector3(x, 2.14, 0.05), STEEL, Vector3.ZERO, 0.42, 0.7)
	LP.add(self, LP.box(Vector3(3.36, 0.06, 0.06)), Vector3(0, 2.18, 0.85), STEEL, Vector3.ZERO, 0.42, 0.7)

	# Çizgili dokulu branda tente
	for i in 5:
		var m := tarp_a if i % 2 == 0 else tarp_w
		LP.add_mat(self, LP.box(Vector3(0.73, 0.05, 2.18)), Vector3(-1.46 + float(i) * 0.73, 2.33, 0.12), m, Vector3(0.18, 0, 0))
	LP.add_mat(self, LP.box(Vector3(3.68, 0.22, 0.04)), Vector3(0, 2.11, 1.17), tarp_a)
	for i in 9:
		var fc := awning_color.darkened(0.12) if i % 2 == 0 else Color(0.96, 0.94, 0.88)
		LP.add(self, LP.prism(Vector3(0.38, 0.13, 0.04)), Vector3(-1.52 + float(i) * 0.38, 1.95, 1.17), fc, Vector3(0, 0, PI))

	_sign_label = Label3D.new()
	_sign_label.text = (owner_name + " Tezgahı") if owner_name != "" else "Tezgah"
	_sign_label.position = Vector3(0, 2.12, 1.22)
	_sign_label.font_size = 34
	_sign_label.outline_size = 8
	_sign_label.modulate = Color(1.0, 0.96, 0.84)
	add_child(_sign_label)


func _build_scale() -> void:
	var sc := Node3D.new()
	sc.position = Vector3(1.44, 0.58, 0.56)
	add_child(sc)
	LP.add(sc, LP.cyl(0.08, 0.10, 0.04, 8), Vector3(0, 0.02, 0), BRASS.darkened(0.18), Vector3.ZERO, 0.3, 0.8)
	LP.add(sc, LP.cyl(0.015, 0.02, 0.28, 6), Vector3(0, 0.16, 0), BRASS, Vector3.ZERO, 0.28, 0.82)
	_scale_beam = Node3D.new()
	_scale_beam.position = Vector3(0, 0.29, 0)
	sc.add_child(_scale_beam)
	LP.add(_scale_beam, LP.box(Vector3(0.28, 0.018, 0.02)), Vector3.ZERO, BRASS, Vector3.ZERO, 0.25, 0.85)
	for side: float in [-1.0, 1.0]:
		LP.add(_scale_beam, LP.cyl(0.004, 0.004, 0.11, 4), Vector3(side * 0.12, -0.055, 0), BRASS, Vector3.ZERO, 0.3, 0.8)
		LP.add(_scale_beam, LP.cyl(0.068, 0.045, 0.022, 8), Vector3(side * 0.12, -0.115, 0), BRASS.lightened(0.1), Vector3.ZERO, 0.25, 0.85)


func tip_scale() -> void:
	if _scale_beam == null:
		return
	var tw := create_tween()
	tw.tween_property(_scale_beam, "rotation:z", 0.34, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_scale_beam, "rotation:z", -0.22, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_scale_beam, "rotation:z", 0.10, 0.16).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_scale_beam, "rotation:z", 0.0, 0.16).set_trans(Tween.TRANS_SINE)


func _build_upgrade_board() -> void:
	var b := Node3D.new()
	b.position = Vector3(-1.68, 1.24, 0.05)
	b.rotation.y = PI / 2
	add_child(b)
	LP.add(b, LP.box(Vector3(0.76, 0.48, 0.05)), Vector3.ZERO, Color(0.14, 0.2, 0.14))
	LP.add(b, LP.box(Vector3(0.82, 0.54, 0.03)), Vector3(0, 0, -0.015), WOOD.darkened(0.15))
	var lbl := Label3D.new()
	lbl.text = "⭐ DÜKKAN\n[P / E]"
	lbl.position = Vector3(0, 0, 0.035)
	lbl.font_size = 24
	lbl.outline_size = 6
	lbl.modulate = Color(1.0, 0.88, 0.35)
	lbl.double_sided = true
	b.add_child(lbl)
	var area := Area3D.new()
	area.name = "UpgradeBoardArea"
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("kind", "upgrade_board")
	area.set_meta("stall_owner", owner_id)
	area.set_meta("hl_size", Vector3(0.84, 0.56, 0.16))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.86, 0.58, 0.22)
	cs.shape = sh
	area.add_child(cs)
	b.add_child(area)


## Tezgaha bırakılan Arabesk Radyo yuvası (sağ arka masa köşesi).
func _build_radio_slot() -> void:
	_radio_node = Items.build_item_model("radyo")
	_radio_node.position = Vector3(1.52, 0.58, -0.05)
	_radio_node.rotation.y = -0.35
	_radio_node.hide()
	add_child(_radio_node)

	_radio_audio = Sfx.make_radio_player()
	_radio_node.add_child(_radio_audio)

	_radio_area = Area3D.new()
	_radio_area.name = "StallRadioArea"
	_radio_area.collision_layer = 0
	_radio_area.collision_mask = 0
	_radio_area.set_meta("kind", "stall_radio")
	_radio_area.set_meta("stall_owner", owner_id)
	_radio_area.set_meta("hl_size", Vector3(0.42, 0.30, 0.24))
	_radio_area.position = Vector3(0, 0.12, 0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.44, 0.32, 0.28)
	cs.shape = sh
	_radio_area.add_child(cs)
	_radio_node.add_child(_radio_area)


func set_radio_synced(placed: bool, playing: bool) -> void:
	if Net.online():
		rpc_set_stall_radio.rpc(placed, playing)
	else:
		rpc_set_stall_radio(placed, playing)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_stall_radio(placed: bool, playing: bool) -> void:
	has_radio = placed
	radio_playing = placed and playing
	if _radio_node:
		_radio_node.visible = placed
	if _radio_area:
		_radio_area.collision_layer = 4 if placed else 0
	if _radio_audio:
		if radio_playing and DisplayServer.get_name() != "headless":
			if not _radio_audio.playing:
				_radio_audio.play()
		elif _radio_audio.playing:
			_radio_audio.stop()


func _build_upgrade_attachments() -> void:
	_upgrade_visuals.clear()
	_light_bulbs.clear()

	var mega := Node3D.new()
	mega.position = Vector3(-1.62, 1.92, 0.92)
	mega.rotation = Vector3(-0.1, 0.25, 0.0)
	LP.add(mega, LP.cyl(0.05, 0.16, 0.32, 8), Vector3(0, 0, 0.14), Color(0.92, 0.24, 0.18), Vector3(PI / 2, 0, 0), 0.35, 0.2)
	LP.add(mega, LP.torus(0.14, 0.17, 10, 5), Vector3(0, 0, 0.30), BRASS, Vector3(PI / 2, 0, 0), 0.25, 0.8)
	LP.add(mega, LP.box(Vector3(0.07, 0.14, 0.07)), Vector3(0, -0.09, 0.02), Color(0.2, 0.2, 0.22))
	mega.hide()
	add_child(mega)
	_upgrade_visuals["megaphone"] = mega

	var lights := Node3D.new()
	for i in 7:
		var lx := -1.5 + float(i) * 0.5
		var col := Color(1.0, 0.84, 0.36) if i % 2 == 0 else Color(1.0, 0.6, 0.28)
		var bulb := LP.add(lights, LP.sphere(0.062, 6, 4), Vector3(lx, 1.88, 1.18), col, Vector3.ZERO, 0.15)
		var bm := bulb.material_override as StandardMaterial3D
		bm.emission_enabled = true
		bm.emission = col
		bm.emission_energy_multiplier = 2.2
		_light_bulbs.append(bm)
	LP.add(lights, LP.box(Vector3(3.68, 0.05, 0.06)), Vector3(0, 2.24, 1.19), BRASS, Vector3.ZERO, 0.25, 0.8)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.84, 0.72)
	glow.light_color = Color(1.0, 0.82, 0.45)
	glow.light_energy = 1.45
	glow.omni_range = 5.5
	lights.add_child(glow)
	lights.hide()
	add_child(lights)
	_upgrade_visuals["lights"] = lights

	var big := Node3D.new()
	LP.add(big, LP.box(Vector3(3.56, 0.05, 0.16)), Vector3(0, 0.58, 0.78), BRASS.darkened(0.15), Vector3.ZERO, 0.35, 0.6)
	LP.add(big, LP.box(Vector3(0.45, 0.26, 0.36)), Vector3(1.62, 0.14, -0.35), WOOD.lightened(0.1))
	big.hide()
	add_child(big)
	_upgrade_visuals["big_crate"] = big

	var bell := Node3D.new()
	bell.position = Vector3(-1.44, 0.58, 0.56)
	_bell_mesh = Node3D.new()
	bell.add_child(_bell_mesh)
	LP.add(_bell_mesh, LP.cyl(0.08, 0.11, 0.03, 8), Vector3(0, 0.015, 0), Color(0.18, 0.14, 0.12))
	LP.add(_bell_mesh, LP.ellipsoid(0.09, 0.068, 0.09, 8, 5), Vector3(0, 0.068, 0), BRASS, Vector3.ZERO, 0.2, 0.88)
	LP.add(_bell_mesh, LP.cyl(0.025, 0.025, 0.03, 6), Vector3(0, 0.135, 0), BRASS.lightened(0.15), Vector3.ZERO, 0.2, 0.9)
	_bell_area = Area3D.new()
	_bell_area.name = "BellArea"
	_bell_area.collision_layer = 0
	_bell_area.collision_mask = 0
	_bell_area.set_meta("kind", "bell")
	_bell_area.set_meta("stall_owner", owner_id)
	_bell_area.set_meta("hl_size", Vector3(0.28, 0.24, 0.28))
	var bcs := CollisionShape3D.new()
	var bsh := BoxShape3D.new()
	bsh.size = Vector3(0.32, 0.28, 0.32)
	bcs.shape = bsh
	_bell_area.position = Vector3(0, 0.08, 0)
	_bell_area.add_child(bcs)
	bell.add_child(_bell_area)
	bell.hide()
	add_child(bell)
	_upgrade_visuals["bell"] = bell


func _show_upgrade_visual(key: String) -> void:
	if _upgrade_visuals.has(key):
		var n: Node3D = _upgrade_visuals[key]
		n.show()
		n.scale = Vector3(0.1, 0.1, 0.1)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if key == "bell" and _bell_area:
		_bell_area.collision_layer = 4


func _build_slots() -> void:
	_slot_visuals.clear()
	_slot_labels.clear()
	_slot_back_labels.clear()
	_slot_tag_mats.clear()
	var crate_cols := [Color(0.12, 0.44, 0.82), Color(0.18, 0.56, 0.26), Color(0.84, 0.24, 0.18), Color(0.88, 0.66, 0.14)]
	for i in 4:
		var sx: float = SLOT_XS[i]
		var cc: Color = crate_cols[i % crate_cols.size()]
		LP.add(self, LP.box(Vector3(0.72, 0.04, 0.66)), Vector3(sx, 0.59, 0.24), cc.darkened(0.22), Vector3.ZERO, 0.55)
		LP.add(self, LP.box(Vector3(0.74, 0.07, 0.04)), Vector3(sx, 0.62, 0.56), cc, Vector3.ZERO, 0.52)
		LP.add(self, LP.box(Vector3(0.74, 0.07, 0.04)), Vector3(sx, 0.62, -0.08), cc, Vector3.ZERO, 0.52)
		var vis := Node3D.new()
		vis.position = Vector3(sx, 0.61, 0.24)
		add_child(vis)
		_slot_visuals.append(vis)
		LP.add(self, LP.cyl(0.011, 0.013, 0.17, 5), Vector3(sx, 0.68, 0.61), WOOD.darkened(0.3))
		var tag_mi := LP.add(self, LP.box(Vector3(0.46, 0.20, 0.02)), Vector3(sx, 0.79, 0.61), Color(0.98, 0.95, 0.84))
		_slot_tag_mats.append(tag_mi.material_override as StandardMaterial3D)
		var lbl := Label3D.new()
		lbl.position = Vector3(sx, 0.79, 0.625)
		lbl.font_size = 24
		lbl.pixel_size = 0.0030
		lbl.outline_size = 5
		lbl.double_sided = false
		lbl.modulate = Color(0.12, 0.08, 0.05)
		lbl.outline_modulate = Color(1.0, 0.97, 0.88)
		add_child(lbl)
		_slot_labels.append(lbl)
		var blbl := Label3D.new()
		blbl.position = Vector3(sx, 0.79, 0.595)
		blbl.rotation.y = PI
		blbl.font_size = 24
		blbl.pixel_size = 0.0030
		blbl.outline_size = 5
		blbl.double_sided = false
		blbl.modulate = Color(0.12, 0.08, 0.05)
		blbl.outline_modulate = Color(1.0, 0.97, 0.88)
		add_child(blbl)
		_slot_back_labels.append(blbl)
		var area := Area3D.new()
		area.name = "SlotArea_%d" % i
		area.collision_layer = 4
		area.collision_mask = 0
		area.set_meta("kind", "slot")
		area.set_meta("stall_owner", owner_id)
		area.set_meta("slot_idx", i)
		area.set_meta("hl_size", Vector3(0.74, 0.42, 0.74))
		area.position = Vector3(sx, 0.76, 0.30)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.74, 0.52, 0.82)
		cs.shape = sh
		area.add_child(cs)
		add_child(area)
		_refresh_slot_visual(i)


func _build_supply_crates() -> void:
	crate_available.clear()
	_crate_visuals.clear()
	_crate_labels.clear()
	var crate_cols := [Color(0.86, 0.22, 0.18), Color(0.18, 0.58, 0.26), Color(0.88, 0.68, 0.14), Color(0.12, 0.46, 0.84)]
	for i in BASIC_ORDER.size():
		var item_id: String = BASIC_ORDER[i]
		var info: Dictionary = ITEMS[item_id]
		crate_available[item_id] = true
		var cx: float = SLOT_XS[i]
		var spot := Node3D.new()
		spot.position = Vector3(cx, 0.0, -1.28)
		add_child(spot)
		LP.add(spot, LP.box(Vector3(0.68, 0.03, 0.58)), Vector3(0, 0.015, 0), WOOD.darkened(0.38))
		var c := Node3D.new()
		spot.add_child(c)
		var cc: Color = crate_cols[i % crate_cols.size()]
		LP.add(c, LP.box(Vector3(0.60, 0.30, 0.50)), Vector3(0, 0.16, 0), cc, Vector3.ZERO, 0.52)
		LP.add(c, LP.box(Vector3(0.64, 0.04, 0.54)), Vector3(0, 0.31, 0), cc.darkened(0.22), Vector3.ZERO, 0.5)
		for j in 8:
			Produce.build_mesh(c, item_id, _crate_item_pos(j, 0.16, 0.12, 0.34), 0.072)
		_crate_visuals[item_id] = c
		var lbl := Label3D.new()
		lbl.text = "%s\n%d TL" % [info["name"], int(info["crate_cost"])]
		lbl.position = Vector3(0, 0.62, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 21
		lbl.outline_size = 6
		lbl.modulate = Color(1.0, 0.96, 0.85)
		spot.add_child(lbl)
		_crate_labels[item_id] = lbl
		var area := Area3D.new()
		area.name = "CrateArea_%s" % item_id
		area.collision_layer = 4
		area.collision_mask = 0
		area.set_meta("kind", "crate")
		area.set_meta("stall_owner", owner_id)
		area.set_meta("item_id", item_id)
		area.set_meta("hl_size", Vector3(0.66, 0.42, 0.56))
		area.position = Vector3(0, 0.32, 0)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.72, 0.68, 0.64)
		cs.shape = sh
		area.add_child(cs)
		spot.add_child(area)


static func _crate_item_pos(j: int, sx: float, sz: float, y0: float) -> Vector3:
	if j < 6:
		return Vector3(-sx + float(j % 3) * sx, y0, -sz * 0.6 + float(int(j / 3)) * (sz * 1.2))
	if j < 10:
		var k := j - 6
		return Vector3(-sx * 0.5 + float(k % 2) * sx, y0 + 0.09, -sz * 0.45 + float(int(k / 2)) * (sz * 0.9))
	var m := j - 10
	return Vector3(-sx * 0.45 + float(m % 2) * sx * 0.9, y0 + 0.175, -sz * 0.3 + float(int(m / 2)) * (sz * 0.6))


static func _slot_item_local_pos(j: int) -> Vector3:
	if j < 6:
		return Vector3(-0.20 + float(j % 3) * 0.20, 0.075, -0.13 + float(int(j / 3)) * 0.26)
	if j < 10:
		var k := j - 6
		return Vector3(-0.10 + float(k % 2) * 0.20, 0.19, -0.07 + float(int(k / 2)) * 0.14)
	if j < 14:
		var k2 := j - 10
		return Vector3(-0.14 + float(k2 % 2) * 0.28, 0.29, -0.08 + float(int(k2 / 2)) * 0.16)
	var k3 := j - 14
	return Vector3(-0.07 + float(k3) * 0.14, 0.38, 0.0)


static func build_held_crate(item_id: String, count: int) -> Node3D:
	var n := Node3D.new()
	# Renkli plastik Türk pazar kasası
	var cc := Color(0.12, 0.46, 0.84)
	if item_id in ["domates", "elma"]:
		cc = Color(0.84, 0.22, 0.18) if item_id == "domates" else Color(0.18, 0.58, 0.26)
	elif item_id in ["karpuz", "patlican"]:
		cc = Color(0.16, 0.56, 0.24)
	elif item_id in ["muz", "sogan", "portakal"]:
		cc = Color(0.90, 0.66, 0.12)
	LP.add(n, LP.box(Vector3(0.42, 0.03, 0.34)), Vector3(0, -0.09, 0), cc.darkened(0.2), Vector3.ZERO, 0.55)
	LP.add(n, LP.box(Vector3(0.42, 0.18, 0.03)), Vector3(0, 0.0, 0.155), cc, Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.42, 0.18, 0.03)), Vector3(0, 0.0, -0.155), cc, Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.03, 0.18, 0.30)), Vector3(-0.195, 0.0, 0), cc.lightened(0.05), Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.03, 0.18, 0.30)), Vector3(0.195, 0.0, 0), cc.lightened(0.05), Vector3.ZERO, 0.52)
	if item_id != "" and ITEMS.has(item_id):
		for j in clampi(count, 0, 14):
			Produce.build_mesh(n, item_id, _crate_item_pos(j, 0.11, 0.08, -0.02), 0.052)
	return n


func set_owner_display_name(n: String) -> void:
	owner_name = n
	if _sign_label:
		_sign_label.text = n + " Tezgahı"


func customer_spot(slot_offset := 0.0) -> Vector3:
	return to_global(Vector3(slot_offset, 0.0, 1.55))


func owner_spawn_pos() -> Vector3:
	return to_global(Vector3(0.0, 0.15, -0.55))


func _refresh_slot_visual(idx: int) -> void:
	var s := slots[idx]
	var vis := _slot_visuals[idx]
	for c in vis.get_children():
		c.queue_free()
	var item_id: String = s["item"]
	var cnt: int = s["count"]
	var price: int = s["price"]
	var lbl := _slot_labels[idx]
	var blbl := _slot_back_labels[idx]
	var tag_mat := _slot_tag_mats[idx]
	if item_id == "" or cnt <= 0:
		lbl.text = "BOŞ"
		lbl.modulate = Color(0.45, 0.4, 0.35)
		blbl.text = "BOŞ"
		blbl.modulate = Color(0.45, 0.4, 0.35)
		tag_mat.albedo_color = Color(0.95, 0.92, 0.84)
		return
	var info: Dictionary = ITEMS[item_id]
	var txt := "%s\n%d TL (%d/%d)" % [info["name"], price, cnt, max_slot_count()]
	lbl.text = txt
	lbl.modulate = Color(0.1, 0.07, 0.04)
	blbl.text = txt
	blbl.modulate = Color(0.1, 0.07, 0.04)
	for j in mini(cnt, max_slot_count()):
		Produce.build_mesh(vis, item_id, _slot_item_local_pos(j), 0.082)
	_refresh_slot_price_color(idx)


func _refresh_slot_price_color(idx: int) -> void:
	var s := slots[idx]
	var item_id: String = s["item"]
	if item_id == "" or int(s["count"]) <= 0:
		_slot_tag_mats[idx].albedo_color = Color(0.95, 0.92, 0.84)
		return
	var all_stalls := _all_stalls()
	var ev := _active_event_item()
	var fp := fair_price(item_id, all_stalls, ev)
	var ratio := float(s["price"]) / maxf(fp, 1.0)
	if float(s["price"]) > gouge_ceiling(item_id, ev):
		_slot_tag_mats[idx].albedo_color = Color(1.0, 0.52, 0.48)
	elif ratio < 0.88:
		_slot_tag_mats[idx].albedo_color = Color(0.74, 0.96, 0.74)
	elif ratio <= 1.15:
		_slot_tag_mats[idx].albedo_color = Color(0.98, 0.95, 0.84)
	else:
		_slot_tag_mats[idx].albedo_color = Color(1.0, 0.80, 0.56)


func refresh_all_price_colors() -> void:
	for i in slots.size():
		_refresh_slot_price_color(i)


func update_crate_prices(prices: Dictionary, emergency_free := false) -> void:
	for item_id in _crate_labels:
		var lbl: Label3D = _crate_labels[item_id]
		var nm: String = ITEMS[item_id]["name"]
		var cost: int = 0 if (emergency_free and item_id == "sogan") else int(prices.get(item_id, ITEMS[item_id]["crate_cost"]))
		if emergency_free and item_id == "sogan":
			lbl.text = "%s\nVERESİYE (0 TL)" % nm
			lbl.modulate = Color(0.5, 1.0, 0.58)
		else:
			lbl.text = "%s\n%d TL (%d ad.)" % [nm, cost, crate_capacity()]
			lbl.modulate = Color(1.0, 0.96, 0.85)


func has_supply_crate(item_id: String) -> bool:
	return bool(crate_available.get(item_id, true))


func can_place(idx: int, item_id: String) -> bool:
	if idx < 0 or idx >= slots.size() or not ITEMS.has(item_id):
		return false
	var s := slots[idx]
	return (s["item"] == "" or s["count"] == 0 or s["item"] == item_id) and s["count"] < max_slot_count()


func has_item(item_id: String) -> bool:
	for s in slots:
		if s["item"] == item_id and s["count"] > 0:
			return true
	return false


func get_item_price(item_id: String) -> int:
	var best := 999999
	for s in slots:
		if s["item"] == item_id and s["count"] > 0:
			best = mini(best, int(s["price"]))
	return best if best < 999999 else int(ITEMS.get(item_id, {"base": 10})["base"])


func total_stock() -> int:
	var t := 0
	for s in slots:
		t += int(s["count"])
	return t


static func gouge_ceiling(item_id: String, event_item := "") -> float:
	var base: float = float(ITEMS.get(item_id, {"base": 10})["base"])
	if event_item != "" and item_id == event_item:
		base *= 1.42
	return base * GOUGE_RATIO


func find_price_gouging(all_stalls: Array, event_item := "") -> Dictionary:
	for s in slots:
		var item_id: String = s["item"]
		if item_id != "" and int(s["count"]) > 0:
			var ceil_p := gouge_ceiling(item_id, event_item)
			if float(s["price"]) > ceil_p:
				var fp := fair_price(item_id, all_stalls, event_item)
				return {"item": item_id, "price": int(s["price"]), "fair": roundi(fp)}
	return {}


func request_place(idx: int, item_id: String, from_world_pos := Vector3.ZERO) -> bool:
	if not can_place(idx, item_id):
		return false
	var s := slots[idx]
	var new_cnt := int(s["count"]) + 1
	var price: int = int(s["price"]) if s["item"] == item_id else int(ITEMS[item_id]["base"])
	if Net.online():
		rpc_place_animated.rpc(idx, item_id, new_cnt, price, from_world_pos)
	else:
		rpc_place_animated(idx, item_id, new_cnt, price, from_world_pos)
	return true


@rpc("any_peer", "call_local", "reliable")
func rpc_place_animated(idx: int, item_id: String, count: int, price: int, from_world_pos: Vector3) -> void:
	if idx < 0 or idx >= slots.size():
		return
	slots[idx] = {"item": item_id, "count": clampi(count, 0, max_slot_count()), "price": clampi(price, 1, 199)}
	if from_world_pos == Vector3.ZERO:
		_refresh_slot_visual(idx)
		return
	var vis := _slot_visuals[idx]
	var target_local := _slot_item_local_pos(clampi(count - 1, 0, max_slot_count() - 1))
	var target_world := vis.to_global(target_local)
	var mid_world := (from_world_pos + target_world) * 0.5 + Vector3(0.0, 0.34, 0.0)
	var fly := Produce.build_mesh(self, item_id, to_local(from_world_pos), 0.082)
	var p0 := to_local(from_world_pos)
	var p1 := to_local(mid_world)
	var p2 := to_local(target_world)
	Sfx.play_3d("place", target_world, self, -4.0, 0.92 + float(count % 5) * 0.05)
	var dur := 0.11 if has_upgrade("big_crate") else 0.16
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(fly):
			var u := 1.0 - t
			fly.position = u * u * p0 + 2.0 * u * t * p1 + t * t * p2
			fly.rotation.x = t * PI * 1.2
			fly.scale = Vector3.ONE * lerpf(0.72, 1.08, t)
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(fly):
			fly.queue_free()
		_refresh_slot_visual(idx)
		VFX.burst_dust(self, target_world, Color(1.0, 0.96, 0.85), 4)
	)


func request_adjust_price(idx: int, delta: int) -> void:
	if idx < 0 or idx >= slots.size():
		return
	var s := slots[idx]
	if s["item"] == "" or s["count"] <= 0:
		return
	var np := clampi(int(s["price"]) + delta, 1, 199)
	if np == int(s["price"]):
		return
	Sfx.play("price_up" if delta > 0 else "price_down", -7.0)
	if Net.online():
		rpc_sync_slot.rpc(idx, s["item"], int(s["count"]), np)
	else:
		rpc_sync_slot(idx, s["item"], int(s["count"]), np)


func consume_for_sale(item_id: String) -> int:
	var best_idx := -1
	var best_price := 999999
	for i in slots.size():
		var s := slots[i]
		if s["item"] == item_id and s["count"] > 0 and int(s["price"]) < best_price:
			best_price = int(s["price"])
			best_idx = i
	if best_idx < 0:
		return 0
	var s := slots[best_idx]
	var new_cnt := int(s["count"]) - 1
	var new_item: String = s["item"] if new_cnt > 0 else ""
	if Net.online():
		rpc_sync_slot.rpc(best_idx, new_item, new_cnt, int(s["price"]))
	else:
		rpc_sync_slot(best_idx, new_item, new_cnt, int(s["price"]))
	tip_scale()
	return best_price


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_slot(idx: int, item_id: String, count: int, price: int) -> void:
	if idx < 0 or idx >= slots.size():
		return
	slots[idx] = {"item": item_id, "count": clampi(count, 0, max_slot_count()), "price": clampi(price, 1, 199)}
	_refresh_slot_visual(idx)


func request_ring_bell() -> bool:
	if not has_upgrade("bell") or bell_cd > 0.0:
		return false
	if Net.online():
		rpc_ring_bell.rpc()
	else:
		rpc_ring_bell()
	return true


@rpc("any_peer", "call_local", "reliable")
func rpc_ring_bell() -> void:
	if not has_upgrade("bell") or bell_cd > 0.0:
		return
	bell_boost = 10.0
	bell_cd = 15.0
	var bell_pos := to_global(Vector3(-1.44, 0.78, 0.56))
	Sfx.play_3d("bell", bell_pos, self, 0.0, 1.0, 32.0)
	VFX.spawn_sound_ring(self, bell_pos, 5.5, Color(1.0, 0.85, 0.28))
	VFX.spawn_floating_text(self, bell_pos + Vector3(0, 0.55, 0), "🔔 GEL VATANDAŞ GEL!", Color(1.0, 0.88, 0.3), 38)
	if _bell_mesh:
		var tw := create_tween()
		tw.tween_property(_bell_mesh, "rotation:z", 0.35, 0.07)
		tw.tween_property(_bell_mesh, "rotation:z", -0.35, 0.10)
		tw.tween_property(_bell_mesh, "rotation:z", 0.2, 0.09)
		tw.tween_property(_bell_mesh, "rotation:z", 0.0, 0.08)


func apply_upgrade_synced(key: String) -> void:
	if Net.online():
		rpc_apply_upgrade.rpc(key)
	else:
		rpc_apply_upgrade(key)


@rpc("any_peer", "call_local", "reliable")
func rpc_apply_upgrade(key: String) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	if not UPGRADES.has(key) or has_upgrade(key):
		return
	upgrades[key] = true
	_show_upgrade_visual(key)
	var pos := to_global(Vector3(0, 1.4, 0.5))
	Sfx.play_3d("upgrade", pos, self, -1.0)
	VFX.burst_coins(self, pos, 14)
	VFX.spawn_floating_text(self, pos + Vector3(0, 0.6, 0), "⭐ " + str(UPGRADES[key]["name"]) + "!", Color(0.55, 1.0, 0.65), 40)
	for i in slots.size():
		_refresh_slot_visual(i)


func export_snapshot() -> Dictionary:
	return {
		"owner_id": owner_id,
		"owner_name": owner_name,
		"spot_idx": spot_idx,
		"slots": slots.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"bell_boost": bell_boost,
		"bell_cd": bell_cd,
		"has_radio": has_radio,
		"radio_playing": radio_playing,
	}


func apply_snapshot(d: Dictionary) -> void:
	if d.has("upgrades"):
		for k in d["upgrades"]:
			if bool(d["upgrades"][k]) and not has_upgrade(k):
				upgrades[k] = true
				_show_upgrade_visual(k)
	if d.has("slots"):
		var arr: Array = d["slots"]
		for i in mini(arr.size(), slots.size()):
			slots[i] = arr[i].duplicate()
			_refresh_slot_visual(i)
	bell_boost = float(d.get("bell_boost", 0.0))
	bell_cd = float(d.get("bell_cd", 0.0))
	rpc_set_stall_radio(bool(d.get("has_radio", false)), bool(d.get("radio_playing", false)))


func _all_stalls() -> Array:
	return get_parent().get_children() if get_parent() else []


func _active_event_item() -> String:
	var w := get_parent().get_parent() if get_parent() else null
	return str(w.get_meta("event_item", "")) if w else ""


static func fair_price(item_id: String, all_stalls: Array, event_item := "") -> float:
	var base: float = float(ITEMS.get(item_id, {"base": 10})["base"])
	if event_item != "" and item_id == event_item:
		base *= 1.42
	var sum_p := 0.0
	var n := 0
	for st in all_stalls:
		if st.has_item(item_id):
			sum_p += float(st.get_item_price(item_id))
			n += 1
	var market_avg := (sum_p / float(n)) if n > 0 else base
	return lerpf(base, market_avg, 0.55)


static func relative_price_score(item_id: String, price: int, all_stalls: Array, event_item := "") -> float:
	var ref := fair_price(item_id, all_stalls, event_item)
	var ratio := float(price) / maxf(ref, 1.0)
	if absf(ratio - 1.0) <= 0.12:
		return 1.0 - (ratio - 1.0) * 0.35
	if ratio < 0.88:
		return clampf(1.04 + (0.88 - ratio) * 0.78, 1.0, 1.30)
	return clampf(0.96 - (ratio - 1.12) * 0.92, 0.04, 0.96)
