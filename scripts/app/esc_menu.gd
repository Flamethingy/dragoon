class_name EscMenu
extends Control
## The game menu (Nico, 2026-11-02): Esc opens it over the table, Esc or "Back to the table"
## closes it. It holds what used to sit at the top right (combat, rules, compendium, the
## world's book) and leaving the session, so the table itself stays clear.
## Entries: [{text, action (Callable), shown (Callable -> bool, optional)}], refreshed on open.

signal closed

var entries: Array = []
var box: VBoxContainer
var title: Label


func _init() -> void:
	name = "EscMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = UISkin.V_PAGE
	center.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(260, 0)
	panel.add_child(box)
	title = Label.new()
	title.text = "Menu"
	title.theme_type_variation = UISkin.V_HEADING
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func open() -> void:
	_fill()
	visible = true
	move_to_front()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _fill() -> void:
	for c in box.get_children():
		box.remove_child(c)
		if c != title:
			c.queue_free()
	box.add_child(title)
	_add("Back to the table", close)
	for it: Dictionary in entries:
		var shown: Callable = it.get("shown", Callable())
		if shown.is_valid() and not bool(shown.call()):
			continue
		var text: Variant = it.text
		_add(str(text.call()) if text is Callable else str(text), func() -> void:
			close()
			(it.action as Callable).call())


func _add(text: String, action: Callable) -> void:
	var b := Button.new()
	b.name = text.validate_node_name().replace(" ", "")
	b.text = text
	b.pressed.connect(action)
	box.add_child(b)


## The button with this text (tests).
func button(text: String) -> Button:
	for c in box.get_children():
		if c is Button and (c as Button).text == text:
			return c
	return null
