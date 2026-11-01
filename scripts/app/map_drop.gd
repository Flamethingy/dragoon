class_name MapDrop
extends Control
## Covers the map while a compendium entry is dragged and takes the drop: a token on that
## cell (NetTable.drop_token, TASK-34/37). Otherwise it lets every click through to the map.
## While it hovers, a transparent ghost of the token shows where it lands (TASK-45).

var table: NetTable
var _ghosts := {}  ## entry key -> composed token texture


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		mouse_filter = Control.MOUSE_FILTER_STOP if EntryDrag.is_entry(get_viewport().gui_get_drag_data()) else Control.MOUSE_FILTER_IGNORE
	elif what == NOTIFICATION_DRAG_END:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hide_ghost()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hide_ghost()


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var ok := table != null and table.is_dm() and EntryDrag.is_entry(data) \
		and str(EntryDrag.entry_of(data).get("_kind", "")) in Timeline.CREATURES
	if ok and table.grid != null:
		var e := EntryDrag.entry_of(data)
		var cells: float = TokenGrid.SIZE_CELLS.get(str(e.get("size", "medium")).to_lower(), 1.0)
		var screen := get_global_transform_with_canvas() * at
		table.grid.plans.show_spawn(ghost_texture(e), cells, table.grid.cell_at_screen(screen))
	return ok


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_hide_ghost()
	var screen := get_global_transform_with_canvas() * at_position
	table.drop_token(EntryDrag.entry_of(data), table.grid.cell_at_screen(screen))


## The token an entry would get (its picture in its ring), for the ghost.
func ghost_texture(e: Dictionary) -> Texture2D:
	var key := "%s/%s|%s" % [e.get("_package", ""), e.get("id", ""), JSON.stringify(e.get("token_style", {}))]
	if not _ghosts.has(key):
		var picture: Texture2D = null
		var path := TokenArt.picture_path(e)
		if path != "" and FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null:
				picture = ImageTexture.create_from_image(img)
		_ghosts[key] = TokenArt.compose(picture, e.get("token_style"), str(e.get("_kind", "")))
	return _ghosts[key]


func _hide_ghost() -> void:
	if table != null and table.grid != null and table.grid.plans != null:
		table.grid.plans.hide_spawn()
