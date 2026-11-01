class_name MapSetup
extends ConfirmationDialog
## Adds a map to the world or lines up an existing map's grid (TASK-34). Drag over one
## square of the picture: its width sets the cell size and its corner the grid offset; the
## numbers can be fine tuned beside it, with the metres per cell. Maps belong to the world
## (maps.json, picture in assets/maps); where tokens stand is up to each timeline.

signal saved(ref: String)

var world_dir := ""
var map := {}  ## the map entry being set up (new: name, kind, grid)
var image_path := ""  ## new map: the picked picture (copied into the world on save)
var texture: Texture2D
var canvas: GridCanvas
var name_edit: LineEdit
var kind_pick: OptionButton
var size_spin: SpinBox
var offset_x: SpinBox
var offset_y: SpinBox
var metres: SpinBox

var _syncing := false


## The picture with its grid; drag a rectangle over one cell.
class GridCanvas extends Control:
	signal cell_dragged(a: Vector2, b: Vector2)  ## in picture pixels

	var texture: Texture2D
	var cell := 70.0
	var offset := Vector2.ZERO
	var _from := Vector2.ZERO
	var _to := Vector2.ZERO
	var _dragging := false

	func _ready() -> void:
		custom_minimum_size = Vector2(640, 480)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		clip_contents = true

	## Picture pixels per screen pixel and where the picture starts (fit into the box).
	func fit() -> Array:
		if texture == null:
			return [1.0, Vector2.ZERO]
		var tsize := texture.get_size()
		var s := minf(size.x / tsize.x, size.y / tsize.y)
		return [s, (size - tsize * s) * 0.5]

	func to_image(p: Vector2) -> Vector2:
		var f := fit()
		return (p - (f[1] as Vector2)) / float(f[0])

	func _draw() -> void:
		if texture == null:
			return
		var f := fit()
		var s: float = f[0]
		var at: Vector2 = f[1]
		var tsize := texture.get_size()
		draw_texture_rect(texture, Rect2(at, tsize * s), false)
		if cell * s >= 3.0:
			var line := Color(1, 1, 1, 0.55)
			var x := fposmod(offset.x, cell)
			while x <= tsize.x:
				draw_line(at + Vector2(x, 0) * s, at + Vector2(x, tsize.y) * s, line)
				x += cell
			var y := fposmod(offset.y, cell)
			while y <= tsize.y:
				draw_line(at + Vector2(0, y) * s, at + Vector2(tsize.x, y) * s, line)
				y += cell
		if _dragging:
			draw_rect(Rect2(_from, _to - _from).abs(), Color(1, 0.8, 0.2), false, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_from = event.position
				_to = event.position
			elif _dragging:
				_dragging = false
				if _from.distance_to(_to) >= 4.0:
					cell_dragged.emit(to_image(_from), to_image(_to))
			queue_redraw()
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_to = event.position
			queue_redraw()
			accept_event()


## The grid from a square dragged over the picture (picture pixels): {size, offset}.
static func grid_from_drag(a: Vector2, b: Vector2) -> Dictionary:
	var r := Rect2(a, b - a).abs()
	var s := snappedf(maxf(maxf(r.size.x, r.size.y), 4.0), 0.5)
	return {"size": s, "offset": Vector2(snappedf(fposmod(r.position.x, s), 0.5), snappedf(fposmod(r.position.y, s), 0.5))}


## Saves a map into the world: copies a new picture into assets/maps, writes maps.json.
## Returns the ref ("maps/<id>"), "" if it could not be written.
static func save_map(world: String, entry: Dictionary, picture := "") -> String:
	var store := EntryStore.open(world)
	var e := entry.duplicate(true)
	var map_name := str(e.get("name", "")).strip_edges()
	if map_name == "":
		map_name = picture.get_file().get_basename().capitalize() if picture != "" else "Map"
	e["name"] = map_name
	if str(e.get("id", "")) == "":
		var eid := EntryStore.slug(map_name)
		var n := 2
		while store.has("maps", eid):
			eid = "%s-%d" % [EntryStore.slug(map_name), n]
			n += 1
		e["id"] = eid
	if picture != "":
		var rel := "assets/maps/%s.%s" % [e.id, picture.get_extension().to_lower()]
		DirAccess.make_dir_recursive_absolute(world.path_join("assets/maps"))
		if DirAccess.copy_absolute(picture, world.path_join(rel)) != OK:
			return ""
		e["image"] = rel
	for key: String in {"description": "", "tags": [], "kind": "local", "tokens": []}:
		if not e.has(key):
			e[key] = {"description": "", "tags": [], "kind": "local", "tokens": []}[key]
	e["draft"] = false
	return "maps/" + str(e.id) if store.save("maps", e) == OK else ""


## A new map from a picture file.
func new_map(world: String, picture: String) -> void:
	world_dir = world
	image_path = picture
	map = {"name": picture.get_file().get_basename().capitalize(), "kind": "local",
		"grid": {"size": 70.0, "offset": [0, 0], "cell_m": 1.5}}
	texture = _load_texture(picture)
	title = "New map"
	_fill()


## Lines up the grid of a map of the world (its entry from maps.json).
func edit_map(world: String, entry: Dictionary) -> void:
	world_dir = world
	image_path = ""
	map = entry.duplicate(true)
	texture = _load_texture(world.path_join(str(entry.get("image", ""))))
	title = "Grid of %s" % entry.get("name", "")
	_fill()


func _ready() -> void:
	ok_button_text = "Save to the world"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	canvas = GridCanvas.new()
	canvas.name = "Canvas"
	row.add_child(canvas)
	canvas.cell_dragged.connect(func(a: Vector2, b: Vector2) -> void: set_grid(grid_from_drag(a, b)))
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(220, 0)
	row.add_child(col)
	var hint := Label.new()
	hint.text = "Drag over one square of the map to set the grid, then fine tune."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = UISkin.V_MUTED
	col.add_child(hint)
	name_edit = _field(col, "Name", LineEdit.new())
	kind_pick = _field(col, "Kind", OptionButton.new())
	kind_pick.add_item("local")
	kind_pick.add_item("world")
	size_spin = _spin(col, "Cell size (px)", 4, 1000, 0.5)
	offset_x = _spin(col, "Offset x (px)", -1000, 1000, 0.5)
	offset_y = _spin(col, "Offset y (px)", -1000, 1000, 0.5)
	metres = _spin(col, "Metres per cell (0: not to scale)", 0, 100000, 0.5)
	for s: SpinBox in [size_spin, offset_x, offset_y]:
		s.value_changed.connect(func(_v: float) -> void: _from_fields())
	confirmed.connect(save)
	_fill()


## Sets the grid ({size, offset}) and shows it.
func set_grid(g: Dictionary) -> void:
	var grid: Dictionary = map.get_or_add("grid", {})
	grid["size"] = float(g.size)
	var o: Vector2 = g.offset
	grid["offset"] = [o.x, o.y]
	_fill()


## Writes the map into the world and tells who listens. Returns the ref ("" on failure).
func save() -> String:
	if name_edit == null:
		return ""
	map["name"] = name_edit.text.strip_edges()
	map["kind"] = kind_pick.get_item_text(kind_pick.selected) if kind_pick.selected >= 0 else "local"
	var grid: Dictionary = map.get_or_add("grid", {})
	grid["size"] = size_spin.value
	grid["offset"] = [offset_x.value, offset_y.value]
	grid["cell_m"] = metres.value
	var ref := save_map(world_dir, map, image_path)
	if ref != "":
		map["id"] = ref.get_file()
		image_path = ""
		saved.emit(ref)
	return ref


func _fill() -> void:
	if canvas == null:
		return
	_syncing = true
	var grid: Dictionary = map.get("grid", {}) if map.get("grid") is Dictionary else {}
	var o: Array = grid.get("offset", [0, 0]) if grid.get("offset") is Array else [0, 0]
	name_edit.text = str(map.get("name", ""))
	kind_pick.select(1 if str(map.get("kind", "local")) == "world" else 0)
	size_spin.value = float(grid.get("size", 70))
	offset_x.value = float(o[0])
	offset_y.value = float(o[1])
	metres.value = float(grid.get("cell_m", 1.5))
	canvas.texture = texture
	canvas.cell = size_spin.value
	canvas.offset = Vector2(offset_x.value, offset_y.value)
	canvas.queue_redraw()
	_syncing = false


func _from_fields() -> void:
	if _syncing:
		return
	var grid: Dictionary = map.get_or_add("grid", {})
	grid["size"] = size_spin.value
	grid["offset"] = [offset_x.value, offset_y.value]
	canvas.cell = size_spin.value
	canvas.offset = Vector2(offset_x.value, offset_y.value)
	canvas.queue_redraw()


static func _load_texture(path: String) -> Texture2D:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	return ImageTexture.create_from_image(img) if img != null else null


func _field(col: VBoxContainer, label: String, c: Control) -> Variant:
	var l := Label.new()
	l.text = label
	l.theme_type_variation = UISkin.V_MUTED
	col.add_child(l)
	col.add_child(c)
	return c


func _spin(col: VBoxContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return _field(col, label, s)
