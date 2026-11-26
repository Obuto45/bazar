extends RefCounted
## Low-poly yardımcıları: düz gölgeli mesh, prosedürel yüzey dokuları (asfalt, beton, branda, ahşap) ve çarpıştırıcılar.

static var _tex_cache := {}


static func flat(m: PrimitiveMesh) -> ArrayMesh:
	var a := m.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var has_uv: bool = a.size() > Mesh.ARRAY_TEX_UV and a[Mesh.ARRAY_TEX_UV] != null
	var src_uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if has_uv else PackedVector2Array()
	for i in range(0, idx.size(), 3):
		var i0 := idx[i]; var i1 := idx[i + 1]; var i2 := idx[i + 2]
		var p0 := v[i0]; var p1 := v[i1]; var p2 := v[i2]
		var n := (p2 - p0).cross(p1 - p0)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		verts.append_array([p0, p1, p2])
		norms.append_array([n, n, n])
		if has_uv:
			uvs.append_array([src_uv[i0], src_uv[i1], src_uv[i2]])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = uvs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am


static func _make_proc_tex(key: String, size: int, painter: Callable) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	painter.call(img, size)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## Gerçekçi pütürlü Türk semt pazarı asfalt dokusu (çatlaklar, yama, yağ lekeleri).
static func tex_asphalt() -> ImageTexture:
	return _make_proc_tex("asphalt", 256, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4101
		var nz := FastNoiseLite.new()
		nz.seed = 77
		nz.frequency = 0.035
		for y in sz:
			for x in sz:
				var grain := r.randf_range(-0.06, 0.06)
				var patch := _tile_noise(nz, x, y, sz) * 0.07
				var speck := 0.10 if r.randf() < 0.025 else (-0.05 if r.randf() < 0.03 else 0.0)
				var v := clampf(0.30 + grain + patch + speck, 0.12, 0.48)
				img.set_pixel(x, y, Color(v, v * 0.99, v * 1.02, 1.0))
		# Onarım yamaları (daha koyu, yeni asfalt)
		for i in 4:
			var px := r.randi_range(0, sz - 1); var py := r.randi_range(0, sz - 1)
			var pw := r.randi_range(22, 60); var ph := r.randi_range(16, 44)
			for yy in ph:
				for xx in pw:
					var cx := (px + xx) % sz; var cy := (py + yy) % sz
					var c := img.get_pixel(cx, cy)
					img.set_pixel(cx, cy, c.darkened(0.22))
		# Yağ lekeleri
		for i in 6:
			var ox := r.randf_range(0, sz); var oy := r.randf_range(0, sz); var rad := r.randf_range(5.0, 13.0)
			for yy in range(int(-rad), int(rad) + 1):
				for xx in range(int(-rad), int(rad) + 1):
					var d := sqrt(float(xx * xx + yy * yy)) / rad
					if d < 1.0:
						var cx := posmod(int(ox) + xx, sz); var cy := posmod(int(oy) + yy, sz)
						var c := img.get_pixel(cx, cy)
						img.set_pixel(cx, cy, c.darkened(0.28 * (1.0 - d)))
		# Çatlaklar (rastgele yürüyüş)
		for i in 9:
			var cx := r.randf_range(0, sz); var cy := r.randf_range(0, sz)
			var ang := r.randf() * TAU
			for st in r.randi_range(30, 90):
				ang += r.randf_range(-0.5, 0.5)
				cx += cos(ang); cy += sin(ang)
				var ix := posmod(int(cx), sz); var iy := posmod(int(cy), sz)
				img.set_pixel(ix, iy, img.get_pixel(ix, iy).darkened(0.55))
	)


static func _tile_noise(nz: FastNoiseLite, x: int, y: int, sz: int) -> float:
	# Dikişsiz (tileable) gürültü: 4 köşenin harmanı
	var fx := float(x) / float(sz); var fy := float(y) / float(sz)
	var a := nz.get_noise_2d(x, y)
	var b := nz.get_noise_2d(x - sz, y)
	var c := nz.get_noise_2d(x, y - sz)
	var d := nz.get_noise_2d(x - sz, y - sz)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Hafif aşınmış kaldırım / beton dokusu.
static func tex_concrete() -> ImageTexture:
	return _make_proc_tex("concrete", 96, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4102
		for y in sz:
			for x in sz:
				var g := r.randf_range(-0.045, 0.045)
				var seam := -0.09 if (x % 48 == 0 or y % 48 == 0) else 0.0
				var v := clampf(0.76 + g + seam, 0.56, 0.88)
				img.set_pixel(x, y, Color(v * 1.01, v * 0.98, v * 0.92, 1.0))
	)


## Dokulu naylon pazar brandası (ince dokuma çizgileri).
static func tex_tarp() -> ImageTexture:
	return _make_proc_tex("tarp", 64, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4103
		for y in sz:
			for x in sz:
				var weave := 0.045 if ((x / 2 + y / 2) % 2 == 0) else -0.035
				var crease := sin(float(y) * 0.25) * 0.03
				var v := clampf(0.92 + weave + crease + r.randf_range(-0.02, 0.02), 0.78, 1.0)
				img.set_pixel(x, y, Color(v, v, v, 1.0))
	)


## Ahşap tezgah ve tahta doku damarları.
static func tex_wood() -> ImageTexture:
	return _make_proc_tex("wood", 64, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4104
		for y in sz:
			var band := sin(float(y) * 0.48) * 0.055 + (0.04 if y % 16 < 2 else 0.0)
			for x in sz:
				var grain := sin(float(x) * 0.14 + float(y) * 0.3) * 0.025 + r.randf_range(-0.02, 0.02)
				var v := clampf(0.92 + band + grain, 0.72, 1.0)
				img.set_pixel(x, y, Color(v, v * 0.96, v * 0.9, 1.0))
	)


## Sıvalı Türk mahalle binası duvar dokusu (lekeli, yağmur izli sıva).
static func tex_plaster() -> ImageTexture:
	return _make_proc_tex("plaster", 128, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4105
		var nz := FastNoiseLite.new()
		nz.seed = 31
		nz.frequency = 0.06
		for y in sz:
			for x in sz:
				var n := _tile_noise(nz, x, y, sz)
				var v := clampf(0.94 + r.randf_range(-0.035, 0.035) + n * 0.05, 0.80, 1.0)
				img.set_pixel(x, y, Color(v, v * 0.99, v * 0.965, 1.0))
	)


## Kilitli parke taşı kaldırım dokusu (gri/kırmızımsı taşlar, derz çizgileri).
static func tex_pavers() -> ImageTexture:
	return _make_proc_tex("pavers", 128, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4106
		var bw := 32; var bh := 16
		var tones := {}
		for y in sz:
			var row := y / bh
			var off := (bw / 2) if row % 2 == 1 else 0
			for x in sz:
				var col := posmod(x + off, sz) / bw
				var key := row * 16 + col
				if not tones.has(key):
					tones[key] = r.randf_range(-0.07, 0.07)
				var t: float = tones[key]
				var lx := posmod(x + off, bw); var ly := y % bh
				var edge := lx < 1 or ly < 1
				var bevel := lx < 2 or ly < 2 or lx > bw - 2 or ly > bh - 2
				var v := 0.80 + t + r.randf_range(-0.035, 0.035)
				if bevel: v -= 0.06
				if edge: v = 0.48
				var warm := 0.0 if (key % 7 != 3) else 0.08
				img.set_pixel(x, y, Color(v + warm, v * 0.97, v * 0.92 - warm * 0.5, 1.0))
	)


## Rögar kapağı (daire maskeli, ızgara desenli, alfa kesimli).
static func tex_manhole() -> ImageTexture:
	return _make_proc_tex("manhole", 64, func(img: Image, sz: int):
		var c0 := float(sz) * 0.5
		for y in sz:
			for x in sz:
				var dx := float(x) - c0 + 0.5; var dy := float(y) - c0 + 0.5
				var d := sqrt(dx * dx + dy * dy) / c0
				if d > 0.98:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				var v := 0.26
				if d > 0.86: v = 0.34
				elif (x / 4 + y / 4) % 2 == 0: v = 0.30
				if absf(d - 0.55) < 0.04: v = 0.36
				img.set_pixel(x, y, Color(v, v * 0.97, v * 0.94, 1.0))
	)


## Dükkan kepengi (yatay oluklu metal).
static func tex_shutter() -> ImageTexture:
	return _make_proc_tex("shutter", 64, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4107
		for y in sz:
			var rib := 0.10 if y % 8 < 2 else (-0.06 if y % 8 == 7 else 0.0)
			for x in sz:
				var v := clampf(0.78 + rib + r.randf_range(-0.03, 0.03), 0.5, 1.0)
				img.set_pixel(x, y, Color(v, v, v * 1.02, 1.0))
	)


## Berber direği (kırmızı-beyaz-mavi çapraz şeritler).
static func tex_barber() -> ImageTexture:
	return _make_proc_tex("barber", 64, func(img: Image, sz: int):
		var cols := [Color(0.85, 0.08, 0.08), Color(0.97, 0.97, 0.97), Color(0.1, 0.25, 0.75), Color(0.97, 0.97, 0.97)]
		for y in sz:
			for x in sz:
				var k := posmod(x + y, sz) / (sz / 4)
				img.set_pixel(x, y, cols[k % 4])
	)


## Türk bayrağı (ay-yıldız) dokusu.
static func tex_flag_tr() -> ImageTexture:
	return _make_proc_tex("flag_tr", 128, func(img: Image, sz: int):
		var red := Color(0.89, 0.04, 0.09)
		var white := Color(1, 1, 1)
		var star := PackedVector2Array()
		var sc := Vector2(0.80, 0.5)
		for i in 10:
			var a := PI + float(i) * TAU / 10.0
			var rr := 0.125 if i % 2 == 0 else 0.05
			star.append(sc + Vector2(cos(a), sin(a)) * rr)
		for y in sz:
			for x in sz:
				# Doku 1.5:1 bayrağa gerilir -> u ekseni 1.5 birim
				var u := (float(x) + 0.5) / float(sz) * 1.5
				var v := (float(y) + 0.5) / float(sz)
				var p := Vector2(u, v)
				var c := red
				var in_out := p.distance_to(Vector2(0.5, 0.5)) < 0.25
				var in_in := p.distance_to(Vector2(0.5625, 0.5)) < 0.2
				if (in_out and not in_in) or Geometry2D.is_point_in_polygon(p, star):
					c = white
				img.set_pixel(x, y, c)
	)


static func mat(c: Color, rough := 0.88, metallic := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = c
	s.roughness = rough
	s.metallic = metallic
	if emission_energy > 0.0:
		s.emission_enabled = true
		s.emission = emission
		s.emission_energy_multiplier = emission_energy
	return s


static func mat_tex(c: Color, tex: Texture2D, rough := 0.9, uv_scale := Vector3.ONE, metallic := 0.0, triplanar := false) -> StandardMaterial3D:
	var s := mat(c, rough, metallic)
	s.albedo_texture = tex
	s.uv1_scale = uv_scale
	s.uv1_triplanar = triplanar
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


static func sphere(r: float, seg := 7, rings := 4) -> ArrayMesh:
	var m := SphereMesh.new()
	m.radius = r; m.height = r * 2.0
	m.radial_segments = seg; m.rings = rings
	return flat(m)


static func ellipsoid(rx: float, ry: float, rz: float, seg := 8, rings := 5) -> ArrayMesh:
	var m := SphereMesh.new()
	m.radius = 1.0; m.height = 2.0
	m.radial_segments = seg; m.rings = rings
	var a := m.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var sc := Vector3(rx, ry, rz)
	for i in range(0, idx.size(), 3):
		var p0 := v[idx[i]] * sc
		var p1 := v[idx[i + 1]] * sc
		var p2 := v[idx[i + 2]] * sc
		var n := (p2 - p0).cross(p1 - p0)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		verts.append_array([p0, p1, p2])
		norms.append_array([n, n, n])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am


static func cyl(top: float, bottom: float, h: float, seg := 7) -> ArrayMesh:
	var m := CylinderMesh.new()
	m.top_radius = top; m.bottom_radius = bottom; m.height = h
	m.radial_segments = seg; m.rings = 1
	return flat(m)


static func box(size: Vector3) -> ArrayMesh:
	var m := BoxMesh.new()
	m.size = size
	return flat(m)


static func prism(size: Vector3) -> ArrayMesh:
	var m := PrismMesh.new()
	m.size = size
	return flat(m)


static func torus(inner_r: float, outer_r: float, rings := 16, ring_seg := 6) -> ArrayMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner_r
	m.outer_radius = outer_r
	m.rings = rings
	m.ring_segments = ring_seg
	return flat(m)


static func add(parent: Node, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, rough := 0.88, metallic := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat(c, rough, metallic)
	parent.add_child(mi)
	return mi


static func add_mat(parent: Node, mesh: Mesh, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func solid(parent: Node, pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)


# ---------------------------------------------------------------------------
# Toplu (batch) statik mesh: yüzlerce küçük dekor parçasını tek draw call'a birleştirir.
# Renk vertex color'da, A kanalı rüzgar salınım ağırlığı. batch_material() ile çizilir.
# ---------------------------------------------------------------------------

static func batch() -> Batch:
	return Batch.new()


class Batch extends RefCounted:
	static var _unit := {}
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	## Sonraki tüm parçalara uygulanan yerel çerçeve (ör. bina cephesi koordinatları)
	var frame := Transform3D.IDENTITY

	static func _flat_arrays(m: PrimitiveMesh) -> Array:
		var a := m.get_mesh_arrays()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var ov := PackedVector3Array()
		var on := PackedVector3Array()
		for i in range(0, idx.size(), 3):
			var p0 := v[idx[i]]; var p1 := v[idx[i + 1]]; var p2 := v[idx[i + 2]]
			var n := (p2 - p0).cross(p1 - p0)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			ov.append_array([p0, p1, p2])
			on.append_array([n, n, n])
		return [ov, on]

	static func _get_unit(key: String) -> Array:
		if _unit.has(key):
			return _unit[key]
		var parts := key.split(":")
		var m: PrimitiveMesh
		match parts[0]:
			"box":
				var bm := BoxMesh.new()
				bm.size = Vector3.ONE
				m = bm
			"prism":
				var pm := PrismMesh.new()
				pm.size = Vector3.ONE
				m = pm
			"sph", "hemi":
				var sm := SphereMesh.new()
				sm.radius = 1.0
				sm.height = 2.0 if parts[0] == "sph" else 1.0
				sm.is_hemisphere = parts[0] == "hemi"
				sm.radial_segments = int(parts[1])
				sm.rings = int(parts[2])
				m = sm
			_:
				var cm := CylinderMesh.new()
				cm.bottom_radius = 1.0
				cm.top_radius = float(parts[2]) / 100.0
				cm.height = 1.0
				cm.radial_segments = int(parts[1])
				cm.rings = 1
				m = cm
		var arr := _flat_arrays(m)
		_unit[key] = arr
		return arr

	func _push(key: String, xf: Transform3D, c: Color, sway := 0.0) -> void:
		var arr := _get_unit(key)
		var v: PackedVector3Array = arr[0]
		var n: PackedVector3Array = arr[1]
		xf = frame * xf
		verts.append_array(xf * v)
		var nb := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
		norms.append_array(nb * n)
		var start := cols.size()
		cols.resize(start + v.size())
		if sway <= 0.0:
			var cc := Color(c.r, c.g, c.b, 0.0)
			for i in v.size():
				cols[start + i] = cc
		else:
			# Alt köşeler daha çok salınır
			for i in v.size():
				cols[start + i] = Color(c.r, c.g, c.b, clampf(0.5 - v[i].y, 0.0, 1.0) * sway)

	static func xf_of(pos: Vector3, rot: Vector3, scl: Vector3) -> Transform3D:
		return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)

	func box(size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, sway := 0.0) -> void:
		_push("box", xf_of(pos, rot, size), c, sway)

	func prism(size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, sway := 0.0) -> void:
		_push("prism", xf_of(pos, rot, size), c, sway)

	func ellipsoid(r: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, seg := 7, rings := 4, sway := 0.0) -> void:
		_push("sph:%d:%d" % [seg, rings], xf_of(pos, rot, r), c, sway)

	func sphere(r: float, pos: Vector3, c: Color, seg := 6, rings := 4) -> void:
		_push("sph:%d:%d" % [seg, rings], xf_of(pos, Vector3.ZERO, Vector3.ONE * r), c)

	## Yarım küre (kubbe): taban pos.y'de, yükseklik r.y
	func dome(r: Vector3, pos: Vector3, c: Color, seg := 12, rings := 4) -> void:
		_push("hemi:%d:%d" % [seg, rings], xf_of(pos, Vector3.ZERO, r), c)

	func cyl(top: float, bottom: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, seg := 7) -> void:
		if bottom >= top and bottom > 0.0001:
			var ratio := int(round(top / bottom * 100.0))
			_push("cyl:%d:%d" % [seg, ratio], xf_of(pos, rot, Vector3(bottom, h, bottom)), c)
		else:
			# Ters koni (üstü geniş): 180° çevrilmiş birim silindir
			var ratio2 := int(round(bottom / maxf(top, 0.0001) * 100.0))
			_push("cyl:%d:%d" % [seg, ratio2], xf_of(pos, rot, Vector3(top, h, top)) * Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO), c)

	## İki nokta arası ince kablo/çubuk
	func rod(a: Vector3, b: Vector3, r: float, c: Color, seg := 4) -> void:
		var d := b - a
		var l := d.length()
		if l < 0.001:
			return
		var y := d / l
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		_push("cyl:%d:100" % seg, Transform3D(Basis(x * r, y * l, z * r), (a + b) * 0.5), c)

	## Sarkan kablo (zincir eğrisi yaklaşımı), parça parça
	func wire(a: Vector3, b: Vector3, sag: float, r: float, c: Color, segs := 6) -> void:
		var prev := a
		for i in range(1, segs + 1):
			var t := float(i) / float(segs)
			var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
			rod(prev, p, r, c, 3)
			prev = p

	func vertex_count() -> int:
		return verts.size()

	func commit(parent: Node, material: Material, shadows := true) -> MeshInstance3D:
		if verts.is_empty():
			return null
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		return mi


const _BATCH_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float rough = 0.86;
uniform float metal = 0.0;
uniform float wind = 1.0;
uniform float wet = 0.0;
uniform float ground_ao = 1.0;
uniform vec3 emit_col : source_color = vec3(0.0);
uniform float emit = 0.0;
uniform float emit_self = 0.0;
varying float wy;
varying vec3 wn;

vec3 to_lin(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.a * wind;
	if (w > 0.0001) {
		VERTEX.x += sin(TIME * 2.3 + wp.x * 0.8 + wp.z * 0.6) * 0.07 * w;
		VERTEX.z += cos(TIME * 1.9 + wp.x * 0.5 - wp.z * 0.7) * 0.07 * w;
		VERTEX.y += sin(TIME * 3.1 + wp.z) * 0.015 * w;
	}
	wy = wp.y;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 c = to_lin(COLOR.rgb);
	float ao = mix(1.0, mix(0.6, 1.0, smoothstep(0.0, 0.5, wy)), ground_ao);
	float up = smoothstep(0.55, 0.95, normalize(wn).y) * wet;
	ALBEDO = c * ao * (1.0 - up * 0.35);
	ROUGHNESS = mix(rough, 0.14, up);
	METALLIC = metal;
	EMISSION = emit_col * emit + c * emit_self;
}
"""

static var _batch_shader: Shader


## Batch mesh'ler için vertex-color shader malzemesi (rüzgar salınımı, yağmur ıslaklığı, zemin AO).
## Parametreler: rough, metal, wind, wet, ground_ao, emit_col, emit
static func batch_material(rough := 0.86, metal := 0.0, ground_ao := 1.0) -> ShaderMaterial:
	if _batch_shader == null:
		_batch_shader = Shader.new()
		_batch_shader.code = _BATCH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _batch_shader
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("ground_ao", ground_ao)
	return m


## Dalgalanan bayrak (Türk bayrağı) – PlaneMesh + vertex dalga shader'ı. Direğe sol kenardan bağlı.
const _FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float wind = 1.0;
uniform float phase = 0.0;
void vertex() {
	float k = clamp(UV.x, 0.0, 1.0);
	float t = TIME * (3.2 + wind) + phase;
	VERTEX.z += (sin(UV.x * 6.0 - t) * 0.10 + sin(UV.x * 11.0 - t * 1.7 + UV.y * 2.0) * 0.035) * k * (0.6 + wind * 0.5);
	VERTEX.y -= k * k * 0.06 / (0.5 + wind);
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * (0.85 + 0.15 * sin(UV.x * 6.0 - TIME * 4.0 + phase));
	ROUGHNESS = 0.8;
	BACKLIGHT = c.rgb * 0.35;
}
"""

static var _flag_shader: Shader


static func flag_material(phase := 0.0) -> ShaderMaterial:
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = _FLAG_SHADER
	var m := ShaderMaterial.new()
	m.shader = _flag_shader
	m.set_shader_parameter("tex", tex_flag_tr())
	m.set_shader_parameter("phase", phase)
	return m


## Bayrak mesh'i: genişlik w (x yönünde, x=0 direkte), yükseklik w/1.5.
static func flag_mesh(w: float) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, w / 1.5)
	pm.orientation = PlaneMesh.FACE_Z
	pm.subdivide_width = 10
	pm.subdivide_depth = 3
	pm.center_offset = Vector3(w * 0.5, 0, 0)
	return pm
