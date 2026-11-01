class_name TokenEditor
extends ConfirmationDialog
## The Token button next to Edit (TASK-41): a live preview of the creature's token. Drag the
## picture to move it, mouse wheel (or the slider) to zoom; border and background colour;
## which way the picture faces. Save hands the new `token_style` to `saved`.

signal saved(style: Dictionary)

const PREVIEW := 256

var entry := {}
var style := {}
var picture: Texture2D
var preview: TextureRect
var border_pick: ColorPickerButton
var background_pick: ColorPickerButton
var zoom_slider: HSlider
var faces_pick: OptionButton
var note: Label

var _dragging := false


func setup(e: Dictionary) -> void:
	entry = e
	theme = UISkin.theme()  # paper and ink like the rest, also as its own window
	style = TokenArt.style_of(e.get("token_style"), str(e.get("_kind", "")))
	name = "TokenEditor"
	title = "Token · %s" % e.get("name", "?")
	ok_button_text = "Save"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	var left := VBoxContainer.new()
	row.add_child(left)
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(PREVIEW, PREVIEW)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.36, 0.48, 0.32)  # map-ish green behind the token
	bg.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", bg)
	left.add_child(frame)
	preview = TextureRect.new()
	preview.name = "Preview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_default_cursor_shape = Control.CURSOR_MOVE
	preview.tooltip_text = "Drag to move the picture, mouse wheel to zoom"
	preview.gui_input.connect(_preview_input)
	frame.add_child(preview)
	var hint := Label.new()
	hint.theme_type_variation = UISkin.V_MUTED
	hint.text = "Drag: move · Wheel: zoom"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(hint)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(220, 0)
	row.add_child(right)
	border_pick = _color(right, "Border", "BorderColor", Color.html(str(style.border)), "border")
	background_pick = _color(right, "Background", "BackgroundColor", Color.html(str(style.background)), "background")
	var zl := Label.new()
	zl.text = "Zoom"
	right.add_child(zl)
	zoom_slider = HSlider.new()
	zoom_slider.name = "Zoom"
	zoom_slider.min_value = 0.2
	zoom_slider.max_value = 6.0
	zoom_slider.step = 0.01
	zoom_slider.value = float(style.zoom)
	zoom_slider.value_changed.connect(func(v: float) -> void:
		style.zoom = v
		_refresh())
	right.add_child(zoom_slider)
	var fl := Label.new()
	fl.text = "The picture looks to the"
	right.add_child(fl)
	faces_pick = OptionButton.new()
	faces_pick.name = "Faces"
	faces_pick.add_item("Right")
	faces_pick.add_item("Left")
	faces_pick.select(1 if style.faces == "left" else 0)
	faces_pick.tooltip_text = "On the map the token is mirrored when it looks the other way"
	faces_pick.item_selected.connect(func(i: int) -> void: style.faces = "left" if i == 1 else "right")
	right.add_child(faces_pick)
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Centre the picture"
	reset.pressed.connect(func() -> void:
		style.offset = [0.0, 0.0]
		style.zoom = 1.0
		zoom_slider.set_value_no_signal(1.0)
		_refresh())
	right.add_child(reset)
	note = Label.new()
	note.name = "Note"
	note.theme_type_variation = UISkin.V_MUTED
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(220, 0)
	note.visible = false
	right.add_child(note)

	confirmed.connect(func() -> void: saved.emit(style.duplicate(true)))
	var path := TokenArt.picture_path(e)
	if path != "":
		ImageCache.request(path, func(tex: Texture2D) -> void:
			if is_instance_valid(self):
				picture = tex
				_refresh())
	_refresh()


## Save is off with a reason (e.g. a read-only source package).
func lock(reason: String) -> void:
	get_ok_button().disabled = true
	note.text = reason
	note.visible = true


func _color(parent: Control, label: String, node_name: String, value: Color, key: String) -> ColorPickerButton:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var pick := ColorPickerButton.new()
	pick.name = node_name
	pick.color = value
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(0, 30)
	pick.color_changed.connect(func(c: Color) -> void:
		style[key] = "#" + c.to_html(false)
		_refresh())
	parent.add_child(pick)
	return pick


func _refresh() -> void:
	preview.texture = TokenArt.compose(picture, style, str(entry.get("_kind", "")))


## Dragging moves the picture (in token diameters), the wheel zooms.
func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_slider.value = float(style.zoom) * (1.08 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.08)
	elif event is InputEventMouseMotion and _dragging:
		move_by((event as InputEventMouseMotion).relative)


## Moves the picture by `pixels` of the preview.
func move_by(pixels: Vector2) -> void:
	var d := PREVIEW * (1.0 - 2.0 * TokenArt.RING)
	style.offset = [float(style.offset[0]) + pixels.x / d, float(style.offset[1]) + pixels.y / d]
	_refresh()
