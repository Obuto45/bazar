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
const SLOT_SPACING := 0.8
const KEEPOUT_BACK := -1.3 # NPC yasak bölgesi: tezgah + arka alan (yerel z)
const KEEPOUT_FRONT := 1.2
const MAX_SLOT_COUNT := 10
const CRATE_CAPACITY := 10
const GOUGE_RATIO := 1.75
# Tazelik: el sürülmemiş bir yuva 300 sn'lik pazar gününün sonunda ~0.35'e iner (ürünün "shelf" çarpanıyla).
const FRESH_DECAY := 0.65 / 300.0
const FRESH_SYNC_SEC := 1.0
const ROTTEN := 0.45
const SPRAY_AMOUNT := 0.35
const REP_MAX := 5.0
const PILE_W := 0.68
const PILE_D := 0.58

var owner_id := 0
var owner_name := ""
var spot_idx := 0
var awning_color := Color(0.14, 0.44, 0.80)
var slots: Array[Dictionary] = []
var expansion_level := 0 # 0: 4 yuva, 1: 6 yuva, 2: 8 yuva (tezgah fiziksel olarak genişler)
var _built: Array = [] # _build_all'ın eklediği çocuklar (genişlemede yeniden kurulur)
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

# İtibar (0..5 yıldız, host yetkili) ve tazelik görselleri
var reputation := 2.5
var _rep_label: Label3D
var _fresh_sync_t := 0.0
var _fresh_vis_t := 0.0
var _stink_cd := 1.0
var _slot_piles: Array = [] # her yuva için {"item", "root", "xf"} veya {}
var _slot_tags: Array[Node3D] = []
var _slot_price_labels: Array[Label3D] = []
var _slot_back_price_labels: Array[Label3D] = []
var _slot_overlays: Array[StandardMaterial3D] = []
var _slot_fresh_bars: Array[MeshInstance3D] = []
var _slot_fresh_mats: Array[StandardMaterial3D] = []
var _slot_flies: Array[Node3D] = []
var last_sale_pos := Vector3.ZERO
var last_sale_ms := -100000


func setup(p_owner_id: int, p_owner_name: String, color_idx: int, p_spot_idx := 0) -> void:
	owner_id = p_owner_id
	owner_name = p_owner_name
	spot_idx = p_spot_idx
	awning_color = AWNINGS[absi(color_idx) % AWNINGS.size()]
	name = "Stall_%d" % owner_id


func _ready() -> void:
	slots.clear()
	for i in 4 + 2 * expansion_level:
		slots.append({"item": "", "count": 0, "price": 10, "fresh": 1.0})
	add_to_group("stall_keepout")
	_build_all()
	for k in upgrades:
		if bool(upgrades[k]):
			_show_upgrade_visual(k)


func _build_all() -> void:
	var n0 := get_child_count()
	_build_geometry()
	_build_slots()
	_build_scale()
	_build_upgrade_board()
	_build_upgrade_attachments()
	_build_radio_slot()
	_built = get_children().slice(n0)


## Tezgah tablası yarı genişliği: 1.77 / 2.57 / 3.37
func half_width() -> float:
	return 1.77 + 0.8 * float(expansion_level)


func _slot_x(i: int) -> float:
	return (float(i) - float(slots.size() - 1) * 0.5) * SLOT_SPACING


## Tezgahı 6 (seviye 1) / 8 (seviye 2) yuvaya genişletir; mevcut yuva içerikleri korunur.
@rpc("any_peer", "call_local", "reliable")
func rpc_set_expansion(level: int) -> void:
	level = clampi(level, 0, 2)
	if level <= expansion_level:
		return
	expansion_level = level
	if not is_node_ready():
		return # _ready doğru boyutta kurar
	while slots.size() < 4 + 2 * level:
		slots.append({"item": "", "count": 0, "price": 10, "fresh": 1.0})
	for n in _built:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_build_all()
	for k in upgrades:
		if bool(upgrades[k]):
			_show_upgrade_visual(k)
	for i in slots.size():
		_apply_fresh_visual(i)
	rpc_set_stall_radio(has_radio, radio_playing)
	VFX.burst_dust(self, to_global(Vector3(0, 0.6, 0.3)), Color(0.8, 0.7, 0.5), 10)


## NPC'leri tezgah + arka alan dışında tutar: dünya konumunu footprint dışına iter (y korunur).
func keepout_push(p: Vector3) -> Vector3:
	var l := to_local(p)
	var hx := half_width() + 0.25
	if absf(l.x) >= hx or l.z <= KEEPOUT_BACK or l.z >= KEEPOUT_FRONT:
		return p
	var dl := l.x + hx
	var dr := hx - l.x
	var db := l.z - KEEPOUT_BACK
	var df := KEEPOUT_FRONT - l.z
	var m := minf(minf(dl, dr), minf(db, df))
	if m == df:
		l.z = KEEPOUT_FRONT
	elif m == dl:
		l.x = -hx
	elif m == dr:
		l.x = hx
	else:
		l.z = KEEPOUT_BACK
	var out := to_global(l)
	out.y = p.y
	return out


## NPC yönlendirme: `dir` (yatay, normalize) yönünde ~1 m ileride yasak bölge varsa tezgahın kenarı boyunca dolan.
static func steer_all(from: Node, pos: Vector3, dir: Vector3, look := 1.0) -> Vector3:
	if from == null or not from.is_inside_tree():
		return dir
	var ahead := pos + dir * minf(look, 1.0)
	for st in from.get_tree().get_nodes_in_group("stall_keepout"):
		var l: Vector3 = st.to_local(ahead)
		var hx: float = st.half_width() + 0.45
		if absf(l.x) < hx and l.z > KEEPOUT_BACK - 0.3 and l.z < KEEPOUT_FRONT + 0.3:
			var ax: Vector3 = st.global_transform.basis.x
			ax.y = 0.0
			ax = ax.normalized()
			var side := signf(dir.dot(ax))
			if absf(dir.dot(ax)) < 0.25:
				side = 1.0 if st.to_local(pos).x >= 0.0 else -1.0
			return (ax * side + dir * 0.15).normalized()
	return dir


## Tüm tezgahların yasak bölgesinden dışarı iter. `from`: ağaçtaki herhangi bir düğüm.
static func keepout_all(from: Node, p: Vector3) -> Vector3:
	if from == null or not from.is_inside_tree():
		return p
	for st in from.get_tree().get_nodes_in_group("stall_keepout"):
		p = st.keepout_push(p)
	return p


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
	_tick_freshness(dt)
	_animate_flies()


func _is_host() -> bool:
	return not Net.online() or multiplayer.is_server()


func _day_paused() -> bool:
	var m := get_parent().get_parent().get_parent() if get_parent() and get_parent().get_parent() else null
	return m != null and "day_ended" in m and bool(m.day_ended)


## Tüm eşler tazeliği yerelde akıcı düşürür; host her ~1 sn'de yetkili değerleri yayınlar.
func _tick_freshness(dt: float) -> void:
	if not _day_paused():
		for i in slots.size():
			var s := slots[i]
			if str(s["item"]) == "" or int(s["count"]) <= 0:
				continue
			var shelf := float(ITEMS.get(s["item"], {}).get("shelf", 1.0))
			s["fresh"] = maxf(float(s.get("fresh", 1.0)) - FRESH_DECAY * shelf * dt, 0.0)
	if _is_host() and Net.online():
		_fresh_sync_t += dt
		if _fresh_sync_t >= FRESH_SYNC_SEC:
			_fresh_sync_t = 0.0
			rpc_sync_freshness.rpc(_fresh_values(), false)
	_fresh_vis_t -= dt
	if _fresh_vis_t <= 0.0:
		_fresh_vis_t = 0.2
		for i in slots.size():
			_apply_fresh_visual(i)
	# Çürüyen yuvalardan ara sıra yeşilimsi koku bulutu
	_stink_cd -= dt
	if _stink_cd <= 0.0:
		_stink_cd = randf_range(1.2, 2.2)
		for i in slots.size():
			var s := slots[i]
			if int(s["count"]) > 0 and float(s.get("fresh", 1.0)) < ROTTEN and randf() < 0.6:
				VFX.burst_dust(self, _slot_visuals[i].global_position + Vector3(randf_range(-0.2, 0.2), 0.32, 0.0), Color(0.56, 0.62, 0.24), 3)


func _fresh_values() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for s in slots:
		arr.append(float(s.get("fresh", 1.0)))
	return arr


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_freshness(vals: PackedFloat32Array, sparkle := false) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	for i in mini(vals.size(), slots.size()):
		slots[i]["fresh"] = clampf(vals[i], 0.0, 1.0)
		_apply_fresh_visual(i)
	if sparkle:
		_spray_fx()


## Tazelik görseli: ürün kararır/büzülür, etiket altındaki bar yeşilden kırmızıya döner, çürüyünce sinek uçuşur.
func _apply_fresh_visual(idx: int) -> void:
	if idx >= _slot_overlays.size():
		return
	var s := slots[idx]
	var f := float(s.get("fresh", 1.0))
	var stocked := str(s["item"]) != "" and int(s["count"]) > 0
	var ov := _slot_overlays[idx]
	ov.albedo_color.a = clampf((0.92 - f) * 0.78, 0.0, 0.62)
	var pile: Dictionary = _slot_piles[idx]
	if not pile.is_empty() and is_instance_valid(pile["root"]):
		var k := lerpf(0.88, 1.0, clampf(f / 0.8, 0.0, 1.0))
		(pile["root"] as Node3D).scale = Vector3(k, k * lerpf(0.86, 1.0, clampf(f / 0.8, 0.0, 1.0)), k)
	var bar := _slot_fresh_bars[idx]
	bar.visible = stocked
	bar.scale.x = maxf(f, 0.02)
	bar.position.x = -0.135 * (1.0 - maxf(f, 0.02))
	var bc := Color(0.92, 0.2, 0.14).lerp(Color(1.0, 0.8, 0.16), clampf(f / 0.55, 0.0, 1.0))
	if f > 0.55:
		bc = Color(1.0, 0.8, 0.16).lerp(Color(0.3, 0.9, 0.3), clampf((f - 0.55) / 0.35, 0.0, 1.0))
	_slot_fresh_mats[idx].albedo_color = bc
	_slot_fresh_mats[idx].emission = bc
	_slot_flies[idx].visible = stocked and f < ROTTEN


func _animate_flies() -> void:
	for i in _slot_flies.size():
		var fl := _slot_flies[i]
		if not fl.visible:
			continue
		var t := _anim_t * 3.2 + float(i) * 1.7
		var k := 0
		for c in fl.get_children():
			var ph := t * (1.0 + float(k) * 0.23) + float(k) * 2.1
			(c as Node3D).position = Vector3(cos(ph) * 0.2, 0.08 + sin(ph * 2.3) * 0.06, sin(ph * 1.3) * 0.16)
			k += 1


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

	var hw := half_width()
	var tw := hw * 2.0
	LP.add_mat(self, LP.box(Vector3(tw - 0.14, 0.52, 0.92)), Vector3(0, 0.26, 0.25), wood_m)
	LP.add(self, LP.box(Vector3(tw - 0.08, 0.08, 0.96)), Vector3(0, 0.06, 0.25), WOOD.darkened(0.24))
	LP.add_mat(self, LP.box(Vector3(tw, 0.06, 1.04)), Vector3(0, 0.545, 0.25), top_m)
	for i in slots.size():
		LP.add(self, LP.box(Vector3(0.06, 0.48, 0.03)), Vector3(_slot_x(i) * 1.03, 0.27, 0.72), WOOD.darkened(0.18))
	LP.solid(self, Vector3(0, 0.285, 0.25), Vector3(tw, 0.57, 1.04))

	# Galvaniz çelik pazarcı direkleri
	for x in [-(hw - 0.15), hw - 0.15]:
		for z in [-0.75, 0.85]:
			LP.add(self, LP.cyl(0.042, 0.048, 2.88, 6), Vector3(x, 1.44, z), STEEL, Vector3.ZERO, 0.42, 0.7)
		LP.add(self, LP.box(Vector3(0.05, 0.05, 1.62)), Vector3(x, 2.74, 0.05), STEEL, Vector3.ZERO, 0.42, 0.7)
	LP.add(self, LP.box(Vector3(tw - 0.18, 0.06, 0.06)), Vector3(0, 2.78, 0.85), STEEL, Vector3.ZERO, 0.42, 0.7)

	# Çizgili dokulu branda tente (genişlemede şerit sayısı artar)
	var ns := 5 + 2 * expansion_level
	var sw := (tw + 0.11) / float(ns)
	for i in ns:
		var m := tarp_a if i % 2 == 0 else tarp_w
		LP.add_mat(self, LP.box(Vector3(sw, 0.05, 2.18)), Vector3(-(tw + 0.11) * 0.5 + sw * (float(i) + 0.5), 2.93, 0.12), m, Vector3(0.18, 0, 0))
	LP.add_mat(self, LP.box(Vector3(tw + 0.14, 0.22, 0.04)), Vector3(0, 2.71, 1.17), tarp_a)
	var nf := 9 + 4 * expansion_level
	for i in nf:
		var fc := awning_color.darkened(0.12) if i % 2 == 0 else Color(0.96, 0.94, 0.88)
		LP.add(self, LP.prism(Vector3((tw - 0.12) / float(nf), 0.13, 0.04)), Vector3(-(tw - 0.12) * 0.5 + (tw - 0.12) / float(nf) * (float(i) + 0.5), 2.55, 1.17), fc, Vector3(0, 0, PI))

	_sign_label = Label3D.new()
	_sign_label.text = (owner_name + " Tezgahı") if owner_name != "" else "Tezgah"
	_sign_label.position = Vector3(0, 2.72, 1.22)
	_sign_label.font_size = 34
	_sign_label.outline_size = 8
	_sign_label.modulate = Color(1.0, 0.96, 0.84)
	add_child(_sign_label)

	# İtibar yıldızları: tabelanın üstünde, uzaktan okunur altın yıldızlar
	_rep_label = Label3D.new()
	_rep_label.position = Vector3(0, 3.02, 1.2)
	_rep_label.font_size = 40
	_rep_label.pixel_size = 0.0042
	_rep_label.outline_size = 10
	_rep_label.outline_modulate = Color(0.22, 0.12, 0.02)
	add_child(_rep_label)
	_refresh_rep_label()


func _build_scale() -> void:
	var sc := Node3D.new()
	sc.position = Vector3(half_width() - 0.33, 0.58, 0.56)
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
	b.position = Vector3(-(half_width() - 0.09), 1.24, 0.05)
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
	_radio_node.position = Vector3(half_width() - 0.25, 0.58, -0.05)
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


## Tezgah radyosunda şarkı değiştir (herkes aynı şarkıyı duyar). Yeni şarkının adını döndürür.
func step_radio_synced(dir: int) -> String:
	var idx := Sfx.radio_step_idx(_radio_audio, dir)
	if Net.online():
		rpc_set_radio_track.rpc(idx)
	else:
		rpc_set_radio_track(idx)
	return Sfx.radio_title(idx)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_radio_track(idx: int) -> void:
	Sfx.radio_set(_radio_audio, idx)


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
	mega.position = Vector3(-(half_width() - 0.15), 2.52, 0.92)
	mega.rotation = Vector3(-0.1, 0.25, 0.0)
	LP.add(mega, LP.cyl(0.05, 0.16, 0.32, 8), Vector3(0, 0, 0.14), Color(0.92, 0.24, 0.18), Vector3(PI / 2, 0, 0), 0.35, 0.2)
	LP.add(mega, LP.torus(0.14, 0.17, 10, 5), Vector3(0, 0, 0.30), BRASS, Vector3(PI / 2, 0, 0), 0.25, 0.8)
	LP.add(mega, LP.box(Vector3(0.07, 0.14, 0.07)), Vector3(0, -0.09, 0.02), Color(0.2, 0.2, 0.22))
	mega.hide()
	add_child(mega)
	_upgrade_visuals["megaphone"] = mega

	var lights := Node3D.new()
	var nb := 7 + 3 * expansion_level
	for i in nb:
		var lx := -(half_width() - 0.27) + float(i) * (half_width() * 2.0 - 0.54) / float(nb - 1)
		var col := Color(1.0, 0.84, 0.36) if i % 2 == 0 else Color(1.0, 0.6, 0.28)
		var bulb := LP.add(lights, LP.sphere(0.062, 6, 4), Vector3(lx, 2.48, 1.18), col, Vector3.ZERO, 0.15)
		var bm := bulb.material_override as StandardMaterial3D
		bm.emission_enabled = true
		bm.emission = col
		bm.emission_energy_multiplier = 2.2
		_light_bulbs.append(bm)
	LP.add(lights, LP.box(Vector3(half_width() * 2.0 + 0.14, 0.05, 0.06)), Vector3(0, 2.84, 1.19), BRASS, Vector3.ZERO, 0.25, 0.8)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 2.44, 0.72)
	glow.light_color = Color(1.0, 0.82, 0.45)
	glow.light_energy = 1.45
	glow.omni_range = 5.5
	lights.add_child(glow)
	lights.hide()
	add_child(lights)
	_upgrade_visuals["lights"] = lights

	var big := Node3D.new()
	LP.add(big, LP.box(Vector3(half_width() * 2.0 + 0.02, 0.05, 0.16)), Vector3(0, 0.58, 0.78), BRASS.darkened(0.15), Vector3.ZERO, 0.35, 0.6)
	LP.add(big, LP.box(Vector3(0.45, 0.26, 0.36)), Vector3(half_width() - 0.15, 0.14, -0.35), WOOD.lightened(0.1))
	big.hide()
	add_child(big)
	_upgrade_visuals["big_crate"] = big

	var bell := Node3D.new()
	bell.position = Vector3(-(half_width() - 0.33), 0.58, 0.56)
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
	_slot_piles.clear()
	_slot_tags.clear()
	_slot_price_labels.clear()
	_slot_back_price_labels.clear()
	_slot_overlays.clear()
	_slot_fresh_bars.clear()
	_slot_fresh_mats.clear()
	_slot_flies.clear()
	var crate_cols := [Color(0.12, 0.44, 0.82), Color(0.18, 0.56, 0.26), Color(0.84, 0.24, 0.18), Color(0.88, 0.66, 0.14)]
	var fly_mesh := LP.sphere(0.012, 4, 3)
	var fly_mat := LP.mat(Color(0.05, 0.05, 0.06), 0.4)
	var bar_mesh := LP.box(Vector3(0.27, 0.018, 0.016))
	for i in slots.size():
		var sx: float = _slot_x(i)
		var cc: Color = crate_cols[i % crate_cols.size()]
		# Plastik pazar kasası tepsisi (alçak kenarlı: yığın taşar gibi görünsün)
		LP.add(self, LP.box(Vector3(0.72, 0.04, 0.66)), Vector3(sx, 0.59, 0.24), cc.darkened(0.22), Vector3.ZERO, 0.55)
		LP.add(self, LP.box(Vector3(0.74, 0.07, 0.04)), Vector3(sx, 0.62, 0.56), cc, Vector3.ZERO, 0.52)
		LP.add(self, LP.box(Vector3(0.74, 0.07, 0.04)), Vector3(sx, 0.62, -0.08), cc, Vector3.ZERO, 0.52)
		LP.add(self, LP.box(Vector3(0.04, 0.07, 0.64)), Vector3(sx - 0.35, 0.62, 0.24), cc.darkened(0.08), Vector3.ZERO, 0.52)
		LP.add(self, LP.box(Vector3(0.04, 0.07, 0.64)), Vector3(sx + 0.35, 0.62, 0.24), cc.darkened(0.08), Vector3.ZERO, 0.52)
		var vis := Node3D.new()
		vis.position = Vector3(sx, 0.61, 0.24)
		add_child(vis)
		_slot_visuals.append(vis)
		_slot_piles.append({})

		var ov := StandardMaterial3D.new()
		ov.albedo_color = Color(0.24, 0.17, 0.06, 0.0)
		ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_slot_overlays.append(ov)

		# Çürüyünce vızıldayan sinekler
		var flies := Node3D.new()
		flies.position = Vector3(0, 0.3, 0)
		for k in 4:
			var fmi := MeshInstance3D.new()
			fmi.mesh = fly_mesh
			fmi.material_override = fly_mat
			fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flies.add_child(fmi)
		flies.hide()
		vis.add_child(flies)
		_slot_flies.append(flies)

		# Pazar usulü fiyat kartonu: ürüne saplanmış çubukta, hafif geriye yatık
		LP.add(self, LP.cyl(0.009, 0.011, 0.12, 5), Vector3(sx + 0.2, 0.64, 0.6), WOOD.darkened(0.3))
		var tag := Node3D.new()
		tag.position = Vector3(sx + 0.2, 0.74, 0.6)
		tag.rotation.x = -0.32
		add_child(tag)
		_slot_tags.append(tag)
		# Koyu çerçeve kartonun içinde kalır (yalnızca kenarı görünür) — yüzeylerde z-fighting olmaz
		LP.add(tag, LP.box(Vector3(0.33, 0.185, 0.012)), Vector3.ZERO, Color(0.2, 0.14, 0.08))
		var tag_mi := LP.add(tag, LP.box(Vector3(0.31, 0.165, 0.018)), Vector3.ZERO, Color(0.98, 0.95, 0.84))
		_slot_tag_mats.append(tag_mi.material_override as StandardMaterial3D)
		var lbl := _make_tag_label(tag, Vector3(0, 0.05, 0.0115), 15, false)
		_slot_labels.append(lbl)
		var plbl := _make_tag_label(tag, Vector3(0, -0.022, 0.0115), 34, false)
		_slot_price_labels.append(plbl)
		var blbl := _make_tag_label(tag, Vector3(0, 0.05, -0.0115), 15, true)
		_slot_back_labels.append(blbl)
		var bplbl := _make_tag_label(tag, Vector3(0, -0.022, -0.0115), 34, true)
		_slot_back_price_labels.append(bplbl)
		# Tazelik barı (karton altında, iki yüzden de görünür)
		LP.add(tag, LP.box(Vector3(0.29, 0.026, 0.012)), Vector3(0, -0.108, 0), Color(0.12, 0.1, 0.08))
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.3, 0.9, 0.3)
		fm.emission_enabled = true
		fm.emission = Color(0.3, 0.9, 0.3)
		fm.emission_energy_multiplier = 0.45
		fm.roughness = 0.5
		var bar := MeshInstance3D.new()
		bar.mesh = bar_mesh
		bar.material_override = fm
		bar.position = Vector3(0, -0.108, 0)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tag.add_child(bar)
		_slot_fresh_bars.append(bar)
		_slot_fresh_mats.append(fm)

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
		sh.size = Vector3(0.78, 0.6, 0.86)
		cs.shape = sh
		area.add_child(cs)
		add_child(area)
		_refresh_slot_visual(i)


func _make_tag_label(parent: Node3D, pos: Vector3, fsize: int, back: bool) -> Label3D:
	var l := Label3D.new()
	l.position = pos
	if back:
		l.rotation.y = PI
	l.font_size = fsize
	l.pixel_size = 0.0022
	l.outline_size = 4 if fsize < 30 else 6
	l.double_sided = false
	l.modulate = Color(0.12, 0.08, 0.05)
	l.outline_modulate = Color(1.0, 0.97, 0.88)
	parent.add_child(l)
	return l


## Eski API (tekil ürün yerleşimi) — geriye uyumluluk için korunur.
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


## Elde/fırlatılan plastik pazar kasası: içinde stokla orantılı küçülen bir ürün yığını.
static func build_held_crate(item_id: String, count: int, capacity := 0) -> Node3D:
	var n := Node3D.new()
	# Renkli plastik Türk pazar kasası
	var cc := Color(0.12, 0.46, 0.84)
	if item_id in ["domates", "elma", "cilek"]:
		cc = Color(0.84, 0.22, 0.18) if item_id != "elma" else Color(0.18, 0.58, 0.26)
	elif item_id in ["karpuz", "patlican", "salatalik", "biber"]:
		cc = Color(0.16, 0.56, 0.24)
	elif item_id in ["muz", "sogan", "portakal", "limon"]:
		cc = Color(0.90, 0.66, 0.12)
	LP.add(n, LP.box(Vector3(0.42, 0.03, 0.34)), Vector3(0, -0.09, 0), cc.darkened(0.2), Vector3.ZERO, 0.55)
	LP.add(n, LP.box(Vector3(0.42, 0.18, 0.03)), Vector3(0, 0.0, 0.155), cc, Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.42, 0.18, 0.03)), Vector3(0, 0.0, -0.155), cc, Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.03, 0.18, 0.30)), Vector3(-0.195, 0.0, 0), cc.lightened(0.05), Vector3.ZERO, 0.52)
	LP.add(n, LP.box(Vector3(0.03, 0.18, 0.30)), Vector3(0.195, 0.0, 0), cc.lightened(0.05), Vector3.ZERO, 0.52)
	# Tutma delikleri (koyu kulp yuvaları)
	for sx: float in [-1.0, 1.0]:
		LP.add(n, LP.box(Vector3(0.012, 0.035, 0.11)), Vector3(sx * 0.212, 0.045, 0), cc.darkened(0.55))
	if item_id != "" and ITEMS.has(item_id) and count > 0:
		var xf := Produce.pile_layout(item_id, 0.36, 0.28, 3, 0.62, 3)
		var cap := maxi(capacity if capacity > 0 else CRATE_CAPACITY, count)
		var pile := Produce.build_pile(n, item_id, xf, Produce.pile_visible_for(count, cap, xf.size()))
		pile.position = Vector3(0, -0.075, 0)
	return n


func set_owner_display_name(n: String) -> void:
	owner_name = n
	if _sign_label:
		_sign_label.text = n + " Tezgahı"


func customer_spot(slot_offset := 0.0) -> Vector3:
	var lim := half_width() - 0.35
	return to_global(Vector3(clampf(slot_offset, -lim, lim), 0.0, 1.55))


## n. müşteri için ön sıradaki ofset (geniş tezgahta daha çok yer: 3 / 5 / 7 nokta).
func spot_offset(n: int) -> float:
	var cnt := 3 + 2 * expansion_level
	return (float(n % cnt) - float(cnt - 1) * 0.5) * 0.68


func owner_spawn_pos() -> Vector3:
	return to_global(Vector3(0.0, 0.15, -0.55))


## Yuva görseli: ürün yığını (MultiMesh) yalnızca ürün değişince yeniden kurulur; stok değişince
## görünür adet ayarlanır, böylece yığın tepeden eriyerek azalır.
func _refresh_slot_visual(idx: int) -> void:
	var s := slots[idx]
	if not s.has("fresh"):
		s["fresh"] = 1.0
	var vis := _slot_visuals[idx]
	var item_id: String = s["item"]
	var cnt: int = s["count"]
	var price: int = s["price"]
	var lbl := _slot_labels[idx]
	var blbl := _slot_back_labels[idx]
	var plbl := _slot_price_labels[idx]
	var bplbl := _slot_back_price_labels[idx]
	var pile: Dictionary = _slot_piles[idx]
	if item_id == "" or cnt <= 0:
		if not pile.is_empty():
			Produce.set_pile_visible(pile["root"], 0)
		lbl.text = "BOŞ"
		lbl.modulate = Color(0.45, 0.4, 0.35)
		blbl.text = "BOŞ YUVA"
		blbl.modulate = Color(0.45, 0.4, 0.35)
		plbl.text = "—"
		bplbl.text = "—"
		plbl.modulate = Color(0.45, 0.4, 0.35)
		bplbl.modulate = Color(0.45, 0.4, 0.35)
		_slot_tag_mats[idx].albedo_color = Color(0.95, 0.92, 0.84)
		_apply_fresh_visual(idx)
		return
	if pile.is_empty() or str(pile["item"]) != item_id or not is_instance_valid(pile["root"]):
		if not pile.is_empty() and is_instance_valid(pile["root"]):
			(pile["root"] as Node3D).queue_free()
		var xf := Produce.pile_layout(item_id, PILE_W, PILE_D, 3, 1.0, spot_idx * 4 + idx)
		var root := Produce.build_pile(vis, item_id, xf, 0)
		Produce.set_pile_overlay(root, _slot_overlays[idx])
		pile = {"item": item_id, "root": root, "xf": xf}
		_slot_piles[idx] = pile
	var xfs: Array = pile["xf"]
	Produce.set_pile_visible(pile["root"], Produce.pile_visible_for(cnt, max_slot_count(), xfs.size()))
	var info: Dictionary = ITEMS[item_id]
	lbl.text = str(info["name"])
	lbl.modulate = Color(0.1, 0.07, 0.04)
	blbl.text = "%s  %d/%d" % [info["name"], cnt, max_slot_count()]
	blbl.modulate = Color(0.1, 0.07, 0.04)
	plbl.text = "%d TL" % price
	bplbl.text = "%d TL" % price
	plbl.modulate = Color(0.62, 0.06, 0.04)
	bplbl.modulate = Color(0.62, 0.06, 0.04)
	_refresh_slot_price_color(idx)
	_apply_fresh_visual(idx)


## Yuvanın görünür en üst ürününün yerel konumu (vis düğümüne göre).
func _pile_top_local(idx: int, cnt: int) -> Vector3:
	var pile: Dictionary = _slot_piles[idx]
	if pile.is_empty():
		return Vector3(0, 0.1, 0)
	var xfs: Array = pile["xf"]
	var n := Produce.pile_visible_for(cnt, max_slot_count(), xfs.size())
	if n <= 0:
		return Vector3(0, 0.08, 0)
	return (xfs[n - 1] as Transform3D).origin


## Yerleştirme/satış anında kasa yığınına küçük squash & stretch.
func _squash_slot(idx: int, strength := 1.0) -> void:
	var vis := _slot_visuals[idx]
	if vis.has_meta("sq_tw"):
		var old: Tween = vis.get_meta("sq_tw")
		if old and old.is_valid():
			old.kill()
	vis.scale = Vector3(1.0 + 0.07 * strength, 1.0 - 0.12 * strength, 1.0 + 0.07 * strength)
	var tw := create_tween()
	tw.tween_property(vis, "scale", Vector3(1.0 - 0.03 * strength, 1.0 + 0.06 * strength, 1.0 - 0.03 * strength), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(vis, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	vis.set_meta("sq_tw", tw)


func _wobble_tag(idx: int, up: bool) -> void:
	if idx >= _slot_tags.size():
		return
	var tag := _slot_tags[idx]
	var tw := create_tween()
	tag.scale = Vector3.ONE * (1.12 if up else 0.92)
	tw.set_parallel()
	tw.tween_property(tag, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tag, "rotation:z", 0.0, 0.3).from(0.12 if up else -0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Satılan (veya çalınan) ürün yığının tepesinden zıplayıp müşteri tarafına uçar.
func _sale_pop(idx: int, item_id: String, old_cnt: int) -> void:
	var vis := _slot_visuals[idx]
	var top_local := _pile_top_local(idx, old_cnt)
	var start := vis.to_global(top_local)
	last_sale_pos = start
	last_sale_ms = Time.get_ticks_msec()
	_squash_slot(idx, 0.6)
	if not is_inside_tree():
		return
	var hop := Produce.build_mesh(self, item_id, to_local(start), 0.082)
	var p0 := hop.position
	var p2 := to_local(start + global_transform.basis.z * 0.75 + Vector3(0, 0.15, 0))
	var p1 := (p0 + p2) * 0.5 + Vector3(0, 0.45, 0)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(hop):
			var u := 1.0 - t
			hop.position = u * u * p0 + 2.0 * u * t * p1 + t * t * p2
			hop.rotation = Vector3(t * 4.0, t * 2.0, 0.0)
			hop.scale = Vector3.ONE * lerpf(1.1, 0.05, t * t)
	, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(hop):
			hop.queue_free()
	)


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
	var old_cnt := int(s["count"]) if s["item"] == item_id else 0
	var new_cnt := old_cnt + 1
	var price: int = int(s["price"]) if s["item"] == item_id else int(ITEMS[item_id]["base"])
	# Taze kasa (1.0) mevcut stokla ağırlıklı ortalanır
	var old_f := float(s.get("fresh", 1.0)) if old_cnt > 0 else 1.0
	var fresh := (old_f * float(old_cnt) + 1.0) / float(new_cnt)
	if Net.online():
		rpc_place_animated.rpc(idx, item_id, new_cnt, price, from_world_pos, fresh)
	else:
		rpc_place_animated(idx, item_id, new_cnt, price, from_world_pos, fresh)
	return true


@rpc("any_peer", "call_local", "reliable")
func rpc_place_animated(idx: int, item_id: String, count: int, price: int, from_world_pos: Vector3, fresh := 1.0) -> void:
	if idx < 0 or idx >= slots.size() or (item_id != "" and not ITEMS.has(item_id)):
		return
	slots[idx] = {"item": item_id, "count": clampi(count, 0, max_slot_count()), "price": clampi(price, 1, 199), "fresh": clampf(fresh, 0.0, 1.0)}
	if from_world_pos == Vector3.ZERO or not is_inside_tree():
		_refresh_slot_visual(idx)
		return
	var vis := _slot_visuals[idx]
	# Yığın kurulu değilse (yeni ürün) önce kur ki hedef tepe noktası doğru olsun
	var pile: Dictionary = _slot_piles[idx]
	if pile.is_empty() or str(pile["item"]) != item_id:
		_refresh_slot_visual(idx)
		Produce.set_pile_visible(_slot_piles[idx]["root"], Produce.pile_visible_for(count - 1, max_slot_count(), (_slot_piles[idx]["xf"] as Array).size()) if count > 1 else 0)
	var target_world := vis.to_global(_pile_top_local(idx, count))
	var mid_world := (from_world_pos + target_world) * 0.5 + Vector3(0.0, 0.34, 0.0)
	var fly := Produce.build_mesh(self, item_id, to_local(from_world_pos), 0.082)
	var p0 := to_local(from_world_pos)
	var p1 := to_local(mid_world)
	var p2 := to_local(target_world)
	var dur := 0.11 if has_upgrade("big_crate") else 0.16
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(fly):
			var u := 1.0 - t
			fly.position = u * u * p0 + 2.0 * u * t * p1 + t * t * p2
			fly.rotation.x = t * PI * 1.2
			# uçarken uzar (stretch), inerken toplanır
			var st := 1.0 + sin(t * PI) * 0.22
			fly.scale = Vector3(1.0 / sqrt(st), st, 1.0 / sqrt(st)) * lerpf(0.72, 1.05, t)
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(fly):
			fly.queue_free()
		_refresh_slot_visual(idx)
		_squash_slot(idx, 1.0)
		Sfx.play_3d("place", target_world, self, -4.0, 0.92 + float(count % 5) * 0.05)
		VFX.burst_dust(self, target_world, Color(1.0, 0.96, 0.85), 4)
		if count >= max_slot_count():
			VFX.spawn_floating_text(self, target_world + Vector3(0, 0.35, 0), "✔ DOLU!", Color(0.55, 1.0, 0.6), 30)
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
	_wobble_tag(idx, delta > 0)
	var f := float(s.get("fresh", 1.0))
	if Net.online():
		rpc_sync_slot.rpc(idx, s["item"], int(s["count"]), np, f)
	else:
		rpc_sync_slot(idx, s["item"], int(s["count"]), np, f)


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
	var f := float(s.get("fresh", 1.0))
	var new_cnt := int(s["count"]) - 1
	var new_item: String = s["item"] if new_cnt > 0 else ""
	if Net.online():
		rpc_sync_slot.rpc(best_idx, new_item, new_cnt, int(s["price"]), f)
	else:
		rpc_sync_slot(best_idx, new_item, new_cnt, int(s["price"]), f)
	tip_scale()
	# Çürük mal satmak itibarı biraz zedeler
	if f < 0.3:
		add_reputation(-0.03)
	return best_price


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_slot(idx: int, item_id: String, count: int, price: int, fresh := 1.0) -> void:
	if idx < 0 or idx >= slots.size() or (item_id != "" and not ITEMS.has(item_id)):
		return
	var old: Dictionary = slots[idx]
	var old_item := str(old["item"])
	var old_cnt := int(old["count"])
	var new_cnt := clampi(count, 0, max_slot_count())
	slots[idx] = {"item": item_id, "count": new_cnt, "price": clampi(price, 1, 199), "fresh": clampf(fresh, 0.0, 1.0)}
	var taken := old_item != "" and old_cnt > new_cnt and (item_id == old_item or item_id == "")
	_refresh_slot_visual(idx)
	if taken and is_inside_tree():
		_sale_pop(idx, old_item, old_cnt)


# ---------- Tazelik API (host yetkili) ----------

## Bu ürünü tutan en iyi (en taze) yuvanın tazeliği; ürün yoksa 1.0.
func get_item_freshness(item_id: String) -> float:
	var best := -1.0
	for s in slots:
		if s["item"] == item_id and int(s["count"]) > 0:
			best = maxf(best, float(s.get("fresh", 1.0)))
	return best if best >= 0.0 else 1.0


## Host: dolu tüm yuvaları tazeler (su fısfısı) ve herkese parıltı efektiyle yayınlar.
func refresh_freshness(amount := SPRAY_AMOUNT) -> void:
	if not _is_host():
		return
	for s in slots:
		if str(s["item"]) != "" and int(s["count"]) > 0:
			s["fresh"] = minf(float(s.get("fresh", 1.0)) + amount, 1.0)
	_fresh_sync_t = 0.0
	if Net.online():
		rpc_sync_freshness.rpc(_fresh_values(), true)
	else:
		rpc_sync_freshness(_fresh_values(), true)


## Sahibin fısfıs isteği (istemci → host). Host: mesafe/sahiplik doğrular, tazeler.
func request_spray(sprayer_id: int) -> void:
	if Net.online():
		rpc_request_spray.rpc_id(1, sprayer_id)
	else:
		rpc_request_spray(sprayer_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_spray(sprayer_id: int) -> void:
	if not _is_host():
		return
	if Net.online():
		var snd := multiplayer.get_remote_sender_id()
		if snd != 0 and snd != sprayer_id:
			return
	if sprayer_id != owner_id:
		return
	refresh_freshness(SPRAY_AMOUNT)


func _spray_fx() -> void:
	if not is_inside_tree():
		return
	for i in slots.size():
		if int(slots[i]["count"]) <= 0:
			continue
		spawn_sparkle(self, _slot_visuals[i].global_position + Vector3(0, 0.25, 0))
	VFX.spawn_floating_text(self, to_global(Vector3(0, 1.25, 0.4)), "💦 TAPTAZE!", Color(0.6, 0.92, 1.0), 40)


## Parıltı: emisyonlu minik elmas kırıntıları yükselip söner (A'nın vfx.gd'sinden bağımsız).
static func spawn_sparkle(parent: Node, world_pos: Vector3, color := Color(0.6, 0.9, 1.0), amount := 9) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.5
	p.amount = amount
	p.lifetime = 0.75
	p.mesh = LP.box(Vector3(0.013, 0.013, 0.013))
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.4))
	shrink.add_point(Vector2(0.3, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.5
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.28, 0.08, 0.24)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, -0.6, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.4, Color(color.r, color.g, color.b, 0.95))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)


# ---------- İtibar (0..5 yıldız) ----------

## Host: itibarı değiştirir ve tüm eşlere yayar.
func add_reputation(delta: float) -> void:
	if not _is_host():
		return
	set_reputation(reputation + delta)


## Host: itibarı doğrudan ayarlar (kariyer kaydı yükleme vb.).
func set_reputation(value: float) -> void:
	if not _is_host():
		return
	var nv := clampf(value, 0.0, REP_MAX)
	if is_equal_approx(nv, reputation):
		return
	if Net.online():
		rpc_sync_reputation.rpc(nv)
	else:
		rpc_sync_reputation(nv)


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_reputation(value: float) -> void:
	if Net.online() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	var old := reputation
	reputation = clampf(value, 0.0, REP_MAX)
	_refresh_rep_label()
	# Yarım yıldız eşiği geçildiğinde belirgin geri bildirim
	var old_step := int(floor(old * 2.0 + 0.001))
	var new_step := int(floor(reputation * 2.0 + 0.001))
	if old_step != new_step and is_inside_tree() and _rep_label:
		var up := new_step > old_step
		var pos := _rep_label.global_position
		Sfx.play_3d("rep_up" if up else "rep_down", pos, self, -3.0, 1.0, 24.0)
		VFX.spawn_floating_text(self, pos + Vector3(0, 0.3, 0), "⭐ İtibar arttı!" if up else "💔 İtibar düştü!",
			Color(1.0, 0.86, 0.3) if up else Color(1.0, 0.4, 0.34), 34)
		if up:
			spawn_sparkle(self, pos, Color(1.0, 0.86, 0.3), 10)
		_rep_label.scale = Vector3.ONE * (1.3 if up else 0.8)
		var tw := create_tween()
		tw.tween_property(_rep_label, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _refresh_rep_label() -> void:
	if _rep_label == null:
		return
	var full := clampi(int(round(reputation)), 0, 5)
	_rep_label.text = "★".repeat(full) + "☆".repeat(5 - full) + "  %.1f" % reputation
	if reputation >= 4.0:
		_rep_label.modulate = Color(1.0, 0.86, 0.22)
	elif reputation >= 2.5:
		_rep_label.modulate = Color(1.0, 0.94, 0.62)
	elif reputation >= 1.5:
		_rep_label.modulate = Color(1.0, 0.7, 0.4)
	else:
		_rep_label.modulate = Color(1.0, 0.45, 0.38)


## Müşteri tezgah seçimi çarpanı: 0★ ≈ 0.75, 2.5★ = 1.0, 5★ ≈ 1.3.
func reputation_mult() -> float:
	if reputation <= 2.5:
		return lerpf(0.75, 1.0, reputation / 2.5)
	return lerpf(1.0, 1.3, (reputation - 2.5) / 2.5)


# ---------- Kapkaççı (hırsız) API ----------

## Host: rastgele (veya istenen üründen) dolu bir yuvadan 1 adet alır; ürün kimliğini döndürür.
func steal_one(item_id := "") -> String:
	if not _is_host():
		return ""
	var cands: Array[int] = []
	for i in slots.size():
		var s := slots[i]
		if int(s["count"]) > 0 and str(s["item"]) != "" and (item_id == "" or s["item"] == item_id):
			cands.append(i)
	if cands.is_empty() and item_id != "":
		return steal_one("")
	if cands.is_empty():
		return ""
	var idx: int = cands.pick_random()
	var s := slots[idx]
	var it := str(s["item"])
	var new_cnt := int(s["count"]) - 1
	var new_item := it if new_cnt > 0 else ""
	if Net.online():
		rpc_sync_slot.rpc(idx, new_item, new_cnt, int(s["price"]), float(s.get("fresh", 1.0)))
	else:
		rpc_sync_slot(idx, new_item, new_cnt, int(s["price"]), float(s.get("fresh", 1.0)))
	return it


## Host: yakalanan hırsızdan geri alınan 1 ürünü aynı ürünlü (yer varsa) veya boş yuvaya koyar.
func restore_one(item_id: String) -> void:
	if not _is_host() or not ITEMS.has(item_id):
		return
	var target := -1
	for i in slots.size():
		var s := slots[i]
		if s["item"] == item_id and int(s["count"]) > 0 and int(s["count"]) < max_slot_count():
			target = i
			break
	if target < 0:
		for i in slots.size():
			if str(slots[i]["item"]) == "" or int(slots[i]["count"]) <= 0:
				target = i
				break
	if target < 0:
		return
	var s := slots[target]
	var same: bool = s["item"] == item_id and int(s["count"]) > 0
	var cnt := (int(s["count"]) if same else 0) + 1
	var price: int = int(s["price"]) if same else int(ITEMS[item_id]["base"])
	var f: float = float(s.get("fresh", 0.9)) if same else 0.9
	var from_p := to_global(Vector3(0, 1.3, 1.4))
	if Net.online():
		rpc_place_animated.rpc(target, item_id, cnt, price, from_p, f)
	else:
		rpc_place_animated(target, item_id, cnt, price, from_p, f)


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
	var bell_pos := to_global(Vector3(-(half_width() - 0.33), 0.78, 0.56))
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
		"expansion_level": expansion_level,
		"upgrades": upgrades.duplicate(true),
		"bell_boost": bell_boost,
		"bell_cd": bell_cd,
		"has_radio": has_radio,
		"radio_playing": radio_playing,
		"reputation": reputation,
	}


func apply_snapshot(d: Dictionary) -> void:
	if d.has("expansion_level"):
		rpc_set_expansion(int(d["expansion_level"]))
	if d.has("upgrades"):
		for k in d["upgrades"]:
			if bool(d["upgrades"][k]) and not has_upgrade(k):
				upgrades[k] = true
				_show_upgrade_visual(k)
	if d.has("slots"):
		var arr: Array = d["slots"]
		for i in mini(arr.size(), slots.size()):
			var sd: Dictionary = arr[i].duplicate()
			var it := str(sd.get("item", ""))
			var ok := ITEMS.has(it)
			slots[i] = {
				"item": it if ok else "",
				"count": clampi(int(sd.get("count", 0)), 0, max_slot_count()) if ok else 0,
				"price": clampi(int(sd.get("price", 10)), 1, 199),
				"fresh": clampf(float(sd.get("fresh", 1.0)), 0.0, 1.0),
			}
			_refresh_slot_visual(i)
	if d.has("reputation"):
		reputation = clampf(float(d["reputation"]), 0.0, REP_MAX)
		_refresh_rep_label()
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
