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


## Gerçekçi pütürlü Türk semt pazarı asfalt dokusu.
static func tex_asphalt() -> ImageTexture:
	return _make_proc_tex("asphalt", 128, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4101
		for y in sz:
			for x in sz:
				var grain := r.randf_range(-0.075, 0.075)
				var patch := sin(float(x) * 0.09) * cos(float(y) * 0.08) * 0.04
				var speck := 0.09 if r.randf() < 0.03 else (-0.06 if r.randf() < 0.03 else 0.0)
				var v := clampf(0.28 + grain + patch + speck, 0.14, 0.44)
				img.set_pixel(x, y, Color(v, v * 0.99, v * 1.02, 1.0))
	)


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


## Sıvalı Türk mahalle binası duvar dokusu.
static func tex_plaster() -> ImageTexture:
	return _make_proc_tex("plaster", 64, func(img: Image, sz: int):
		var r := RandomNumberGenerator.new()
		r.seed = 4105
		for y in sz:
			for x in sz:
				var v := clampf(0.93 + r.randf_range(-0.04, 0.04) + sin(float(y) * 0.12) * 0.02, 0.80, 1.0)
				img.set_pixel(x, y, Color(v, v * 0.99, v * 0.97, 1.0))
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
