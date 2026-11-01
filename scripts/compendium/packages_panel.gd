class_name PackagesPanel
extends Control
## The Packages window over the compendium (TASK-16): every installed source package
## with an on/off switch, Export and Remove, plus Import. Importing shows the package's
## name, version and entry counts first and, if the id is taken, asks: replace, keep
## both or cancel. Emits `changed` after anything that needs the book to reload.

signal changed
signal import_requested(input: String)  ## "Import from link..." (TASK-28)

var manager: PackageManager

var _list: VBoxContainer
var _note: Label
var _dirty := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UISkin.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UISkin.WINE.darkened(0.5), 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.custom_minimum_size = Vector2(760, 560)
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	page.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "Source packages"
	title.theme_type_variation = UISkin.V_HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var import_button := Button.new()
	import_button.text = "Import..."
	import_button.pressed.connect(_pick_import)
	head.add_child(import_button)
	var link_button := Button.new()
	link_button.name = "ImportLink"
	link_button.text = "Import from link..."
	link_button.tooltip_text = "Turn a PDF, image or web page into entries with the import agent"
	link_button.pressed.connect(func() -> void:
		import_requested.emit("")
		_close())
	head.add_child(link_button)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close)
	head.add_child(close)
	_note = Label.new()
	_note.theme_type_variation = UISkin.V_MUTED
	_note.text = "Switched-off packages stay installed but don't show in the book. Removed ones go to data/removed."
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for m in manager.list():
		_list.add_child(_row(m))


func _row(m: Dictionary) -> Control:
	var id: String = m._folder
	var chip := PanelContainer.new()
	chip.theme_type_variation = UISkin.V_CHIP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	var on := Button.new()
	on.toggle_mode = true
	on.button_pressed = m._enabled
	on.text = "On" if m._enabled else "Off"
	on.custom_minimum_size = Vector2(64, 0)
	on.tooltip_text = "Show this package in the book"
	on.toggled.connect(func(pressed: bool) -> void:
		manager.set_enabled(id, pressed)
		on.text = "On" if pressed else "Off"
		_dirty = true)
	row.add_child(on)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", -2)
	row.add_child(info)
	var label := Label.new()
	label.text = "%s  v%s" % [m.get("name", id), m.get("version", "?")]
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(label)
	var counts := Label.new()
	counts.theme_type_variation = UISkin.V_MUTED
	counts.text = counts_text(m.get("counts", {}))
	counts.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	counts.tooltip_text = counts.text
	info.add_child(counts)
	var export_button := Button.new()
	export_button.text = "Export..."
	export_button.pressed.connect(_pick_export.bind(id))
	row.add_child(export_button)
	var remove := Button.new()
	remove.text = "Remove"
	remove.pressed.connect(_confirm_remove.bind(id, str(m.get("name", id))))
	row.add_child(remove)
	return chip


## "322 monsters, 349 spells, ..." from a manifest's counts.
static func counts_text(counts: Variant) -> String:
	if not counts is Dictionary or counts.is_empty():
		return "no entries"
	var parts := PackedStringArray()
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
	for k: Variant in keys:
		parts.append("%d %s" % [int(counts[k]), k])
	return ", ".join(parts)


# --- Export --------------------------------------------------------------------------

func _pick_export(id: String) -> void:
	var docs := manager.documents(id).size()
	var dialog := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export package (%s%s)" % [
		PackageManager.size_text(manager.package_size(id)), ", %d PDFs" % docs if docs > 0 else ""])
	dialog.current_file = "%s.%s" % [id, PackageManager.EXTENSION]
	dialog.file_selected.connect(func(path: String) -> void:
		var err := manager.export_package(id, path)
		_message("Exported to %s" % path if err == OK else "Export failed: %s" % error_string(err)))
	dialog.popup_centered_ratio(0.6)


# --- Import --------------------------------------------------------------------------

func _pick_import() -> void:
	var dialog := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Import package")
	dialog.file_selected.connect(_confirm_import)
	dialog.popup_centered_ratio(0.6)


## Shows what's in the file and how to install it.
func _confirm_import(path: String) -> void:
	var info := manager.inspect(path)
	if not info.ok:
		_message("Can't import: %s" % info.error)
		return
	var m: Dictionary = info.manifest
	var text := "%s  v%s\n%s" % [m.get("name", m.id), m.get("version", "?"), counts_text(m.get("counts", {}))]
	var buttons: Array = [["Install", PackageManager.Conflict.CANCEL]]
	if info.exists:
		text += "\n\nA package with the id \"%s\" is already installed." % m.id
		buttons = [["Replace", PackageManager.Conflict.REPLACE], ["Keep both", PackageManager.Conflict.KEEP_BOTH]]
	_ask("Import package", text, buttons, func(choice: int) -> void:
		var r := manager.install(path, choice)
		if r.ok:
			_dirty = true
			_refresh()
			_message("Installed %s" % r.id)
		else:
			_message("Not installed: %s" % r.error))


# --- Remove --------------------------------------------------------------------------

func _confirm_remove(id: String, pkg_name: String) -> void:
	_ask("Remove package", "Remove \"%s\"?\nIt is moved to data/removed, so it can be put back by hand." % pkg_name,
		[["Remove", 0]], func(_c: int) -> void:
			var err := manager.remove(id)
			if err == OK:
				_dirty = true
				_refresh()
			_message("Removed %s" % pkg_name if err == OK else "Can't remove: %s" % error_string(err)))


# --- Helpers -------------------------------------------------------------------------

func _file_dialog(mode: FileDialog.FileMode, title: String) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.title = title
	d.filters = PackedStringArray(["*.%s ; Dragoon package" % PackageManager.EXTENSION, "*.zip ; Zip file"])
	d.visibility_changed.connect(func() -> void:
		if not d.visible:
			d.queue_free.call_deferred())
	add_child(d)
	return d


## A small in-book question: text and buttons [[label, value]] plus Cancel.
func _ask(title: String, text: String, buttons: Array, on_choice: Callable) -> void:
	var cover := Control.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var page := PanelContainer.new()
	page.theme_type_variation = UISkin.V_PAGE
	page.custom_minimum_size = Vector2(440, 0)
	center.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var plate := PanelContainer.new()
	plate.theme_type_variation = UISkin.V_PLATE
	col.add_child(plate)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = UISkin.V_PLATE_LABEL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(t)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(400, 0)
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for b: Array in buttons:
		var button := Button.new()
		button.text = b[0]
		button.pressed.connect(func() -> void:
			cover.queue_free()
			on_choice.call(b[1]))
		row.add_child(button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(cover.queue_free)
	row.add_child(cancel)


func _message(text: String) -> void:
	_note.text = text


func _close() -> void:
	if _dirty:
		changed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
