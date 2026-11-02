class_name DieShapes
## The polyhedra of the dice (TASK-61): mesh (flat shaded), collision points and per face its
## outward normal and centre. d4 tetrahedron, d6 cube, d8 octahedron, d10 pentagonal
## trapezohedron, d12 dodecahedron, d20 icosahedron; about 0.5 units across.

static var _cache := {}


## {mesh: ArrayMesh, points: PackedVector3Array, faces: [{normal, center}], label_scale}.
static func shape(sides: int) -> Dictionary:
	if _cache.has(sides):
		return _cache[sides]
	var poly: Dictionary
	match sides:
		4:
			poly = _tetra()
		6:
			poly = _cube()
		8:
			poly = _octa()
		10:
			poly = _trapezo()
		12:
			poly = _dodeca()
		_:
			poly = _icosa()
	var out := _build(poly.verts, poly.faces, float(poly.get("scale", 0.3)), bool(poly.get("raw", false)))
	out["label_scale"] = float(poly.get("label", 1.0))
	_cache[sides] = out
	return out


static func _build(verts: Array, faces: Array, size: float, raw := false) -> Dictionary:
	var pts := PackedVector3Array()
	for v: Vector3 in verts:
		pts.append(v * 0.3 if raw else v.normalized() * size)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var info := []
	for f: Array in faces:
		var center := Vector3.ZERO
		for i: int in f:
			center += pts[i]
		center /= f.size()
		var n := (pts[f[1]] - pts[f[0]]).cross(pts[f[2]] - pts[f[0]]).normalized()
		if n.dot(center) < 0:
			n = -n
			f = f.duplicate()
			f.reverse()
		info.append({"normal": n, "center": center})
		for k in range(1, f.size() - 1):  # a fan; counter-clockwise seen from outside
			for idx: int in [f[0], f[k + 1], f[k]]:
				st.set_normal(n)
				st.add_vertex(pts[idx])
	return {"mesh": st.commit(), "points": pts, "faces": info}


static func _tetra() -> Dictionary:
	var v := [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]
	return {"verts": v, "faces": [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]], "scale": 0.36, "label": 0.8}


static func _cube() -> Dictionary:
	var v := []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				v.append(Vector3(x, y, z))
	# indices: x*4 + y*2 + z (0/1 for -1/1)
	return {"verts": v, "faces": [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]], "scale": 0.3, "label": 1.3}


static func _octa() -> Dictionary:
	var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var f := []
	for a in [0, 1]:
		for b in [2, 3]:
			for c in [4, 5]:
				f.append([a, b, c])
	return {"verts": v, "faces": f, "scale": 0.32, "label": 0.9}


static func _trapezo() -> Dictionary:
	# Apexes at +-h, rings at +-a with a = h (1 - cos 36) / (1 + cos 36): the kites are flat.
	var h := 1.0
	var c := cos(deg_to_rad(36.0))
	var a := h * (1.0 - c) / (1.0 + c)
	var v := [Vector3(0, h, 0), Vector3(0, -h, 0)]
	for k in 5:
		var t := deg_to_rad(72.0 * k)
		v.append(Vector3(cos(t), a, sin(t)))  # 2 + k: upper ring
	for k in 5:
		var t := deg_to_rad(72.0 * k + 36.0)
		v.append(Vector3(cos(t), -a, sin(t)))  # 7 + k: lower ring
	var f := []
	for k in 5:
		f.append([0, 2 + k, 7 + k, 2 + (k + 1) % 5])
		f.append([1, 7 + k, 2 + (k + 1) % 5, 7 + (k + 1) % 5])
	return {"verts": v, "faces": f, "label": 0.85, "raw": true}  # not onto a sphere: the kites stay flat


static func _dodeca() -> Dictionary:
	var p := (1.0 + sqrt(5.0)) / 2.0
	var q := 1.0 / p
	var v := []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				v.append(Vector3(x, y, z))
	for a in [-q, q]:
		for b in [-p, p]:
			v.append(Vector3(0, a, b))
	for a in [-q, q]:
		for b in [-p, p]:
			v.append(Vector3(a, b, 0))
	for a in [-p, p]:
		for b in [-q, q]:
			v.append(Vector3(a, 0, b))
	return {"verts": v, "faces": _faces_by_plane(v, 5), "scale": 0.3, "label": 0.8}


static func _icosa() -> Dictionary:
	var p := (1.0 + sqrt(5.0)) / 2.0
	var v := []
	for a in [-1, 1]:
		for b in [-p, p]:
			v.append(Vector3(0, a, b))
			v.append(Vector3(a, b, 0))
			v.append(Vector3(b, 0, a))
	return {"verts": v, "faces": _faces_by_plane(v, 3), "scale": 0.33, "label": 0.6}


## The faces of a convex polyhedron whose faces have `n` corners: the planes through n of its
## vertices with every vertex on one side, corners in order around the face.
static func _faces_by_plane(v: Array, n: int) -> Array:
	var pts: Array[Vector3] = []
	for p: Vector3 in v:
		pts.append(p.normalized())
	var seen := {}
	var out := []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			for k in range(j + 1, pts.size()):
				var normal := (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if normal.length() < 1e-6:
					continue
				normal = normal.normalized()
				var d := normal.dot(pts[i])
				if d < 0:
					normal = -normal
					d = -d
				var on := []
				var outside := false
				for m in pts.size():
					var s := normal.dot(pts[m]) - d
					if absf(s) < 1e-4:
						on.append(m)
					elif s > 1e-4:
						outside = true
						break
				if outside or on.size() != n:
					continue
				var key := str(on)
				if seen.has(key):
					continue
				seen[key] = true
				var center := Vector3.ZERO
				for m: int in on:
					center += pts[m]
				center /= n
				var ref := (pts[on[0]] - center).normalized()
				var side := normal.cross(ref)
				on.sort_custom(func(a: int, b: int) -> bool:
					var va := pts[a] - center
					var vb := pts[b] - center
					return atan2(va.dot(side), va.dot(ref)) < atan2(vb.dot(side), vb.dot(ref)))
				out.append(on)
	return out
