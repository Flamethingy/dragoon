class_name CropView
extends Control
## A source page with a crop rectangle (TASK-28): shows the page fitted into the view, the
## draft's current crop and lets the DM drag a new one. `selection` is in page pixels.

signal selection_changed(rect: Rect2i)

var texture: Texture2D
var selection := Rect2i()  ## page pixels; empty = none

var _drag_from := Vector2.ZERO
var _dragging := false


func _init() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	custom_minimum_size = Vector2(320, 360)


func show_page(tex: Texture2D, crop: Rect2i) -> void:
	texture = tex
	selection = crop
	queue_redraw()


## Where the page is drawn (fitted, centered).
func page_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var tsize := texture.get_size()
	var s := minf(size.x / tsize.x, size.y / tsize.y)
	return Rect2((size - tsize * s) / 2.0, tsize * s)


func to_page(p: Vector2) -> Vector2:
	var r := page_rect()
	if r.size.x <= 0:
		return Vector2.ZERO
	var local := ((p - r.position) / r.size * texture.get_size()).clamp(Vector2.ZERO, texture.get_size())
	return local


func _gui_input(event: InputEvent) -> void:
	if texture == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_from = to_page(event.position)
			selection = Rect2i(Vector2i(_drag_from), Vector2i.ZERO)
		else:
			_dragging = false
			selection_changed.emit(selection)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var to := to_page(event.position)
		selection = Rect2i(Vector2i(_drag_from.min(to)), Vector2i((to - _drag_from).abs()))
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	if texture == null:
		draw_string(get_theme_default_font(), Vector2(12, 24), "No source page", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
		return
	var r := page_rect()
	draw_texture_rect(texture, r, false)
	if selection.size.x > 0 and selection.size.y > 0:
		var k := r.size / texture.get_size()
		var box := Rect2(r.position + Vector2(selection.position) * k, Vector2(selection.size) * k)
		draw_rect(box, Color(1, 0.8, 0.2, 0.18))
		draw_rect(box, Color(1, 0.75, 0.1), false, 2.0)
