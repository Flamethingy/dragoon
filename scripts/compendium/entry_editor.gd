class_name EntryEditor
extends VBoxContainer
## The entry editor (TASK-21), shown in an entry's full-view tab after "Edit" (TASK-22).
## A form built from Schema.fields(kind): text lines, numbers, choices, lists, refs, images
## (copied into the store's assets/), ability scores, speeds, bonuses, JSON for the rest,
## and Markdown fields with a live preview and [[wikilink]] suggestions (name_source).
## Monsters edit their feature lists (add, reorder, remove; "Edit" opens the feature as its
## own entry). Save goes through EntryStore.commit (session edits in a campaign become
## events). Source packages are read-only: edit a copy in a world/campaign, or unlock.

signal saved(entry: Dictionary)
signal cancelled
signal deleted
## Open another entry in the editor (a feature, a duplicate, a copy in another store).
signal open_requested(store: EntryStore, kind: String, id: String)

const SUGGESTIONS := 12

var store: EntryStore
var kind := ""
var original := {}  ## the entry as opened (file version)
var event_log: EventLog  ## campaign log, for edits during a session (optional)
## prefix -> PackedStringArray of entry names, for [[ suggestions.
var name_source: Callable = func(_p: String) -> PackedStringArray: return PackedStringArray()
## Writable stores to "edit a copy" in (read-only stores only).
var copy_targets: Array = []

var status: Label
var save_button: Button
var _getters := {}  ## key -> Callable() -> Variant, or {_error: "..."} if unreadable
var _form: GridContainer


func setup(entry_store: EntryStore, entry_kind: String, entry: Dictionary) -> void:
	store = entry_store
	kind = entry_kind
	original = EntryStore.strip(entry).duplicate(true)
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_getters.clear()
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var title := Label.new()
	title.theme_type_variation = UISkin.V_HEADING
	title.text = "Edit %s" % str(original.get("name", "?"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	bar.add_child(title)
	save_button = _button(bar, "Save", "Save the changes (Ctrl+S)", save)
	_button(bar, "Cancel", "Back to the view without saving", func() -> void: cancelled.emit())
	var dup := _button(bar, "Duplicate", "A copy of this entry under a new id", duplicate_entry)
	var del := _button(bar, "Delete", "Delete this entry", _confirm_delete)

	status = Label.new()
	status.theme_type_variation = UISkin.V_MUTED
	status.text = "%s · %s (%s)" % [kind.capitalize(), store.name, store.layer]
	add_child(status)

	if store.is_read_only():
		add_child(_read_only_banner())
		for b: Button in [save_button, dup, del]:
			b.disabled = true
			b.tooltip_text = "The source package is read-only"

	_form = GridContainer.new()
	_form.columns = 2
	_form.add_theme_constant_override("h_separation", 14)
	_form.add_theme_constant_override("v_separation", 10)
	add_child(_form)
	for f in Schema.fields(kind, original):
		_add_field(f)


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _read_only_banner() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = UISkin.V_CHIP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var text := Label.new()
	text.text = "\"%s\" is a source package and read-only." % store.name
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	var targets := OptionButton.new()
	targets.name = "CopyTarget"
	for t: EntryStore in copy_targets:
		targets.add_item("%s (%s)" % [t.name, t.layer])
	targets.disabled = copy_targets.is_empty()
	row.add_child(targets)
	var copy := _button(row, "Edit a copy", "Copy the entry (and its features) there and edit it", func() -> void:
		edit_copy_in(copy_targets[targets.selected]))
	copy.disabled = copy_targets.is_empty()
	if copy_targets.is_empty():
		copy.tooltip_text = "Create a world package first (New... in Browse)"
	_button(row, "Unlock", "Allow editing this source package itself", func() -> void:
		store.unlock()
		_build())
	return panel


# --- Fields ----------------------------------------------------------------------------

func _add_field(f: Dictionary) -> void:
	var key: String = f.key
	var value: Variant = original.get(key, Schema.empty(f.type))
	var label := Label.new()
	label.text = f.label
	label.theme_type_variation = UISkin.V_MUTED
	label.custom_minimum_size = Vector2(150, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_form.add_child(label)
	var control: Control
	match str(f.type):
		"line", "ref":
			control = _line(key, str(value))
		"markdown":
			control = _markdown(key, str(value))
		"int", "float":
			control = _number(key, value, f.type == "float")
		"bool":
			var c := CheckBox.new()
			c.button_pressed = bool(value)
			_getters[key] = func() -> Variant: return c.button_pressed
			control = c
		"choice":
			control = _choice(key, str(value), f.options)
		"list", "refs":
			control = _list(key, value)
		"image":
			control = _image(key, str(value))
		"stats":
			control = _numbers(key, value, Schema.ABILITIES, 10, true)
		"speed":
			control = _numbers(key, value, Schema.SPEEDS, 0, false)
		"bonuses":
			control = _bonuses(key, value)
		"features":
			control = FeatureList.new()
			control.setup(self, value if value is Array else [])
			_getters[key] = control.ids
		"cell":
			control = _cell(key, value)
		_:
			control = _json(key, value)
	control.name = "Field_" + key
	if not control is SpinBox:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(control)


func _line(key: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	_getters[key] = func() -> Variant: return e.text.strip_edges()
	return e


func _number(key: String, value: Variant, decimals: bool) -> SpinBox:
	var s := SpinBox.new()
	s.allow_greater = true
	s.allow_lesser = true
	s.step = 0.001 if decimals else 1.0
	s.custom_arrow_step = 1.0
	s.value = float(value) if value is int or value is float else 0.0
	s.custom_minimum_size = Vector2(130, 0)
	s.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_getters[key] = func() -> Variant: return s.value if decimals else int(s.value)
	return s


func _choice(key: String, value: String, options: Array) -> OptionButton:
	var b := OptionButton.new()
	var opts := options.duplicate()
	if value not in opts:
		opts.append(value)
	for o: String in opts:
		b.add_item(o if o != "" else "—")
	b.selected = opts.find(value)
	_getters[key] = func() -> Variant: return opts[b.selected]
	return b


func _list(key: String, value: Variant) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = "comma, separated"
	e.text = ", ".join(PackedStringArray(value.map(func(x: Variant) -> String: return str(x)))) if value is Array else str(value)
	_getters[key] = func() -> Variant: return split_list(e.text)
	return e


static func split_list(text: String) -> Array:
	var out := []
	for part in text.split(","):
		if part.strip_edges() != "":
			out.append(part.strip_edges())
	return out


func _image(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = "assets/... (relative to the folder)"
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	var pick := _button(row, "Pick...", "Choose an image; it is copied into the folder's assets/", func() -> void:
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		dialog.use_native_dialog = true
		dialog.file_selected.connect(func(path: String) -> void:
			e.text = store.import_image(path, kind)
			dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered_ratio(0.6))
	pick.disabled = store.is_read_only()
	_getters[key] = func() -> Variant: return e.text.strip_edges()
	return row


func _numbers(key: String, value: Variant, names: Array, default: int, keep_all: bool) -> Control:
	var d: Dictionary = value if value is Dictionary else {}
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	var boxes := {}
	for n: String in names:
		var col := VBoxContainer.new()
		var l := Label.new()
		l.text = n.to_upper() if keep_all else n
		l.theme_type_variation = UISkin.V_MUTED
		col.add_child(l)
		var s := SpinBox.new()
		s.allow_greater = true
		s.value = float(d.get(n, default))
		s.step = 1.0 if keep_all else 0.5
		s.custom_minimum_size = Vector2(96, 0)
		col.add_child(s)
		row.add_child(col)
		boxes[n] = s
	_getters[key] = func() -> Variant:
		var out := {}
		for n: String in names:
			var v: float = boxes[n].value
			if keep_all or v != 0.0:
				out[n] = int(v) if v == floorf(v) else v
		return out
	return row


func _bonuses(key: String, value: Variant) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = "con +8, perception +10"
	var parts := PackedStringArray()
	if value is Dictionary:
		for k: Variant in value:
			parts.append("%s %+d" % [k, int(value[k])])
	e.text = ", ".join(parts)
	_getters[key] = func() -> Variant: return parse_bonuses(e.text)
	return e


## "con +8, sleight of hand +5" -> {con: 8, "sleight of hand": 5}; [error] if a part has no number.
static func parse_bonuses(text: String) -> Variant:
	var out := {}
	for part in split_list(text):
		var p: String = part
		var at := p.rfind(" ")
		var num := p.substr(at + 1).replace("+", "") if at > 0 else ""
		if not num.is_valid_int():
			return {"_error": "\"%s\" needs a name and a number" % p}
		out[p.left(at).strip_edges().to_lower()] = int(num)
	return out


func _cell(key: String, value: Variant) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = "x, y (empty = none)"
	e.text = "%d, %d" % [int(value[0]), int(value[1])] if value is Array and value.size() == 2 else ""
	_getters[key] = func() -> Variant:
		var p := split_list(e.text)
		if p.is_empty():
			return []
		if p.size() != 2 or not str(p[0]).is_valid_int() or not str(p[1]).is_valid_int():
			return {"_error": "needs two whole numbers: x, y"}
		return [int(p[0]), int(p[1])]
	return e


func _json(key: String, value: Variant) -> CodeEdit:
	var c := CodeEdit.new()
	c.text = JSON.stringify(EntryStore.whole_numbers(value), "  ")
	c.custom_minimum_size = Vector2(0, clampi(c.get_line_count() * 22 + 16, 60, 260))
	_getters[key] = func() -> Variant:
		var j := JSON.new()
		if j.parse(c.text) != OK:
			return {"_error": "JSON line %d: %s" % [j.get_error_line(), j.get_error_message()]}
		return j.data
	return c


func _markdown(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var edit := CodeEdit.new()
	edit.name = "Text"
	edit.text = value
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(0, 180 if key in ["description", "text"] else 90)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(edit)
	var suggest := ItemList.new()
	suggest.name = "Suggestions"
	suggest.visible = false
	suggest.auto_height = true
	suggest.custom_minimum_size = Vector2(260, 0)
	suggest.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(suggest)
	var preview := RichTextLabel.new()
	preview.name = "Preview"
	preview.bbcode_enabled = true
	preview.fit_content = true
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.text = Markdown.to_bbcode(value)
	row.add_child(preview)
	edit.text_changed.connect(func() -> void:
		preview.text = Markdown.to_bbcode(edit.text)
		_update_suggestions(edit, suggest))
	edit.caret_changed.connect(func() -> void: _update_suggestions(edit, suggest))
	edit.gui_input.connect(func(event: InputEvent) -> void: _suggest_keys(event, edit, suggest))
	suggest.item_activated.connect(func(i: int) -> void: accept_suggestion(edit, suggest.get_item_text(i)); suggest.hide())
	suggest.item_clicked.connect(func(i: int, _at: Vector2, _b: int) -> void: accept_suggestion(edit, suggest.get_item_text(i)); suggest.hide())
	_getters[key] = func() -> Variant: return edit.text
	return row


## The text after an open [[ before the caret ("" = not in a link).
static func link_prefix(edit: TextEdit) -> String:
	var line := edit.get_line(edit.get_caret_line()).left(edit.get_caret_column())
	var at := line.rfind("[[")
	if at < 0 or "]]" in line.substr(at):
		return ""
	var partial := line.substr(at + 2)
	return partial if partial != "" and not "|" in partial and not "#" in partial else ""


func _update_suggestions(edit: CodeEdit, suggest: ItemList) -> void:
	var prefix := link_prefix(edit)
	suggest.clear()
	if prefix != "":
		for n in name_source.call(prefix):
			if suggest.item_count >= SUGGESTIONS:
				break
			suggest.add_item(n)
	suggest.visible = suggest.item_count > 0
	if suggest.visible:
		suggest.select(0)


func _suggest_keys(event: InputEvent, edit: CodeEdit, suggest: ItemList) -> void:
	if not suggest.visible or not (event is InputEventKey and event.pressed):
		return
	var sel := suggest.get_selected_items()
	var i: int = sel[0] if not sel.is_empty() else 0
	match event.keycode:
		KEY_DOWN, KEY_UP:
			i = clampi(i + (1 if event.keycode == KEY_DOWN else -1), 0, suggest.item_count - 1)
			suggest.select(i)
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			accept_suggestion(edit, suggest.get_item_text(i))
			suggest.hide()
		KEY_ESCAPE:
			suggest.hide()
		_:
			return
	edit.accept_event()


## Replaces the partial link before the caret with "[[name]]".
static func accept_suggestion(edit: TextEdit, entry_name: String) -> void:
	var prefix := link_prefix(edit)
	var line := edit.get_caret_line()
	var col := edit.get_caret_column()
	edit.select(line, col - prefix.length(), line, col)
	var rest := edit.get_line(line).substr(col)
	edit.insert_text_at_caret(entry_name + ("" if rest.begins_with("]]") else "]]"))
	edit.deselect()
	edit.set_caret_column(col - prefix.length() + entry_name.length() + 2)


# --- Actions ---------------------------------------------------------------------------

## The form's values as an entry, or {error: "..."} if a field can't be read.
func collect() -> Dictionary:
	var out := original.duplicate(true)
	for key: String in _getters:
		var v: Variant = _getters[key].call()
		if v is Dictionary and v.has("_error"):
			return {"error": "%s: %s" % [key.capitalize(), v._error]}
		out[key] = v
	if str(out.get("name", "")).strip_edges() == "" and kind != "notes":
		return {"error": "The name can't be empty"}
	return {"entry": out}


func save() -> Dictionary:
	var got := collect()
	if got.has("error"):
		_say(got.error, true)
		return {}
	var r := store.commit(kind, original, got.entry, event_log)
	if r.error != OK:
		_say("Couldn't save: %s" % error_string(r.error), true)
		return {}
	original = EntryStore.strip(store.find(kind, str(got.entry.id))).duplicate(true)
	_say("Saved" + (" · %d change(s) logged as events" % r.events.size() if not r.events.is_empty() else ""))
	saved.emit(original)
	return original


func duplicate_entry() -> void:
	var copy := store.duplicate_entry(kind, str(original.get("id", "")))
	if not copy.is_empty():
		open_requested.emit(store, kind, str(copy.id))


func edit_copy_in(target: EntryStore) -> Dictionary:
	var copy := target.copy_entry(store, kind, str(original.get("id", "")))
	if not copy.is_empty():
		open_requested.emit(target, kind, str(copy.id))
	return copy


func _confirm_delete() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Delete \"%s\" from %s?\nThis can't be undone." % [original.get("name", "?"), store.name]
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(delete_entry)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func delete_entry() -> void:
	if store.delete(kind, str(original.get("id", ""))) == OK:
		deleted.emit()


func _say(text: String, error := false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color(0.7, 0.15, 0.15) if error else UISkin.INK_SOFT)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and event.ctrl_pressed and event.keycode == KEY_S and is_visible_in_tree():
		if not store.is_read_only():
			save()
		get_viewport().set_input_as_handled()
