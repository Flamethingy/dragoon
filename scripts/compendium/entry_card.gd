class_name EntryCard
extends PanelContainer
## One card in the compendium binder: picture, badge (CR / level ...), name, subtitle.

signal pressed(entry: Dictionary)
signal open_requested(entry: Dictionary)  ## double-click: own tab
signal background_requested(entry: Dictionary)  ## middle-click: tab in the background
signal package_toggled(entry: Dictionary, on: bool)  ## packages: the small on/off switch (TASK-23)

const SIZE := Vector2(150, 204)

var entry: Dictionary
var selected := false:
	set(value):
		selected = value
		_restyle()

var _hover := false


func setup(e: Dictionary) -> void:
	entry = e
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "%s\n%s · %s" % [e.get("name", "?"), CardData.subtitle(e), e.get("_package_name", "")]
	_restyle()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var art := CardArt.new()
	art.custom_minimum_size = Vector2(0, 118)
	art.show_entry(e)
	box.add_child(art)
	var b := CardData.badge(e)
	if not b.is_empty():
		var hex := UISkin.hex_badge(b[0], b[1])
		hex.position = Vector2(-4, -2)
		hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(hex)

	var name := Label.new()
	name.text = str(e.get("name", "?"))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.custom_minimum_size = Vector2(SIZE.x - 20, 0)
	name.add_theme_font_size_override("font_size", 14)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var sub := Label.new()
	sub.theme_type_variation = UISkin.V_MUTED
	sub.text = CardData.subtitle(e)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	sub.add_theme_font_size_override("font_size", 12)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)

	if e.get("_kind") == "packages":
		var on := CheckButton.new()
		on.name = "Switch"
		on.button_pressed = bool(e.get("_enabled", true))
		on.tooltip_text = "Show this package's entries in the book"
		on.position = Vector2(SIZE.x - 64, 2)
		on.toggled.connect(func(pressed: bool) -> void: package_toggled.emit(entry, pressed))
		art.add_child(on)

	mouse_entered.connect(func() -> void: _hover = true; _restyle())
	mouse_exited.connect(func() -> void: _hover = false; _restyle())


func _restyle() -> void:
	theme_type_variation = UISkin.V_CARD_SELECTED if selected or _hover else UISkin.V_CARD
	modulate = Color(1.04, 1.04, 1.04) if _hover and not selected else Color.WHITE
	if entry.get("_kind") == "packages" and not bool(entry.get("_enabled", true)):
		modulate.a = 0.5  # switched off: dimmed


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			open_requested.emit(entry)
		else:
			pressed.emit(entry)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		background_requested.emit(entry)
		accept_event()
