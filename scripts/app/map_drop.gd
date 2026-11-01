class_name MapDrop
extends Control
## Covers the map while a compendium entry is dragged and takes the drop: a token on that
## cell (NetTable.drop_token, TASK-34/37). Otherwise it lets every click through to the map.

var table: NetTable


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		mouse_filter = Control.MOUSE_FILTER_STOP if EntryDrag.is_entry(get_viewport().gui_get_drag_data()) else Control.MOUSE_FILTER_IGNORE
	elif what == NOTIFICATION_DRAG_END:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return table != null and table.is_dm() and EntryDrag.is_entry(data) \
		and str(EntryDrag.entry_of(data).get("_kind", "")) in Timeline.CREATURES


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var screen := get_global_transform_with_canvas() * at_position
	table.drop_token(EntryDrag.entry_of(data), table.grid.cell_at_screen(screen))
