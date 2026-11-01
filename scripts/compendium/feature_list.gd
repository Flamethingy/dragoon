class_name FeatureList
extends VBoxContainer
## A monster's feature list in the entry editor (TASK-21): feature ids shown by name, with
## up / down / edit / remove per row. "Add" takes a name or id: an existing feature of the
## store is linked, otherwise a new feature entry is created in its features.json (features
## are entries of their own; "Edit" opens one in its own tab).

var editor: EntryEditor
var _ids: Array = []
var _rows: VBoxContainer
var _add: LineEdit


func setup(owner_editor: EntryEditor, ids: Array) -> void:
	editor = owner_editor
	_ids = ids.map(func(x: Variant) -> String: return str(x))
	add_theme_constant_override("separation", 4)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)
	var bottom := HBoxContainer.new()
	add_child(bottom)
	_add = LineEdit.new()
	_add.placeholder_text = "Feature name or id"
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.text_submitted.connect(func(t: String) -> void: add_feature(t))
	bottom.add_child(_add)
	var b := Button.new()
	b.text = "Add"
	b.tooltip_text = "Link an existing feature of this package, or create a new one"
	b.pressed.connect(func() -> void: add_feature(_add.text))
	bottom.add_child(b)
	var read_only := editor.store.is_read_only()
	_add.editable = not read_only
	b.disabled = read_only
	_refresh()


func ids() -> Array:
	return _ids.duplicate()


## Adds a feature by id or name (an existing one if the store has it, else a new entry).
func add_feature(text: String) -> String:
	var t := text.strip_edges()
	if t == "" or editor.store.is_read_only():
		return ""
	var feature_id := ""
	if editor.store.has("features", t):
		feature_id = t
	else:
		for f: Variant in editor.store.list("features"):
			if f is Dictionary and str(f.get("name", "")).to_lower() == t.to_lower():
				feature_id = str(f.id)
				break
	if feature_id == "":
		var e := editor.store.create("features", t)
		feature_id = str(e.id)
	_ids.append(feature_id)
	_add.text = ""
	_refresh()
	return feature_id


func move(index: int, by: int) -> void:
	var to := index + by
	if to < 0 or to >= _ids.size():
		return
	var id: String = _ids[index]
	_ids.remove_at(index)
	_ids.insert(to, id)
	_refresh()


func remove(index: int) -> void:
	_ids.remove_at(index)
	_refresh()


func _refresh() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if _ids.is_empty():
		var none := Label.new()
		none.text = "None"
		none.theme_type_variation = UISkin.V_MUTED
		_rows.add_child(none)
	var read_only := editor.store.is_read_only()
	for i in _ids.size():
		var id: String = _ids[i]
		var f := editor.store.find("features", id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var label := Label.new()
		label.text = str(f.get("name", id)) if not f.is_empty() else "%s (missing)" % id
		label.tooltip_text = "%s\n\n%s" % [id, str(f.get("text", "")).left(300)]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		_small(row, "↑", "Move up", func() -> void: move(i, -1), read_only or i == 0)
		_small(row, "↓", "Move down", func() -> void: move(i, 1), read_only or i == _ids.size() - 1)
		_small(row, "Edit", "Open this feature in its own tab", func() -> void:
			editor.open_requested.emit(editor.store, "features", id), f.is_empty())
		_small(row, "✕", "Remove from this list (the feature entry stays)", func() -> void: remove(i), read_only)
		_rows.add_child(row)


func _small(row: HBoxContainer, text: String, tip: String, action: Callable, off := false) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.disabled = off
	b.pressed.connect(action)
	row.add_child(b)
