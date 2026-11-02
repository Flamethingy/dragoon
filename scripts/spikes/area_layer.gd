class_name AreaLayer
extends Node2D
## Area templates and the ruler on the map (TASK-67). Templates (sphere, cone, line, cube,
## cylinder; sizes in metres) are the table's (everyone sees them); this layer draws them,
## places new ones (a sphere with one click on a grid corner; cone, line and cube: a click for
## the point of origin, then aim with the mouse and click again) and measures with the ruler
## (drag, metres like moving: every square 1.5 m, diagonals too). Esc cancels.
## Geometry is in cell units: (0, 0) is the map's top-left grid corner, a cell's centre is
## (x + 0.5, y + 0.5). A square is covered if its centre is inside or half of it is (5e grid rule).

signal placed(template: Dictionary)  ## a new template, for the table to share
signal ruler_changed

const CONE_HALF_ANGLE := 0.4636476  ## atan(1/2): a 5e cone is as wide as it is long
const SHAPES := ["sphere", "cone", "line", "cube", "cylinder"]

var grid: TokenGrid
var templates: Array = []  ## the table's: [{id, shape, size, width, origin: [x, y], angle, by, color}]
var mode := ""  ## "" | "place" | "ruler"
var placing := {}  ## the template being placed (origin set once `aiming`)
var aiming := false
var ruler_from := Vector2.ZERO
var ruler_to := Vector2.ZERO
var measuring := false
var _font: Font


func _ready() -> void:
	name = "Areas"
	z_index = 5
	_font = ThemeDB.fallback_font


func set_templates(list: Array) -> void:
	templates = list.duplicate(true)
	queue_redraw()


## Starts placing a `shape` of `size_m` (a line `width_m` wide).
func start_place(shape: String, size_m: float, width_m := 1.5, extra := {}) -> void:
	mode = "place"
	aiming = false
	placing = {"shape": shape if shape in SHAPES else "sphere", "size": size_m / TokenGrid.METRES_PER_CELL,
		"width": maxf(width_m, 0.0) / TokenGrid.METRES_PER_CELL, "origin": [0.0, 0.0], "angle": 0.0}
	placing.merge(extra)
	queue_redraw()


func start_ruler() -> void:
	mode = "ruler"
	measuring = false
	queue_redraw()


func cancel() -> void:
	mode = ""
	placing = {}
	aiming = false
	measuring = false
	queue_redraw()
	ruler_changed.emit()


## The map position under the mouse in cell units.
func _cell_pos(world: Vector2) -> Vector2:
	return (world - grid.offset) / grid.cell


static func snap_corner(p: Vector2) -> Vector2:
	return p.round()


## The TokenGrid's input goes here first; true if it was used.
func handle(event: InputEvent) -> bool:
	if mode == "":
		return false
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		cancel()
		return true
	var world := get_global_mouse_position()
	if event is InputEventMouse:  # where the event happened (like the grid reads it)
		world = get_canvas_transform().affine_inverse() * (event as InputEventMouse).position
	var p := _cell_pos(world)
	if event is InputEventMouseMotion:
		if mode == "place":
			if aiming:
				var o := Vector2(placing.origin[0], placing.origin[1])
				if p.distance_to(o) > 0.05:
					placing.angle = (p - o).angle()
			else:
				var c := snap_corner(p)
				placing.origin = [c.x, c.y]
			queue_redraw()
		elif mode == "ruler" and measuring:
			ruler_to = (p - Vector2(0.5, 0.5)).round() + Vector2(0.5, 0.5)
			queue_redraw()
			ruler_changed.emit()
		return false  # hover and panning still work
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if mode == "place" and event.pressed:
			if str(placing.shape) in ["sphere", "cylinder"] or aiming:
				var t := placing.duplicate(true)
				mode = ""
				placing = {}
				aiming = false
				queue_redraw()
				placed.emit(t)
			else:
				aiming = true
			return true
		if mode == "ruler":
			var c := (p - Vector2(0.5, 0.5)).round() + Vector2(0.5, 0.5)
			if event.pressed:
				measuring = true
				ruler_from = c
				ruler_to = c
			else:
				measuring = false  # it stays on the map until the next measure or Esc
			queue_redraw()
			ruler_changed.emit()
			return true
	return false


## Metres between two cell centres (like moving: Chebyshev squares x 1.5 m).
static func metres(a: Vector2, b: Vector2) -> float:
	var d := (b - a).abs().round()
	return maxf(d.x, d.y) * TokenGrid.METRES_PER_CELL


func ruler_metres() -> float:
	return metres(ruler_from, ruler_to)


# --- Geometry ----------------------------------------------------------------------------------

static func contains(t: Dictionary, p: Vector2) -> bool:
	var o := Vector2(float(t.origin[0]), float(t.origin[1]))
	var size := float(t.size)
	var dir := Vector2.from_angle(float(t.get("angle", 0.0)))
	var rel := p - o
	match str(t.shape):
		"sphere", "cylinder":
			return rel.length() <= size + 0.0001
		"cone":
			var d := rel.dot(dir)
			return d >= 0.0 and d <= size + 0.0001 and absf(rel.dot(dir.orthogonal())) <= d / 2.0 + 0.0001
		"line":
			var d := rel.dot(dir)
			return d >= 0.0 and d <= size + 0.0001 and absf(rel.dot(dir.orthogonal())) <= maxf(float(t.get("width", 1.0)), 0.01) / 2.0 + 0.0001
		"cube":
			var d := rel.dot(dir)
			return d >= 0.0 and d <= size + 0.0001 and absf(rel.dot(dir.orthogonal())) <= size / 2.0 + 0.0001
	return false


## The squares the template covers (its centre is in, or half of it).
static func cells_of(t: Dictionary) -> Array[Vector2i]:
	var o := Vector2(float(t.origin[0]), float(t.origin[1]))
	var r := ceili(float(t.size) + float(t.get("width", 0.0))) + 1
	var out: Array[Vector2i] = []
	for y in range(floori(o.y) - r, ceili(o.y) + r):
		for x in range(floori(o.x) - r, ceili(o.x) + r):
			if contains(t, Vector2(x + 0.5, y + 0.5)):
				out.append(Vector2i(x, y))
				continue
			var n := 0
			for sy in 4:
				for sx in 4:
					if contains(t, Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0)):
						n += 1
			if n >= 8:
				out.append(Vector2i(x, y))
	return out


## The tokens in the template (any of their squares covered).
static func tokens_in(t: Dictionary, g: TokenGrid) -> Array:
	var covered := {}
	for c: Vector2i in cells_of(t):
		covered[c] = true
	var out := []
	for id: String in g.tokens:
		var at: Vector2i = g.tokens[id].get_meta("cell", Vector2i.ZERO)
		var n := maxi(1, ceili(float(g.tokens[id].get_meta("cells", 1.0))))
		var hit := false
		for y in n:
			for x in n:
				if covered.has(at + Vector2i(x, y)):
					hit = true
		if hit:
			out.append(id)
	return out


## The outline in cell units (a circle as a polygon).
static func outline(t: Dictionary) -> PackedVector2Array:
	var o := Vector2(float(t.origin[0]), float(t.origin[1]))
	var size := float(t.size)
	var dir := Vector2.from_angle(float(t.get("angle", 0.0)))
	var side := dir.orthogonal()
	match str(t.shape):
		"cone":
			return PackedVector2Array([o, o + dir * size + side * size / 2.0, o + dir * size - side * size / 2.0])
		"line", "cube":
			var w := (float(t.get("width", 1.0)) if str(t.shape) == "line" else size) / 2.0
			return PackedVector2Array([o + side * w, o + dir * size + side * w, o + dir * size - side * w, o - side * w])
	var pts := PackedVector2Array()
	for i in 48:
		pts.append(o + Vector2.from_angle(TAU * i / 48.0) * size)
	return pts


# --- Drawing -----------------------------------------------------------------------------------

func _draw() -> void:
	if grid == null:
		return
	for t: Dictionary in templates:
		_draw_template(t, Color.html(str(t.get("color", "#e07a2e"))) if Color.html_is_valid(str(t.get("color", ""))) else Color(0.88, 0.48, 0.18))
	if mode == "place" and not placing.is_empty():
		_draw_template(placing, Color(0.95, 0.85, 0.3))
	if mode == "ruler" or measuring or ruler_from != ruler_to:
		if ruler_from != ruler_to:
			var a := grid.offset + ruler_from * grid.cell
			var b := grid.offset + ruler_to * grid.cell
			draw_line(a, b, Color(1, 1, 0.4, 0.95), 3.0)
			draw_circle(a, 5.0, Color(1, 1, 0.4))
			draw_circle(b, 5.0, Color(1, 1, 0.4))
			var label := "%s m" % MovePlans._num(ruler_metres())
			draw_string(_font, b + Vector2(10, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.6))


func _draw_template(t: Dictionary, color: Color) -> void:
	for c: Vector2i in cells_of(t):
		draw_rect(Rect2(grid.offset + Vector2(c) * grid.cell, Vector2.ONE * grid.cell), Color(color, 0.16))
	var pts := PackedVector2Array()
	for p: Vector2 in outline(t):
		pts.append(grid.offset + p * grid.cell)
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(color, 0.18))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Color(color, 0.95), 2.5)
	var o := grid.offset + Vector2(float(t.origin[0]), float(t.origin[1])) * grid.cell
	draw_circle(o, 4.0, color)
	var label := "%s %s m" % [str(t.shape), MovePlans._num(float(t.size) * TokenGrid.METRES_PER_CELL)]
	draw_string(_font, o + Vector2(8, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))
