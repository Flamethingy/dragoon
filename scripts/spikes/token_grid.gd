class_name TokenGrid
extends Node2D
## A map image with a grid overlay and tokens on it at their creature size (TASK-3 spike,
## the shared table since TASK-7). It only shows what it is given: show_map() and
## add_token_view(); the table (NetTable) decides. Tokens are keyed by entity ref and placed
## by cell; moves glide. Mouse wheel zooms, right/middle drag pans, hovering a token shows
## its name (and HP/AC when the viewer may see them).

## A token was dropped on a cell (left drag). Whoever owns the state decides.
signal move_requested(entity: String, cell: Vector2i)
## A token was clicked (pressed and released without dragging), e.g. to open its sheet.
signal token_clicked(entity: String)
## WASD / arrow keys with tokens selected (TASK-42): step one cell in `dir` (8 directions),
## or with Shift only turn that way. Whoever owns the state decides.
signal step_requested(entity: String, dir: Vector2i, turn_only: bool)
signal selection_changed

## The 8 directions a token can look (TASK-42).
const FACINGS := {"n": Vector2i(0, -1), "ne": Vector2i(1, -1), "e": Vector2i(1, 0), "se": Vector2i(1, 1),
	"s": Vector2i(0, 1), "sw": Vector2i(-1, 1), "w": Vector2i(-1, 0), "nw": Vector2i(-1, -1)}
## Keys pressed within this time count as one diagonal step (W and D together).
const COMBINE_SECONDS := 0.07

## Tokens per side for each creature size (tiny shares a square, drawn half size).
const SIZE_CELLS := {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 3.0, "gargantuan": 4.0}
const MOVE_SECONDS_PER_CELL := 0.12

@export var grid_color := Color(0, 0, 0, 0.35)

var map_id := ""  ## ref of the shown map, e.g. "maps/forest-road"
var cell := 70.0
var offset := Vector2.ZERO
var map_size := Vector2.ZERO
var grid_size := Vector2i.ZERO  ## map size in cells
var tokens := {}  ## entity id -> Sprite2D (meta: cell Vector2i, cells float, info Dictionary)
## Which tokens this user may drag (empty = all), e.g. players only their own PC.
var can_drag: Callable

var _image: Sprite2D

var _camera: Camera2D
var _info: Label
var _panning := false
var _dragging: Sprite2D
var _drag_from := Vector2.ZERO
var _pressed: Sprite2D  ## the token under the mouse when the left button went down
var _press_at := Vector2.ZERO  ## screen position of that press
var selected := {}  ## entity id -> true (TASK-42)
var active := ""  ## the active token (TASK-44, orange ring); "" = none
var _drag_group := {}  ## the other selected tokens dragged along: id -> start position
var _box_from := Vector2.ZERO  ## map position where a selection box started
var _boxing := false
var _box: Node2D
var _pending := Vector2i.ZERO  ## keys pressed together, collected for COMBINE_SECONDS
var _pending_turn := false
var _combine: Timer


func _ready() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	var ui := CanvasLayer.new()
	ui.layer = 0
	add_child(ui)
	_info = Label.new()
	_info.position = Vector2(12, 8)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	ui.add_child(_info)
	_box = Node2D.new()
	_box.name = "SelectBox"
	_box.z_index = 20
	_box.draw.connect(_draw_box)
	add_child(_box)
	_combine = Timer.new()
	_combine.one_shot = true
	_combine.wait_time = COMBINE_SECONDS
	_combine.timeout.connect(_send_pending)
	add_child(_combine)


## Shows a map from data: {id, name, grid: {size, offset: Vector2}} and its image.
## Removes the previous map and all tokens.
func show_map(view: Dictionary, texture: Texture2D) -> void:
	clear()
	map_id = str(view.get("id", ""))
	var grid: Dictionary = view.get("grid", {})
	cell = float(grid.get("size", 70.0))
	offset = grid.get("offset", Vector2.ZERO)
	_image = Sprite2D.new()
	_image.texture = texture
	_image.centered = false
	_image.z_index = -1  # the grid (_draw) goes on top of it
	add_child(_image)
	map_size = texture.get_size()
	grid_size = Vector2i(floori((map_size.x - offset.x) / cell), floori((map_size.y - offset.y) / cell))
	queue_redraw()
	if _camera:
		_camera.position = map_size * 0.5


## Removes the map image and all tokens.
func clear() -> void:
	for token: Sprite2D in tokens.values():
		token.queue_free()
	tokens.clear()
	selected.clear()
	if _image:
		_image.queue_free()
		_image = null
	map_size = Vector2.ZERO
	queue_redraw()


## The map's own token list: entity id -> start cell.
func start_cells() -> Dictionary:
	var out := {}
	for id: String in tokens:
		out[id] = tokens[id].get_meta("start")
	return out


## A token from data: {id, name, size, ...} (the info is shown on hover).
func add_token_view(info: Dictionary, texture: Texture2D, at: Vector2i) -> void:
	var id := str(info.get("id", ""))
	var facing := str(info.get("facing", ""))
	if tokens.has(id):
		if facing == "":
			facing = str(tokens[id].get_meta("facing", ""))
		tokens[id].queue_free()
	var cells: float = SIZE_CELLS.get(str(info.get("size", "medium")).to_lower(), 1.0)
	var token := Sprite2D.new()
	token.texture = texture
	token.scale = Vector2.ONE * cell * cells / maxf(texture.get_width(), texture.get_height())
	token.set_meta("entity", id)
	token.set_meta("cells", cells)
	token.set_meta("start", at)
	token.set_meta("info", info)
	tokens[id] = token
	var marks := TokenMarks.new()
	marks.name = "Marks"
	marks.scale = Vector2.ONE / token.scale
	marks.radius = cell * cells * 0.5
	marks.selected = selected.has(id)
	marks.active = id == active
	token.add_child(marks)
	add_child(token)
	set_token_cell(id, at, false)
	set_token_facing(id, facing)


## Turns a token (n, ne, e ... nw): the triangle at its edge, and the picture mirrored when
## it looks to the other side than the picture faces (token_style.faces).
func set_token_facing(id: String, facing: String) -> void:
	var token: Sprite2D = tokens.get(id)
	if token == null:
		return
	token.set_meta("facing", facing)
	(token.get_node("Marks") as TokenMarks).set_facing(facing)
	var dx: int = FACINGS[facing].x if FACINGS.has(facing) else 0
	if dx != 0:
		var style: Variant = (token.get_meta("info", {}) as Dictionary).get("token_style")
		var faces := str(style.get("faces", "right")) if style is Dictionary else "right"
		token.flip_h = (dx < 0) == (faces == "right")


func token_facing(id: String) -> String:
	return str(tokens[id].get_meta("facing", "")) if tokens.has(id) else ""


## The facing for a step (or "" for none).
static func facing_of(dir: Vector2i) -> String:
	var d := dir.clamp(Vector2i(-1, -1), Vector2i(1, 1))
	for f: String in FACINGS:
		if FACINGS[f] == d:
			return f
	return ""


# --- Selection (TASK-42) --------------------------------------------------------------------

## Selects these tokens (only those this user may move); `add` keeps the others.
func select(ids: Array, add := false) -> void:
	if not add:
		for id: String in selected:
			if tokens.has(id):
				(tokens[id].get_node("Marks") as TokenMarks).selected = false
		selected.clear()
	for id: Variant in ids:
		if tokens.has(str(id)) and (not can_drag.is_valid() or can_drag.call(str(id))):
			selected[str(id)] = true
			(tokens[str(id)].get_node("Marks") as TokenMarks).selected = true
	selection_changed.emit()


## Marks the active token (orange ring); the selection stays as it is.
func set_active(id: String) -> void:
	if tokens.has(active):
		(tokens[active].get_node("Marks") as TokenMarks).active = false
	active = id
	if tokens.has(id):
		(tokens[id].get_node("Marks") as TokenMarks).active = true


## The selected tokens that are still on the map.
func selection() -> Array:
	return selected.keys().filter(func(id: String) -> bool: return tokens.has(id))


## Steps every selected token one cell (or turns them): front ones first, so a group
## moving together doesn't block itself.
func step_selection(dir: Vector2i, turn_only := false) -> void:
	var ids := selection()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return Vector2(token_cell(a)).dot(Vector2(dir)) > Vector2(token_cell(b)).dot(Vector2(dir)))
	for id: String in ids:
		step_requested.emit(id, dir, turn_only)


func _key_dir(key: Key) -> Vector2i:
	match key:
		KEY_W, KEY_UP:
			return Vector2i(0, -1)
		KEY_S, KEY_DOWN:
			return Vector2i(0, 1)
		KEY_A, KEY_LEFT:
			return Vector2i(-1, 0)
		KEY_D, KEY_RIGHT:
			return Vector2i(1, 0)
	return Vector2i.ZERO


## The direction of every movement key held right now (for held-down repeats).
func _held_dir() -> Vector2i:
	var d := Vector2i.ZERO
	for key: Key in [KEY_W, KEY_UP, KEY_S, KEY_DOWN, KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT]:
		if Input.is_physical_key_pressed(key) or Input.is_key_pressed(key):
			d += _key_dir(key)
	return d.clamp(Vector2i(-1, -1), Vector2i(1, 1))


## A movement key: collected for a moment so two keys together make a diagonal.
func key_step(key: Key, turn_only: bool, echo := false) -> bool:
	var d := _key_dir(key)
	if d == Vector2i.ZERO or selection().is_empty():
		return false
	if echo:
		var held := _held_dir()
		step_selection(held if held != Vector2i.ZERO else d, turn_only)
		return true
	_pending = (_pending + d).clamp(Vector2i(-1, -1), Vector2i(1, 1))
	_pending_turn = turn_only
	if _combine == null or not _combine.is_inside_tree():
		_send_pending()
	elif _combine.is_stopped():
		_combine.start()
	return true


func _send_pending() -> void:
	var d := _pending
	_pending = Vector2i.ZERO
	if d != Vector2i.ZERO:
		step_selection(d, _pending_turn)


func _draw_box() -> void:
	if _boxing:
		var r := Rect2(_box_from, get_global_mouse_position() - _box_from).abs()
		_box.draw_rect(r, Color(1.0, 0.86, 0.35, 0.15))
		_box.draw_rect(r, Color(1.0, 0.86, 0.35, 0.9), false, 2.0)


## Puts a token on a cell (its top-left cell for big creatures), gliding if `animate`.
func set_token_cell(id: String, at: Vector2i, animate := true) -> void:
	var token: Sprite2D = tokens.get(id)
	if token == null:
		return
	var from: Vector2i = token.get_meta("cell", at)
	token.set_meta("cell", at)
	var target := cell_center(at, token.get_meta("cells"))
	if not animate or not is_inside_tree():
		token.position = target
		return
	var steps := maxf(1.0, Vector2(at - from).length())
	var tween := token.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(token, "position", target, MOVE_SECONDS_PER_CELL * steps)


func token_cell(id: String) -> Vector2i:
	return tokens[id].get_meta("cell") if tokens.has(id) else Vector2i(-1, -1)


## Where a token of `cells` squares sits when its top-left cell is `at`.
func cell_center(at: Vector2i, cells: float) -> Vector2:
	return offset + Vector2(at) * cell + Vector2.ONE * cell * maxf(cells, 1.0) * 0.5


func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - offset) / cell).floor())


static var _placeholders := {}


## A round token for creatures without a picture, coloured by kind (pcs, npcs, monsters).
static func placeholder(kind: String) -> Texture2D:
	if not _placeholders.has(kind):
		var color: Color = {"characters": Color("#2e6e60")}.get(kind, Color("#8f3b3b"))
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length()
				if d <= 31.0:
					img.set_pixel(x, y, Color(0.95, 0.9, 0.8) if d > 26.0 else color)
		_placeholders[kind] = ImageTexture.create_from_image(img)
	return _placeholders[kind]


## The cell under a point on the screen (drops from the UI, TASK-34).
func cell_at_screen(pos: Vector2) -> Vector2i:
	return cell_at(get_canvas_transform().affine_inverse() * pos)


## True if a token of `id` fits at `at`: inside the map and not overlapping another
## token (tiny creatures may share).
func can_place(id: String, at: Vector2i) -> bool:
	if not tokens.has(id):
		return false
	var size := maxi(1, int(tokens[id].get_meta("cells")))
	if at.x < 0 or at.y < 0 or at.x + size > grid_size.x or at.y + size > grid_size.y:
		return false
	var mine := Rect2i(at, Vector2i(size, size))
	for other: String in tokens:
		if other == id or float(tokens[other].get_meta("cells")) < 1.0:
			continue
		var s := int(tokens[other].get_meta("cells"))
		if mine.intersects(Rect2i(tokens[other].get_meta("cell"), Vector2i(s, s))):
			return false
	return true


## Where a dragged group lands (Nico, 2026-11-01): the dragged token on `target`, the other
## selected ones on the free cells closest to it (nearest ones first). Cells of the other
## tokens count as taken, also those of the group (so the moves work in any order), except
## a token's own. Returns id -> cell (tokens that found no place are left out).
func plan_group_move(lead: String, others: Array, target: Vector2i) -> Dictionary:
	var movers: Array = [lead]
	var rest := others.filter(func(id: Variant) -> bool: return tokens.has(str(id)) and str(id) != lead)
	var from := token_cell(lead)
	rest.sort_custom(func(a: String, b: String) -> bool:
		return Vector2(token_cell(a) - from).length_squared() < Vector2(token_cell(b) - from).length_squared())
	movers.append_array(rest)
	var claimed: Array[Rect2i] = []
	var out := {}
	for id: String in movers:
		if not tokens.has(id):
			continue
		var size := maxi(1, int(tokens[id].get_meta("cells")))
		var cell := _free_cell_near(id, target, size, claimed)
		if cell.x < 0:
			continue
		out[id] = cell
		claimed.append(Rect2i(cell, Vector2i(size, size)))
	return out


func _free_cell_near(id: String, target: Vector2i, size: int, claimed: Array[Rect2i]) -> Vector2i:
	var reach := maxi(grid_size.x, grid_size.y)
	for r in reach + 1:
		var ring: Array[Vector2i] = []
		for y in range(target.y - r, target.y + r + 1):
			for x in range(target.x - r, target.x + r + 1):
				if maxi(absi(x - target.x), absi(y - target.y)) == r:
					ring.append(Vector2i(x, y))
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a - target).length_squared() < Vector2(b - target).length_squared())
		for at in ring:
			if _fits(id, at, size, claimed):
				return at
	return Vector2i(-1, -1)


func _fits(id: String, at: Vector2i, size: int, claimed: Array[Rect2i]) -> bool:
	if at.x < 0 or at.y < 0 or at.x + size > grid_size.x or at.y + size > grid_size.y:
		return false
	var mine := Rect2i(at, Vector2i(size, size))
	for r in claimed:
		if mine.intersects(r):
			return false
	for other: String in tokens:
		if other == id or float(tokens[other].get_meta("cells")) < 1.0:
			continue
		var s := int(tokens[other].get_meta("cells"))
		if mine.intersects(Rect2i(tokens[other].get_meta("cell"), Vector2i(s, s))):
			return false
	return true


var info_visible := true  ## the help line at the top left (off at the app's calm table)


func set_info(text: String) -> void:
	if _info:
		_info.text = text
		_info.visible = info_visible


func _draw() -> void:
	if map_size == Vector2.ZERO:
		return
	var x := fposmod(offset.x, cell)
	while x <= map_size.x:
		draw_line(Vector2(x, 0), Vector2(x, map_size.y), grid_color, 1.0)
		x += cell
	var y := fposmod(offset.y, cell)
	while y <= map_size.y:
		draw_line(Vector2(0, y), Vector2(map_size.x, y), grid_color, 1.0)
		y += cell


func _token_under(at: Vector2) -> Sprite2D:
	var best: Sprite2D = null
	for token: Sprite2D in tokens.values():
		if token.get_rect().has_point(token.to_local(at)):
			best = token  # later ones are drawn on top
	return best


## Movement keys are taken before the UI sees them (Nico, 2026-11-01: the arrow keys only
## worked sometimes, a focused button used them to move its focus), unless something is
## being typed.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or _typing():
		return
	if key_step(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode, k.shift_pressed, k.echo):
		get_viewport().set_input_as_handled()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom = (_camera.zoom * 1.1).clampf(0.2, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera.zoom = (_camera.zoom / 1.1).clampf(0.2, 4.0)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var at := get_canvas_transform().affine_inverse() * (event as InputEventMouseButton).position
			if event.pressed:
				get_viewport().gui_release_focus()  # the map has the keys now
				_pressed = _token_under(at)
				_press_at = event.position
				if _pressed == null:
					_boxing = true
					_box_from = at
				_dragging = _pressed
				if _dragging and can_drag.is_valid() and not can_drag.call(str(_dragging.get_meta("entity"))):
					_dragging = null
				if _dragging:
					_drag_from = _dragging.position
					_dragging.z_index = 10
					_drag_group.clear()
					var lead := str(_dragging.get_meta("entity"))
					if selected.has(lead):  # the whole selection comes along
						for other: String in selection():
							if other != lead:
								_drag_group[other] = tokens[other].position
								tokens[other].z_index = 9
			elif _dragging:
				var id: String = _dragging.get_meta("entity")
				var cells: float = _dragging.get_meta("cells")
				# The top-left cell under the dragged token's top-left corner.
				var corner := _dragging.position - Vector2.ONE * cell * maxf(cells, 1.0) * 0.5 + Vector2.ONE * cell * 0.5
				var target := cell_at(corner)
				_dragging.z_index = 0
				_dragging.position = _drag_from  # snaps back until the move is confirmed
				_dragging = null
				var group: Array = _drag_group.keys()
				for other: String in group:
					if tokens.has(other):
						tokens[other].position = _drag_group[other]
						tokens[other].z_index = 0
				_drag_group.clear()
				if group.is_empty():
					if target != token_cell(id):
						move_requested.emit(id, target)
				else:
					var plan := plan_group_move(id, group, target)
					for mover: String in plan:
						if plan[mover] != token_cell(mover):
							move_requested.emit(mover, plan[mover])
			if not event.pressed:
				var clicked := _pressed
				_pressed = null
				var add: bool = (event as InputEventMouseButton).shift_pressed or (event as InputEventMouseButton).ctrl_pressed
				if _boxing:
					_boxing = false
					_box.queue_redraw()
					var r := Rect2(_box_from, at - _box_from).abs()
					if event.position.distance_to(_press_at) < 6.0:
						if not add:
							select([])  # a click on the empty map
					else:
						select(tokens.keys().filter(func(id: String) -> bool: return r.has_point(tokens[id].position)), add)
				elif clicked != null and is_instance_valid(clicked):
					var cid := str(clicked.get_meta("entity"))
					if event.position.distance_to(_press_at) < 6.0:
						select([cid], add)
						token_clicked.emit(cid)
					elif not selected.has(cid):
						select([cid], add)
	elif event is InputEventMouseMotion:
		if _panning:
			_camera.position -= event.relative / _camera.zoom
		if _dragging:
			_dragging.position += event.relative / _camera.zoom
			for other: String in _drag_group:
				if tokens.has(other):
					tokens[other].position += event.relative / _camera.zoom
		elif _boxing:
			_box.queue_redraw()
		else:
			_hover(get_global_mouse_position())


func _hover(at: Vector2) -> void:
	var token := _token_under(at)
	if token:
		var info: Dictionary = token.get_meta("info", {})
		var parts := PackedStringArray([str(info.get("name", "?"))])
		for key: String in ["hp", "ac"]:
			if info.has(key):
				parts.append("%s %s" % [key.to_upper(), info[key]])
		parts.append("(%s)" % info.get("size", "medium"))
		if str(info.get("owner", "")) != "":
			parts.append("· %s" % info.owner)
		set_info("  ".join(parts))
