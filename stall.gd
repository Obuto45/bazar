extends Node3D
## Oyuncu tezgahı: karaktere uygun boyutlu (masa 0.72m, tente 2.25m), başta boş 4 ürün yuvası,
## 3D fiyat etiketleri ve arkada 4 depo kasası (domates, elma, soğan, portakal).

const LP := preload("res://lowpoly.gd")
const WOOD := Color(0.55, 0.37, 0.22)
const AWNINGS := [
	Color(0.85, 0.22, 0.18), Color(0.2, 0.52, 0.85), Color(0.95, 0.72, 0.18), Color(0.28, 0.68, 0.32),
	Color(0.65, 0.34, 0.8), Color(0.95, 0.48, 0.62), Color(0.16, 0.72, 0.72), Color(0.95, 0.52, 0.16),
]
const ITEMS := {
	"domates": {"name": "Domates", "base": 10, "color": Color(0.92, 0.16, 0.14), "stem": Color(0.2, 0.62, 0.18)},
	"elma": {"name": "Elma", "base": 12, "color": Color(0.45, 0.78, 0.22), "stem": Color(0.38, 0.22, 0.1)},
	"sogan": {"name": "Soğan", "base": 8, "color": Color(0.84, 0.62, 0.28), "stem": Color(0.55, 0.42, 0.18)},
	"portakal": {"name": "Portakal", "base": 14, "color": Color(0.98, 0.52, 0.08), "stem": Color(0.22, 0.55, 0.16)},
}
const ITEM_ORDER := ["domates", "elma", "sogan", "portakal"]
const SLOT_XS := [-1.2, -0.4, 0.4, 1.2]
const MAX_SLOT_COUNT := 10
const CRATE_CAPACITY := 10

var owner_id := 0
var owner_name := ""
var awning_color := Color(0.85, 0.22, 0.18)
# Her yuva: {"item": String, "count": int, "price": int}
var slots: Array[Dictionary] = []
var crate_available: Dictionary = {} # item_id -> arkadaki tek kasa hâlâ orada mı?
var _crate_visuals: Dictionary = {} # item_id -> Node3D
var _crate_labels: Dictionary = {} # item_id -> Label3D
var _slot_visuals: Array[Node3D] = []
var _slot_labels: Array[Label3D] = []
var _sign_label: Label3D


func setup(p_owner_id: int, p_owner_name: String, color_idx: int) -> void:
	owner_id = p_owner_id
	owner_name = p_owner_name
	awning_color = AWNINGS[absi(color_idx) % AWNINGS.size()]
	name = "Stall_%d" % owner_id


func _ready() -> void:
	slots.clear()
	for i in 4:
		slots.append({"item": "", "count": 0, "price": 10})
	_build_geometry()
	_build_slots()
	_build_supply_crates()


func _build_geometry() -> void:
	# Karaktere (boy 1.4m, göz 1.16m) göre alçak, ergonomik tezgah (masa 0.56m, tente 2.08m)
	LP.add(self, LP.box(Vector3(3.4, 0.52, 0.92)), Vector3(0, 0.26, 0.25), WOOD) # gövde
	LP.add(self, LP.box(Vector3(3.52, 0.05, 1.02)), Vector3(0, 0.545, 0.25), WOOD.lightened(0.14)) # tabla
	LP.solid(self, Vector3(0, 0.285, 0.25), Vector3(3.5, 0.57, 1.02))
	# Dört köşe direk (yüksekliği 2.08m)
	for x in [-1.62, 1.62]:
		for z in [-0.75, 0.85]:
			LP.add(self, LP.cyl(0.05, 0.06, 2.10, 6), Vector3(x, 1.05, z), WOOD.darkened(0.22))
	# Çizgili eğik tente
	for i in 5:
		var c := awning_color if i % 2 == 0 else Color(0.96, 0.93, 0.86)
		LP.add(self, LP.box(Vector3(0.72, 0.05, 2.15)), Vector3(-1.44 + i * 0.72, 2.16, 0.12), c, Vector3(0.18, 0, 0))
	LP.add(self, LP.box(Vector3(3.64, 0.20, 0.04)), Vector3(0, 1.95, 1.16), awning_color) # ön saçak
	# Üstte oyuncu tezgah tabelası
	_sign_label = Label3D.new()
	_sign_label.text = (owner_name + " Tezgahı") if owner_name != "" else "Tezgah"
	_sign_label.position = Vector3(0, 1.96, 1.21)
	_sign_label.font_size = 34
	_sign_label.outline_size = 8
	_sign_label.modulate = Color(1.0, 0.96, 0.84)
	add_child(_sign_label)


func _build_slots() -> void:
	_slot_visuals.clear()
	_slot_labels.clear()
	for i in 4:
		var sx: float = SLOT_XS[i]
		# Boş ahşap ürün yuvası (başta boş, alçak masa üstü 0.59m)
		LP.add(self, LP.box(Vector3(0.72, 0.04, 0.66)), Vector3(sx, 0.59, 0.24), WOOD.darkened(0.28))
		LP.add(self, LP.box(Vector3(0.74, 0.06, 0.04)), Vector3(sx, 0.61, 0.56), WOOD.darkened(0.15))
		LP.add(self, LP.box(Vector3(0.74, 0.06, 0.04)), Vector3(sx, 0.61, -0.08), WOOD.darkened(0.15))
		# Ürün görsellerinin konteyneri
		var vis := Node3D.new()
		vis.position = Vector3(sx, 0.61, 0.24)
		add_child(vis)
		_slot_visuals.append(vis)
		# Ön kenarda dikili 3D fiyat etiketi çubuğu + karton tabela
		LP.add(self, LP.cyl(0.012, 0.014, 0.24, 5), Vector3(sx, 0.72, 0.60), WOOD.darkened(0.3))
		LP.add(self, LP.box(Vector3(0.46, 0.22, 0.02)), Vector3(sx, 0.86, 0.61), Color(0.98, 0.95, 0.84))
		var lbl := Label3D.new()
		lbl.position = Vector3(sx, 0.86, 0.63)
		lbl.font_size = 22
		lbl.outline_size = 6
		lbl.modulate = Color(0.12, 0.08, 0.05)
		lbl.outline_modulate = Color(1.0, 0.97, 0.88)
		lbl.double_sided = true
		add_child(lbl)
		_slot_labels.append(lbl)
		# Raycast etkileşim alanı (yuva + fiyat etiketi)
		var area := Area3D.new()
		area.name = "SlotArea_%d" % i
		area.collision_layer = 4
		area.collision_mask = 0
		area.set_meta("kind", "slot")
		area.set_meta("stall_owner", owner_id)
		area.set_meta("slot_idx", i)
		area.position = Vector3(sx, 0.78, 0.30)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.74, 0.52, 0.82)
		cs.shape = sh
		area.add_child(cs)
		add_child(area)
		_refresh_slot_visual(i)


## Tezgahın arkasında her meyve/sebzeden 1'er adet kasa (10'luk). E ile yerinden alınır.
func _build_supply_crates() -> void:
	crate_available.clear()
	_crate_visuals.clear()
	_crate_labels.clear()
	for i in ITEM_ORDER.size():
		var item_id: String = ITEM_ORDER[i]
		var info: Dictionary = ITEMS[item_id]
		crate_available[item_id] = true
		var cx: float = SLOT_XS[i]
		var spot := Node3D.new()
		spot.position = Vector3(cx, 0.0, -1.25)
		add_child(spot)
		# Yerdeki kasa altlığı (kasa alınınca yeri belli olsun)
		LP.add(spot, LP.box(Vector3(0.68, 0.03, 0.58)), Vector3(0, 0.015, 0), WOOD.darkened(0.38))
		# Kasa görseli (eline alınca yerinden kalkar)
		var c := Node3D.new()
		spot.add_child(c)
		LP.add(c, LP.box(Vector3(0.60, 0.30, 0.50)), Vector3(0, 0.16, 0), WOOD.lightened(0.06))
		LP.add(c, LP.box(Vector3(0.64, 0.04, 0.54)), Vector3(0, 0.31, 0), WOOD.darkened(0.18))
		for j in CRATE_CAPACITY:
			_add_produce_mesh(c, item_id, _crate_item_pos(j, 0.16, 0.12, 0.33), 0.072)
		_crate_visuals[item_id] = c
		var lbl := Label3D.new()
		lbl.text = "%s\n(%d ad.)" % [info["name"], CRATE_CAPACITY]
		lbl.position = Vector3(0, 0.60, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 22
		lbl.outline_size = 6
		lbl.modulate = Color(1.0, 0.96, 0.85)
		spot.add_child(lbl)
		_crate_labels[item_id] = lbl
		# Etkileşim alanı (layer 4)
		var area := Area3D.new()
		area.name = "CrateArea_%s" % item_id
		area.collision_layer = 4
		area.collision_mask = 0
		area.set_meta("kind", "crate")
		area.set_meta("stall_owner", owner_id)
		area.set_meta("item_id", item_id)
		area.position = Vector3(0, 0.32, 0)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.72, 0.68, 0.64)
		cs.shape = sh
		area.add_child(cs)
		spot.add_child(area)


static func _crate_item_pos(j: int, sx: float, sz: float, y0: float) -> Vector3:
	if j < 6:
		return Vector3(-sx + (j % 3) * sx, y0, -sz * 0.6 + int(j / 3) * (sz * 1.2))
	var k := j - 6
	return Vector3(-sx * 0.5 + (k % 2) * sx, y0 + 0.095, -sz * 0.45 + int(k / 2) * (sz * 0.9))


static func _slot_item_local_pos(j: int) -> Vector3:
	if j < 6:
		var col := j % 3
		var row := int(j / 3)
		return Vector3(-0.20 + col * 0.20, 0.07, -0.13 + row * 0.26)
	var k := j - 6
	var col := k % 2
	var row := int(k / 2)
	return Vector3(-0.10 + col * 0.20, 0.19, -0.07 + row * 0.14)


static func _add_produce_mesh(parent: Node, item_id: String, pos: Vector3, radius := 0.08) -> Node3D:
	var info: Dictionary = ITEMS.get(item_id, ITEMS["domates"])
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	LP.add(holder, LP.sphere(radius, 6, 4), Vector3.ZERO, info["color"])
	LP.add(holder, LP.cyl(radius * 0.12, radius * 0.18, radius * 0.65, 5), Vector3(0, radius * 0.95, 0), info["stem"])
	return holder


## Elde tutulan veya fırlatılan 3D kasa: içindeki ürün sayısı (count: 0..10) birebir görünür.
static func build_held_crate(item_id: String, count: int) -> Node3D:
	var n := Node3D.new()
	# İçi boş ahşap kasa (taban + 4 duvar, boşken içi açıkça boş görünür!)
	LP.add(n, LP.box(Vector3(0.42, 0.03, 0.34)), Vector3(0, -0.09, 0), WOOD.darkened(0.15))
	LP.add(n, LP.box(Vector3(0.42, 0.18, 0.03)), Vector3(0, 0.0, 0.155), WOOD.lightened(0.08))
	LP.add(n, LP.box(Vector3(0.42, 0.18, 0.03)), Vector3(0, 0.0, -0.155), WOOD.lightened(0.08))
	LP.add(n, LP.box(Vector3(0.03, 0.18, 0.30)), Vector3(-0.195, 0.0, 0), WOOD.lightened(0.04))
	LP.add(n, LP.box(Vector3(0.03, 0.18, 0.30)), Vector3(0.195, 0.0, 0), WOOD.lightened(0.04))
	if item_id != "" and ITEMS.has(item_id):
		for j in clampi(count, 0, CRATE_CAPACITY):
			_add_produce_mesh(n, item_id, _crate_item_pos(j, 0.11, 0.08, -0.02), 0.052)
	return n


func set_owner_display_name(n: String) -> void:
	owner_name = n
	if _sign_label:
		_sign_label.text = n + " Tezgahı"


## Müşterinin tezgah önünde duracağı dünya noktası ve bakacağı yön.
func customer_spot(slot_offset := 0.0) -> Vector3:
	return to_global(Vector3(slot_offset, 0.0, 1.55))


## Oyuncunun kendi tezgahının arkasındaki spawn noktası.
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
	if item_id == "" or cnt <= 0:
		lbl.text = "BOŞ"
		lbl.modulate = Color(0.45, 0.4, 0.35)
		return
	var info: Dictionary = ITEMS[item_id]
	lbl.text = "%s\n%d TL\n(%d)" % [info["name"], price, cnt]
	lbl.modulate = Color(0.1, 0.07, 0.04)
	# Piramit düzeninde yerleştirilen ürünler (en fazla 10 adet)
	for j in mini(cnt, MAX_SLOT_COUNT):
		_add_produce_mesh(vis, item_id, _slot_item_local_pos(j), 0.082)


func has_supply_crate(item_id: String) -> bool:
	return bool(crate_available.get(item_id, false))


func request_take_crate(item_id: String) -> bool:
	if not has_supply_crate(item_id):
		return false
	if Net.online():
		rpc_set_crate_available.rpc(item_id, false)
	else:
		rpc_set_crate_available(item_id, false)
	return true


func request_restock_crate(item_id: String) -> void:
	if has_supply_crate(item_id):
		return
	if Net.online():
		rpc_set_crate_available.rpc(item_id, true)
	else:
		rpc_set_crate_available(item_id, true)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_crate_available(item_id: String, avail: bool) -> void:
	crate_available[item_id] = avail
	if _crate_visuals.has(item_id):
		(_crate_visuals[item_id] as Node3D).visible = avail
	if _crate_labels.has(item_id):
		var lbl: Label3D = _crate_labels[item_id]
		var nm: String = ITEMS[item_id]["name"]
		lbl.text = "%s\n(%d ad.)" % [nm, CRATE_CAPACITY] if avail else "%s\n[E: Yeni Kasa]" % nm
		lbl.modulate = Color(1.0, 0.96, 0.85) if avail else Color(0.75, 0.72, 0.65, 0.75)


func can_place(idx: int, item_id: String) -> bool:
	if idx < 0 or idx >= slots.size() or not ITEMS.has(item_id):
		return false
	var s := slots[idx]
	return (s["item"] == "" or s["count"] == 0 or s["item"] == item_id) and s["count"] < MAX_SLOT_COUNT


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


## Bir ürün yerleştirir; kasadan tezgah yuvasına yay çizerek uçuş animasyonu oynatır.
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
	slots[idx] = {"item": item_id, "count": clampi(count, 0, MAX_SLOT_COUNT), "price": clampi(price, 1, 99)}
	if from_world_pos == Vector3.ZERO:
		_refresh_slot_visual(idx)
		return
	var vis := _slot_visuals[idx]
	var target_local := _slot_item_local_pos(clampi(count - 1, 0, MAX_SLOT_COUNT - 1))
	var target_world := vis.to_global(target_local)
	var mid_world := (from_world_pos + target_world) * 0.5 + Vector3(0.0, 0.34, 0.0)
	var fly := _add_produce_mesh(self, item_id, to_local(from_world_pos), 0.082)
	var p0 := to_local(from_world_pos)
	var p1 := to_local(mid_world)
	var p2 := to_local(target_world)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(fly):
			var u := 1.0 - t
			fly.position = u * u * p0 + 2.0 * u * t * p1 + t * t * p2
			fly.rotation.x = t * PI * 1.2
			fly.scale = Vector3.ONE * lerpf(0.72, 1.08, t)
	, 0.0, 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(fly):
			fly.queue_free()
		_refresh_slot_visual(idx)
	)


## Fiyatı delta kadar (+1/-1 TL) değiştirir.
func request_adjust_price(idx: int, delta: int) -> void:
	if idx < 0 or idx >= slots.size():
		return
	var s := slots[idx]
	if s["item"] == "" or s["count"] <= 0:
		return
	var np := clampi(int(s["price"]) + delta, 1, 99)
	if np == int(s["price"]):
		return
	if Net.online():
		rpc_sync_slot.rpc(idx, s["item"], int(s["count"]), np)
	else:
		rpc_sync_slot(idx, s["item"], int(s["count"]), np)


## Satışta belirtilen üründen 1 adet düşer ve satış fiyatını döndürür (yoksa 0).
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
	return best_price


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_slot(idx: int, item_id: String, count: int, price: int) -> void:
	if idx < 0 or idx >= slots.size():
		return
	slots[idx] = {"item": item_id, "count": clampi(count, 0, MAX_SLOT_COUNT), "price": clampi(price, 1, 99)}
	_refresh_slot_visual(idx)


## Pazardaki tüm tezgahlara göre göreceli fiyat cazibesi (0.0 .. 1.25).
## 10 TL ile 9 TL gibi küçük farklar (%12 bant içi) neredeyse aynı seviyede değerlendirilir.
static func relative_price_score(item_id: String, price: int, all_stalls: Array) -> float:
	var base: float = float(ITEMS.get(item_id, {"base": 10})["base"])
	var sum_p := 0.0
	var n := 0
	for st in all_stalls:
		if st.has_item(item_id):
			sum_p += float(st.get_item_price(item_id))
			n += 1
	var market_avg := (sum_p / float(n)) if n > 0 else base
	var ref := lerpf(base, market_avg, 0.65)
	var ratio := float(price) / maxf(ref, 1.0)
	# %12'lik tolerans bandı (ör. 9 TL ile 10 TL) neredeyse eşit cazibe verir
	if absf(ratio - 1.0) <= 0.12:
		return 1.0 - (ratio - 1.0) * 0.35
	if ratio < 0.88:
		# Ucuzlaştıkça cazibe artar (maks 1.28)
		return clampf(1.04 + (0.88 - ratio) * 0.75, 1.0, 1.28)
	# Pahalılaştıkça cazibe düşer; 2.2x üstü neredeyse kimse almaz
	return clampf(0.96 - (ratio - 1.12) * 0.92, 0.04, 0.96)
