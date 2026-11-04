class_name MovePlans
extends Node2D
## Planned moves on the map (TASK-45, Nico 2026-11-01). Dragging a token leaves the real one
## where it is: a transparent ghost follows the mouse and a dotted trail marks the way it
## took, with the distance. On release the ghost stays at the end; nothing has moved yet.
## Space sends every planned move: the tokens glide along their trails, which disappear
## behind them. Esc drops the plans. A ghost can be picked up again to change its move
## (Nico, 2026-11-02): the trail goes on from where it ended. Also the ghost of a token being
## spawned from the Book.
## A child of the TokenGrid, drawn above the tokens.

const GHOST_ALPHA := 0.45
const DOT := 7.0  ## length of a dash, pixels on the map
const GAP := 6.0
const FADE := 1.5  ## metres over which the colour changes at the walking speed and at double
const YELLOW := Color(1.0, 0.88, 0.25)  ## just past the walking speed
const ORANGE := Color(1.0, 0.55, 0.15)  ## at double (a Dash)
const RED := Color(1.0, 0.3, 0.25)  ## further than a Dash

var grid: TokenGrid
## id -> {path: Array[Vector2i] (cells, start first), ghost: Sprite2D, done: int (cells passed),
##        hard: difficult squares, speed: walking metres (both taken when the drag starts)}
var plans := {}
var _dragging := {}  ## ids being dragged now -> true (their plan follows the mouse)
var _spawn: Sprite2D  ## the ghost of a token being dropped in from the Book
var _font: Font


func _ready() -> void:
	z_index = 20
	_font = ThemeDB.fallback_font


## A drag of these tokens starts (the first one leads): ghosts at the tokens, trails at their cells.
func begin_drag(ids: Array) -> void:
	_dragging.clear()
	for id: String in ids:
		if not grid.tokens.has(id):
			continue
		cancel(id)
		var token: Sprite2D = grid.tokens[id]
		plans[id] = {"path": [grid.token_cell(id)], "ghost": _ghost_of(token), "done": 0}
		(plans[id].ghost as Sprite2D).position = token.position
		_dragging[id] = true
		_measure(id)
	queue_redraw()


## The planned ghost under `pos` (map pixels), "" if none: it can be picked up again.
func ghost_at(pos: Vector2) -> String:
	for id: String in plans:
		var plan: Dictionary = plans[id]
		if plan.has("going") or _dragging.has(id) or not grid.tokens.has(id):
			continue
		var cells: float = grid.tokens[id].get_meta("cells")
		if (plan.ghost as Sprite2D).position.distance_to(pos) <= grid.cell * maxf(cells, 1.0) * 0.5:
			return id
	return ""


## Picks up the ghost of `id` again: dragging it goes on with its trail.
func resume_drag(id: String) -> void:
	_dragging.clear()
	if plans.has(id) and not plans[id].has("going"):
		_dragging[id] = true
		_measure(id)
	queue_redraw()


## What the trail's label needs, taken once when a drag starts: looking it up on every mouse
## move made dragging lag (Nico 2026-11-04).
func _measure(id: String) -> void:
	plans[id]["hard"] = grid.difficult_for(id)  # TASK-73 terrain, TASK-79 other creatures
	plans[id]["speed"] = float(grid.speed.call(id)) if grid.speed.is_valid() else 0.0


## The mouse moved by `delta` (map pixels): every dragged ghost moves; the lead's trail grows
## by the cells its ghost passes (going back over the trail shortens it).
func drag_by(lead: String, delta: Vector2) -> void:
	for id: String in _dragging:
		if plans.has(id):
			(plans[id].ghost as Sprite2D).position += delta
	if plans.has(lead):
		var cell := cell_under_ghost(lead)
		plans[lead].path = extend(plans[lead].path, cell)
	queue_redraw()


## The drag ended: the lead's trail ends at `target`, the others go straight to their cells
## (`ends`: id -> cell; ids missing there have no place and lose their plan).
func end_drag(lead: String, target: Vector2i, ends: Dictionary) -> void:
	for id: String in _dragging.keys():
		if not plans.has(id):
			continue
		var end: Variant = target if id == lead else ends.get(id)
		if end == null:
			cancel(id)
			continue
		var path: Array = plans[id].path if id == lead else [grid.token_cell(id)]
		path = extend(path, end)
		if path.size() < 2:
			cancel(id)
			continue
		plans[id].path = path
		var ghost: Sprite2D = plans[id].ghost
		ghost.position = grid.cell_center(end, float(grid.tokens[id].get_meta("cells")))
	_dragging.clear()
	queue_redraw()


## Space: every planned token goes. Returns the moves (id -> {to, path}) the grid sends.
func go() -> Dictionary:
	var out := {}
	for id: String in plans.keys():
		if _dragging.has(id) or not grid.tokens.has(id):
			continue
		var path: Array = plans[id].path
		out[id] = {"to": path[path.size() - 1], "path": path.duplicate()}
		(plans[id].ghost as Sprite2D).visible = false
		plans[id]["going"] = true
	queue_redraw()
	return out


## The token of a plan reached the n-th cell of its trail: the trail behind it disappears;
## at the end the plan is gone.
func advance(id: String, n: int) -> void:
	if not plans.has(id):
		return
	plans[id].done = n
	if n >= (plans[id].path as Array).size() - 1:
		cancel(id)
	queue_redraw()


func has_plans() -> bool:
	return plans.keys().any(func(id: String) -> bool: return not _dragging.has(id) and not plans[id].has("going"))


## Drops a plan ("" = all of them).
func cancel(id := "") -> void:
	for key: String in (plans.keys() if id == "" else [id]):
		if plans.has(key):
			var ghost: Sprite2D = plans[key].ghost
			if is_instance_valid(ghost):
				ghost.queue_free()
			plans.erase(key)
			_dragging.erase(key)
	queue_redraw()


## Squares along a trail (5e: a diagonal step is one square too).
static func squares(path: Array) -> int:
	return maxi(0, path.size() - 1)


## One more square for each difficult one the trail enters (TASK-73).
static func extra_cost(path: Array, terrain: Dictionary) -> int:
	var n := 0
	for i in range(1, path.size()):
		if terrain.has(path[i]):
			n += 1
	return n


## The trail extended to `cell`: one square at a time (diagonals first); if the cell is
## already on it, the trail goes back to there.
static func extend(path: Array, cell: Vector2i) -> Array:
	var out := path.duplicate()
	var at := out.find(cell)
	if at >= 0:
		return out.slice(0, at + 1)
	var last: Vector2i = out[out.size() - 1]
	while last != cell:
		last += Vector2i(signi(cell.x - last.x), signi(cell.y - last.y))
		var back := out.find(last)
		if back >= 0:
			out = out.slice(0, back + 1)
		else:
			out.append(last)
	return out


## The cell under a dragged ghost (its top-left cell for big creatures).
func cell_under_ghost(id: String) -> Vector2i:
	var ghost: Sprite2D = plans[id].ghost
	var cells: float = grid.tokens[id].get_meta("cells")
	var corner := ghost.position - Vector2.ONE * grid.cell * maxf(cells, 1.0) * 0.5 + Vector2.ONE * grid.cell * 0.5
	return grid.cell_at(corner)


## The ghost of a token being spawned (null texture or cell < 0: hide it).
func show_spawn(texture: Texture2D, cells: float, at: Vector2i) -> void:
	if texture == null or at.x < 0:
		hide_spawn()
		return
	if _spawn == null:
		_spawn = Sprite2D.new()
		_spawn.name = "SpawnGhost"
		_spawn.modulate.a = GHOST_ALPHA
		add_child(_spawn)
	_spawn.texture = texture
	_spawn.scale = Vector2.ONE * grid.cell * cells / maxf(texture.get_width(), texture.get_height())
	_spawn.position = grid.cell_center(at, cells)
	_spawn.visible = true


func hide_spawn() -> void:
	if _spawn != null:
		_spawn.visible = false


func spawn_visible() -> bool:
	return _spawn != null and _spawn.visible


func _ghost_of(token: Sprite2D) -> Sprite2D:
	var g := Sprite2D.new()
	g.texture = token.texture
	g.scale = token.scale
	g.flip_h = token.flip_h
	g.modulate.a = GHOST_ALPHA
	add_child(g)
	return g


func _draw() -> void:
	for id: String in plans:
		if not grid.tokens.has(id):
			continue
		var plan: Dictionary = plans[id]
		var path: Array = plan.path
		var cells: float = grid.tokens[id].get_meta("cells")
		# Each point of the trail with the metres walked up to it (difficult squares count
		# twice), so the dots take the colour of how far the creature has come there.
		var hard: Dictionary = plan.get("hard", {})
		var speed := float(plan.get("speed", 0.0))
		var walked := [0.0]
		for i in range(1, path.size()):
			walked.append(float(walked[i - 1]) + TokenGrid.METRES_PER_CELL * (2.0 if hard.has(path[i]) else 1.0))
		var pts := PackedVector2Array()
		var metres := PackedFloat32Array()
		for i in range(int(plan.done), path.size()):
			pts.append(grid.cell_center(path[i], cells))
			metres.append(float(walked[i]))
		if _dragging.has(id):  # the trail runs on to the ghost under the mouse
			pts.append((plan.ghost as Sprite2D).position)
			metres.append(float(walked[walked.size() - 1]))
		var n := squares(path) + extra_cost(path, hard)  # TASK-73 terrain, TASK-79 other creatures
		var color := distance_color(n * TokenGrid.METRES_PER_CELL, speed)
		_dotted(pts, metres, speed, 4.0)
		if plan.has("going") or path.size() < 2 and not _dragging.has(id):
			continue
		var label := "%s m" % _metres(n)  # just this drag's distance (Nico 2026-11-04)
		var at: Vector2 = (plan.ghost as Sprite2D).position + Vector2(grid.cell * maxf(cells, 1.0) * 0.5 + 6, -8)
		var size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_rect(Rect2(at + Vector2(-5, -size.y + 2), size + Vector2(10, 6)), Color(0, 0, 0, 0.55))
		draw_string(_font, at + Vector2(0, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)


## The trail's colour after `metres` of a creature walking `speed` metres (Nico 2026-11-04):
## white up to its speed, then a short fade to yellow, turning orange towards double (a Dash),
## a short fade to red beyond that. White if the speed isn't known.
static func distance_color(metres: float, speed: float) -> Color:
	if speed <= 0.0 or metres <= speed:
		return Color.WHITE
	if metres <= speed + FADE:
		return Color.WHITE.lerp(YELLOW, (metres - speed) / FADE)
	if metres <= 2.0 * speed:
		return YELLOW.lerp(ORANGE, (metres - speed - FADE) / maxf(speed - FADE, 0.01))
	if metres <= 2.0 * speed + FADE:
		return ORANGE.lerp(RED, (metres - 2.0 * speed) / FADE)
	return RED


static func _num(m: float) -> String:
	return str(int(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m


static func _metres(squares_moved: int) -> String:
	var m := squares_moved * TokenGrid.METRES_PER_CELL
	return str(int(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m


## A dashed line through `pts`; each dash coloured by the metres walked where it starts
## (`metres`: one per point, interpolated along the segments). The dash pattern runs on
## across the points, so dashes don't pile up where two segments meet.
func _dotted(pts: PackedVector2Array, metres: PackedFloat32Array, speed: float, width: float) -> void:
	var phase := 0.0  ## how far into the current dash + gap the line is
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0:
			continue
		var dir := (b - a) / length
		var t := 0.0
		while t < length:
			if phase < DOT:  # in a dash: draw up to its end or the segment's
				var to := minf(t + DOT - phase, length)
				var m := lerpf(metres[i], metres[i + 1], t / length)
				draw_line(a + dir * t, a + dir * to, Color(distance_color(m, speed), 0.85), width, true)
				phase += to - t
				t = to
			else:  # in a gap
				var to := minf(t + DOT + GAP - phase, length)
				phase += to - t
				t = to
			if phase >= DOT + GAP - 0.001:
				phase = 0.0
