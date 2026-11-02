class_name MapLayer
extends Node2D
## Walls, doors, light, difficult terrain and fog of war on the map (TASK-73). Draws what the
## table sends: the DM sees walls (grey), doors (brown; open ones dashed), lights and the
## terrain; players see doors, the terrain in what they see, and the fog (black where they
## never looked, dimmed where they looked before). The DM edits here: "wall" / "door" (click
## grid corners one after the other; Esc or a right click ends the line), "erase" (a click on
## a wall), "terrain" (click or drag over squares) and "light" (a click puts a light there or
## takes it away). A click on a door (no tool) opens or closes it.

signal edited(changes: Dictionary)  ## {walls | terrain | lights: the new list}, for the table
signal door_clicked(index: int)

var grid: TokenGrid
var dm := false
var walls: Array = []  ## [{a: [x, y], b: [x, y], door}] (the DM's; players get only doors)
var doors: Array = []  ## [{i, a, b, open}]
var terrain := {}  ## Vector2i -> true
var lights: Array = []
var lighting := "bright"
var fog := false  ## fog of war on this map (players)
var seen := {}  ## Vector2i -> true: what the player sees now
var explored := {}  ## Vector2i -> true: what the player saw before
var mode := ""  ## "" | "wall" | "door" | "erase" | "terrain" | "light"
var _from := Vector2(-1, -1)  ## the line being drawn: its last corner
var _hover := Vector2.ZERO
var _painting := false
var _paint_on := true


func _ready() -> void:
	name = "MapLayer"
	z_index = 4  # over the tokens (fog), under area templates


## The table's map data: {walls, doors, terrain, lights, lighting, fog} and the player's
## {visible, explored} ([[x, y], ...]).
func set_data(map: Dictionary, vision: Dictionary) -> void:
	walls = (map.get("walls", []) as Array).duplicate(true) if map.get("walls") is Array else []
	doors = (map.get("doors", []) as Array).duplicate(true) if map.get("doors") is Array else []
	terrain = Vision.terrain_of(map)
	lights = (map.get("lights", []) as Array).duplicate(true) if map.get("lights") is Array else []
	lighting = str(map.get("lighting", "bright"))
	fog = bool(map.get("fog", false)) and not dm
	seen = _cells(vision.get("visible", []))
	explored = _cells(vision.get("explored", []))
	queue_redraw()


static func _cells(list: Variant) -> Dictionary:
	var out := {}
	if list is Array:
		for c: Variant in list:
			if c is Array and (c as Array).size() >= 2:
				out[Vector2i(int(c[0]), int(c[1]))] = true
	return out


func start(tool: String) -> void:
	mode = tool
	_from = Vector2(-1, -1)
	queue_redraw()


func cancel() -> void:
	mode = ""
	_from = Vector2(-1, -1)
	_painting = false
	queue_redraw()


func _pos(event: InputEventMouse) -> Vector2:
	return ((get_canvas_transform().affine_inverse() * event.position) - grid.offset) / grid.cell


## The TokenGrid's input comes here first; true if it was used.
func handle(event: InputEvent) -> bool:
	if mode == "":
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var d := _door_at(_pos(event))
			if d >= 0:
				door_clicked.emit(d)
				return true
		return false
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		cancel()
		return true
	if not event is InputEventMouse:
		return false
	var p := _pos(event)
	if event is InputEventMouseMotion:
		_hover = p
		if mode == "terrain" and _painting:
			_paint(Vector2i(floori(p.x), floori(p.y)))
		queue_redraw()
		return false
	var b := event as InputEventMouseButton
	if b.button_index == MOUSE_BUTTON_RIGHT and b.pressed and mode in ["wall", "door"]:
		_from = Vector2(-1, -1)  # the line ends; the tool stays
		queue_redraw()
		return true
	if b.button_index != MOUSE_BUTTON_LEFT:
		return false
	match mode:
		"wall", "door":
			if b.pressed:
				var c := p.round()
				if _from.x >= 0 and c != _from:
					var list := walls.duplicate(true)
					list.append({"a": [int(_from.x), int(_from.y)], "b": [int(c.x), int(c.y)], "door": mode == "door"})
					walls = list
					edited.emit({"walls": list})
					_from = c if mode == "wall" else Vector2(-1, -1)  # walls chain on, a door is one piece
				else:
					_from = c
				queue_redraw()
			return true
		"erase":
			if b.pressed:
				var i := _wall_at(p)
				if i >= 0:
					var list := walls.duplicate(true)
					list.remove_at(i)
					walls = list
					edited.emit({"walls": list})
			return true
		"terrain":
			var c := Vector2i(floori(p.x), floori(p.y))
			if b.pressed:
				_painting = true
				_paint_on = not terrain.has(c)
				_paint(c)
			else:
				_painting = false
				edited.emit({"terrain": terrain.keys().map(func(v: Vector2i) -> Array: return [v.x, v.y])})
			return true
		"light":
			if b.pressed:
				var c := Vector2i(floori(p.x), floori(p.y))
				var list := lights.filter(func(l: Dictionary) -> bool: return Vision._v(l.at) != Vector2(c))
				if list.size() == lights.size():
					list.append({"at": [c.x, c.y], "bright": 6.0, "dim": 6.0})
				lights = list
				edited.emit({"lights": list})
				queue_redraw()
			return true
	return false


func _paint(c: Vector2i) -> void:
	if _paint_on:
		terrain[c] = true
	else:
		terrain.erase(c)
	queue_redraw()


## The wall (index) within a fifth of a square of `p`, -1 if none.
func _wall_at(p: Vector2) -> int:
	for i in walls.size():
		var w: Dictionary = walls[i]
		if _near(p, Vision._v(w.a), Vision._v(w.b)):
			return i
	return -1


func _door_at(p: Vector2) -> int:
	for d: Variant in doors:
		if d is Dictionary and _near(p, Vision._v(d.a), Vision._v(d.b)):
			return int(d.i)
	return -1


static func _near(p: Vector2, a: Vector2, b: Vector2) -> bool:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 0.2


func _draw() -> void:
	if grid == null or grid.map_size == Vector2.ZERO:
		return
	var c := grid.cell
	var o := grid.offset
	for t: Vector2i in terrain:  # difficult terrain: hatched
		if fog and not seen.has(t):
			continue
		var r := Rect2(o + Vector2(t) * c, Vector2.ONE * c)
		draw_rect(r, Color(0.55, 0.4, 0.15, 0.18))
		for k in 3:
			var f := (k + 1) / 4.0
			draw_line(r.position + Vector2(r.size.x * f, 0), r.position + Vector2(0, r.size.y * f), Color(0.6, 0.45, 0.2, 0.5), 1.5)
	if dm:
		for w: Variant in walls:
			if w is Dictionary and not bool(w.get("door", false)):
				draw_line(o + Vision._v(w.a) * c, o + Vision._v(w.b) * c, Color(0.85, 0.85, 0.9, 0.9), 4.0)
		for l: Variant in lights:
			if l is Dictionary:
				var at := o + (Vision._v(l.at) + Vector2(0.5, 0.5)) * c
				draw_circle(at, c * 0.18, Color(1, 0.85, 0.3, 0.9))
				draw_arc(at, float(l.get("bright", 6.0)) / TokenGrid.METRES_PER_CELL * c, 0, TAU, 48, Color(1, 0.85, 0.3, 0.5), 2.0)
				draw_arc(at, (float(l.get("bright", 6.0)) + float(l.get("dim", 6.0))) / TokenGrid.METRES_PER_CELL * c, 0, TAU, 48, Color(1, 0.85, 0.3, 0.25), 1.5)
	for d: Variant in doors:
		if not d is Dictionary:
			continue
		var a := o + Vision._v(d.a) * c
		var b := o + Vision._v(d.b) * c
		if bool(d.get("open", false)):
			draw_dashed_line(a, b, Color(0.7, 0.5, 0.25, 0.8), 3.0, 8.0)
		else:
			draw_line(a, b, Color(0.55, 0.33, 0.12, 1.0), 6.0)
	if fog:
		for y in grid.grid_size.y + 1:  # + the part squares at the map's edge
			for x in grid.grid_size.x + 1:
				var cc := Vector2i(x, y)
				if seen.has(cc):
					continue
				draw_rect(Rect2(o + Vector2(cc) * c, Vector2.ONE * c), Color(0, 0, 0, 0.55) if explored.has(cc) else Color(0.02, 0.02, 0.03, 1.0))
	if mode in ["wall", "door"]:
		var h := _hover.round()
		draw_circle(o + h * c, 5.0, Color(1, 1, 0.5))
		if _from.x >= 0:
			draw_line(o + _from * c, o + h * c, Color(1, 1, 0.5, 0.8), 3.0)
