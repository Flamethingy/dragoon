class_name MapDrop
extends Control
## Covers the map while a compendium entry is dragged and takes the drop: a token on that
## cell (NetTable.drop_token, TASK-34/37). Otherwise it lets every click through to the map.
## While it hovers, a transparent ghost of the token shows where it lands (TASK-45).
## TASK-94: an item, spell or feature dropped on a token joins that creature's lists (the token
## under the mouse lights up; one the dropper may not change refuses it).

var table: NetTable
var _ghosts := {}  ## entry key -> composed token texture
var _lit: Sprite2D  ## the token an item etc. would go to


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		mouse_filter = Control.MOUSE_FILTER_STOP if EntryDrag.is_entry(get_viewport().gui_get_drag_data()) else Control.MOUSE_FILTER_IGNORE
	elif what == NOTIFICATION_DRAG_END:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hide_ghost()
		_light(null)
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hide_ghost()
		_light(null)


## The creature whose token is under `at` (this control's position), "" for none.
func token_ref_at(at: Vector2) -> String:
	if table == null or table.grid == null:
		return ""
	var screen := get_global_transform_with_canvas() * at
	var t := table.grid._token_under(table.grid.get_canvas_transform().affine_inverse() * screen)
	return str(t.get_meta("entity")) if t != null else ""


func _light(t: Sprite2D) -> void:
	if _lit == t:
		return
	if _lit != null and is_instance_valid(_lit):
		_lit.modulate = Color.WHITE
	_lit = t
	if _lit != null:
		_lit.modulate = Color(1.35, 1.25, 0.9)


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var dropped := EntryDrag.entry_of(data)
	if table != null and EntryDrag.SHEET_LISTS.has(str(dropped.get("_kind", ""))):  # TASK-94: onto a token
		var ref := token_ref_at(at)
		var ok_on := ref != "" and table.can_take_entry(ref, dropped)
		_light(table.grid.tokens.get(ref) if ok_on else null)
		return ok_on
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
	_light(null)
	var dropped := EntryDrag.entry_of(data)
	if EntryDrag.SHEET_LISTS.has(str(dropped.get("_kind", ""))):
		table.add_entry_to(token_ref_at(at_position), dropped)
		return
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
