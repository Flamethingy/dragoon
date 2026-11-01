class_name TokenPalette
extends PanelContainer
## The DM's compendium beside the map (TASK-34): the monsters, NPCs and PCs of the books,
## this world and this timeline, to drag onto the map. A dropped monster becomes a numbered
## copy in the timeline (Goblin 1, Goblin 2) with its own HP; NPCs and PCs are placed
## themselves. The drop is a `token.placed` event (NetTable.drop_token).

const KINDS := ["monsters", "npcs", "pcs"]
const MAX_ROWS := 300

var table: NetTable
var packages_root := ""
var db: PackageDB
var search: LineEdit
var list: DragList
var shown: Array[Dictionary] = []  ## the entries in the list, in order


## A list whose rows can be dragged (data: {type: "dragoon_entry", entry}).
class DragList extends ItemList:
	var palette: TokenPalette

	func _get_drag_data(at_position: Vector2) -> Variant:
		var i := get_item_at_position(at_position, true)
		if i < 0 or i >= palette.shown.size():
			return null
		var e: Dictionary = palette.shown[i]
		var l := Label.new()
		l.text = str(e.get("name", ""))
		if get_viewport().gui_is_dragging():
			set_drag_preview(l)
		return TokenPalette.drag_data(e)


## Covers the map while something is dragged and takes the drop (otherwise lets clicks through).
class MapDrop extends Control:
	var table: NetTable

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			mouse_filter = Control.MOUSE_FILTER_STOP if TokenPalette.is_entry_drag(get_viewport().gui_get_drag_data()) else Control.MOUSE_FILTER_IGNORE
		elif what == NOTIFICATION_DRAG_END:
			mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return table.is_dm() and TokenPalette.is_entry_drag(data)

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		var screen := get_global_transform_with_canvas() * at_position
		table.drop_token(data.entry, table.grid.cell_at_screen(screen))


static func drag_data(e: Dictionary) -> Dictionary:
	return {"type": "dragoon_entry", "entry": e}


static func is_entry_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "dragoon_entry" and data.get("entry") is Dictionary


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	custom_minimum_size = Vector2(260, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := Label.new()
	head.text = "Drag onto the map"
	head.theme_type_variation = UISkin.V_HEADING
	col.add_child(head)
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Goblin, Mira, wolf ..."
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t: String) -> void: refresh())
	col.add_child(search)
	list = DragList.new()
	list.name = "Entries"
	list.palette = self
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.tooltip_text = "Drag a monster, NPC or PC onto the map"
	col.add_child(list)
	reload()


## Reads the books, the world and the timeline again.
func reload() -> void:
	db = PackageDB.new()
	db.timeline_dir = table.timeline_dir if table != null else ""
	db.load_now(packages_root)
	refresh()


func refresh() -> void:
	if list == null or db == null:
		return
	list.clear()
	shown = []
	var world := db.timeline_world
	var f := search.text.strip_edges().to_lower()
	for kind: String in KINDS:
		for e: Dictionary in db.list(kind):
			var layer := str(e.get("_layer", ""))
			if layer == "world" and str(e.get("_package", "")) != world:
				continue  # another world's
			if f != "" and not str(e._key).contains(f):
				continue
			if e.has("copy_of"):
				continue  # tokens already made from a book entry
			shown.append(e)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a._key) < str(b._key))
	shown.resize(mini(shown.size(), MAX_ROWS))
	for e in shown:
		var where: String = {"timeline": "this timeline", "world": "world"}.get(str(e._layer), str(e.get("_package_name", "")))
		list.add_item("%s  ·  %s, %s" % [e.get("name", ""), str(e._kind).trim_suffix("s"), where])


## The entry in row `i` (tests).
func entry_at(i: int) -> Dictionary:
	return shown[i] if i >= 0 and i < shown.size() else {}
