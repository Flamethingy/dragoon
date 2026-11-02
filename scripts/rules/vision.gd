class_name Vision
extends RefCounted
## Walls, doors, light and sight on a map (TASK-73). In cell units: (0, 0) is the map's
## top-left grid corner, walls run between grid corners ({a: [x, y], b: [x, y], door}),
## a cell's centre is (x + 0.5, y + 0.5). A map's `lighting` is "bright" (the default: walls
## alone limit sight), "dim" or "dark"; `lights` [{at: [x, y], bright: m, dim: m}] light the
## squares around them. A creature sees a square if no wall (or closed door) is in the way and
## it is lit (bright or dim), or within its darkvision. Difficult terrain (`terrain`, cells)
## costs an extra square to enter.

const MAX_SIGHT := 40  ## squares (60 m): as far as anyone looks on a battle map


## The walls that block: every wall but the open doors (`open`: wall index -> true).
static func blocking(walls: Array, open: Dictionary) -> Array:
	var out := []
	for i in walls.size():
		var w: Variant = walls[i]
		if not w is Dictionary:
			continue
		if bool(w.get("door", false)) and bool(open.get(i, open.get(str(i), false))):
			continue
		out.append([_v(w.get("a")), _v(w.get("b"))])
	return out


static func _v(p: Variant) -> Vector2:
	if p is Vector2:
		return p
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


## Do segments p-q and a-b cross (touching counts: a corner where walls meet blocks too)?
static func crosses(p: Vector2, q: Vector2, a: Vector2, b: Vector2) -> bool:
	var d1 := (q - p).cross(a - p)
	var d2 := (q - p).cross(b - p)
	var d3 := (b - a).cross(p - a)
	var d4 := (b - a).cross(q - a)
	if ((d1 > 0.0001 and d2 < -0.0001) or (d1 < -0.0001 and d2 > 0.0001)) and ((d3 > 0.0001 and d4 < -0.0001) or (d3 < -0.0001 and d4 > 0.0001)):
		return true
	return (absf(d1) <= 0.0001 and _on(p, q, a)) or (absf(d2) <= 0.0001 and _on(p, q, b)) \
		or (absf(d3) <= 0.0001 and _on(a, b, p) and absf(d4) > 0.0001) or (absf(d4) <= 0.0001 and _on(a, b, q) and absf(d3) > 0.0001)


static func _on(p: Vector2, q: Vector2, r: Vector2) -> bool:
	return r.x >= minf(p.x, q.x) - 0.0001 and r.x <= maxf(p.x, q.x) + 0.0001 and r.y >= minf(p.y, q.y) - 0.0001 and r.y <= maxf(p.y, q.y) + 0.0001


static func line_clear(from: Vector2, to: Vector2, segs: Array) -> bool:
	for s: Array in segs:
		if crosses(from, to, s[0], s[1]):
			return false
	return true


## 2 bright, 1 dim, 0 dark at a cell centre.
static func light_at(p: Vector2, lights: Array, ambient: String) -> int:
	var level := 2 if ambient == "bright" or ambient == "" else (1 if ambient == "dim" else 0)
	for l: Variant in lights:
		if not l is Dictionary or level == 2:
			continue
		var at := _v(l.get("at")) + Vector2(0.5, 0.5)
		var m := p.distance_to(at) * TokenGrid.METRES_PER_CELL
		if m <= float(l.get("bright", 6.0)) + 0.01:
			level = 2
		elif m <= float(l.get("bright", 6.0)) + float(l.get("dim", 6.0)) + 0.01:
			level = maxi(level, 1)
	return level


## The squares the viewers see: {Vector2i: true}. A viewer: {cell: Vector2i, cells: size in
## squares, darkvision: metres}. `size`: the map in squares. Its own squares are always seen.
static func visible(map: Dictionary, viewers: Array, open: Dictionary, size: Vector2i) -> Dictionary:
	var segs := blocking(map.get("walls", []) if map.get("walls") is Array else [], open)
	var lights: Array = map.get("lights", []) if map.get("lights") is Array else []
	var ambient := str(map.get("lighting", "bright"))
	var out := {}
	for v: Dictionary in viewers:
		var at: Vector2i = v.cell
		var n := maxi(1, ceili(float(v.get("cells", 1.0))))
		var eye := Vector2(at) + Vector2.ONE * n / 2.0
		var dark := float(v.get("darkvision", 0.0)) / TokenGrid.METRES_PER_CELL
		for y in n:
			for x in n:
				out[at + Vector2i(x, y)] = true
		for y in range(maxi(0, at.y - MAX_SIGHT), mini(size.y, at.y + n + MAX_SIGHT)):
			for x in range(maxi(0, at.x - MAX_SIGHT), mini(size.x, at.x + n + MAX_SIGHT)):
				var c := Vector2i(x, y)
				if out.has(c):
					continue
				var p := Vector2(x + 0.5, y + 0.5)
				var dist := eye.distance_to(p)
				if dist > MAX_SIGHT:
					continue
				if light_at(p, lights, ambient) == 0 and dist > dark + 0.5:
					continue
				if line_clear(eye, p, segs):
					out[c] = true
	return out


## Squares a straight move from `from` to `to` enters (like moving: diagonals count as one).
static func path_cells(from: Vector2i, to: Vector2i) -> Array:
	var out := []
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		out.append(Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t))))
	return out


## The squares a move costs: one per square, one more for each difficult one it enters.
static func move_cost(from: Vector2i, to: Vector2i, terrain: Dictionary) -> int:
	var cost := 0
	for c: Vector2i in path_cells(from, to):
		cost += 2 if terrain.has(c) else 1
	return cost


## {Vector2i: true} from a map's `terrain` [[x, y], ...].
static func terrain_of(map: Dictionary) -> Dictionary:
	var out := {}
	for c: Variant in map.get("terrain", []):
		if c is Array and (c as Array).size() >= 2:
			out[Vector2i(int(c[0]), int(c[1]))] = true
		elif c is Vector2i:
			out[c] = true
	return out


## Darkvision in metres from a sheet's `darkvision` or senses ("Darkvision 18 m", "60 ft.").
static func darkvision_m(s: Dictionary) -> float:
	if s.get("darkvision") is float or s.get("darkvision") is int:
		return float(s.darkvision)
	for v: Variant in (s.get("senses", []) if s.get("senses") is Array else [str(s.get("senses", ""))]):
		var m := RegEx.create_from_string("(?i)darkvision\\s*(\\d+(?:\\.\\d+)?)\\s*(m|ft)?").search(str(v))
		if m != null:
			var n := float(m.get_string(1))
			return n * 0.3 if m.get_string(2).to_lower() == "ft" else n
	return 0.0
