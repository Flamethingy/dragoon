class_name EntryWindow
extends Window
## A spell's, item's or feature's view over the table (TASK-109): double-clicking it in a sheet
## list (SheetLists) opens it here. The compendium's EntryView (TASK-108: chips, On Use, the
## text) without the book's buttons. One window per entry; opening it again brings it forward.

static var _open := {}  ## ref -> EntryWindow

var ref := ""
var view: EntryView


## Shows `e` (an entry with `_kind`) in its window, a new one or the open one.
static func show_for(parent: Node, entry_ref: String, e: Dictionary) -> EntryWindow:
	var w: EntryWindow = _open.get(entry_ref)
	if w == null or not is_instance_valid(w):
		w = EntryWindow.new()
		w.ref = entry_ref
		_open[entry_ref] = w
		parent.add_child(w)
	w.fill(e)
	w.popup_centered(Vector2i(900, 620))
	w.grab_focus()
	return w


func _init() -> void:
	name = "EntryWindow"
	wrap_controls = false
	transient = true
	close_requested.connect(_close)
	window_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close())


func _close() -> void:
	if _open.get(ref) == self:
		_open.erase(ref)
	queue_free()


func fill(e: Dictionary) -> void:
	title = str(e.get("name", ref.get_file().capitalize()))
	if view != null:
		remove_child(view)
		view.queue_free()
	var bg := get_node_or_null("Bg") as Panel
	if bg == null:
		bg = Panel.new()
		bg.name = "Bg"
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.theme = UISkin.theme()
		var sb := StyleBoxFlat.new()
		sb.bg_color = UISkin.CREAM
		bg.add_theme_stylebox_override("panel", sb)
		add_child(bg)
	view = EntryView.new()
	view.name = "View"
	view.theme = UISkin.theme()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.setup(e)
	for b: Control in [view.edit_button, view.token_button, view.back_button, view.send_button]:
		if b != null:
			b.visible = false
