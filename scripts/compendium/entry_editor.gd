class_name EntryEditor
extends VBoxContainer
## The entry editor (TASK-21), shown in an entry's full-view tab after "Edit" (TASK-22).
## A form built from Schema.fields(kind): text lines, numbers, choices, lists, refs, images
## (copied into the store's assets/), ability scores, speeds, bonuses, JSON for the rest,
## and Markdown fields with a live preview and [[wikilink]] suggestions (name_source).
## Monsters edit their feature lists (add, reorder, remove; "Edit" opens the feature as its
## own entry). Save goes through EntryStore.commit (session edits in a timeline become
## events). Source packages are read-only: edit a copy in a world/timeline, or unlock.

signal saved(entry: Dictionary)
signal cancelled
signal deleted
## Open another entry in the editor (a feature, a duplicate, a copy in another store).
signal open_requested(store: EntryStore, kind: String, id: String)
signal entry_open_requested(entry: Dictionary)  ## Ctrl+click on a ref token (TASK-29)
## Other entries of the store changed with this one (publishing: its features and tables, a
## replaced entry): [[kind, id]] to re-read (or drop, if gone) (TASK-30).
signal entries_changed(store: EntryStore, changes: Array)

const SUGGESTIONS := 12

var store: EntryStore
var db: PackageDB  ## the loaded book: token fields offer its values (optional)
var is_new := false  ## a just created entry: "Save as draft" / "Save" (publish) (TASK-30)
var publish_button: Button
var crop: CropView  ## the source page of imported entries (source_page)
var kind := ""
var original := {}  ## the entry as opened (file version)
var event_log: EventLog  ## timeline log, for edits during a session (optional)
## prefix -> PackedStringArray of entry names, for [[ suggestions.
var name_source: Callable = func(_p: String) -> PackedStringArray: return PackedStringArray()
## Writable stores to "edit a copy" in (read-only stores only).
var copy_targets: Array = []
## Accounts for the "Visible for" popup: id -> {name, color}, "dm" = the DM (TASK-19).
var accounts := {}

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
	var draft := EntryStore.is_draft(original)
	if is_new:
		_button(bar, "Save as draft", "Save it unfinished: hidden from the book and players until published", save).name = "SaveDraft"
		save_button = _button(bar, "Save", "Save and publish it", publish)
	else:
		save_button = _button(bar, "Save", "Save the changes (Ctrl+S)" + (" (stays a draft)" if draft else ""), save)
		publish_button = _button(bar, "Publish" if draft else "Back to draft",
			"Make it visible in the book (and to players)" if draft else "Hide it again until it is finished",
			publish if draft else back_to_draft)
		publish_button.name = "Publish" if draft else "BackToDraft"
	_button(bar, "Cancel", "Back to the view without saving", func() -> void: cancelled.emit())
	var dup := _button(bar, "Duplicate", "A copy of this entry under a new id", duplicate_entry)
	var del := _button(bar, "Delete", "Delete this entry", _confirm_delete)

	status = Label.new()
	status.theme_type_variation = UISkin.V_MUTED
	status.text = "%s · %s (%s)" % [kind.capitalize(), store.name, store.layer]
	add_child(status)

	if draft:
		status.text += " · draft"
	if store.is_read_only():
		add_child(_read_only_banner())
		if publish_button:
			publish_button.disabled = true
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
	if str(original.get("source_page", "")) != "":
		_source_page()


## Imported entries: the page they came from, with a crop box for the picture (TASK-28/30).
func _source_page() -> void:
	var head := Label.new()
	head.theme_type_variation = UISkin.V_HEADING
	head.text = "Source page"
	add_child(head)
	var origin: Dictionary = original.get("origin", {}) if original.get("origin") is Dictionary else {}
	var note := Label.new()
	note.theme_type_variation = UISkin.V_MUTED
	note.text = "%s%s · drag a box around the picture" % [str(origin.get("file", origin.get("url", "?"))).get_file(),
		"  · page %d" % int(origin.page) if origin.has("page") else ""]
	add_child(note)
	crop = CropView.new()
	crop.name = "SourcePage"
	crop.custom_minimum_size = Vector2(0, 520)
	var img := ImageCache.decode(FileAccess.get_file_as_bytes(store.folder.path_join(str(original.source_page))))
	var c: Array = original.get("crop", []) if original.get("crop") is Array else []
	crop.show_page(ImageTexture.create_from_image(img) if img else null,
		Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])) if c.size() == 4 else Rect2i())
	add_child(crop)
	var use := _button(self, "Use selection as picture", "Crop the box from the page into this entry's picture", apply_crop)
	use.name = "UseCrop"
	use.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	use.disabled = store.is_read_only()


func apply_crop() -> void:
	var r := store.crop_picture(kind, str(original.get("id", "")), crop.selection)
	if r.is_empty():
		_say("Drag a box on the page first.", true)
		return
	original["image"] = r.image
	original["crop"] = r.crop
	_build()
	_say("Picture cropped from the page.")


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
		"token", "tokens":
			var tokens := TokenField.new()
			tokens.setup(f, TokenField.build_options(f, kind, db), value)
			tokens.open_requested.connect(func(o: Dictionary) -> void: entry_open_requested.emit(o.entry))
			_getters[key] = tokens.value
			control = tokens
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
		"effects":
			control = _effects(key, value)
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
			if keep_all or v != 0.0 or d.has(n):
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


## The effects (TASK-65): JSON, with presets to add and "From the text" (the parser).
## TASK-108: on top the flow of coloured nodes (OnUseFlow); the JSON stays below, folded
## ("Show the JSON"), both kept in step.
func _effects(key: String, value: Variant) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var flow := OnUseFlow.new()
	flow.name = "Flow"
	box.add_child(flow)
	var c := CodeEdit.new()
	c.name = "Json"
	c.text = JSON.stringify(EntryStore.whole_numbers(value if value is Array else []), "  ")
	c.custom_minimum_size = Vector2(0, clampi(c.get_line_count() * 22 + 16, 60, 260))
	c.visible = false
	var syncing := {"on": false}
	var to_flow := func() -> void:  # the JSON changed: the flow follows (when it parses)
		if syncing.on:
			return
		var j: Variant = JSON.parse_string(c.text if c.text.strip_edges() != "" else "[]")
		if j is Array:
			flow.setup(j, original)
	flow.changed.connect(func(list: Array) -> void:
		syncing.on = true
		c.text = JSON.stringify(EntryStore.whole_numbers(list), "  ")
		syncing.on = false)
	c.text_changed.connect(to_flow)
	to_flow.call()
	var row := HBoxContainer.new()
	box.add_child(row)
	var presets := MenuButton.new()
	presets.name = "Presets"
	presets.text = "Add preset"
	presets.flat = false
	var names: Array = Effects.PRESETS.keys()
	for i in names.size():
		presets.get_popup().add_item(str(names[i]), i)
	presets.get_popup().id_pressed.connect(func(i: int) -> void:
		var list: Variant = JSON.parse_string(c.text)
		var arr: Array = list if list is Array else []
		arr.append((Effects.PRESETS[names[i]] as Dictionary).duplicate(true))
		c.text = JSON.stringify(arr, "  ")
		to_flow.call())
	row.add_child(presets)
	var from_text := _button(row, "From the text", "Fill it from the description (the parser; only the clear cases)", func() -> void:
		var e := original.duplicate()
		for k: String in ["description", "text", "level", "concentration", "duration"]:
			if _getters.has(k):
				e[k] = _getters[k].call()
		c.text = JSON.stringify(Effects.parse(e), "  ")
		to_flow.call())
	from_text.name = "FromText"
	var show_json := CheckButton.new()
	show_json.name = "ShowJson"
	show_json.text = "Show the JSON"
	show_json.toggled.connect(func(on: bool) -> void: c.visible = on)
	row.add_child(show_json)
	box.add_child(c)
	_getters[key] = func() -> Variant:
		var j := JSON.new()
		if j.parse(c.text if c.text.strip_edges() != "" else "[]") != OK:
			return {"_error": "Effects JSON line %d: %s" % [j.get_error_line(), j.get_error_message()]}
		return j.data if j.data is Array else {"_error": "Effects must be a list [...]"}
	return box


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
	preview.meta_clicked.connect(func(meta: Variant) -> void: RollTables.handle_meta(str(meta)))
	RollTables.hub.changed.connect(func(id: String) -> void:
		if is_instance_valid(preview) and RollTables.embeds(edit.text, id):
			preview.text = Markdown.to_bbcode(edit.text))
	row.add_child(preview)
	edit.text_changed.connect(func() -> void:
		preview.text = Markdown.to_bbcode(edit.text)
		_update_suggestions(edit, suggest))
	edit.caret_changed.connect(func() -> void: _update_suggestions(edit, suggest))
	edit.gui_input.connect(func(event: InputEvent) -> void: _suggest_keys(event, edit, suggest))
	suggest.item_activated.connect(func(i: int) -> void: accept_suggestion(edit, suggest.get_item_text(i)); suggest.hide())
	suggest.item_clicked.connect(func(i: int, _at: Vector2, _b: int) -> void: accept_suggestion(edit, suggest.get_item_text(i)); suggest.hide())
	RevealPopup.attach(edit, func() -> Dictionary: return accounts,
		func(from: int, to: int, who: PackedStringArray) -> void: apply_reveal(key, edit, from, to, who))
	_getters[key] = func() -> Variant: return edit.text
	return row


## "Visible for" on a selection of a Markdown field. Normally the text gets (or changes) a
## <reveal> tag; in a timeline during a session, changing an existing passage is a
## reveal.changed event instead (the text keeps its starting `for`).
func apply_reveal(key: String, edit: TextEdit, from: int, to: int, who: PackedStringArray) -> void:
	var span := Reveal.span_at(edit.text, from, to)
	if not span.is_empty() and _live_session():
		var ref := "%s/%s" % [kind, original.get("id", "")]
		var ops: Array = Reveal.grants_from(event_log.effective(ref), ref).get(key, {}).get(span.id, [])
		var now := Reveal.current_viewers(span.for, ops)
		var target := who if not who.is_empty() else PackedStringArray([Reveal.PARTY])
		var add := Array(target).filter(func(v: String) -> bool: return v not in now)
		var remove := Array(now).filter(func(v: String) -> bool: return v not in target)
		if not add.is_empty() or not remove.is_empty():
			event_log.change_reveal(ref, span.id, key, add, remove)
			_say("Logged: %s now visible for %s" % [span.id, ", ".join(target)])
		return
	var texts := [edit.text]
	for k: Variant in original:
		texts.append(str(original[k]))
	var r := Reveal.apply(edit.text, from, to, who, Reveal.next_id(texts))
	if r.text != edit.text:
		edit.text = r.text
		edit.text_changed.emit()


func _live_session() -> bool:
	return store.layer == EntryStore.TIMELINE and event_log != null and event_log.in_session()


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


# --- Drafts (TASK-30) ---------------------------------------------------------------------

## Saves and publishes: a published entry of the same name asks replace / keep both / skip
## first (on_duplicate ASK); the other choices go straight through.
func publish(on_duplicate := EntryStore.ASK) -> Dictionary:
	var got := collect()
	if got.has("error"):
		_say(got.error, true)
		return {}
	var e: Dictionary = got.entry
	e["draft"] = true
	var r := store.commit(kind, original, e, event_log)
	if r.error != OK:
		_say("Couldn't save: %s" % error_string(r.error), true)
		return {}
	original = EntryStore.strip(store.find(kind, str(e.id))).duplicate(true)
	var p := store.publish(kind, str(e.id), on_duplicate)
	if p.has("duplicate"):
		_ask_duplicate(p.duplicate)
		return p
	if p.has("error"):
		_say(str(p.error), true)
		return p
	var changes: Array = p.get("removed", []) + p.get("parts", [])
	if not changes.is_empty():
		entries_changed.emit(store, changes)
	if p.has("skipped"):
		deleted.emit()
		return p
	original = EntryStore.strip(p.published).duplicate(true)
	is_new = false
	_say("Published")
	saved.emit(original)
	return p


## A published entry goes back to being a draft.
func back_to_draft() -> Dictionary:
	var e := store.unpublish(kind, str(original.get("id", "")))
	if e.is_empty():
		return {}
	original = EntryStore.strip(e).duplicate(true)
	_say("Back to draft")
	saved.emit(original)
	return e


func _ask_duplicate(dup: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "DuplicateQuestion"
	dialog.title = "Already published"
	dialog.dialog_text = "\"%s\" is already in %s.
Replace it, keep both, or throw this draft away?" % [dup.get("name", "?"), store.name]
	dialog.ok_button_text = "Replace"
	dialog.add_button("Keep both", false, EntryStore.KEEP_BOTH)
	dialog.add_button("Skip (discard draft)", false, EntryStore.SKIP)
	dialog.confirmed.connect(func() -> void:
		_drop(dialog)
		publish(EntryStore.REPLACE))
	dialog.custom_action.connect(func(action: StringName) -> void:
		_drop(dialog)
		publish(str(action)))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


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


## Takes a finished question out of the tree at once (the next one may take its name).
func _drop(dialog: Node) -> void:
	if dialog.get_parent():
		dialog.get_parent().remove_child(dialog)
	dialog.queue_free()
