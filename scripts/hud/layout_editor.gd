class_name LayoutEditor
extends Control
## Puts a layout together on a grid (TASK-47): the HUD over the whole screen (F2) or the
## sheet pages (F3). The rest is blurred and dimmed; a grid shows the cells. A toolkit lists
## the pieces (HudWidgets.KINDS): click one to add it. Drag a piece to move it, drag its
## lower right corner to resize, right-click removes it. Several layouts can be edited
## (the sheet pages: one tab each, add / delete). Done saves (the HUD also on F2 / F3 / Esc);
## Cancel drops the changes.

signal finished(sets: Array, saved: bool)

const HANDLE := 16.0
const BLUR := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.0;
void fragment() {
	COLOR = vec4(textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.55, 1.0);
}
"""

var grid := HudWidgets.HUD_GRID
var area := Rect2()  ## where the grid is, in this control's pixels (empty = all of it)
var sets: Array = []  ## [{name, items}] (the HUD: one set)
var current := 0
var multi := false  ## pages: tabs, add and delete
var sheet := {}
var hud: CharacterHud

var _layer: Control  ## the pieces
var _frames: Control  ## outlines and resize handles above them
var _toolkit: VBoxContainer
var _tabs: HBoxContainer
var _drag := -1  ## index of the piece being moved / resized
var _resizing := false
var _grab := Vector2.ZERO  ## where in the piece it was grabbed (moving)


func _init() -> void:
	name = "LayoutEditor"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blur := ColorRect.new()
	blur.name = "Blur"
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BLUR
	mat.shader = shader
	blur.material = mat
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(blur)
	_layer = Control.new()
	_layer.name = "Pieces"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	_frames = Control.new()
	_frames.name = "Frames"
	_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frames.draw.connect(_draw_frames)
	add_child(_frames)
	_build_toolkit()
	resized.connect(_rebuild)
	_rebuild()
	grab_focus()


func items() -> Array:
	return sets[current].items if current < sets.size() else []


func cell_size() -> Vector2:
	return _area().size / Vector2(grid)


func _area() -> Rect2:
	return area if area.has_area() else Rect2(Vector2.ZERO, size)


func _build_toolkit() -> void:
	var panel := PanelContainer.new()
	panel.name = "Toolkit"
	panel.theme_type_variation = UISkin.V_PAGE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -230
	panel.offset_right = -12
	panel.offset_top = 56
	add_child(panel)
	_toolkit = VBoxContainer.new()
	_toolkit.add_theme_constant_override("separation", 4)
	panel.add_child(_toolkit)
	var title := Label.new()
	title.text = "Sheet pages" if multi else "HUD"
	title.theme_type_variation = UISkin.V_HEADING
	_toolkit.add_child(title)
	if multi:
		_tabs = HBoxContainer.new()
		_tabs.name = "Pages"
		_toolkit.add_child(_tabs)
		var row := HBoxContainer.new()
		_toolkit.add_child(row)
		_tool_button(row, "+ Page", add_page)
		_tool_button(row, "Delete page", delete_page)
	var hint := Label.new()
	hint.text = "Click to add · drag to move\ncorner: resize · right-click: remove"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UISkin.INK_SOFT)
	_toolkit.add_child(hint)
	for kind: String in HudWidgets.KINDS:
		var b := _tool_button(_toolkit, str(HudWidgets.KINDS[kind].label), add.bind(kind))
		b.name = "Add_" + kind
	_toolkit.add_child(HSeparator.new())
	_tool_button(_toolkit, "Reset to default", reset)
	var end := HBoxContainer.new()
	_toolkit.add_child(end)
	_tool_button(end, "Cancel", finish.bind(false))
	_tool_button(end, "Done", finish.bind(true))


func _tool_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Adds a piece at the first free place for its default size (else top left).
func add(kind: String) -> void:
	if sets.is_empty():
		sets.append({"name": "Page 1", "items": []})
	var size: Array = HudWidgets.KINDS[kind].size
	var w := mini(int(size[0]), grid.x)
	var h := mini(int(size[1]), grid.y)
	var at := Vector2i.ZERO
	var found := false
	for y in grid.y - h + 1:
		for x in grid.x - w + 1:
			if not found and _free(Rect2i(x, y, w, h), -1):
				at = Vector2i(x, y)
				found = true
	items().append({"w": kind, "r": [at.x, at.y, w, h]})
	_rebuild()


func remove(index: int) -> void:
	if index >= 0 and index < items().size():
		items().remove_at(index)
		_rebuild()


func reset() -> void:
	if multi:
		sets = HudWidgets.DEFAULT_PAGES.duplicate(true)
		current = 0
	else:
		sets = [{"name": "HUD", "items": HudWidgets.DEFAULT_HUD.duplicate(true)}]
	_rebuild()


func add_page() -> void:
	if sets.size() >= 9:
		return
	sets.append({"name": "Page %d" % (sets.size() + 1), "items": []})
	current = sets.size() - 1
	_rebuild()


func delete_page() -> void:
	if sets.size() <= 1:
		return
	sets.remove_at(current)
	current = clampi(current, 0, sets.size() - 1)
	_rebuild()


func show_set(index: int) -> void:
	current = clampi(index, 0, maxi(sets.size() - 1, 0))
	_rebuild()


func finish(save: bool) -> void:
	finished.emit(sets, save)
	queue_free()


## Moves / resizes piece `index` to `r` (cells), kept inside the grid.
func place(index: int, r: Rect2i) -> void:
	var w := clampi(r.size.x, 1, grid.x)
	var h := clampi(r.size.y, 1, grid.y)
	items()[index].r = [clampi(r.position.x, 0, grid.x - w), clampi(r.position.y, 0, grid.y - h), w, h]
	_rebuild()


func _free(r: Rect2i, skip: int) -> bool:
	var list := items()
	for i in list.size():
		var o: Array = list[i].r
		if i != skip and r.intersects(Rect2i(int(o[0]), int(o[1]), int(o[2]), int(o[3]))):
			return false
	return true


func _rect_px(r: Array) -> Rect2:
	var c := cell_size()
	return Rect2(_area().position + Vector2(float(r[0]), float(r[1])) * c, Vector2(float(r[2]), float(r[3])) * c)


func _rebuild() -> void:
	if _layer == null:
		return
	for c in _layer.get_children():
		_layer.remove_child(c)
		c.queue_free()
	var list := items()
	for i in list.size():
		var rect := _rect_px(list[i].r)
		var piece := HudWidgets.build(str(list[i].w), sheet, hud, rect.size)
		piece.position = rect.position
		piece.size = rect.size
		_ignore_mouse(piece)
		_layer.add_child(piece)
	if _tabs != null:
		for c in _tabs.get_children():
			_tabs.remove_child(c)
			c.queue_free()
		for i in sets.size():
			var b := _tool_button(_tabs, str(i + 1), show_set.bind(i))
			b.toggle_mode = true
			b.button_pressed = i == current
			b.tooltip_text = str(sets[i].get("name", ""))
	queue_redraw()
	if _frames != null:
		_frames.queue_redraw()


static func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_ignore_mouse(child)


func _draw() -> void:
	var a := _area()
	var c := cell_size()
	draw_rect(a, Color(1, 1, 1, 0.04))
	for x in grid.x + 1:
		draw_line(a.position + Vector2(x * c.x, 0), a.position + Vector2(x * c.x, a.size.y), Color(1, 1, 1, 0.12), 1.0)
	for y in grid.y + 1:
		draw_line(a.position + Vector2(0, y * c.y), a.position + Vector2(a.size.x, y * c.y), Color(1, 1, 1, 0.12), 1.0)


## Outlines and resize handles above the pieces.
func _draw_frames() -> void:
	var list := items()
	for i in list.size():
		var rect := _rect_px(list[i].r)
		var col := Color(1.0, 0.55, 0.1, 0.95) if i == _drag else Color(1, 1, 1, 0.85)
		_frames.draw_rect(rect, col, false, 2.0)
		_frames.draw_rect(Rect2(rect.end - Vector2(HANDLE, HANDLE), Vector2(HANDLE, HANDLE)), col)


func _piece_at(pos: Vector2) -> int:
	var list := items()
	for i in range(list.size() - 1, -1, -1):
		if _rect_px(list[i].r).has_point(pos):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			remove(_piece_at(mb.position))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = _piece_at(mb.position)
				if _drag >= 0:
					var rect := _rect_px(items()[_drag].r)
					_resizing = Rect2(rect.end - Vector2(HANDLE, HANDLE), Vector2(HANDLE, HANDLE)).grow(4).has_point(mb.position)
					_grab = mb.position - rect.position
			else:
				_drag = -1
				_frames.queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _drag >= 0:
		var mm := event as InputEventMouseMotion
		var c := cell_size()
		var r: Array = items()[_drag].r
		var local := mm.position - _area().position
		if _resizing:
			var end := Vector2i(((local) / c).round())
			place(_drag, Rect2i(int(r[0]), int(r[1]), maxi(1, end.x - int(r[0])), maxi(1, end.y - int(r[1]))))
		else:
			var at := Vector2i(((local - _grab) / c).round())
			if at != Vector2i(int(r[0]), int(r[1])):
				place(_drag, Rect2i(at.x, at.y, int(r[2]), int(r[3])))
		accept_event()
