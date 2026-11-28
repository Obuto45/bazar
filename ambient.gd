extends Node3D
## Kozmetik mahalle hayatı (sadece yerel, senkronize edilmez):
## kasalarda uyuyan / oturan kediler, gezinen bir tekir, oyuncu koşunca havalanan güvercin sürüsü (tek MultiMesh),
## sırtında simit tablası taşıyan simitçi ve askılı tepsiyle dolaşan çaycı.
## bazaar.gd tarafından oluşturulur; oyuncuları World/Players altında arar (yoksa sessizce çalışır).

const LP := preload("res://lowpoly.gd")
const VFX := preload("res://vfx.gd")
const CHAR_SIMITCI := preload("res://models/char_simitci.glb")
const CHAR_CAYCI := preload("res://models/char_cayci.glb")
const SIMIT_MODEL := preload("res://models/simit.glb")
const TEA_MODEL := preload("res://models/turkish_tea.glb")
const StallScript := preload("res://stall.gd")

const PIGEON_SHADER := """
shader_type spatial;
render_mode cull_disabled;
vec3 to_lin(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}
void vertex() {
	float flap = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g;
	float peck = INSTANCE_CUSTOM.b;
	float ax = abs(VERTEX.x);
	if (ax > 0.075) {
		float fold = mix(0.42, 1.0, flap);
		float r = (ax - 0.07) * fold;
		float ang = sin(TIME * 24.0 + ph) * 1.05 * flap;
		VERTEX.x = sign(VERTEX.x) * (0.07 + r * cos(ang));
		VERTEX.y += r * sin(ang);
	}
	float head = smoothstep(-0.085, -0.13, VERTEX.z);
	float pk = peck * max(0.0, sin(TIME * 7.0 + ph * 3.0));
	VERTEX.y -= head * pk * 0.06;
	VERTEX.z -= head * pk * 0.025;
}
void fragment() {
	ALBEDO = to_lin(COLOR.rgb);
	ROUGHNESS = 0.8;
}
"""

const CAT_COLS := [
	[Color(0.92, 0.56, 0.22), Color(0.98, 0.9, 0.8)], # sarman
	[Color(0.12, 0.12, 0.13), Color(0.95, 0.95, 0.95)], # kara
	[Color(0.56, 0.56, 0.6), Color(0.85, 0.85, 0.86)], # tekir gri
	[Color(0.96, 0.95, 0.92), Color(0.85, 0.5, 0.2)], # beyaz-sarı
]

enum PState { GROUND, FLY_UP, PERCHED, RETURN, FEED }

const VENDOR_OFFERS := {
	"cay": {"price": 12, "hint": "[E] 🍵 Ayağına gelen çay — 12 TL  (Kıraathanede 10 TL)",
		"ask": "Abi çay ister misin?\nTavşan kanı, 12 lira!", "thanks": "Afiyet olsun abi, sıcak iç!", "bye": "Sonra uğrarım abi!"},
	"simit": {"price": 18, "hint": "[E] 🥯 Ayağına gelen simit — 18 TL  (Fırında 15 TL)",
		"ask": "Sıcak simit abi?\nÇıtır çıtır, 18 lira!", "thanks": "Bereket versin abi, çıtır çıtır!", "bye": "Kolay gelsin abi!"},
}

var bazaar: Node3D
var cat_spots: Array = []

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _cat_mat: ShaderMaterial
var _sleepers: Array = [] # [Node3D, phase, Node3D tail or null]
var _walker: Dictionary = {}
var _people: Array = []
var _mm: MultiMesh
var _pigeons: Array = []
var _flocks: Array = []
var _players: Node
var _prev_pos := {}


func _ready() -> void:
	# Kedi/yürüyen/güvercinler _process'te hareket eder; fizik interpolasyonu açıkken bu titreme yapar
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 2024
	_cat_mat = LP.batch_material(0.9, 0.0, 0.0)
	_build_cats()
	_build_pigeons()
	add_to_group("ambient")
	_build_people()


func _process(dt: float) -> void:
	_t += dt
	for s in _sleepers:
		var n: Node3D = s[0]
		var ph: float = s[1]
		n.scale = Vector3(1.0, 1.0 + sin(_t * 1.9 + ph) * 0.045, 1.0 + sin(_t * 1.9 + ph) * 0.02)
		if s[2] != null:
			(s[2] as Node3D).rotation.y = sin(_t * 1.3 + ph) * 0.5
	_tick_walker(dt)
	for p in _people:
		_tick_person(p, dt)
	_tick_pigeons(dt)


# ---------------------------------------------------------------------------
# Kediler
# ---------------------------------------------------------------------------

func _cat_body(b, cols: Array, mode: int) -> void:
	var c: Color = cols[0]
	var c2: Color = cols[1]
	var eye := Color(0.35, 0.75, 0.2)
	match mode:
		0: # uyuyan: kıvrılmış top
			b.ellipsoid(Vector3(0.17, 0.09, 0.13), Vector3(0, 0.09, 0), c, Vector3.ZERO, 8, 4)
			b.ellipsoid(Vector3(0.1, 0.05, 0.09), Vector3(0.03, 0.13, 0.02), c2, Vector3.ZERO, 6, 3)
			b.sphere(0.07, Vector3(-0.12, 0.09, 0.06), c, 7, 4)
			b.prism(Vector3(0.04, 0.05, 0.02), Vector3(-0.15, 0.15, 0.04), c, Vector3(0, 0.4, 0.5))
			b.prism(Vector3(0.04, 0.05, 0.02), Vector3(-0.11, 0.16, 0.1), c, Vector3(0, 0.4, 0.2))
			b.ellipsoid(Vector3(0.14, 0.03, 0.035), Vector3(0.0, 0.035, 0.13), c, Vector3(0, 0.3, 0), 6, 3)
		1: # oturan
			b.ellipsoid(Vector3(0.1, 0.15, 0.11), Vector3(0, 0.14, 0), c, Vector3.ZERO, 8, 4)
			b.ellipsoid(Vector3(0.06, 0.08, 0.04), Vector3(0, 0.14, -0.08), c2, Vector3.ZERO, 6, 3)
			b.sphere(0.075, Vector3(0, 0.31, -0.03), c, 7, 4)
			b.prism(Vector3(0.045, 0.06, 0.02), Vector3(-0.04, 0.39, -0.03), c, Vector3(0, 0, 0.2))
			b.prism(Vector3(0.045, 0.06, 0.02), Vector3(0.04, 0.39, -0.03), c, Vector3(0, 0, -0.2))
			b.sphere(0.012, Vector3(-0.028, 0.32, -0.095), eye, 4, 2)
			b.sphere(0.012, Vector3(0.028, 0.32, -0.095), eye, 4, 2)
			b.ellipsoid(Vector3(0.03, 0.03, 0.06), Vector3(-0.05, 0.03, -0.08), c2, Vector3.ZERO, 5, 3)
			b.ellipsoid(Vector3(0.03, 0.03, 0.06), Vector3(0.05, 0.03, -0.08), c2, Vector3.ZERO, 5, 3)
		2: # yürüyen gövde (bacaklar ayrı)
			b.ellipsoid(Vector3(0.08, 0.075, 0.19), Vector3(0, 0.22, 0), c, Vector3.ZERO, 8, 4)
			b.ellipsoid(Vector3(0.06, 0.04, 0.12), Vector3(0, 0.18, -0.02), c2, Vector3.ZERO, 6, 3)
			b.sphere(0.075, Vector3(0, 0.3, -0.2), c, 7, 4)
			b.ellipsoid(Vector3(0.035, 0.03, 0.03), Vector3(0, 0.28, -0.265), c2, Vector3.ZERO, 5, 3)
			b.prism(Vector3(0.045, 0.06, 0.02), Vector3(-0.04, 0.38, -0.2), c, Vector3(0, 0, 0.2))
			b.prism(Vector3(0.045, 0.06, 0.02), Vector3(0.04, 0.38, -0.2), c, Vector3(0, 0, -0.2))
			b.sphere(0.012, Vector3(-0.03, 0.31, -0.265), eye, 4, 2)
			b.sphere(0.012, Vector3(0.03, 0.31, -0.265), eye, 4, 2)


func _make_mesh(b) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b.verts
	arr[Mesh.ARRAY_NORMAL] = b.norms
	arr[Mesh.ARRAY_COLOR] = b.cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _mesh_node(parent: Node, b, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _make_mesh(b)
	mi.material_override = _cat_mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_cats() -> void:
	var spots := cat_spots.duplicate()
	var n := mini(5, spots.size())
	for i in n:
		var idx := _rng.randi() % spots.size()
		var sp: Array = spots[idx]
		spots.remove_at(idx)
		var root := Node3D.new()
		root.position = sp[0]
		root.rotation.y = float(sp[1]) + _rng.randf_range(-0.6, 0.6)
		add_child(root)
		var mode := 0 if i % 3 != 2 else 1
		var b := LP.batch()
		_cat_body(b, CAT_COLS[i % CAT_COLS.size()], mode)
		_mesh_node(root, b)
		var tail: Node3D = null
		if mode == 1:
			tail = Node3D.new()
			tail.position = Vector3(0, 0.04, 0.1)
			root.add_child(tail)
			var tb := LP.batch()
			tb.ellipsoid(Vector3(0.025, 0.025, 0.13), Vector3(0, 0, 0.11), CAT_COLS[i % CAT_COLS.size()][0], Vector3(0, 0, 0), 5, 3)
			_mesh_node(tail, tb)
		_sleepers.append([root, _rng.randf() * TAU, tail])
	# Gezinen tekir: batı kaldırımında palet ve banklardan temiz hat üzerinde volta atar
	var root2 := Node3D.new()
	root2.position = Vector3(-10.8, 0.04, -8.0)
	add_child(root2)
	var cols: Array = CAT_COLS[0]
	var bb := LP.batch()
	_cat_body(bb, cols, 2)
	var body := _mesh_node(root2, bb)
	var legs: Array[Node3D] = []
	for lp in [Vector3(-0.05, 0.19, -0.12), Vector3(0.05, 0.19, -0.12), Vector3(-0.05, 0.19, 0.12), Vector3(0.05, 0.19, 0.12)]:
		var leg := Node3D.new()
		leg.position = lp
		root2.add_child(leg)
		var lb := LP.batch()
		lb.box(Vector3(0.035, 0.19, 0.035), Vector3(0, -0.095, 0), cols[0])
		lb.box(Vector3(0.04, 0.025, 0.05), Vector3(0, -0.18, -0.01), cols[1])
		_mesh_node(leg, lb)
		legs.append(leg)
	var tail2 := Node3D.new()
	tail2.position = Vector3(0, 0.26, 0.17)
	root2.add_child(tail2)
	var tb2 := LP.batch()
	tb2.ellipsoid(Vector3(0.022, 0.022, 0.14), Vector3(0, 0.05, 0.12), cols[0], Vector3(-0.6, 0, 0), 5, 3)
	_mesh_node(tail2, tb2)
	_walker = {"root": root2, "body": body, "legs": legs, "tail": tail2,
		"pts": [Vector3(-10.8, 0.04, -9.0), Vector3(-10.8, 0.04, -3.2), Vector3(-10.8, 0.04, 3.4), Vector3(-10.8, 0.04, 8.8)],
		"i": 1, "dir": 1, "wait": 1.0, "speed": 0.75}


## Kedi besleme: ~9 m içindeki gezgin tekir yeme koşar, yer, sonra besleyenin tezgahına gidip miyavlar.
func feed_cat_at(food_pos: Vector3, stall_pos: Vector3) -> void:
	if _walker.is_empty():
		return
	var root: Node3D = _walker["root"]
	var fl := to_local(food_pos)
	if Vector2(root.position.x - fl.x, root.position.z - fl.z).length() > 9.0 or str(_walker.get("visit", "")) != "":
		return
	fl.y = 0.04 if absf(fl.x) > 4.25 else 0.0
	var sl := StallScript.world_keepout_all(self, to_local(stall_pos))
	sl.y = 0.04 if absf(sl.x) > 4.25 else 0.0
	_walker["visit"] = "eat"
	_walker["food"] = fl
	_walker["stall"] = sl
	_walker["visit_t"] = 0.0
	_walker["wait"] = 0.0
	_walker["speed_v"] = 1.6
	SteamMgr.unlock("ACH_CAT_FRIEND")


## Ziyaret modunda: hedefe yürü (engel sakınmalı; döndürür true = vardı).
func _walker_go(root: Node3D, legs: Array[Node3D], target: Vector3, spd: float, dt: float) -> bool:
	var to := target - root.position
	to.y = 0.0
	var d := to.length()
	if d < 0.15 or float(_walker.get("visit_t", 0.0)) > 16.0:
		for l in legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, dt * 6.0)
		return true
	var dir := StallScript.world_steer_all(self, root.position, to / d, d - 0.1)
	var np := StallScript.world_keepout_all(self, root.position + dir * minf(d, spd * dt))
	np.y = lerpf(root.position.y, 0.04 if absf(np.x) > 4.25 else 0.0, minf(dt * 10.0, 1.0))
	root.position = np
	root.rotation.y = lerp_angle(root.rotation.y, atan2(-dir.x, -dir.z), dt * 6.0)
	var ph := _t * 12.0
	legs[0].rotation.x = sin(ph) * 0.6
	legs[3].rotation.x = sin(ph) * 0.6
	legs[1].rotation.x = -sin(ph) * 0.6
	legs[2].rotation.x = -sin(ph) * 0.6
	return false


func _tick_cat_visit(dt: float, root: Node3D, legs: Array[Node3D]) -> void:
	var mode := str(_walker["visit"])
	_walker["visit_t"] = float(_walker["visit_t"]) + dt
	if mode == "eat":
		if _walker_go(root, legs, _walker["food"], 1.6, dt):
			_walker["visit"] = "eating"
			_walker["visit_t"] = 0.0
	elif mode == "eating":
		root.rotation.x = lerpf(root.rotation.x, 0.12 * (0.5 + 0.5 * sin(_t * 9.0)), dt * 8.0)
		if float(_walker["visit_t"]) > 2.5:
			root.rotation.x = 0.0
			_walker["visit"] = "go_stall"
			_cat_meow(root)
	elif mode == "go_stall":
		if _walker_go(root, legs, _walker["stall"], 1.2, dt):
			_walker["visit"] = "sit"
			_walker["visit_t"] = 0.0
			_walker["meow_t"] = 1.0
	elif mode == "sit":
		_walker["meow_t"] = float(_walker["meow_t"]) - dt
		if float(_walker["meow_t"]) <= 0.0:
			_walker["meow_t"] = _rng.randf_range(4.0, 8.0)
			_cat_meow(root)
		if float(_walker["visit_t"]) > 45.0:
			_walker["visit"] = ""


func _cat_meow(root: Node3D) -> void:
	var p := root.global_position + Vector3(0, 0.45, 0)
	Sfx.play_3d("cat", p, self, -4.0, _rng.randf_range(0.95, 1.15), 16.0)
	VFX.spawn_floating_text(self, p + Vector3(0, 0.2, 0), "🐱 Miyav!", Color(1.0, 0.9, 0.6), 30)


func _tick_walker(dt: float) -> void:
	if _walker.is_empty():
		return
	var root: Node3D = _walker["root"]
	var legs: Array[Node3D] = _walker["legs"]
	var tail: Node3D = _walker["tail"]
	tail.rotation.y = sin(_t * 2.2) * 0.35
	if str(_walker.get("visit", "")) != "":
		_tick_cat_visit(dt, root, legs)
		return
	if float(_walker["wait"]) > 0.0:
		_walker["wait"] = float(_walker["wait"]) - dt
		for l in legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, dt * 6.0)
		return
	var pts: Array = _walker["pts"]
	var target: Vector3 = pts[int(_walker["i"])]
	var to := target - root.position
	to.y = 0.0
	var d := to.length()
	if d < 0.05:
		var ni := int(_walker["i"]) + int(_walker["dir"])
		if ni < 0 or ni >= pts.size():
			_walker["dir"] = -int(_walker["dir"])
			ni = int(_walker["i"]) + int(_walker["dir"])
		_walker["i"] = ni
		_walker["wait"] = _rng.randf_range(1.0, 5.0) if _rng.randf() < 0.6 else 0.0
		return
	var step := minf(d, float(_walker["speed"]) * dt)
	root.position += to / d * step
	root.rotation.y = lerp_angle(root.rotation.y, atan2(-to.x, -to.z), dt * 6.0)
	var ph := _t * 9.0
	legs[0].rotation.x = sin(ph) * 0.55
	legs[3].rotation.x = sin(ph) * 0.55
	legs[1].rotation.x = -sin(ph) * 0.55
	legs[2].rotation.x = -sin(ph) * 0.55


# ---------------------------------------------------------------------------
# Güvercinler (tek MultiMesh, kanat çırpma shader'da)
# ---------------------------------------------------------------------------

func _build_pigeons() -> void:
	var b := LP.batch()
	var grey := Color(0.56, 0.6, 0.66)
	b.ellipsoid(Vector3(0.065, 0.06, 0.12), Vector3(0, 0.1, 0), grey, Vector3(-0.15, 0, 0), 7, 4)
	b.ellipsoid(Vector3(0.045, 0.045, 0.05), Vector3(0, 0.14, -0.08), Color(0.36, 0.5, 0.48), Vector3.ZERO, 6, 3)
	b.sphere(0.04, Vector3(0, 0.18, -0.115), Color(0.48, 0.52, 0.6), 6, 3)
	b.prism(Vector3(0.016, 0.03, 0.016), Vector3(0, 0.175, -0.16), Color(0.25, 0.22, 0.22), Vector3(-PI / 2, 0, 0))
	b.box(Vector3(0.07, 0.01, 0.09), Vector3(0, 0.1, 0.15), Color(0.3, 0.32, 0.38), Vector3(0.2, 0, 0))
	for s in [-1.0, 1.0]:
		b.box(Vector3(0.13, 0.012, 0.1), Vector3(s * 0.135, 0.12, 0.0), Color(0.5, 0.54, 0.6))
		b.box(Vector3(0.012, 0.06, 0.012), Vector3(s * 0.025, 0.03, 0.0), Color(0.8, 0.35, 0.35))
	var sh := Shader.new()
	sh.code = PIGEON_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mesh := _make_mesh(b)
	mesh.surface_set_material(0, mat)
	_flocks = [
		{"home": Vector3(-2.9, 0.0, -2.4), "perch_z": -4.5, "perch_x": [-3.6, -0.6], "cd": 0.0},
		{"home": Vector3(2.0, 0.0, -16.6), "perch_z": -17.5, "perch_x": [0.6, 3.6], "cd": 0.0},
	]
	var per := 9
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = per * _flocks.size()
	for fi in _flocks.size():
		for k in per:
			var home: Vector3 = _flocks[fi]["home"]
			var p := home + Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))
			var pg := {"pos": p, "yaw": _rng.randf() * TAU, "state": PState.GROUND, "flock": fi,
				"a": p, "c": p, "e": p, "t": 0.0, "dur": 1.0, "wait": 0.0,
				"walk": p, "ph": _rng.randf() * TAU, "flap": 0.0, "peck": 1.0}
			_pigeons.append(pg)
			var tint := Color(1, 1, 1).darkened(_rng.randf_range(0.0, 0.3))
			if _rng.randf() < 0.15:
				tint = Color(1.3, 1.2, 1.1)
			_mm.set_instance_color(_pigeons.size() - 1, tint)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


func _scare_check(dt: float) -> void:
	if _players == null or not is_instance_valid(_players):
		_players = null
		if bazaar and bazaar.get_parent():
			_players = bazaar.get_parent().get_node_or_null("Players")
		if _players == null:
			return
	for f in _flocks:
		f["cd"] = maxf(0.0, float(f["cd"]) - dt)
	for pl in _players.get_children():
		if not (pl is Node3D):
			continue
		var pos: Vector3 = (pl as Node3D).global_position
		var id := pl.get_instance_id()
		var spd := 0.0
		if _prev_pos.has(id):
			spd = (pos - (_prev_pos[id] as Vector3)).length() / maxf(dt, 0.001)
		_prev_pos[id] = pos
		for fi in _flocks.size():
			var f: Dictionary = _flocks[fi]
			if float(f["cd"]) > 0.0:
				continue
			# Yalnızca yuvaya değil, yemlenen/gezen kuşların gerçek konumuna bak
			var near_bird := false
			for pg in _pigeons:
				if int(pg["flock"]) != fi or not (int(pg["state"]) in [PState.GROUND, PState.FEED]):
					continue
				var bp: Vector3 = pg["pos"]
				var bd := Vector2(pos.x - bp.x, pos.z - bp.z).length()
				if bd < 1.9 or (bd < 4.6 and spd > 4.6 and spd < 30.0):
					near_bird = true
					break
			if near_bird:
				_burst(fi, pos)


func _burst(fi: int, from: Vector3) -> void:
	var f: Dictionary = _flocks[fi]
	f["cd"] = 6.0
	var any := false
	var px: Array = f["perch_x"]
	for pg in _pigeons:
		if int(pg["flock"]) != fi or not (int(pg["state"]) in [PState.GROUND, PState.FEED]):
			continue
		any = true
		var a: Vector3 = pg["pos"]
		var away := Vector3(a.x - from.x, 0, a.z - from.z).normalized()
		var e := Vector3(_rng.randf_range(float(px[0]), float(px[1])), 4.19, float(f["perch_z"]) + _rng.randf_range(-0.02, 0.02))
		if _rng.randf() < 0.3:
			e = Vector3(signf(a.x + 0.01) * 14.8 + _rng.randf_range(-0.2, 0.2), 7.6, a.z + _rng.randf_range(-3.0, 3.0))
		pg["state"] = PState.FLY_UP
		pg["a"] = a
		pg["c"] = a + away * 2.2 + Vector3(0, 3.2, 0)
		pg["e"] = e
		pg["t"] = 0.0
		pg["dur"] = _rng.randf_range(1.3, 2.1)
		pg["peck"] = 0.0
		pg["feed_t"] = 0.0
	if any:
		var home: Vector3 = f["home"]
		VFX.spawn_feathers(self, home + Vector3(0, 0.4, 0), 6)
		var sfx := get_node_or_null("/root/Sfx")
		if sfx and sfx.has_method("play_3d"):
			sfx.play_3d("pigeon_flap", home, null, -2.0)


func _tick_pigeons(dt: float) -> void:
	if _mm == null:
		return
	_scare_check(dt)
	for i in _pigeons.size():
		var pg: Dictionary = _pigeons[i]
		var st := int(pg["state"])
		var pos: Vector3 = pg["pos"]
		var flap := 0.0
		match st:
			PState.GROUND:
				var w: Vector3 = pg["walk"]
				var to := w - pos
				if to.length() < 0.03:
					pg["wait"] = float(pg["wait"]) - dt
					if float(pg["wait"]) <= 0.0:
						var home: Vector3 = _flocks[int(pg["flock"])]["home"]
						pg["walk"] = home + Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))
						pg["wait"] = _rng.randf_range(0.8, 4.0)
					pg["peck"] = minf(1.0, float(pg["peck"]) + dt * 2.0)
				else:
					var stp := minf(to.length(), 0.35 * dt)
					pos += to.normalized() * stp
					pos.y = absf(sin(_t * 14.0 + float(pg["ph"]))) * 0.012
					pg["yaw"] = lerp_angle(float(pg["yaw"]), atan2(-to.x, -to.z), dt * 8.0)
					pg["peck"] = 0.0
			PState.FLY_UP, PState.RETURN:
				var t := minf(1.0, float(pg["t"]) + dt / float(pg["dur"]))
				pg["t"] = t
				var a: Vector3 = pg["a"]; var c: Vector3 = pg["c"]; var e: Vector3 = pg["e"]
				var np := a.lerp(c, t).lerp(c.lerp(e, t), t)
				var mv := np - pos
				if mv.length() > 0.001:
					pg["yaw"] = lerp_angle(float(pg["yaw"]), atan2(-mv.x, -mv.z), dt * 10.0)
				pos = np
				flap = 1.0 if (st == PState.FLY_UP or t < 0.25 or t > 0.85) else 0.25
				if t >= 1.0:
					if st == PState.FLY_UP:
						pg["state"] = PState.PERCHED
						pg["wait"] = _rng.randf_range(7.0, 15.0)
						pg["yaw"] = float(pg["yaw"]) + _rng.randf_range(-0.5, 0.5)
					elif float(pg.get("feed_t", 0.0)) > 0.0:
						# Yem noktasına indi: gagalamaya başlar
						pg["state"] = PState.FEED
						pg["walk"] = pos
						pg["wait"] = 0.0
						pos.y = 0.0
					else:
						pg["state"] = PState.GROUND
						pg["walk"] = pos
						pg["wait"] = _rng.randf_range(0.5, 2.0)
						pos.y = 0.0
			PState.FEED:
				# Yemi gagalar, ufak ufak yer değiştirir; süre bitince sürüsüne geri uçar
				pg["feed_t"] = float(pg["feed_t"]) - dt
				var fp: Vector3 = pg["feed_pt"]
				var fw: Vector3 = pg["walk"]
				var fto := fw - pos
				if fto.length() < 0.03:
					pg["wait"] = float(pg["wait"]) - dt
					if float(pg["wait"]) <= 0.0:
						pg["walk"] = fp + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5))
						pg["wait"] = _rng.randf_range(0.5, 1.4)
					pg["peck"] = minf(1.0, float(pg["peck"]) + dt * 2.0)
				else:
					pos += fto.normalized() * minf(fto.length(), 0.5 * dt)
					pos.y = absf(sin(_t * 14.0 + float(pg["ph"]))) * 0.012
					pg["yaw"] = lerp_angle(float(pg["yaw"]), atan2(-fto.x, -fto.z), dt * 8.0)
					pg["peck"] = 0.0
				if float(pg["feed_t"]) <= 0.0:
					var home3: Vector3 = _flocks[int(pg["flock"])]["home"]
					var e3 := home3 + Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))
					pg["state"] = PState.RETURN
					pg["a"] = pos
					pg["c"] = pos.lerp(e3, 0.5) + Vector3(0, 1.4, 0)
					pg["e"] = e3
					pg["t"] = 0.0
					pg["dur"] = clampf(pos.distance_to(e3) * 0.18, 1.0, 3.5)
			PState.PERCHED:
				pg["wait"] = float(pg["wait"]) - dt
				if float(pg["wait"]) <= 0.0:
					var home2: Vector3 = _flocks[int(pg["flock"])]["home"]
					var e2 := home2 + Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))
					pg["state"] = PState.RETURN
					pg["a"] = pos
					pg["c"] = pos.lerp(e2, 0.5) + Vector3(0, 1.2, 0)
					pg["e"] = e2
					pg["t"] = 0.0
					pg["dur"] = _rng.randf_range(2.0, 3.2)
		pg["pos"] = pos
		pg["flap"] = lerpf(float(pg["flap"]), flap, minf(1.0, dt * 10.0))
		var peck := float(pg["peck"]) if st == PState.GROUND or st == PState.FEED else 0.0
		_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(pg["yaw"])), pos))
		_mm.set_instance_custom_data(i, Color(float(pg["flap"]), float(pg["ph"]), peck, 0.0))


# ---------------------------------------------------------------------------
# Simitçi ve çaycı
# ---------------------------------------------------------------------------

func _make_person(kind: String) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	# Blender modeli (char_simitci / char_cayci): yüzer eller/ayaklar. Model +Z'ye bakar,
	# yürüyüş kodu -Z'ye baktığı için 180° çevrilir. Body+Head "body" düğümünde (sallanma),
	# eller kol pivotlarında, ayaklar bacak pivotlarında: eski bacak/kol salınımı aynen çalışır.
	var src: Node3D = (CHAR_SIMITCI if kind == "simit" else CHAR_CAYCI).instantiate()
	var flip := Basis(Vector3.UP, PI)
	var body := Node3D.new()
	body.name = "Figure"
	root.add_child(body)
	var take := func(n: String) -> Node3D:
		var m: Node3D = src.find_child(n, true, false)
		var pos := flip * m.position
		m.get_parent().remove_child(m)
		m.owner = null
		m.transform = Transform3D(flip, Vector3.ZERO)
		m.set_meta("rest", pos)
		return m
	for n in ["Body", "Head"]:
		var m: Node3D = take.call(n)
		body.add_child(m)
		m.position = m.get_meta("rest")
	if kind == "simit":
		# Baştaki halka bezin üstünde simit tablası + gerçek PBR simitler!
		var b := LP.batch()
		b.cyl(0.42, 0.42, 0.03, Vector3(0, 1.53, 0), Color(0.55, 0.38, 0.22), Vector3.ZERO, 12)
		_mesh_node(body, b)
		for k in 7:
			var a := float(k) * TAU / 6.0
			var r := 0.24 if k < 6 else 0.0
			var sm := SIMIT_MODEL.instantiate()
			sm.position = Vector3(cos(a) * r, 1.56 + (0.04 if k == 6 else 0.0), sin(a) * r)
			sm.rotation = Vector3(PI * 0.5, a, 0.0)
			sm.scale = Vector3(0.88, 0.88, 0.88)
			body.add_child(sm)
	var legs: Array[Node3D] = []
	for fn in ["FootL", "FootR"]:
		var f: Node3D = take.call(fn)
		var fp: Vector3 = f.get_meta("rest")
		var leg := Node3D.new()
		leg.position = Vector3(fp.x, 0.6, fp.z)
		root.add_child(leg)
		leg.add_child(f)
		f.position = Vector3(0, fp.y - 0.6, 0)
		legs.append(leg)
	var arms: Array[Node3D] = []
	for hn in ["HandL", "HandR"]:
		var hnd: Node3D = take.call(hn)
		var hp: Vector3 = hnd.get_meta("rest")
		var arm := Node3D.new()
		arm.position = Vector3(hp.x, hp.y + 0.58, hp.z)
		root.add_child(arm)
		arm.add_child(hnd)
		hnd.position = Vector3(0, -0.58, 0)
		if kind == "cay" and hn == "HandR":
			# Askılı çay tepsisi + gerçek ince belli PBR çay bardakları!
			var ab := LP.batch()
			ab.rod(Vector3(0, -0.6, 0), Vector3(0.0, -0.75, -0.18), 0.008, Color(0.75, 0.75, 0.78))
			ab.rod(Vector3(0, -0.6, 0), Vector3(0.0, -0.75, 0.18), 0.008, Color(0.75, 0.75, 0.78))
			ab.cyl(0.2, 0.2, 0.015, Vector3(0, -0.76, 0), Color(0.8, 0.78, 0.74), Vector3.ZERO, 12)
			_mesh_node(arm, ab)
			for k in 3:
				var a := float(k) * TAU / 3.0 + 0.4
				var tg := TEA_MODEL.instantiate()
				tg.position = Vector3(cos(a) * 0.10, -0.75, sin(a) * 0.10)
				tg.scale = Vector3(0.72, 0.72, 0.72)
				arm.add_child(tg)
		arms.append(arm)
	src.free()
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 30
	lbl.outline_size = 8
	lbl.modulate = Color(1.0, 0.95, 0.8)
	lbl.position = Vector3(0, 1.95 if kind == "simit" else 1.75, 0)
	lbl.visible = false
	root.add_child(lbl)
	# Oyuncunun [E] ile satın alabildiği teklif alanı (player.gd "vendor")
	var offer: Dictionary = VENDOR_OFFERS[kind]
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("kind", "vendor")
	area.set_meta("vendor", kind)
	area.set_meta("price", int(offer["price"]))
	area.set_meta("offer", str(offer["hint"]))
	area.set_meta("hl_size", Vector3(0.6, 1.9, 0.5))
	area.position = Vector3(0, 0.95, 0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.8, 1.9, 0.8)
	cs.shape = sh
	area.add_child(cs)
	root.add_child(area)
	return {"root": root, "body": body, "legs": legs, "arms": arms, "label": lbl, "kind": kind,
		"i": 1, "dir": 1, "wait": 0.0, "speed": 1.05, "shout": _rng.randf_range(3.0, 8.0), "lbl_t": 0.0,
		"pts": [], "loop": false, "stops": [], "area": area,
		"near_t": 0.0, "prev": -1}


## Yerel oyuncu (bu bilgisayardaki); menüde ya da oyun dışında null.
func _local_player() -> Node3D:
	if _players == null or not is_instance_valid(_players):
		return null
	for pl in _players.get_children():
		if pl is Node3D and pl.is_multiplayer_authority():
			return pl
	return null


## player.gd satın alınca çağırır: teşekkür eder ve rotasına döner.
func vendor_purchase(area: Area3D) -> void:
	for p in _people:
		if p["area"] == area:
			var lbl: Label3D = p["label"]
			lbl.text = str(VENDOR_OFFERS[p["kind"]]["thanks"])
			lbl.visible = true
			p["lbl_t"] = 2.4
			p.erase("call")
			p["wait"] = 2.0 # teşekkür edip bir an bekler, sonra dolaşmaya devam
			return


## Yakında (<=2.4 m) yerel oyuncu varsa satıcı durup ona döner; böylece [E] ile alışveriş kolay olur.
## Asla oyuncuyu kovalamaz. Oyuncu çok uzun oyalanırsa (6 sn) satıcı yoluna devam eder.
func _tick_near_player(p: Dictionary, dt: float) -> bool:
	var pl := _local_player()
	var root: Node3D = p["root"]
	if pl == null:
		p["near_t"] = 0.0
		return false
	var to := pl.global_position - root.global_position
	to.y = 0.0
	var d := to.length()
	if d > 3.4:
		p["near_t"] = 0.0
		return false
	if d > 2.4 or float(p["near_t"]) > 6.0:
		return false
	p["near_t"] = float(p["near_t"]) + dt
	root.rotation.y = lerp_angle(root.rotation.y, atan2(-to.x, -to.z), dt * 5.0)
	var legs: Array[Node3D] = p["legs"]
	var arms: Array[Node3D] = p["arms"]
	for l in legs:
		l.rotation.x = lerpf(l.rotation.x, 0.0, dt * 6.0)
	arms[0].rotation.x = lerpf(arms[0].rotation.x, 0.0, dt * 6.0)
	arms[1].rotation.x = lerpf(arms[1].rotation.x, sin(_t * 2.0) * 0.05 if p["kind"] == "cay" else 0.0, dt * 6.0)
	return true


## Rastgele bir sonraki dolaşma noktası: yakın (<=10.6 m), mevcut/önceki nokta hariç.
func _next_wander(pts: Array, cur: int, prev: int) -> int:
	var cands: Array = []
	var cp: Vector3 = pts[cur]
	for j in pts.size():
		if j == cur or j == prev:
			continue
		var q: Vector3 = pts[j]
		if Vector2(q.x - cp.x, q.z - cp.z).length() <= 10.6:
			cands.append(j)
	if cands.is_empty():
		return (cur + 1) % pts.size()
	return int(cands[_rng.randi() % cands.size()])


func _build_people() -> void:
	var sim := _make_person("simit")
	# Yürünebilir yol noktaları (iki yan şerit + orta enine yol); satıcılar rastgele yakın noktaya gider.
	var lane: Array = []
	for sx in [-3.35, 3.35]:
		for z in [-19.0, -12.5, -6.0, 0.0, 6.0, 12.5, 19.0]:
			lane.append(Vector3(sx, 0.0, z))
	lane.append_array([Vector3(-4.8, 0.0, 3.4), Vector3(4.8, 0.0, 3.4)])
	sim["pts"] = lane.duplicate()
	sim["lines"] = ["Simiiit! Taze simit!", "Sıcak simit, gevrek simit!", "Simitçi geldiii!", "Çıtır çıtır simit!"]
	sim["i"] = _rng.randi() % lane.size()
	(sim["root"] as Node3D).position = sim["pts"][sim["i"]]
	sim["i"] = _next_wander(sim["pts"], sim["i"], -1)
	sim["wait"] = _rng.randf_range(1.0, 5.0)
	_people.append(sim)
	var cay := _make_person("cay")
	var cp := Vector3(11.4, 0.04, 11.2)
	if bazaar and bazaar.has_meta("cay_pos"):
		cp = bazaar.get_meta("cay_pos")
	var cpts: Array = [cp, Vector3(10.9, 0.04, 3.4), Vector3(-10.9, 0.04, 3.4), Vector3(-10.9, 0.04, -2.9)]
	cpts.append_array(lane)
	cay["pts"] = cpts
	cay["speed"] = 1.1
	cay["lines"] = ["Çaaay! Taze demlendi!", "Çay isteyen var mı?", "Tavşan kanı çay!", "Ocak sıcak, çay hazır!"]
	cay["i"] = _next_wander(cpts, 0, -1)
	(cay["root"] as Node3D).position = cp
	_people.append(cay)


## [T] "Çaycı!": kıraathane çaycısı seslenen oyuncunun yanına gelir ve 30 sn bekler (bu bilgisayarda yerel).
func call_cay_to(world_pos: Vector3) -> bool:
	for p in _people:
		if p["kind"] == "cay":
			var t := StallScript.world_keepout_all(self, to_local(world_pos))
			t.y = 0.04 if absf(t.x) > 4.25 else 0.0
			p["call"] = t
			p["call_t"] = 40.0
			p["wait"] = 0.0
			var lbl: Label3D = p["label"]
			lbl.text = "Geliyorum abi! 🍵"
			lbl.visible = true
			p["lbl_t"] = 2.4
			return true
	return false


func _tick_called(p: Dictionary, dt: float) -> bool:
	if not p.has("call"):
		return false
	p["call_t"] = float(p["call_t"]) - dt
	if float(p["call_t"]) <= 0.0:
		p.erase("call")
		return false
	var root: Node3D = p["root"]
	var legs: Array[Node3D] = p["legs"]
	var arms: Array[Node3D] = p["arms"]
	var lbl: Label3D = p["label"]
	if lbl.visible:
		p["lbl_t"] = float(p["lbl_t"]) - dt
		if float(p["lbl_t"]) <= 0.0:
			lbl.visible = false
	var target: Vector3 = p["call"]
	var to := target - root.position
	to.y = 0.0
	var d := to.length()
	if d < 0.9:
		# Vardı: oyuncuya dönüp teklif eder, satın alınana ya da süre bitene kadar bekler
		var pl := _local_player()
		if pl:
			var tp := pl.global_position - root.global_position
			root.rotation.y = lerp_angle(root.rotation.y, atan2(-tp.x, -tp.z), dt * 5.0)
		for l in legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, dt * 6.0)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, 0.0, dt * 6.0)
		arms[1].rotation.x = sin(_t * 2.0) * 0.05
		if not lbl.visible and float(p.get("ask_cd", 0.0)) <= 0.0:
			lbl.text = str(VENDOR_OFFERS[p["kind"]]["ask"])
			lbl.visible = true
			p["lbl_t"] = 3.0
			p["ask_cd"] = 7.0
		p["ask_cd"] = float(p.get("ask_cd", 0.0)) - dt
		return true
	var dir := to / d
	dir = StallScript.world_steer_all(self, root.position, dir, d - 0.2)
	var np := StallScript.world_keepout_all(self, root.position + dir * minf(d, 1.7 * dt))
	np.y = lerpf(root.position.y, 0.04 if absf(np.x) > 4.25 else 0.0, minf(dt * 10.0, 1.0))
	root.position = np
	root.rotation.y = lerp_angle(root.rotation.y, atan2(-dir.x, -dir.z), dt * 6.0)
	var ph := _t * 8.0
	legs[0].rotation.x = sin(ph) * 0.5
	legs[1].rotation.x = -sin(ph) * 0.5
	arms[0].rotation.x = -sin(ph) * 0.35
	arms[1].rotation.x = sin(_t * 2.0) * 0.04
	(p["body"] as Node3D).position.y = absf(sin(ph)) * 0.03
	return true


func _tick_person(p: Dictionary, dt: float) -> void:
	var root: Node3D = p["root"]
	var legs: Array[Node3D] = p["legs"]
	var arms: Array[Node3D] = p["arms"]
	var lbl: Label3D = p["label"]
	if _tick_called(p, dt):
		return
	if _tick_near_player(p, dt):
		return
	# Bağırma balonu
	p["shout"] = float(p["shout"]) - dt
	if float(p["shout"]) <= 0.0:
		p["shout"] = _rng.randf_range(9.0, 16.0)
		var lines: Array = p["lines"]
		lbl.text = lines[_rng.randi() % lines.size()]
		lbl.visible = true
		p["lbl_t"] = 2.6
	if lbl.visible:
		p["lbl_t"] = float(p["lbl_t"]) - dt
		if float(p["lbl_t"]) <= 0.0:
			lbl.visible = false
	var tray_swing := sin(_t * 2.0) * 0.06
	if float(p["wait"]) > 0.0:
		p["wait"] = float(p["wait"]) - dt
		for l in legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, dt * 6.0)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, 0.0, dt * 6.0)
		if p["kind"] == "cay":
			arms[1].rotation.x = tray_swing
		return
	var pts: Array = p["pts"]
	var target: Vector3 = pts[int(p["i"])]
	var to := target - root.position
	to.y = 0.0
	var d := to.length()
	p["leg_t"] = float(p.get("leg_t", 0.0)) + dt
	if d < 0.12 or float(p["leg_t"]) > 30.0:
		# Vardı (ya da takıldı): rastgele yakın bir sonraki noktaya, çoğu zaman durup bekleyerek
		var cur := int(p["i"])
		p["i"] = _next_wander(pts, cur, int(p["prev"]))
		p["prev"] = cur
		p["leg_t"] = 0.0
		if _rng.randf() < 0.7:
			p["wait"] = _rng.randf_range(3.0, 8.0)
			if p["kind"] == "cay":
				var sfx := get_node_or_null("/root/Sfx")
				if sfx and sfx.has_method("play_3d"):
					sfx.play_3d("tea", root.global_position, null, -6.0)
		return
	var dir := to / d
	dir = StallScript.world_steer_all(self, root.position, dir, d - 0.2) # tezgah ve kamyonet içine girme
	var step := minf(d, float(p["speed"]) * dt)
	var np := StallScript.world_keepout_all(self, root.position + dir * step)
	np.y = lerpf(root.position.y, 0.04 if absf(np.x) > 4.25 else 0.0, minf(dt * 10.0, 1.0))
	root.position = np
	root.rotation.y = lerp_angle(root.rotation.y, atan2(-dir.x, -dir.z), dt * 5.0)
	var ph := _t * 6.2
	legs[0].rotation.x = sin(ph) * 0.45
	legs[1].rotation.x = -sin(ph) * 0.45
	arms[0].rotation.x = -sin(ph) * 0.35
	if p["kind"] == "cay":
		arms[1].rotation.x = tray_swing * 0.6
	else:
		arms[1].rotation.x = sin(ph) * 0.35
	(p["body"] as Node3D).position.y = absf(sin(ph)) * 0.03


# ---------------------------------------------------------------------------
# Kuş besleme (her eşte yerel çalışır; çağıran RPC ile senkronlar)
# ---------------------------------------------------------------------------

## ~12 m içindeki güvercinler noktaya uçar/yürür, birkaç sn gagalar, sonra sürüsüne döner.
func feed_birds_at(world_pos: Vector3) -> void:
	if _mm == null:
		return
	var lp := to_local(world_pos)
	lp.y = 0.0
	for pg in _pigeons:
		var st := int(pg["state"])
		if st != PState.GROUND and st != PState.PERCHED and st != PState.FEED:
			continue
		var pos: Vector3 = pg["pos"]
		if Vector2(pos.x - lp.x, pos.z - lp.z).length() > 12.0:
			continue
		var e := lp + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
		pg["feed_pt"] = lp
		pg["feed_t"] = _rng.randf_range(4.0, 7.0)
		if st == PState.FEED:
			continue
		pg["state"] = PState.RETURN # uçuş yayı; inince feed_t>0 olduğu için FEED'e geçer
		pg["a"] = pos
		pg["c"] = pos.lerp(e, 0.5) + Vector3(0, 1.2 if st == PState.GROUND else 0.6, 0)
		pg["e"] = e
		pg["t"] = 0.0
		pg["dur"] = clampf(pos.distance_to(e) * 0.16 + _rng.randf_range(0.2, 0.9), 0.9, 3.2)
		pg["peck"] = 0.0
