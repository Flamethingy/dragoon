class_name TokenGrid
extends Node2D
## A map entity (markdown) -> its image with a grid overlay, and the entity files it
## lists -> tokens on the grid at their creature size (TASK-3 spike, used by the TASK-5
## network spike). Tokens are keyed by entity id and placed by cell; moves glide.
## Mouse wheel zooms, right/middle drag pans, hovering a token shows its name and HP.

## A token was dropped on a cell (left drag). Whoever owns the state decides.
signal move_requested(entity: String, cell: Vector2i)

## Tokens per side for each creature size (tiny shares a square, drawn half size).
const SIZE_CELLS := {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 3.0, "gargantuan": 4.0}
const MOVE_SECONDS_PER_CELL := 0.12

## Campaign folder; entity ids and image paths in the files are relative to it.
@export_dir var campaign_dir := "res://examples/campaign"
## Map entity id (path without .md).
@export var map_id := "maps/forest-road"
@export var grid_color := Color(0, 0, 0, 0.35)
## Load the map in _ready (off for tests that call load_map themselves).
@export var auto_load := true

var cell := 70.0
var offset := Vector2.ZERO
var map_size := Vector2.ZERO
var grid_size := Vector2i.ZERO  ## map size in cells
var entities := {}  ## entity id -> {"frontmatter", "body"}
var tokens := {}  ## entity id -> Sprite2D (meta: cell Vector2i, cells float)

var _camera: Camera2D
var _info: Label
var _panning := false
var _dragging: Sprite2D
var _drag_from := Vector2.ZERO


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
	if auto_load:
		load_map(map_id)


## Shows a map entity and its tokens. Returns false (with an error) if it can't.
func load_map(id: String) -> bool:
	map_id = id
	var map := _entity(id)
	if map.is_empty():
		return false
	var fm: Dictionary = map.frontmatter
	var texture := _texture(str(fm.get("image", "")))
	if texture == null:
		return false
	var grid: Dictionary = fm.get("grid", {}) if fm.get("grid") is Dictionary else {}
	cell = float(grid.get("size", 70))
	var off: Variant = grid.get("offset", [0, 0])
	offset = Vector2(float(off[0]), float(off[1])) if off is Array and off.size() == 2 else Vector2.ZERO

	var image := Sprite2D.new()
	image.texture = texture
	image.centered = false
	image.z_index = -1  # the grid (_draw) goes on top of it
	add_child(image)
	map_size = texture.get_size()
	grid_size = Vector2i(floori((map_size.x - offset.x) / cell), floori((map_size.y - offset.y) / cell))
	queue_redraw()

	for t: Variant in fm.get("tokens", []):
		if t is Dictionary:
			var at: Variant = t.get("at", [0, 0])
			add_token(str(t.get("entity", "")), Vector2i(int(at[0]), int(at[1])) if at is Array and at.size() == 2 else Vector2i.ZERO)
	if _camera:
		_camera.position = map_size * 0.5
	set_info("%s: %d tokens (left drag: move, wheel: zoom, right drag: pan)" % [fm.get("name", id), tokens.size()])
	return true


## The map's own token list: entity id -> start cell.
func start_cells() -> Dictionary:
	var out := {}
	for id: String in tokens:
		out[id] = tokens[id].get_meta("start")
	return out


func add_token(id: String, at: Vector2i) -> void:
	var entity := _entity(id)
	if entity.is_empty():
		return
	var fm: Dictionary = entity.frontmatter
	var texture := _texture(str(fm.get("token", "")))
	if texture == null:
		return
	var cells: float = SIZE_CELLS.get(str(fm.get("size", "medium")).to_lower(), 1.0)
	var token := Sprite2D.new()
	token.texture = texture
	token.scale = Vector2.ONE * cell * cells / maxf(texture.get_width(), texture.get_height())
	token.set_meta("entity", id)
	token.set_meta("cells", cells)
	token.set_meta("start", at)
	tokens[id] = token
	add_child(token)
	set_token_cell(id, at, false)


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


func set_info(text: String) -> void:
	if _info:
		_info.text = text


## Loads (and caches) an entity file of the campaign.
func _entity(id: String) -> Dictionary:
	if entities.has(id):
		return entities[id]
	var path := campaign_dir.path_join(id + ".md")
	var data := Frontmatter.load_file(path)
	if data.is_empty():
		return {}
	entities[id] = data
	return data


## An image of the campaign folder, loaded at runtime (campaign files aren't imported).
func _texture(rel: String) -> Texture2D:
	var path := campaign_dir.path_join(rel)
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Image not found: %s" % path)
		return null
	return ImageTexture.create_from_image(image)


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom = (_camera.zoom * 1.1).clampf(0.2, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera.zoom = (_camera.zoom / 1.1).clampf(0.2, 4.0)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var at := get_global_mouse_position()
			if event.pressed:
				_dragging = _token_under(at)
				if _dragging:
					_drag_from = _dragging.position
					_dragging.z_index = 10
			elif _dragging:
				var id: String = _dragging.get_meta("entity")
				var cells: float = _dragging.get_meta("cells")
				# The top-left cell under the dragged token's top-left corner.
				var corner := _dragging.position - Vector2.ONE * cell * maxf(cells, 1.0) * 0.5 + Vector2.ONE * cell * 0.5
				var target := cell_at(corner)
				_dragging.z_index = 0
				_dragging.position = _drag_from  # snaps back until the move is confirmed
				_dragging = null
				if target != token_cell(id):
					move_requested.emit(id, target)
	elif event is InputEventMouseMotion:
		if _panning:
			_camera.position -= event.relative / _camera.zoom
		if _dragging:
			_dragging.position += event.relative / _camera.zoom
		else:
			_hover(get_global_mouse_position())


func _hover(at: Vector2) -> void:
	var token := _token_under(at)
	if token:
		var fm: Dictionary = entities[token.get_meta("entity")].frontmatter
		set_info("%s  HP %s  AC %s  (%s)" % [fm.get("name", "?"), fm.get("hp", "?"), fm.get("ac", "?"), fm.get("size", "?")])
