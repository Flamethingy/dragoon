class_name RevealPopup
extends PopupPanel
## "Visible for" (TASK-19): a small popup with a checkbox per player (in their account
## color), Party and DM only. Shown when text is selected in a Markdown editor (attach()).
## `applied` gives the new viewers; an empty list means "visible to all" (removes the tag).

signal applied(who: PackedStringArray)

var _boxes := {}  ## id -> CheckBox


## accounts: id -> {name, color}; "dm" is the DM. current: the passage's viewers (if any).
func setup(accounts: Dictionary, current := PackedStringArray()) -> void:
	theme = UISkin.theme()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var title := Label.new()
	title.text = "Visible for"
	title.theme_type_variation = UISkin.V_MUTED
	col.add_child(title)
	for id: String in accounts:
		if id != Reveal.DM:
			col.add_child(_box(id, str(accounts[id].get("name", id)), current))
	col.add_child(_box(Reveal.PARTY, "Party (all players)", current))
	col.add_child(_box(Reveal.DM, "DM only", current))
	var row := HBoxContainer.new()
	col.add_child(row)
	var ok := Button.new()
	ok.text = "Apply"
	ok.pressed.connect(func() -> void: _apply(chosen()))
	row.add_child(ok)
	var all := Button.new()
	all.text = "Visible to all"
	all.tooltip_text = "Remove the tag"
	all.pressed.connect(func() -> void: _apply(PackedStringArray()))
	row.add_child(all)


func _box(id: String, text: String, current: PackedStringArray) -> CheckBox:
	var b := CheckBox.new()
	b.name = "Who_" + id
	b.text = text
	b.button_pressed = id in current
	b.add_theme_color_override("font_color", Markdown.account_color(id).darkened(0.25))
	b.add_theme_color_override("font_pressed_color", Markdown.account_color(id).darkened(0.25))
	_boxes[id] = b
	return b


## The ticked viewers: DM only wins, then Party, then the players.
func chosen() -> PackedStringArray:
	if _boxes[Reveal.DM].button_pressed:
		return PackedStringArray([Reveal.DM])
	if _boxes[Reveal.PARTY].button_pressed:
		return PackedStringArray([Reveal.PARTY])
	var out := PackedStringArray()
	for id: String in _boxes:
		if _boxes[id].button_pressed:
			out.append(id)
	if out.is_empty():
		out.append(Reveal.DM)  # nobody ticked: keep it hidden
	return out


func tick(id: String, on := true) -> void:
	_boxes[id].button_pressed = on


func _apply(who: PackedStringArray) -> void:
	applied.emit(who)
	hide()
	queue_free()


# --- Wiring into a TextEdit ------------------------------------------------------------------

## Shows the popup when text is selected with the mouse in `edit` (or Ctrl+H on a selection or
## inside a passage). `accounts` returns the accounts; `on_apply(from, to, who)` gets the
## selection as character offsets.
static func attach(edit: TextEdit, accounts: Callable, on_apply: Callable) -> void:
	edit.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_up: bool = event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var key: bool = event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_H
		if (mouse_up and edit.has_selection()) or key:
			open_for(edit, accounts.call(), on_apply, edit.get_global_mouse_position() if mouse_up else Vector2.ZERO)
			if key:
				edit.accept_event())


static func open_for(edit: TextEdit, accounts: Dictionary, on_apply: Callable, at := Vector2.ZERO) -> RevealPopup:
	var r := selection_range(edit)
	var span := Reveal.span_at(edit.text, r[0], r[1])
	var popup := RevealPopup.new()
	popup.setup(accounts, span.get("for", PackedStringArray()))
	popup.applied.connect(func(who: PackedStringArray) -> void: on_apply.call(r[0], r[1], who))
	edit.add_child(popup)
	var pos := Vector2i(at) if at != Vector2.ZERO else Vector2i(edit.get_global_rect().position + edit.get_caret_draw_pos())
	popup.popup(Rect2i(pos + Vector2i(8, 8), Vector2i.ZERO))
	return popup


## The selection (or the caret) as [from, to] character offsets in edit.text.
static func selection_range(edit: TextEdit) -> Array:
	if edit.has_selection():
		var a := offset(edit, edit.get_selection_from_line(), edit.get_selection_from_column())
		var b := offset(edit, edit.get_selection_to_line(), edit.get_selection_to_column())
		return [a, b]
	var c := offset(edit, edit.get_caret_line(), edit.get_caret_column())
	return [c, c]


static func offset(edit: TextEdit, line: int, column: int) -> int:
	var n := 0
	for l in line:
		n += edit.get_line(l).length() + 1
	return n + column
