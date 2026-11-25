extends RefCounted
## Low-poly yardımcıları: düz (flat) gölgeli mesh, malzeme ve çarpıştırıcılar.


## Primitive mesh'i köşe paylaşmayan, yüz başına normalli hale getirir: köşeli low-poly görünüm.
static func flat(m: PrimitiveMesh) -> ArrayMesh:
	var a := m.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, idx.size(), 3):
		var p0 := v[idx[i]]; var p1 := v[idx[i + 1]]; var p2 := v[idx[i + 2]]
		var n := (p2 - p0).cross(p1 - p0)
		if n.length_squared() < 1e-12:
			continue # kutuplardaki sıfır alanlı üçgenler
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


## Mesh'i renkli bir MeshInstance3D olarak ekler.
static func add(parent: Node, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, rough := 0.88, metallic := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat(c, rough, metallic)
	parent.add_child(mi)
	return mi


## Görünmez kutu çarpıştırıcı (tezgah, duvar...).
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
