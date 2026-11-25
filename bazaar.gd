extends Node3D
## Pazar mekanı: ortada çeşme, iki yanda tezgahlar, çevrede sur, ağaçlar ve fenerler.
## Hepsi koddan üretilen low-poly parçalar; rastgelelik sabit tohumla, herkes aynı pazarı görür.

const LP := preload("res://lowpoly.gd")
const HALF := 22.0 # pazar alanının yarı genişliği (m)
const AWNINGS := [Color(0.85, 0.25, 0.2), Color(0.95, 0.75, 0.25), Color(0.25, 0.55, 0.75), Color(0.4, 0.65, 0.35),
	Color(0.75, 0.4, 0.65), Color(0.95, 0.55, 0.2)]
const GOODS := [Color(0.9, 0.2, 0.15), Color(1.0, 0.6, 0.1), Color(0.95, 0.85, 0.2), Color(0.45, 0.75, 0.2),
	Color(0.5, 0.25, 0.55), Color(0.85, 0.85, 0.8)]
const WOOD := Color(0.55, 0.37, 0.22)
const STONE := Color(0.72, 0.66, 0.56)

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1453
	_env()
	_ground()
	_fountain(Vector3.ZERO)
	# Ana cadde iki yanında tezgahlar (cadde Z ekseni boyunca)
	for z in [-15.0, -9.0, 9.0, 15.0]:
		_stall(Vector3(-6.5, 0, z), PI / 2)
		_stall(Vector3(6.5, 0, z), -PI / 2)
	# Meydanın yanlarında (çeşmeye dönük)
	for x in [-14.0, 14.0]:
		for z in [-4.0, 4.0]:
			_stall(Vector3(x, 0, z), -PI / 2 if x < 0 else PI / 2)
	_walls()
	for i in 26:
		var p := Vector3(rng.randf_range(-HALF + 2, HALF - 2), 0, rng.randf_range(-HALF + 2, HALF - 2))
		if absf(p.x) > 17.0 or (absf(p.z) > 19.0 and absf(p.x) > 4.0):
			_tree(p)
	for z in [-18.0, -12.0, -6.0, 6.0, 12.0, 18.0]:
		_lantern(Vector3(-3.2, 0, z))
		_lantern(Vector3(3.2, 0, z))
	for i in 18: # dağınık sandık ve fıçılar
		var p := Vector3(rng.randf_range(-HALF + 3, HALF - 3), 0, rng.randf_range(-HALF + 3, HALF - 3))
		if p.length() > 6.0 and absf(p.x) > 3.5:
			if rng.randf() < 0.5:
				_crate(p, rng.randf() * TAU)
			else:
				_barrel(p)


func _env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.45, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.85, 0.72, 0.55)
	sky_mat.ground_bottom_color = Color(0.4, 0.32, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.82, 0.65)
	env.fog_density = 0.002
	env.fog_sky_affect = 0.0 # gökyüzü mavi kalsın
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2 + 40, HALF * 2 + 40)
	g.mesh = pm
	g.material_override = LP.mat(Color(0.82, 0.7, 0.5)) # kum
	add_child(g)
	LP.solid(self, Vector3(0, -0.5, 0), Vector3(HALF * 2 + 40, 1, HALF * 2 + 40))
	# Taş döşeli cadde ve meydan: hafif renk farklı karolar
	for x in range(-3, 3):
		for z in range(-11, 11):
			_tile(Vector3(x * 1.0 + 0.5, 0.01, z * 2.0 + 1.0), Vector2(0.96, 1.96))
	for x in range(-5, 5):
		for z in range(-4, 4):
			_tile(Vector3(x * 2.0 + 1.0, 0.015, z * 2.0 + 1.0), Vector2(1.96, 1.96))


func _tile(p: Vector3, s: Vector2) -> void:
	var c := STONE.darkened(rng.randf_range(0.0, 0.12))
	LP.add(self, LP.box(Vector3(s.x, 0.03, s.y)), p, c)


func _fountain(p: Vector3) -> void:
	var f := Node3D.new()
	f.position = p
	add_child(f)
	LP.add(f, LP.cyl(2.4, 2.6, 0.5, 8), Vector3(0, 0.25, 0), STONE.darkened(0.1))
	var water := LP.add(f, LP.cyl(2.1, 2.1, 0.05, 8), Vector3(0, 0.52, 0), Color(0.25, 0.55, 0.8))
	(water.material_override as StandardMaterial3D).roughness = 0.1
	LP.add(f, LP.cyl(0.3, 0.45, 1.6, 6), Vector3(0, 1.1, 0), STONE)
	LP.add(f, LP.cyl(0.9, 0.4, 0.3, 8), Vector3(0, 1.9, 0), STONE.darkened(0.05))
	LP.add(f, LP.sphere(0.25, 6, 3), Vector3(0, 2.2, 0), Color(0.4, 0.7, 0.9))
	var b := StaticBody3D.new()
	b.position = p + Vector3(0, 0.5, 0)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 2.6; sh.height = 1.0
	cs.shape = sh
	b.add_child(cs)
	add_child(b)


## Tezgah: tahta masa, dört direk, çizgili tente, üstünde mallar. Ön yüz +Z'ye bakar, sonra döndürülür.
func _stall(p: Vector3, yaw: float) -> void:
	var s := Node3D.new()
	s.position = p
	s.rotation.y = yaw
	add_child(s)
	var awn: Color = AWNINGS[rng.randi() % AWNINGS.size()]
	LP.add(s, LP.box(Vector3(3.2, 0.9, 1.2)), Vector3(0, 0.45, 0.3), WOOD) # masa
	LP.add(s, LP.box(Vector3(3.3, 0.08, 1.3)), Vector3(0, 0.92, 0.3), WOOD.lightened(0.15))
	for x in [-1.5, 1.5]:
		for z in [-0.6, 1.1]:
			LP.add(s, LP.cyl(0.06, 0.07, 2.6, 5), Vector3(x, 1.3, z), WOOD.darkened(0.2))
	for i in 4: # çizgili eğik tente
		var c := awn if i % 2 == 0 else Color(0.95, 0.92, 0.85)
		LP.add(s, LP.box(Vector3(0.84, 0.05, 2.2)), Vector3(-1.26 + i * 0.84, 2.65, 0.25), c, Vector3(0.22, 0, 0))
	LP.add(s, LP.box(Vector3(3.4, 0.25, 0.04)), Vector3(0, 2.4, 1.33), awn) # saçak
	# Mallar: masa üstünde meyve tepecikleri veya çömlekler
	if rng.randf() < 0.7:
		for i in 3:
			var c: Color = GOODS[rng.randi() % GOODS.size()]
			var base := Vector3(-1.0 + i * 1.0, 1.0, 0.3)
			LP.add(s, LP.box(Vector3(0.8, 0.12, 0.7)), base, WOOD.darkened(0.3)) # kasa
			for j in 6:
				var o := Vector3(rng.randf_range(-0.28, 0.28), 0.14 + (0.12 if j > 3 else 0.0), rng.randf_range(-0.22, 0.22))
				LP.add(s, LP.sphere(0.11, 5, 3), base + o, c.darkened(rng.randf_range(0.0, 0.2)))
	else:
		for i in 4:
			var h := rng.randf_range(0.3, 0.55)
			LP.add(s, LP.cyl(0.1, 0.2, h, 6), Vector3(-1.1 + i * 0.73, 0.96 + h / 2, 0.3),
				Color(0.75, 0.42, 0.28).darkened(rng.randf_range(0.0, 0.25)))
	_crate(p + Vector3(1.0, 0, -1.0).rotated(Vector3.UP, yaw), yaw + 0.3)
	LP.solid(s, Vector3(0, 0.5, 0.25), Vector3(3.3, 1.0, 1.4))


func _crate(p: Vector3, yaw: float) -> void:
	var c := Node3D.new()
	c.position = p
	c.rotation.y = yaw
	add_child(c)
	LP.add(c, LP.box(Vector3(0.7, 0.6, 0.7)), Vector3(0, 0.3, 0), WOOD.lightened(0.1))
	LP.add(c, LP.box(Vector3(0.74, 0.08, 0.74)), Vector3(0, 0.6, 0), WOOD.darkened(0.15))
	LP.solid(c, Vector3(0, 0.3, 0), Vector3(0.7, 0.6, 0.7))


func _barrel(p: Vector3) -> void:
	var b := Node3D.new()
	b.position = p
	add_child(b)
	LP.add(b, LP.cyl(0.32, 0.32, 0.85, 8), Vector3(0, 0.43, 0), WOOD)
	for y in [0.15, 0.7]:
		LP.add(b, LP.cyl(0.34, 0.34, 0.06, 8), Vector3(0, y, 0), Color(0.3, 0.3, 0.32))
	LP.solid(b, Vector3(0, 0.43, 0), Vector3(0.64, 0.85, 0.64))


func _tree(p: Vector3) -> void:
	var t := Node3D.new()
	t.position = p
	t.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
	add_child(t)
	LP.add(t, LP.cyl(0.15, 0.22, 1.6, 5), Vector3(0, 0.8, 0), WOOD.darkened(0.3))
	var g := Color(0.35, 0.6, 0.3).darkened(rng.randf_range(0.0, 0.25))
	LP.add(t, LP.cyl(0.0, 1.2, 1.6, 6), Vector3(0, 2.1, 0), g)
	LP.add(t, LP.cyl(0.0, 0.9, 1.3, 6), Vector3(0, 2.9, 0), g.lightened(0.08))
	LP.solid(t, Vector3(0, 1, 0), Vector3(0.4, 2, 0.4))


func _lantern(p: Vector3) -> void:
	var l := Node3D.new()
	l.position = p
	add_child(l)
	LP.add(l, LP.cyl(0.05, 0.07, 3.0, 5), Vector3(0, 1.5, 0), Color(0.2, 0.18, 0.16))
	var glow := LP.add(l, LP.box(Vector3(0.28, 0.35, 0.28)), Vector3(0, 3.1, 0), Color(1.0, 0.8, 0.4))
	var m := glow.material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.3)
	m.emission_energy_multiplier = 2.0
	var light := OmniLight3D.new()
	light.position.y = 3.0
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 0.8
	light.omni_range = 6.0
	l.add_child(light)
	LP.solid(l, Vector3(0, 1.5, 0), Vector3(0.15, 3, 0.15))


## Çevre suru; dört yönde kemerli kapı boşluğu.
func _walls() -> void:
	for side in 4:
		var yaw := side * PI / 2
		var wall := Node3D.new()
		wall.rotation.y = yaw
		add_child(wall)
		for seg in [-1, 1]:
			var wl := HALF - 2.5
			var x: float = seg * (2.5 + wl / 2)
			LP.add(wall, LP.box(Vector3(wl, 3.0, 0.8)), Vector3(x, 1.5, -HALF), STONE.darkened(0.15))
			LP.solid(wall, Vector3(x, 1.5, -HALF), Vector3(wl, 3.0, 0.8))
			for i in int(wl / 1.6): # mazgallar
				LP.add(wall, LP.box(Vector3(0.7, 0.5, 0.85)), Vector3(x - wl / 2 + 0.5 + i * 1.6, 3.25, -HALF), STONE.darkened(0.2))
		for gx in [-2.5, 2.5]: # kapı kuleleri
			LP.add(wall, LP.box(Vector3(1.4, 4.4, 1.4)), Vector3(gx, 2.2, -HALF), STONE.darkened(0.25))
			LP.solid(wall, Vector3(gx, 2.2, -HALF), Vector3(1.4, 4.4, 1.4))
		LP.add(wall, LP.box(Vector3(6.4, 0.7, 1.0)), Vector3(0, 4.0, -HALF), STONE.darkened(0.25)) # kemer üstü
		LP.add(wall, LP.box(Vector3(4.0, 0.9, 0.05)), Vector3(0, 3.4, -HALF + 0.55), AWNINGS[side]) # bayrak
	# Kapıdan dışarı kaçılmasın: görünmez dış sınır
	for side in 4:
		var d := Vector3(0, 0, -(HALF + 6)).rotated(Vector3.UP, side * PI / 2)
		LP.solid(self, d + Vector3(0, 3, 0), Vector3(60, 6, 1), side * PI / 2)
