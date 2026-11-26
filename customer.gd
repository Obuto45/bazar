extends Node3D
## Yapay zeka pazar müşterisi: gerçekçi başörtülü/pazar arabalı Pazar Teyzesi dahil 4 tip,
## belirgin pop-up çizgi roman konuşma kartları, güçlü bağırma çekimi (daha çok bağıran pazarcıya gider!)
## ve iki kapıdan sakin tempoda gezinen + Ford Transit'ten kaçınan yapay zeka.

const MODEL := preload("res://models/character.glb")
const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const StallScript := preload("res://stall.gd")
const VFX := preload("res://vfx.gd")

const HAIRS := [Color(0.2, 0.12, 0.07), Color(0.08, 0.06, 0.05), Color(0.75, 0.55, 0.25), Color(0.55, 0.22, 0.1),
	Color(0.4, 0.28, 0.18), Color(0.85, 0.8, 0.7)]
const SHIRTS := [Color(0.82, 0.28, 0.24), Color(0.24, 0.52, 0.82), Color(0.92, 0.72, 0.2), Color(0.32, 0.7, 0.36),
	Color(0.62, 0.36, 0.78), Color(0.92, 0.48, 0.65), Color(0.18, 0.68, 0.68), Color(0.92, 0.54, 0.18)]
const SCARF_COLORS := [
	Color(0.88, 0.24, 0.44), Color(0.18, 0.62, 0.66), Color(0.66, 0.26, 0.68),
	Color(0.92, 0.50, 0.20), Color(0.24, 0.52, 0.82), Color(0.24, 0.62, 0.34),
]

enum State { STROLL, APPROACH, WAIT_BUY, LEAVE }
enum Archetype { NORMAL, BARGAINER, IMPATIENT, VIP } # BARGAINER = İkonik Pazar Teyzesi!

var state: int = State.STROLL
var archetype: int = Archetype.NORMAL
var color_seed := 0
var wants: Dictionary = {}
var offers: Dictionary = {}
var bought_items: Array = []
var target_owner_id := 0
var target_pos := Vector3.ZERO
var exit_pos := Vector3(0, 0, 21.5)
var walk_speed := 1.72
var max_wait := 28.0
var wait_timer := 28.0
var eval_timer := 0.0
var mood_text := ""
var _last_bubble_txt := ""

var rig: Node3D
var head: Node3D
var parts := {}
var rest := {}
var _popup_pivot: Node3D
var _popup_card: MeshInstance3D
var _popup_border: MeshInstance3D
var _popup_tail: MeshInstance3D
var _popup_border_mat: StandardMaterial3D
var _popup_bg_mat: StandardMaterial3D
var _popup_tw: Tween
var bubble: Label3D
var _bag_anchor: Node3D
var _bag_items_root: Node3D
var _trolley_wheels: Array[Node3D] = []
var _patience_root: Node3D
var _patience_fill: MeshInstance3D
var _patience_mat: StandardMaterial3D
var _body_yaw := 0.0
var _phase := 0.0
var _spd := 0.0
var _react_jump := 0.0
var _react_shake := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_spd := 0.0
var _sync_t := 0.0


func init_customer(p_name: String, p_seed: int, start_pos: Vector3, p_exit: Vector3,
		p_wants: Dictionary, p_archetype: int = Archetype.NORMAL) -> void:
	name = p_name
	color_seed = p_seed
	archetype = p_archetype
	position = start_pos
	_net_pos = start_pos
	exit_pos = p_exit
	target_pos = p_exit
	wants = p_wants.duplicate()
	# Sakin, doğal Türk pazarı gezinme temposu
	match archetype:
		Archetype.IMPATIENT:
			walk_speed = 2.45
			max_wait = 15.0
		Archetype.BARGAINER: # Pazar Teyzesi: ağır ağır gezer, sabırlı ama sıkı pazarlıkçı!
			walk_speed = 1.48
			max_wait = 32.0
		Archetype.VIP:
			walk_speed = 1.78
			max_wait = 26.0
		_:
			walk_speed = 1.68 + float(absi(p_seed) % 4) * 0.08
			max_wait = 28.0
	wait_timer = max_wait


func _ready() -> void:
	if archetype == Archetype.BARGAINER:
		_build_teyze_visual()
	else:
		_build_visual()
		_build_accessories_and_bag()
	_build_popup_bubble_patience_and_area()
	_refresh_bag_visual()
	_refresh_bubble()


## Bıyıksız, kasketsiz, başörtülü, gözlüklü, çiçekli hırkalı ve tekerlekli pazar arabalı İKONİK PAZAR TEYZESİ!
func _build_teyze_visual() -> void:
	rig = Node3D.new()
	add_child(rig)
	head = Node3D.new()
	add_child(head)

	var scarf_col: Color = SCARF_COLORS[absi(color_seed) % SCARF_COLORS.size()]
	var cardigan_col: Color = SHIRTS[absi(color_seed * 5 + 2) % SHIRTS.size()]
	var skirt_col := cardigan_col.darkened(0.32)
	var skin_col := Color(0.93, 0.78, 0.66)

	# Gövde: uzun etek + yumuşak teyze hırkası + desenli önlük
	var body_w := Node3D.new(); body_w.name = "Body"
	rest["Body"] = Vector3(0, 0.50, 0)
	body_w.position = rest["Body"]
	LP.add(body_w, LP.cyl(0.22, 0.30, 0.42, 9), Vector3(0, -0.14, 0), skirt_col)
	LP.add(body_w, LP.ellipsoid(0.25, 0.24, 0.23, 9, 5), Vector3(0, 0.14, 0), cardigan_col)
	LP.add(body_w, LP.box(Vector3(0.22, 0.36, 0.04)), Vector3(0, -0.02, 0.22), Color(0.96, 0.94, 0.88)) # önlük
	rig.add_child(body_w)
	parts["Body"] = body_w

	# Kafa: bıyıksız güler yüz + başörtüsü (yemeni) + altın gözlük + al yanaklar!
	var head_w := Node3D.new(); head_w.name = "Head"
	rest["Head"] = Vector3(0, 1.06, 0)
	head.position = rest["Head"]
	head.add_child(head_w)
	parts["Head"] = head_w
	LP.add(head_w, LP.sphere(0.25, 9, 6), Vector3.ZERO, skin_col, Vector3.ZERO, 0.82)
	# Başörtüsü / eşarp (başın üstünü, yanlarını ve enseyi sarar, çene altında düğüm)
	LP.add(head_w, LP.ellipsoid(0.28, 0.26, 0.28, 9, 6), Vector3(0, 0.04, -0.04), scarf_col)
	LP.add(head_w, LP.cyl(0.24, 0.28, 0.22, 8), Vector3(0, -0.14, -0.12), scarf_col.darkened(0.08))
	LP.add(head_w, LP.torus(0.21, 0.26, 10, 5), Vector3(0, 0.02, 0.08), scarf_col.lightened(0.14), Vector3(PI / 2, 0, 0))
	# Gözler + yuvarlak altın teyze gözlüğü + al yanaklar + sıcak gülümseme
	for sx: float in [-0.085, 0.085]:
		LP.add(head_w, LP.sphere(0.036, 6, 4), Vector3(sx, 0.03, 0.225), Color.WHITE, Vector3.ZERO, 0.2)
		LP.add(head_w, LP.sphere(0.020, 6, 4), Vector3(sx, 0.03, 0.252), Color(0.1, 0.08, 0.07), Vector3.ZERO, 0.1)
		LP.add(head_w, LP.torus(0.044, 0.053, 10, 4), Vector3(sx, 0.03, 0.255), Color(0.88, 0.72, 0.22), Vector3(PI / 2, 0, 0), 0.25, 0.85)
		LP.add(head_w, LP.sphere(0.034, 5, 3), Vector3(sx * 1.45, -0.04, 0.215), Color(0.95, 0.56, 0.56))
	LP.add(head_w, LP.box(Vector3(0.06, 0.012, 0.012)), Vector3(0, 0.03, 0.255), Color(0.88, 0.72, 0.22), Vector3.ZERO, 0.25, 0.85)
	LP.add(head_w, LP.sphere(0.032, 5, 3), Vector3(0, -0.02, 0.255), skin_col.darkened(0.05)) # minik burun
	LP.add(head_w, LP.box(Vector3(0.085, 0.022, 0.02)), Vector3(0, -0.10, 0.242), Color(0.76, 0.28, 0.30)) # gülümseme

	# Eller ve ayaklar
	for side: float in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var fw := Node3D.new(); fw.name = fn
		rest[fn] = Vector3(side * 0.13, 0.10, 0)
		fw.position = rest[fn]
		LP.add(fw, LP.ellipsoid(0.08, 0.055, 0.12, 6, 4), Vector3.ZERO, Color(0.24, 0.18, 0.16))
		rig.add_child(fw)
		parts[fn] = fw
		var hw := Node3D.new(); hw.name = hn
		rest[hn] = Vector3(side * 0.33, 0.54, 0.05)
		hw.position = rest[hn]
		LP.add(hw, LP.sphere(0.068, 6, 4), Vector3.ZERO, skin_col)
		rig.add_child(hw)
		parts[hn] = hw

	# Sağ elin arkasında tekerlekli ekose PAZAR ARABASI (aldıkça içi meyve dolar!)
	var trolley := Node3D.new()
	trolley.position = Vector3(-0.34, 0.0, -0.42)
	rig.add_child(trolley)
	var t_col := Color(0.76, 0.18, 0.24) if (color_seed % 2 == 0) else Color(0.18, 0.38, 0.66)
	LP.add(trolley, LP.box(Vector3(0.30, 0.44, 0.24)), Vector3(0, 0.34, 0), t_col)
	LP.add(trolley, LP.box(Vector3(0.31, 0.06, 0.25)), Vector3(0, 0.44, 0), Color(0.95, 0.90, 0.80))
	LP.add(trolley, LP.box(Vector3(0.31, 0.06, 0.25)), Vector3(0, 0.24, 0), Color(0.95, 0.90, 0.80))
	LP.add(trolley, LP.cyl(0.012, 0.012, 0.68, 5), Vector3(0, 0.48, 0.15), Color(0.65, 0.66, 0.68), Vector3(0.32, 0, 0))
	LP.add(trolley, LP.box(Vector3(0.22, 0.03, 0.03)), Vector3(0, 0.78, 0.26), Color(0.18, 0.18, 0.2))
	_trolley_wheels.clear()
	for wx: float in [-0.17, 0.17]:
		var wh := LP.add(trolley, LP.cyl(0.095, 0.095, 0.035, 8), Vector3(wx, 0.095, -0.02), Color(0.16, 0.16, 0.18), Vector3(0, 0, PI / 2))
		_trolley_wheels.append(wh)
	_bag_items_root = Node3D.new()
	_bag_items_root.position = Vector3(0, 0.56, 0)
	trolley.add_child(_bag_items_root)

	scale = Vector3(0.96, 0.96, 0.96)


func _build_visual() -> void:
	var src := MODEL.instantiate()
	rig = Node3D.new()
	add_child(rig)
	head = Node3D.new()
	add_child(head)
	var hair_col: Color = HAIRS[absi(color_seed) % HAIRS.size()]
	var shirt_col: Color = SHIRTS[absi(color_seed * 3 + 1) % SHIRTS.size()]
	if archetype == Archetype.VIP:
		shirt_col = Color(0.18, 0.14, 0.24)
	elif archetype == Archetype.IMPATIENT:
		shirt_col = Color(0.96, 0.42, 0.12)
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
	var sc := 0.94 + float(absi(color_seed) % 5) * 0.03
	if archetype == Archetype.VIP:
		sc = 1.08
	scale = Vector3(sc, sc, sc)


func _build_accessories_and_bag() -> void:
	var h := parts["Head"] as Node3D
	match archetype:
		Archetype.VIP:
			LP.add(h, LP.cyl(0.28, 0.28, 0.04, 10), Vector3(0, 0.27, 0), Color(0.12, 0.11, 0.15))
			LP.add(h, LP.cyl(0.20, 0.19, 0.28, 10), Vector3(0, 0.42, 0), Color(0.12, 0.11, 0.15))
			LP.add(h, LP.cyl(0.205, 0.205, 0.05, 10), Vector3(0, 0.32, 0), Color(0.95, 0.78, 0.2), Vector3.ZERO, 0.25, 0.85)
		Archetype.IMPATIENT:
			LP.add(h, LP.torus(0.22, 0.27, 10, 5), Vector3(0, 0.18, 0), Color(1.0, 0.76, 0.14))
			LP.add(h, LP.box(Vector3(0.28, 0.035, 0.22)), Vector3(0, 0.18, 0.26), Color(0.96, 0.32, 0.12))

	_bag_anchor = Node3D.new()
	_bag_anchor.position = Vector3(0.0, -0.24, 0.06)
	(parts["HandR"] as Node3D).add_child(_bag_anchor)
	var bag_col := Color(0.24, 0.18, 0.32) if archetype == Archetype.VIP else Color(0.86, 0.76, 0.56)
	LP.add(_bag_anchor, LP.box(Vector3(0.22, 0.24, 0.18)), Vector3.ZERO, bag_col)
	LP.add(_bag_anchor, LP.torus(0.055, 0.072, 8, 4), Vector3(0, 0.16, 0), bag_col.darkened(0.25), Vector3(PI / 2, 0, 0))
	_bag_items_root = Node3D.new()
	_bag_items_root.position = Vector3(0, 0.11, 0)
	_bag_anchor.add_child(_bag_items_root)


func _refresh_bag_visual() -> void:
	if _bag_items_root == null:
		return
	for c in _bag_items_root.get_children():
		c.queue_free()
	for i in mini(bought_items.size(), 6):
		var item_id: String = str(bought_items[i])
		var ox := -0.055 + float(i % 2) * 0.11
		var oy := float(int(i / 2)) * 0.068
		var oz := -0.035 + float((i + 1) % 2) * 0.07
		Produce.build_mesh(_bag_items_root, item_id, Vector3(ox, oy, oz), 0.052)


## Yüksek kontrastlı, açılışta zıplayarak beliren Pop-Up konuşma balonu kartı + sabır çubuğu.
func _build_popup_bubble_patience_and_area() -> void:
	_popup_pivot = Node3D.new()
	_popup_pivot.position = Vector3(0, 2.02, 0)
	add_child(_popup_pivot)

	# Dış renkli çerçeve
	_popup_border = MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(1.42, 0.42)
	_popup_border.mesh = bq
	_popup_border.position = Vector3(0, 0, -0.012)
	_popup_border_mat = StandardMaterial3D.new()
	_popup_border_mat.albedo_color = Color(0.16, 0.11, 0.08, 0.96)
	_popup_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_popup_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_popup_border.material_override = _popup_border_mat
	_popup_pivot.add_child(_popup_border)

	# Parlak krem/beyaz iç kart
	_popup_card = MeshInstance3D.new()
	var cq := QuadMesh.new()
	cq.size = Vector2(1.34, 0.34)
	_popup_card.mesh = cq
	_popup_card.position = Vector3(0, 0, -0.004)
	_popup_bg_mat = StandardMaterial3D.new()
	_popup_bg_mat.albedo_color = Color(1.0, 0.98, 0.92, 0.96)
	_popup_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_popup_bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_popup_card.material_override = _popup_bg_mat
	_popup_pivot.add_child(_popup_card)

	# Konuşma balonu alt ok ucu
	_popup_tail = MeshInstance3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(0.15, 0.15)
	_popup_tail.mesh = tq
	_popup_tail.position = Vector3(0, -0.19, -0.010)
	_popup_tail.rotation.z = PI / 4.0
	_popup_tail.material_override = _popup_bg_mat
	_popup_pivot.add_child(_popup_tail)

	# Kart üstü belirgin koyu yazı
	bubble = Label3D.new()
	bubble.position = Vector3(0, 0, 0.012)
	bubble.font_size = 30
	bubble.pixel_size = 0.0032
	bubble.outline_size = 5
	bubble.double_sided = false
	bubble.modulate = Color(0.10, 0.07, 0.05)
	bubble.outline_modulate = Color(1.0, 0.98, 0.92)
	_popup_pivot.add_child(bubble)

	# Baş üstü 3D sabır çubuğu
	_patience_root = Node3D.new()
	_patience_root.position = Vector3(0, 1.66, 0)
	var bg := MeshInstance3D.new()
	var bg_m := QuadMesh.new()
	bg_m.size = Vector2(0.76, 0.095)
	bg.mesh = bg_m
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.08, 0.06, 0.05, 0.85)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg.material_override = bg_mat
	_patience_root.add_child(bg)

	_patience_fill = MeshInstance3D.new()
	var fg_m := QuadMesh.new()
	fg_m.size = Vector2(0.70, 0.06)
	_patience_fill.mesh = fg_m
	_patience_fill.position = Vector3(0, 0, 0.01)
	_patience_mat = StandardMaterial3D.new()
	_patience_mat.albedo_color = Color(0.35, 0.95, 0.42)
	_patience_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patience_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_patience_mat.billboard_keep_scale = true
	_patience_mat.no_depth_test = true
	_patience_fill.material_override = _patience_mat
	_patience_root.add_child(_patience_fill)
	_patience_root.hide()
	add_child(_patience_root)

	var area := Area3D.new()
	area.name = "CustomerArea"
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("kind", "customer")
	area.set_meta("customer_name", name)
	area.set_meta("hl_size", Vector3(0.88, 1.55, 0.88))
	area.position = Vector3(0, 0.85, 0)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45; sh.height = 1.65
	cs.shape = sh
	area.add_child(cs)
	add_child(area)


func archetype_tag() -> String:
	match archetype:
		Archetype.BARGAINER:
			return "🧣 Teyze"
		Archetype.IMPATIENT:
			return "⚡ Aceleci"
		Archetype.VIP:
			return "⭐ VIP"
		_:
			return ""


func _refresh_bubble() -> void:
	if bubble == null or _popup_pivot == null:
		return
	var txt := ""
	var border_c := Color(0.22, 0.16, 0.12, 0.96)
	var bg_c := Color(1.0, 0.98, 0.92, 0.96)

	if mood_text != "":
		txt = mood_text
		if "😊" in mood_text or "⭐" in mood_text or "⚡" in mood_text or "Bereketli" in mood_text:
			border_c = Color(0.18, 0.68, 0.28, 0.98)
			bg_c = Color(0.90, 1.0, 0.92, 0.97)
		else:
			border_c = Color(0.82, 0.22, 0.18, 0.98)
			bg_c = Color(1.0, 0.90, 0.88, 0.97)
	else:
		var segs := PackedStringArray()
		for k in wants:
			var cnt: int = int(wants[k])
			if cnt > 0 and StallScript.ITEMS.has(k):
				segs.append("%dx %s" % [cnt, StallScript.ITEMS[k]["name"]])
		if not segs.is_empty():
			var prefix := archetype_tag()
			if prefix != "":
				prefix += " • "
			var st: Node3D = _find_stall(target_owner_id) if state == State.WAIT_BUY else null
			var cur := _current_item(st) if st else ""
			if offers.has(cur):
				var ask := "Abi %s %d lira olmaz mı?" if archetype != Archetype.BARGAINER else "Evladım %s %d liraya ver hele!"
				txt = "🤔 " + prefix + (ask % [StallScript.ITEMS[cur]["name"], int(offers[cur])])
				border_c = Color(0.92, 0.48, 0.12, 0.98)
				bg_c = Color(1.0, 0.95, 0.84, 0.98)
			elif state == State.WAIT_BUY:
				txt = "🛒 " + prefix + ", ".join(segs)
				border_c = Color(0.88, 0.64, 0.10, 0.98)
				bg_c = Color(1.0, 0.97, 0.86, 0.97)
			else:
				txt = "💬 " + prefix + ", ".join(segs)

	if txt == "":
		_popup_pivot.hide()
		_last_bubble_txt = ""
		return

	_popup_pivot.show()
	bubble.text = txt
	_popup_border_mat.albedo_color = border_c
	_popup_bg_mat.albedo_color = bg_c
	# Kart genişliğini metin uzunluğuna göre bol kenar boşluklu ayarla
	var card_w := clampf(float(txt.length()) * 0.062 + 0.42, 0.96, 2.65)
	(_popup_card.mesh as QuadMesh).size = Vector2(card_w, 0.32)
	(_popup_border.mesh as QuadMesh).size = Vector2(card_w + 0.08, 0.40)

	if txt != _last_bubble_txt:
		_last_bubble_txt = txt
		if _popup_tw and _popup_tw.is_valid():
			_popup_tw.kill()
		_popup_pivot.scale = Vector3(0.08, 0.08, 0.08)
		_popup_tw = create_tween()
		_popup_tw.tween_property(_popup_pivot, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_patience_bar() -> void:
	if _patience_root == null:
		return
	if state != State.WAIT_BUY:
		_patience_root.hide()
		return
	_patience_root.show()
	var ratio := clampf(wait_timer / maxf(max_wait, 1.0), 0.0, 1.0)
	_patience_fill.scale = Vector3(maxf(ratio, 0.02), 1.0, 1.0)
	if ratio > 0.55:
		_patience_mat.albedo_color = Color(0.35, 0.95, 0.42)
	elif ratio > 0.25:
		_patience_mat.albedo_color = Color(1.0, 0.82, 0.22)
	else:
		var pulse := 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.018)
		_patience_mat.albedo_color = Color(1.0 * pulse, 0.22, 0.18)


func _process(_dt: float) -> void:
	# Pop-up konuşma kartı daima aktif kameraya baksın
	if _popup_pivot and _popup_pivot.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to_cam := cam.global_position - _popup_pivot.global_position
			to_cam.y = 0.0
			if to_cam.length_squared() > 0.001:
				_popup_pivot.global_rotation = Vector3(0, atan2(to_cam.x, to_cam.z), 0)


func _physics_process(dt: float) -> void:
	var is_host := (not Net.online()) or multiplayer.is_server()
	if is_host:
		_tick_ai(dt)
		_sync_t += dt
		if Net.online() and _sync_t >= 0.1:
			_sync_t = 0.0
			rpc_sync_state.rpc(position, _body_yaw, _spd, state, target_owner_id, wants, offers, mood_text, wait_timer)
	else:
		position = position.lerp(_net_pos, minf(dt * 12.0, 1.0))
		_body_yaw = lerp_angle(_body_yaw, _net_yaw, minf(dt * 12.0, 1.0))
		_spd = lerpf(_spd, _net_spd, minf(dt * 10.0, 1.0))
	rig.rotation.y = _body_yaw
	var shake_y := 0.0
	if _react_shake > 0.0:
		_react_shake = maxf(_react_shake - dt, 0.0)
		shake_y = sin(_react_shake * 34.0) * 0.42 * (_react_shake / 0.55)
	head.rotation.y = lerp_angle(head.rotation.y, _body_yaw + shake_y, minf(dt * 14.0, 1.0))
	_update_patience_bar()
	_animate_walk(dt)


func _tick_ai(dt: float) -> void:
	match state:
		State.STROLL:
			_move_toward_target(dt, walk_speed)
			eval_timer -= dt
			if eval_timer <= 0.0:
				eval_timer = 0.35
				_evaluate_stalls(false)
			if Vector2(position.x - exit_pos.x, position.z - exit_pos.z).length() < 1.3:
				queue_free()
		State.APPROACH:
			var st := _find_stall(target_owner_id)
			if st == null or not _stall_has_any_want(st):
				state = State.STROLL
				target_owner_id = 0
				target_pos = exit_pos
				_refresh_bubble()
				return
			# Yürürken başka bir pazarcı ÇOK DAHA GÜÇLÜ bağırırsa ona dön!
			eval_timer -= dt
			if eval_timer <= 0.0:
				eval_timer = 0.65
				_evaluate_stalls(true)
			_move_toward_target(dt, walk_speed * 1.15)
			if Vector2(position.x - target_pos.x, position.z - target_pos.z).length() < 0.38:
				state = State.WAIT_BUY
				_spd = 0.0
				wait_timer = max_wait
				var look_dir: Vector3 = (st as Node3D).global_position - global_position
				_body_yaw = atan2(look_dir.x, look_dir.z)
				_make_offers(st)
				_refresh_bubble()
				if not offers.is_empty():
					Sfx.play_3d("haggle", global_position + Vector3(0, 1.3, 0), self, -6.0)
		State.WAIT_BUY:
			_spd = 0.0
			wait_timer -= dt
			var st := _find_stall(target_owner_id)
			if st == null or not _stall_has_any_want(st) or _total_wants() <= 0 or wait_timer <= 0.0:
				if _total_wants() <= 0:
					mood_text = "😊 Bereketli olsun evladım!" if archetype == Archetype.BARGAINER else "😊 Teşekkürler!"
				elif wait_timer <= 0.0:
					mood_text = "😤 Çok bekledim!" if archetype == Archetype.IMPATIENT else "😕 Çok bekledim..."
					_trigger_reaction(false)
				state = State.LEAVE
				target_owner_id = 0
				target_pos = exit_pos
				_refresh_bubble()
		State.LEAVE:
			_move_toward_target(dt, walk_speed * 1.08)
			if Vector2(position.x - exit_pos.x, position.z - exit_pos.z).length() < 1.3:
				queue_free()


func _move_toward_target(dt: float, speed: float) -> void:
	var diff := Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	var dist := diff.length()
	if dist < 0.05:
		_spd = 0.0
		return
	var dir := diff / dist
	# Ortadaki Ford Transit Toptancı park/sürüş halindeyse yanından kibarca dolan
	var w := get_parent().get_parent() if get_parent() else null
	var truck := w.get_node_or_null("Wholesaler") as Node3D if w else null
	if truck and truck.is_present():
		var rel_x := position.x - truck.position.x
		var rel_z := position.z - truck.position.z
		if absf(rel_x) < 2.25 and absf(rel_z) < 4.5:
			var push_x := 1.0 if rel_x >= 0.0 else -1.0
			dir = (dir + Vector3(push_x * 1.3, 0.0, 0.0)).normalized()
	position += dir * minf(speed * dt, dist)
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 8.0, 1.0))
	_spd = speed


## Güçlendirilmiş bağırma odaklı tezgah seçimi: daha yüksek bağıran (veya Megafon kullanan) pazarcı müşteriyi kazanır!
func _evaluate_stalls(only_louder_override: bool) -> void:
	var stalls := _all_stalls()
	if stalls.is_empty():
		return
	var ev := _active_event_item()
	var cur_shout := 0.0
	if only_louder_override and target_owner_id != 0:
		var cur_owner := _find_player(target_owner_id)
		if cur_owner and cur_owner.has_method("get_effective_shout"):
			cur_shout = cur_owner.get_effective_shout()

	var best_stall = null
	var best_score := 0.0
	var best_shout := 0.0

	for st in stalls:
		var owner := _find_player(st.owner_id)
		var eff_shout := 0.0
		var hearing_range := 22.0
		if owner and owner.global_position.distance_to(st.global_position) < 6.0:
			eff_shout = owner.get_effective_shout() if owner.has_method("get_effective_shout") else float(owner.shout_power)
			if owner.has_method("is_holding_item") and owner.is_holding_item("megafon"):
				hearing_range = 34.0
		var dist := global_position.distance_to(st.global_position)
		if dist > hearing_range:
			continue
		var matched := 0
		var price_sum := 0.0
		for k in wants:
			if int(wants[k]) > 0 and st.has_item(k):
				matched += 1
				price_sum += StallScript.relative_price_score(k, st.get_item_price(k), stalls, ev)
		if matched == 0:
			continue
		var avg_price_score := price_sum / float(matched)
		if avg_price_score < 0.14:
			continue

		# Bağırma dominansı: daha yüksek dB / Megafon doğrusal değil üstel avantaj sağlar!
		var shout_score := 0.0
		if owner and eff_shout > 0.08:
			var heard := global_position.distance_to(owner.global_position)
			var falloff := 0.045 if hearing_range > 25.0 else 0.08
			shout_score = clampf(pow(eff_shout, 1.3) / (1.0 + heard * falloff), 0.0, 2.4)
		if st.bell_boost > 0.0:
			shout_score = maxf(shout_score, clampf(1.55 / (1.0 + dist * 0.05), 0.45, 1.6))

		# Ek çekicilik bonusları: Süslü Işıklar, Arabesk Radyo, Küba Purosu Prestiji!
		var charm := 0.0
		if st.has_upgrade("lights"):
			charm += 0.18
		if st.has_radio and st.radio_playing:
			charm += 0.18
		if owner and owner.has_method("has_prestige_aura") and owner.has_prestige_aura():
			charm += 0.18 if archetype == Archetype.VIP else 0.10

		var variety := clampf(float(matched) / float(maxi(wants.size(), 1)), 0.0, 1.0)
		var proximity := clampf(1.0 - dist / hearing_range, 0.0, 1.0)
		var busy := _count_customers_at(st.owner_id)
		# Bağırma ağırlığı %62 (baskın!), fiyat %28, çeşit/yakınlık %10 + tezgah cazibesi
		var score := shout_score * 0.62 * clampf(avg_price_score, 0.45, 1.15) \
			+ avg_price_score * 0.28 + (variety * 0.55 + proximity * 0.45) * 0.10 \
			+ charm - float(busy) * 0.20

		if score > best_score:
			best_score = score
			best_stall = st
			best_shout = eff_shout

	if best_stall == null:
		return
	if only_louder_override:
		# Başka bir pazarcı açık ara daha güçlü bağırıyorsa ona çevril!
		if best_stall.owner_id != target_owner_id and best_shout > cur_shout + 0.50 and best_shout >= 0.70:
			target_owner_id = best_stall.owner_id
			var busy_n := _count_customers_at(target_owner_id)
			target_pos = best_stall.customer_spot(float(busy_n % 3 - 1) * 0.68)
			_refresh_bubble()
		return

	var lure_prob := clampf(best_score * 0.85 + (0.28 if best_shout >= 0.5 else 0.0), 0.14, 0.97)
	if best_score > 0.24 and randf() < lure_prob:
		target_owner_id = best_stall.owner_id
		var busy_n := _count_customers_at(target_owner_id)
		var side_off := float(busy_n % 3 - 1) * 0.68
		target_pos = best_stall.customer_spot(side_off)
		state = State.APPROACH
		_refresh_bubble()


func _make_offers(st) -> void:
	offers.clear()
	if archetype == Archetype.VIP:
		return
	var stalls := _all_stalls()
	var ev := _active_event_item()
	for k in wants:
		if int(wants[k]) <= 0 or not st.has_item(k):
			continue
		var price: int = st.get_item_price(k)
		var score := StallScript.relative_price_score(k, price, stalls, ev)
		var prob := clampf(1.15 - score, 0.15, 0.85)
		var discount := 0.80
		if archetype == Archetype.BARGAINER:
			prob = clampf(prob + 0.42, 0.55, 0.96)
			discount = 0.74
		elif archetype == Archetype.IMPATIENT:
			prob *= 0.45
		if price >= 2 and (score <= 1.06 or archetype == Archetype.BARGAINER) and randf() < prob:
			offers[k] = clampi(roundi(price * discount), 1, price - 1)


func try_sell_one_from(seller_id: int, insist := false) -> Dictionary:
	if state != State.WAIT_BUY or target_owner_id != seller_id:
		return {}
	var st := _find_stall(seller_id)
	var k := _current_item(st) if st else ""
	if k == "":
		return {}
	var ev := _active_event_item()
	var offer: int = int(offers.get(k, 0))
	var was_haggle := offer > 0
	if insist:
		if offer <= 0:
			return {}
		offers.erase(k)
		var base_ch := StallScript.relative_price_score(k, st.get_item_price(k), _all_stalls(), ev) * 0.8
		if archetype == Archetype.BARGAINER:
			base_ch *= 0.72
		var chance := clampf(base_ch, 0.1, 0.9)
		if randf() >= chance:
			mood_text = "😤 Çok pahalıymış, öbür tezgaha bakayım!" if archetype == Archetype.BARGAINER else "😤 Pahalıymış abi..."
			state = State.LEAVE
			target_owner_id = 0
			target_pos = exit_pos
			_refresh_bubble()
			if Net.online():
				rpc_on_angry.rpc(mood_text)
			else:
				_trigger_reaction(false)
			return {}
		offer = 0
		was_haggle = false
	var price: int = st.consume_for_sale(k)
	if price <= 0:
		return {}
	if offer > 0:
		price = mini(price, offer)
	wants[k] = int(wants[k]) - 1
	if int(wants[k]) <= 0:
		wants.erase(k)
		offers.erase(k)
	bought_items.append(k)

	var tip := 0
	if archetype == Archetype.IMPATIENT and wait_timer / maxf(max_wait, 1.0) >= 0.55:
		tip += randi_range(4, 7)
	wait_timer = minf(wait_timer + 6.0, max_wait)
	var done := _total_wants() <= 0 or not _stall_has_any_want(st)
	if done:
		if archetype == Archetype.VIP and _total_wants() <= 0:
			tip += randi_range(12, 20)
			mood_text = "⭐ Harika servis! +%d TL Bahşiş!" % tip
		elif tip > 0:
			mood_text = "⚡ Süper hız! +%d TL Bahşiş!" % tip
		elif archetype == Archetype.BARGAINER:
			mood_text = "😊 Bereketli olsun evladım!"
		else:
			mood_text = "😊 Teşekkürler!"
		state = State.LEAVE
		target_owner_id = 0
		target_pos = exit_pos
	_refresh_bubble()
	if Net.online():
		rpc_on_sold.rpc(k, price, tip, wants, offers, bought_items, state, mood_text)
	else:
		_apply_sold_fx(k, price, tip)
	return {"item": k, "price": price, "tip": tip, "haggle": was_haggle}


@rpc("any_peer", "call_local", "reliable")
func rpc_request_sell(seller_id: int, insist: bool) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	var res := try_sell_one_from(seller_id, insist)
	if not res.is_empty():
		var p := _find_player(seller_id)
		if p:
			p.award_money(int(res["price"]), int(res.get("tip", 0)), bool(res.get("haggle", false)))


@rpc("authority", "call_local", "reliable")
func rpc_on_sold(item_id: String, price: int, tip: int, new_wants: Dictionary, new_offers: Dictionary, new_bought: Array, new_state: int, new_mood: String) -> void:
	wants = new_wants
	offers = new_offers
	bought_items = new_bought
	state = new_state
	mood_text = new_mood
	_refresh_bubble()
	_apply_sold_fx(item_id, price, tip)


@rpc("authority", "call_local", "reliable")
func rpc_on_angry(new_mood: String) -> void:
	mood_text = new_mood
	state = State.LEAVE
	_refresh_bubble()
	_trigger_reaction(false)


func _apply_sold_fx(_item_id: String, price: int, tip: int) -> void:
	_refresh_bag_visual()
	_trigger_reaction(true)
	var pos := global_position + Vector3(0, 1.9, 0)
	VFX.burst_coins(self, global_position + Vector3(0, 1.3, 0), 12 if tip > 0 else 8)
	VFX.spawn_floating_text(self, pos, "+%d TL" % price, Color(1.0, 0.86, 0.22), 46)
	Sfx.play_3d("coin", pos, self, -2.0)
	if tip > 0:
		VFX.spawn_floating_text(self, pos + Vector3(0, 0.42, 0), "⭐ +%d TL BAHŞİŞ!" % tip, Color(0.42, 1.0, 0.62), 40)
		Sfx.play_3d("tip", pos, self, -1.5)


func _trigger_reaction(happy: bool) -> void:
	if happy:
		_react_jump = 0.34
		VFX.burst_mood(self, global_position + Vector3(0, 1.5, 0), true)
		if state == State.LEAVE:
			Sfx.play_3d("happy", global_position + Vector3(0, 1.4, 0), self, -4.0)
	else:
		_react_shake = 0.55
		VFX.burst_mood(self, global_position + Vector3(0, 1.5, 0), false)
		Sfx.play_3d("angry", global_position + Vector3(0, 1.4, 0), self, -3.5)


@rpc("authority", "unreliable_ordered")
func rpc_sync_state(p: Vector3, yaw: float, s: float, st: int, own: int, w: Dictionary, off: Dictionary, mood: String, wt := 28.0) -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	wait_timer = wt
	if state != st or wants != w or offers != off or mood_text != mood or target_owner_id != own:
		state = st
		target_owner_id = own
		wants = w
		offers = off
		mood_text = mood
		_refresh_bubble()


func export_snapshot() -> Dictionary:
	return {
		"name": name, "seed": color_seed, "archetype": archetype,
		"pos": position, "yaw": _body_yaw, "exit": exit_pos,
		"target_pos": target_pos, "target_owner": target_owner_id,
		"state": state, "wants": wants.duplicate(), "offers": offers.duplicate(),
		"bought": bought_items.duplicate(), "mood": mood_text, "wait": wait_timer,
	}


func apply_snapshot(d: Dictionary) -> void:
	position = d.get("pos", position)
	_net_pos = position
	_body_yaw = float(d.get("yaw", 0.0))
	_net_yaw = _body_yaw
	target_pos = d.get("target_pos", exit_pos)
	target_owner_id = int(d.get("target_owner", 0))
	state = int(d.get("state", State.STROLL))
	wants = d.get("wants", {}).duplicate()
	offers = d.get("offers", {}).duplicate()
	bought_items = d.get("bought", []).duplicate()
	mood_text = str(d.get("mood", ""))
	wait_timer = float(d.get("wait", max_wait))
	_refresh_bag_visual()
	_refresh_bubble()


func get_next_sell_hint(seller_id: int) -> String:
	if state != State.WAIT_BUY or target_owner_id != seller_id:
		return ""
	var st := _find_stall(seller_id)
	var k := _current_item(st) if st else ""
	if k == "":
		return ""
	var nm: String = StallScript.ITEMS[k]["name"]
	var p: int = st.get_item_price(k)
	if offers.has(k):
		return "[E] Olur: %s %d TL  •  [R] Olmaz, %d TL  •  Kalan: %d" % [nm, mini(p, int(offers[k])), p, _total_wants()]
	return "[E] Sat: %s (%d TL)  •  Kalan: %d" % [nm, p, _total_wants()]


func _current_item(st) -> String:
	for k in wants:
		if int(wants[k]) > 0 and st.has_item(k):
			return k
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


func _active_event_item() -> String:
	var w := get_parent().get_parent() if get_parent() else null
	return str(w.get_meta("event_item", "")) if w else ""


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
	var kw := clampf(_spd / 2.2, 0.0, 1.0)
	var stride := 0.24 * kw
	var lift := 0.09 * kw
	if _spd > 0.08:
		_phase = wrapf(_phase + dt * (_spd / 0.24) * 0.94, 0.0, TAU)
		for wh in _trolley_wheels:
			wh.rotation.x += _spd * dt / 0.095
	var f := minf(dt * 14.0, 1.0)
	var hop := 0.0
	if _react_jump > 0.0:
		_react_jump = maxf(_react_jump - dt, 0.0)
		hop = sin((_react_jump / 0.34) * PI) * 0.24
	for side: float in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = _phase + (0.0 if side < 0 else PI)
		var fp: Vector3 = rest[fn] + Vector3(0, maxf(0.0, sin(c)) * lift + hop * 0.5, -cos(c) * stride)
		parts[fn].position = parts[fn].position.lerp(fp, f)
		parts[fn].rotation = parts[fn].rotation.lerp(Vector3(-sin(c) * 0.38 * kw, 0, 0), f)
		var hp: Vector3 = rest[hn] + Vector3(0, maxf(0.0, cos(c)) * 0.04 * kw + hop * 1.1, cos(c) * 0.18 * kw)
		parts[hn].position = parts[hn].position.lerp(hp, f)
		parts[hn].rotation = parts[hn].rotation.lerp(Vector3(-cos(c) * 0.42 * kw, 0, 0), f)
	var bp: Vector3 = rest["Body"] + Vector3(0, absf(sin(_phase)) * 0.032 * kw + hop, 0)
	parts["Body"].position = parts["Body"].position.lerp(bp, f)
	head.position = head.position.lerp(rest["Head"] + Vector3(0, (parts["Body"].position.y - rest["Body"].y) * 1.1, 0), f)
