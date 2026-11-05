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
signal token_double_clicked(entity: String)  ## TASK-110: opens the first sheet page
signal group_requested(ids: Array)  ## TASK-115: G with two tokens or more selected
signal member_out_requested(group: String, member: String, cell: Vector2i)  ## dragged out of a group's ring
signal token_menu(entity: String)  ## right click on a token without panning (TASK-56)
## WASD / arrow keys with tokens selected (TASK-42): step one cell in `dir` (8 directions),
## or with Shift only turn that way. Whoever owns the state decides.
signal step_requested(entity: String, dir: Vector2i, turn_only: bool)
signal selection_changed
## A click on the empty map: everything deselected, the active token too (Nico, 2026-11-01).
signal cleared

## The 8 directions a token can look (TASK-42).
const FACINGS := {"n": Vector2i(0, -1), "ne": Vector2i(1, -1), "e": Vector2i(1, 0), "se": Vector2i(1, 1),
	"s": Vector2i(0, 1), "sw": Vector2i(-1, 1), "w": Vector2i(-1, 0), "nw": Vector2i(-1, -1)}
## Keys pressed within this time count as one diagonal step (W and D together).
const COMBINE_SECONDS := 0.07

## Tokens per side for each creature size (tiny shares a square, drawn half size).
const SIZE_CELLS := {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 3.0, "gargantuan": 4.0}
const MOVE_SECONDS_PER_CELL := 0.12
const METRES_PER_CELL := 1.5  ## one square (5e: 5 ft); the trail of a planned move counts them

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
var _resume := ""  ## the token whose planned ghost was picked up again (its trail goes on)
var _drag_from := Vector2.ZERO
var _pressed: Sprite2D  ## the token under the mouse when the left button went down
var _press_at := Vector2.ZERO  ## screen position of that press
var selected := {}  ## entity id -> true (TASK-42)
var active := ""  ## the active token (TASK-44, orange ring); "" = none
var _drag_group := {}  ## the other selected tokens dragged along: id -> true
var _drag_started := false  ## the mouse moved since the press: the ghosts are out
var plans: MovePlans  ## planned moves: ghosts, dotted trails, Space to go (TASK-45)
var areas: AreaLayer  ## area templates and the ruler (TASK-67)
var map_layer: MapLayer  ## walls, doors, light, terrain and fog (TASK-73)
## id -> its walking speed in metres (the move trail turns yellow at it, orange at double)
var speed: Callable
## The squares of other tokens that count as difficult for `id` (TASK-79): id -> {cell: true}.
var crowd: Callable
var past := {}  ## id -> Sprite2D of the moment looked back at (TASK-83); the live tokens are hidden then
var locked := false  ## no moves, steps, selection or token menus (looking back, TASK-83)
var _past_layer: Node2D
var _past_drag: Sprite2D  ## a past token the DM drags (TASK-85)
var _seg := {}  ## id -> its way to the next moment while the cursor is between two (real time)
var _glide := {}  ## id -> trail (cells) the next confirmed move of it glides along
var _right_at := Vector2.ZERO  ## where the right button went down (a click opens the token's menu)
var _box_from := Vector2.ZERO  ## map position where a selection box started
var _boxing := false
var _box: Node2D
var _pending := Vector2i.ZERO  ## keys pressed together, collected for COMBINE_SECONDS
var _pending_turn := false
var _combine: Timer
var ring: GroupStack.Ring  ## a group's members around it, opened by a double-click (TASK-115)
var _fanned: Sprite2D  ## the group token whose members fan out under the mouse


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
	plans = MovePlans.new()
	plans.name = "Plans"
	plans.grid = self
	add_child(plans)
	areas = AreaLayer.new()
	areas.grid = self
	add_child(areas)
	map_layer = MapLayer.new()
	map_layer.grid = self
	add_child(map_layer)
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
	map_id = ""  # nothing shown: the next table view builds the map again
	set_meta("image", "")
	queue_redraw()


## The map picture is really there (Nico 2026-11-02: it sometimes went missing while the grid
## and the tokens stayed).
func has_picture() -> bool:
	return _image != null and is_instance_valid(_image) and not _image.is_queued_for_deletion() 		and _image.is_inside_tree() and _image.visible and _image.texture != null 		and _image.texture.get_width() > 0


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
	var token := _token_sprite(info, texture)
	token.set_meta("start", at)
	token.visible = _past_layer == null  # looking back: it shows again at now
	tokens[id] = token
	var marks := token.get_node("Marks") as TokenMarks
	marks.selected = selected.has(id)
	marks.active = id == active
	add_child(token)
	set_token_cell(id, at, false)
	set_token_facing(id, facing)


## A group token's members (TASK-115): [{id, name, texture}], the leader first.
func set_group_faces(id: String, faces: Array) -> void:
	var token: Sprite2D = tokens.get(id)
	if token == null:
		return
	var stack := token.get_node_or_null("Stack") as GroupStack
	if stack == null:
		stack = GroupStack.new()
		stack.name = "Stack"
		stack.scale = Vector2.ONE / token.scale
		token.add_child(stack)
	stack.set_faces(faces, cell * float(token.get_meta("cells", 1.0)) * 0.5)
	if ring != null and ring.group == id:
		ring.open(id, faces, cell * float(token.get_meta("cells", 1.0)))


## Opens the ring of a group token's members (a double-click on it).
func open_ring(id: String) -> void:
	var token: Sprite2D = tokens.get(id)
	var stack := token.get_node_or_null("Stack") as GroupStack if token != null else null
	if stack == null:
		return
	if ring == null:
		ring = GroupStack.Ring.new()
		ring.name = "GroupRing"
		ring.z_index = 5
		add_child(ring)
	ring.position = token.position
	ring.open(id, stack.faces, cell * float(token.get_meta("cells", 1.0)))


func _token_sprite(info: Dictionary, texture: Texture2D) -> Sprite2D:
	var cells: float = SIZE_CELLS.get(str(info.get("size", "medium")).to_lower(), 1.0)
	var token := Sprite2D.new()
	token.texture = texture
	token.scale = Vector2.ONE * cell * cells / maxf(texture.get_width(), texture.get_height())
	token.set_meta("entity", str(info.get("id", "")))
	token.set_meta("cells", cells)
	token.set_meta("info", info)
	var marks := TokenMarks.new()
	marks.name = "Marks"
	marks.scale = Vector2.ONE / token.scale
	marks.radius = cell * cells * 0.5
	token.add_child(marks)
	return token


# --- Looking back (TASK-83) -------------------------------------------------------------------

## Shows the tokens of a past moment over the hidden live ones: `list` [{info (token view with
## its cell), texture}], `paths` {id: [Vector2i...]}: the way each token went from the moment
## shown before (it walks it, also backwards). The live tokens go on underneath unseen.
## `progress` >= 0: the cursor is between two moments; `paths` lead to the next one and each
## token stands that far along its way (no animation: the cursor drives it).
func show_past(list: Array, paths: Dictionary, progress := -1.0) -> void:
	if _past_layer == null:
		_past_layer = Node2D.new()
		_past_layer.name = "Past"
		add_child(_past_layer)
		for t: Sprite2D in tokens.values():
			t.visible = false
		if plans != null:
			plans.cancel()
	var keep := {}
	for p: Dictionary in list:
		var info: Dictionary = p.info
		var id := str(info.id)
		var at: Vector2i = info.cell
		keep[id] = true
		var s: Sprite2D = past.get(id)
		if s != null and s.texture != p.texture:
			s.queue_free()
			s = null
		if s == null:
			s = _token_sprite(info, p.texture)
			past[id] = s
			_past_layer.add_child(s)
			s.position = cell_center(at, s.get_meta("cells"))
		elif progress < 0.0:
			s.set_meta("info", info)
			_walk(s, paths.get(id, []), at)
		else:
			s.set_meta("info", info)
		s.set_meta("cell", at)
		if str(info.get("facing", "")) != "":
			_face(s, str(info.facing))
		_mark_conditions(s, id, info.get("conditions", []), int(info.get("exhaustion", 0)))
	for id: String in past.keys():
		if not keep.has(id):
			past[id].queue_free()
			past.erase(id)
	_seg = paths if progress >= 0.0 else {}
	if progress >= 0.0:
		past_progress(progress)


## The cursor moved between the same two moments: every token stands `f` along its way.
func past_progress(f: float) -> void:
	for id: String in past:
		var s: Sprite2D = past[id]
		var running: Tween = s.get_meta("tween") if s.has_meta("tween") else null
		if running != null and running.is_valid():
			running.kill()
		var path: Array = _seg.get(id, [])
		var cells: float = s.get_meta("cells")
		if path.size() < 2:
			s.position = cell_center(s.get_meta("cell"), cells)
			continue
		var x := clampf(f, 0.0, 1.0) * (path.size() - 1)
		var i := mini(floori(x), path.size() - 2)
		s.position = cell_center(path[i], cells).lerp(cell_center(path[i + 1], cells), x - i)
		var face := facing_of(Vector2i(path[i + 1]) - Vector2i(path[i]))
		if face != "":
			_face(s, face)


## Back to now: the past tokens go, the live ones show.
func end_past() -> void:
	if _past_layer == null:
		return
	_past_layer.queue_free()
	_past_layer = null
	past.clear()
	_seg = {}
	for t: Sprite2D in tokens.values():
		t.visible = true


func is_past() -> bool:
	return _past_layer != null


## Looking back, not locked (the DM): a past token is dragged straight to a square; the move is
## asked for (move_requested) and the table puts it into the past.
func _past_press(event: InputEventMouseButton) -> void:
	if locked:
		return
	var at := get_canvas_transform().affine_inverse() * event.position
	if event.pressed:
		_past_drag = _token_under(at)
		return
	if _past_drag == null:
		return
	var s := _past_drag
	_past_drag = null
	var cells: float = s.get_meta("cells")
	var target := cell_at(s.position - Vector2.ONE * cell * (maxf(cells, 1.0) - 1.0) * 0.5)
	var was: Vector2i = s.get_meta("cell")
	s.position = cell_center(was, cells)
	if target != was:
		move_requested.emit(str(s.get_meta("entity")), target)


## A past token walks `path` (cells, square by square) to `at`; at most ~1.5 s however far.
func _walk(s: Sprite2D, path: Array, at: Vector2i) -> void:
	var running: Tween = s.get_meta("tween") if s.has_meta("tween") else null
	if running != null and running.is_valid():
		running.kill()
	var cells: float = s.get_meta("cells")
	var points: Array = path.slice(1) if path.size() >= 2 and path.back() == at else [at]
	if points.size() == 1 and cell_center(at, cells).is_equal_approx(s.position):
		return
	if not is_inside_tree():
		s.position = cell_center(at, cells)
		return
	var step := minf(MOVE_SECONDS_PER_CELL, 1.5 / points.size())
	var tween := s.create_tween().set_trans(Tween.TRANS_LINEAR)
	s.set_meta("tween", tween)
	var prev: Vector2i = path[0] if path.size() >= 2 and path.back() == at else Vector2i(-9999, -9999)
	for c: Vector2i in points:
		if prev != Vector2i(-9999, -9999):
			var face := facing_of(c - prev)
			if face != "":
				tween.tween_callback(_face.bind(s, face))
		tween.tween_property(s, "position", cell_center(c, cells), step)
		prev = c


## Marks a token as an attack's target (TASK-54: a red ring).
func set_targeted(id: String, on: bool) -> void:
	if tokens.has(id):
		var marks := tokens[id].get_node_or_null("Marks") as TokenMarks
		if marks != null:
			marks.targeted = on


## The condition marks on a token (TASK-56): a small coloured disc with its short name each.
func set_token_conditions(id: String, conditions: Array, exhaustion := 0) -> void:
	if tokens.has(id):
		_mark_conditions(tokens[id], id, conditions, exhaustion)


func _mark_conditions(token: Sprite2D, id: String, conditions: Array, exhaustion: int) -> void:
	var marks := token.get_node_or_null("Marks") as TokenMarks
	if marks == null:
		return
	var list := []
	for c: Variant in conditions:
		var cond := Rules.condition(str(c))
		if cond.is_empty():
			list.append({"abbr": str(c).left(3).capitalize(), "color": Color("#666666"), "name": str(c)})
		else:
			var abbr := str(cond.abbr) + (str(exhaustion) if str(c) == "exhaustion" and exhaustion > 0 else "")
			list.append({"abbr": abbr, "color": Color(str(cond.color)), "name": str(cond.name)})
	marks.conditions = list
	# TASK-57: a dead (or knocked out) creature is greyed
	var down := "dead" in conditions or ("unconscious" in conditions and not id.begins_with("characters/"))
	token.self_modulate = Color(0.45, 0.45, 0.45, 0.8) if down else Color.WHITE


## Turns a token (n, ne, e ... nw): the triangle at its edge, and the picture mirrored when
## it looks to the other side than the picture faces (token_style.faces).
func set_token_facing(id: String, facing: String) -> void:
	var token: Sprite2D = tokens.get(id)
	if token != null:
		_face(token, facing)


func _face(token: Sprite2D, facing: String) -> void:
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


## The selected tokens that are still on the map, the active one included (Nico,
## 2026-11-01: the orange ring counts as selected, so WASD and drags move it too).
func selection() -> Array:
	var out := picked()
	if tokens.has(active) and active not in out and (not can_drag.is_valid() or can_drag.call(active)):
		out.append(active)
	return out


## Only the tokens selected by click or box (white ring), not the active one.
func picked() -> Array:
	return selected.keys().filter(func(id: String) -> bool: return tokens.has(id))


## Steps every selected token one cell (or turns them): front ones first, so a group
## moving together doesn't block itself.
func step_selection(dir: Vector2i, turn_only := false) -> void:
	var ids := selection()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return Vector2(token_cell(a)).dot(Vector2(dir)) > Vector2(token_cell(b)).dot(Vector2(dir)))
	for id: String in ids:
		plans.cancel(id)  # a step replaces a planned move
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
	if locked or d == Vector2i.ZERO or selection().is_empty():
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
	var running: Tween = token.get_meta("tween") if token.has_meta("tween") else null
	if running != null and running.is_valid() and running.is_running():
		if from == at:
			return  # already on its way there (a planned move's glide)
		running.kill()
	if not animate or not is_inside_tree():
		token.position = target
		return
	var trail: Array = _glide.get(id, [])
	_glide.erase(id)
	var tween := token.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	token.set_meta("tween", tween)
	if trail.size() >= 2 and trail[0] == from and trail[trail.size() - 1] == at:
		# a planned move: along its trail, square by square; the dots vanish behind it
		var cells: float = token.get_meta("cells")
		tween.set_trans(Tween.TRANS_LINEAR)
		for i in range(1, trail.size()):
			var face := facing_of(Vector2i(trail[i]) - Vector2i(trail[i - 1]))  # TASK-76: it turns along each step
			if face != "":
				tween.tween_callback(set_token_facing.bind(id, face))
			tween.tween_property(token, "position", cell_center(trail[i], cells), MOVE_SECONDS_PER_CELL)
			tween.tween_callback(plans.advance.bind(id, i))
		return
	var steps := maxf(1.0, Vector2(at - from).length())
	tween.tween_property(token, "position", target, MOVE_SECONDS_PER_CELL * steps)


## A free drag let go (TASK-114, Nico 2026-11-05): the ghosts go and each token is asked to
## move straight to its cell (no trail: the log keeps a straight line, its cost the straight
## squares).
func move_free(ends: Dictionary) -> void:
	for id: String in ends:
		plans.cancel(id)
		_glide.erase(id)
		if tokens.has(id) and Vector2i(ends[id]) != token_cell(id):
			move_requested.emit(id, Vector2i(ends[id]))


## Esc while dragging (TASK-114): the ghosts go, nothing moves.
func cancel_drag() -> void:
	plans.cancel_drag()
	_dragging = null
	_drag_group.clear()
	_drag_started = false
	_pressed = null


## Space: every planned move goes (the moves are asked for; confirmed ones glide).
func go_planned() -> bool:
	var moves := plans.go()
	for id: String in moves:
		_glide[id] = moves[id].path
		move_requested.emit(id, moves[id].to)
	return not moves.is_empty()


## The trail the next confirmed move of `id` glides along ([] if none): sent with the move.
func trail_of(id: String) -> Array:
	return _glide.get(id, [])


## The next move of `id` glides along `trail` (from the host: everyone sees the same way).
func glide_along(id: String, trail: Array) -> void:
	if trail.size() >= 2:
		_glide[id] = trail


## Difficult squares for a move of `id`: the map's terrain and other creatures' squares.
func difficult_for(id: String) -> Dictionary:
	var out: Dictionary = (map_layer.terrain as Dictionary).duplicate() if map_layer != null else {}
	if crowd.is_valid():
		out.merge(crowd.call(id) as Dictionary)
	return out


## The squares the other tokens cover (`keep`: which ones count; all by default).
func occupied(except: String, keep := Callable()) -> Dictionary:
	var out := {}
	for other: String in tokens:
		if other == except or float(tokens[other].get_meta("cells")) < 1.0 or (keep.is_valid() and not keep.call(other)):
			continue
		var s := int(tokens[other].get_meta("cells"))
		var at: Vector2i = tokens[other].get_meta("cell")
		for y in s:
			for x in s:
				out[at + Vector2i(x, y)] = true
	return out


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
	for token: Sprite2D in (past if _past_layer != null else tokens).values():
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
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code == KEY_G and not k.echo and not locked and _dragging == null and selection().size() >= 2:  # TASK-115
		group_requested.emit(selection())
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE and ring != null and ring.is_open():
		ring.close()
		get_viewport().set_input_as_handled()
	elif _dragging != null and code == KEY_SPACE:  # TASK-114: measure the drag from now on
		if not k.echo and _drag_started:
			plans.start_measure()
		get_viewport().set_input_as_handled()
	elif _dragging != null and code == KEY_ESCAPE:  # the drag is dropped, nothing moves
		cancel_drag()
		get_viewport().set_input_as_handled()
	elif code == KEY_SPACE and not k.echo and plans.has_plans():
		go_planned()
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE and plans.has_plans():
		plans.cancel()
		get_viewport().set_input_as_handled()
	elif key_step(code, k.shift_pressed, k.echo):
		get_viewport().set_input_as_handled()


const WHEELS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]


## TASK-90: the mouse is over a panel or window (any Control that takes the mouse), not the
## free map. Scroll events pass through a list at its end (mouse_force_pass_scroll_events)
## and would reach the map as unhandled input.
func over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


func _unhandled_input(event: InputEvent) -> void:
	if areas != null and areas.handle(event):  # placing an area or measuring (TASK-67)
		get_viewport().set_input_as_handled()
		return
	if map_layer != null and map_layer.handle(event):  # walls, terrain, lights; a door (TASK-73)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		return
	if event is InputEventMouseButton:
		if event.button_index in WHEELS and over_ui():
			return  # TASK-90: scrolling a panel at its end lets the wheel through; the map stays
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom = (_camera.zoom * 1.1).clampf(0.2, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera.zoom = (_camera.zoom / 1.1).clampf(0.2, 4.0)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = event.pressed
			if event.button_index == MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_right_at = event.position
				elif event.position.distance_to(_right_at) < 6.0:
					var t := _token_under(get_canvas_transform().affine_inverse() * (event as InputEventMouseButton).position)
					if t != null and not locked:
						token_menu.emit(str(t.get_meta("entity")))
		elif event.button_index == MOUSE_BUTTON_LEFT and is_past():
			_past_press(event as InputEventMouseButton)
		elif event.button_index == MOUSE_BUTTON_LEFT and not locked and ring != null and ring.is_open() and (ring.dragged != "" or (event.pressed
				and ring.member_at(get_canvas_transform().affine_inverse() * (event as InputEventMouseButton).position) != "")):
			_ring_press(event as InputEventMouseButton)  # TASK-115: a member is taken out of the group
		elif event.button_index == MOUSE_BUTTON_LEFT and not locked:
			var at := get_canvas_transform().affine_inverse() * (event as InputEventMouseButton).position
			if event.pressed and ring != null and ring.is_open():
				ring.close()  # a click beside the ring closes it
			if event.pressed:
				get_viewport().gui_release_focus()  # the map has the keys now
				var ghost := plans.ghost_at(at)  # a planned move's ghost is picked up again
				_resume = ghost if tokens.has(ghost) and (not can_drag.is_valid() or can_drag.call(ghost)) else ""
				_pressed = tokens[_resume] if _resume != "" else _token_under(at)
				_press_at = event.position
				if _pressed != null and (event as InputEventMouseButton).double_click:
					token_double_clicked.emit(str(_pressed.get_meta("entity")))
					if _pressed.has_node("Stack"):  # TASK-115: a group opens its ring
						open_ring(str(_pressed.get_meta("entity")))
						_pressed = null
						return
				if _pressed == null:
					_boxing = true
					_box_from = at
				_dragging = _pressed
				if _dragging and can_drag.is_valid() and not can_drag.call(str(_dragging.get_meta("entity"))):
					_dragging = null
				if _dragging:
					_drag_started = false
					_drag_group.clear()
					var lead := str(_dragging.get_meta("entity"))
					if _resume == "" and lead in selection():  # the whole selection comes along, the active one too
						for other: String in selection():
							if other != lead:
								_drag_group[other] = true
			elif _dragging:
				# Measured (Space while dragging): the real tokens stay, the ghosts stay at the ends
				# as planned moves (Space: go). Free (TASK-114): the tokens move straight there now.
				var id: String = _dragging.get_meta("entity")
				var group: Array = _drag_group.keys()
				_dragging = null
				_drag_group.clear()
				if _drag_started:
					_drag_started = false
					var target := plans.cell_under_ghost(id)
					var ends := plan_group_move(id, group, target) if not group.is_empty() else {id: target}
					var onto := _token_under(at) if (event as InputEventMouseButton).alt_pressed else null
					if onto != null and str(onto.get_meta("entity")) != id and not str(onto.get_meta("entity")) in group:
						for g: String in [id] + group:  # TASK-115: Alt + drop onto a token groups them (it leads)
							plans.cancel(g)
						group_requested.emit([str(onto.get_meta("entity")), id] + group)
					elif plans.is_measuring(id):
						plans.end_drag(id, ends.get(id, target), ends)
					else:
						move_free(ends)
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
							set_active("")  # a click on the empty map: nothing selected or active
							select([])
							cleared.emit()
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
		if ring != null and ring.dragged != "":
			ring.drag_at = get_global_mouse_position()
			ring.queue_redraw()
		elif _past_drag != null:
			_past_drag.position += event.relative / _camera.zoom
		elif _dragging:
			var lead := str(_dragging.get_meta("entity"))
			if not _drag_started:
				_drag_started = true
				if _resume == lead:
					plans.resume_drag(lead)
				else:
					plans.begin_drag([lead] + _drag_group.keys())
			plans.drag_by(lead, event.relative / _camera.zoom)
		elif _boxing:
			_box.queue_redraw()
		else:
			_hover(get_global_mouse_position())


## A press or release on the open ring: the member under the mouse follows it and leaves the
## group where it is let go (on the ring itself: nothing happens).
func _ring_press(event: InputEventMouseButton) -> void:
	var at := get_canvas_transform().affine_inverse() * event.position
	if event.pressed:
		ring.dragged = ring.member_at(at)
		ring.drag_at = at
	else:
		var member := ring.dragged
		ring.dragged = ""
		if ring.member_at(at) == member and at.distance_to(ring.position) < cell * 2.0:
			ring.queue_redraw()
			return
		var gid := ring.group
		ring.close()
		member_out_requested.emit(gid, member, cell_at(at))
	get_viewport().set_input_as_handled()


func _hover(at: Vector2) -> void:
	var token := _token_under(at)
	var fan := token if token != null and token.has_node("Stack") else null
	if fan != _fanned:
		if _fanned != null and is_instance_valid(_fanned):
			(_fanned.get_node("Stack") as GroupStack).fanned = false
		_fanned = fan
		if fan != null:
			(fan.get_node("Stack") as GroupStack).fanned = true
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
