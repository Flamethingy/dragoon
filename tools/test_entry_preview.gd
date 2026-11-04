extends SceneTree
## Headless check of the drag preview (TASK-93): dragging a card shows a transparent copy of it
## under the mouse; over the map a creature's card makes way for the token ghost and comes back
## off the map; a spell keeps its card over the map; dropping still places the token.
## godot --headless --path . -s tools/test_entry_preview.gd

const PORT := 47843
const DIR := "user://test_entry_preview"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	root.size = Vector2i(1280, 720)  # headless starts with a tiny window
	var goblin := {"_kind": "creatures", "id": "goblin", "name": "Goblin", "size": "small"}
	var bolt := {"_kind": "spells", "id": "fire-bolt", "name": "Fire Bolt"}

	# the preview itself: a card, see-through, the mouse at its middle
	var p := EntryDrag.preview(goblin)
	var card := p.get_node_or_null("Card") as EntryCard
	_check(card != null and card.entry == goblin, "the preview is the entry's card")
	_check(is_equal_approx(p.modulate.a, EntryDrag.PREVIEW_ALPHA) and p.modulate.a < 0.7, "and see-through")
	_check(card != null and card.position == -EntryCard.SIZE * 0.5 and card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "centred on the mouse, not in the way")
	_check(EntryDrag.preview_node() == p, "remembered while dragging")
	p.free()
	_check(EntryDrag.preview_node() == null, "gone with the drag")

	# a real drag from a card in a book
	var book := EntryCard.new()
	book.setup(goblin)
	book.position = Vector2(40, 40)
	root.add_child(book)
	await process_frame
	root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	var at := book.get_global_rect().get_center()
	_motion(at)
	await process_frame
	_mouse(at, true)
	for step in 6:
		await process_frame
		_motion(at + Vector2(12 * (step + 1), 0))
	await process_frame
	_check(root.gui_is_dragging(), "a real drag started")
	var shown := EntryDrag.preview_node()
	_check(shown != null and shown.visible and shown.get_node_or_null("Card") is EntryCard, "a card follows the mouse")
	# (the map comes after the drag has started: its grid takes the mouse)
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	var dm := NetTable.new()
	dm.name = "Table"
	dm.timeline_dir = TIMELINE
	dm.cache_dir = DIR.path_join("cache")
	dm.auto_ui = false
	holder.add_child(dm)
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	await process_frame

	# over the map: the token ghost instead of the card
	var drop := MapDrop.new()
	drop.table = dm
	holder.add_child(drop)
	drop.size = Vector2(1280, 720)
	await process_frame
	var spot := _free_spot(drop)
	var data := EntryDrag.data(goblin)
	_check(drop._can_drop_data(spot, data), "a creature may be dropped on the map")
	_check(shown != null and not shown.visible, "over the map: the card hides")
	_check(dm.grid.plans.spawn_visible(), "the token ghost shows")
	drop._notification(Control.NOTIFICATION_MOUSE_EXIT)
	_check(shown != null and shown.visible, "back off the map: the card again")
	_check(not drop._can_drop_data(spot, EntryDrag.data(bolt)) and shown != null and shown.visible, "a spell keeps its card over the map")

	# dropping still places the token
	var before := dm.event_log.events.size()
	var borin := EntryDrag.data({"_kind": "characters", "id": "borin", "name": "Borin", "_layer": "world"})
	_check(drop._can_drop_data(spot, borin), "a character may be dropped too")
	drop._drop_data(spot, borin)
	await process_frame
	_check(dm.event_log.events.size() > before, "dropped: a token on the map")
	_check(shown != null and shown.visible, "and the card isn't left hidden")
	_mouse(at, false)
	await process_frame

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("entry preview: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _free_spot(drop: MapDrop) -> Vector2:
	for x in range(300, 1260, 40):
		for y in range(60, 700, 40):
			if drop.token_ref_at(Vector2(x, y)) == "":
				return Vector2(x, y)
	return Vector2(600, 400)


func _mouse(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(ev)


func _motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.relative = Vector2(12, 0)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
