extends Node2D
## TASK-3 spike: a map entity (markdown) -> its image with a grid overlay, and the entity
## files it lists -> tokens on the grid at their creature size.
## Mouse wheel zooms, right/middle drag pans, hovering a token shows its name and HP.

## Tokens per side for each creature size (tiny shares a square, drawn half size).
const SIZE_CELLS := {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 3.0, "gargantuan": 4.0}

## Campaign folder; entity ids and image paths in the files are relative to it.
@export_dir var campaign_dir := "res://examples/campaign"
## Map entity id (path without .md).
@export var map_id := "maps/forest-road"
@export var grid_color := Color(0, 0, 0, 0.35)

var cell := 70.0
var offset := Vector2.ZERO
var map_size := Vector2.ZERO
var entities := {}  ## entity id -> {"frontmatter", "body"}

var _camera: Camera2D
var _info: Label
var _panning := false


func _ready() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	var ui := CanvasLayer.new()
	add_child(ui)
	_info = Label.new()
	_info.position = Vector2(12, 8)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	ui.add_child(_info)
	load_map(map_id)


## Shows a map entity and its tokens. Returns false (with an error) if it can't.
func load_map(id: String) -> bool:
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
	add_child(image)
	map_size = texture.get_size()
	queue_redraw()  # the grid is drawn by _draw, on top of the image via z_index below
	image.z_index = -1

	for t: Variant in fm.get("tokens", []):
		if t is Dictionary:
			_add_token(str(t.get("entity", "")), t.get("at", [0, 0]))
	_camera.position = map_size * 0.5
	_info.text = "%s: %d tokens (wheel: zoom, right drag: pan)" % [fm.get("name", id), get_tree().get_nodes_in_group("tokens").size()]
	return true


func _add_token(id: String, at: Variant) -> void:
	var entity := _entity(id)
	if entity.is_empty():
		return
	var fm: Dictionary = entity.frontmatter
	var texture := _texture(str(fm.get("token", "")))
	if texture == null:
		return
	var cells: float = SIZE_CELLS.get(str(fm.get("size", "medium")).to_lower(), 1.0)
	var side := cell * cells
	var token := Sprite2D.new()
	token.texture = texture
	token.scale = Vector2.ONE * side / maxf(texture.get_width(), texture.get_height())
	var c := Vector2(float(at[0]), float(at[1])) if at is Array and at.size() == 2 else Vector2.ZERO
	# Top-left cell of the token; it covers maxf(cells, 1) squares per side.
	token.position = offset + c * cell + Vector2.ONE * cell * maxf(cells, 1.0) * 0.5
	token.set_meta("entity", id)
	token.add_to_group("tokens")
	add_child(token)


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom = (_camera.zoom * 1.1).clampf(0.2, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera.zoom = (_camera.zoom / 1.1).clampf(0.2, 4.0)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = event.pressed
	elif event is InputEventMouseMotion:
		if _panning:
			_camera.position -= event.relative / _camera.zoom
		_hover(get_global_mouse_position())


func _hover(at: Vector2) -> void:
	for token: Sprite2D in get_tree().get_nodes_in_group("tokens"):
		if token.get_rect().has_point(token.to_local(at)):
			var fm: Dictionary = entities[token.get_meta("entity")].frontmatter
			_info.text = "%s  HP %s  AC %s  (%s)" % [fm.get("name", "?"), fm.get("hp", "?"), fm.get("ac", "?"), fm.get("size", "?")]
			return
