extends SceneTree
## Headless check of the panels around the table (TASK-37): docking left / right / bottom as
## tabs, moving between areas, own windows (closing docks back), hiding, the free middle for
## the map, and the layout kept in a file and restored; plus the drag targets' rules
## (EntryDrag: sheet lists, note links).
## godot --headless --path . -s tools/test_dock.gd

const FILE := "user://test_dock_layout.json"

var _failed := 0


func _init() -> void:
	Dock.layout_file = FILE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	root.add_child(screen)
	var host := Control.new()
	host.size = Vector2(1600, 950)
	screen.add_child(host)

	var dock := Dock.new()
	host.add_child(dock)
	await process_frame
	for id: String in ["a", "b", "c", "d"]:
		var l := Label.new()
		l.text = id
		dock.add_panel(id, id.to_upper(), l, "right" if id != "c" else "bottom")
	_check(not dock.is_shown("a") and dock.free_rect().size.x >= 1590, "registered panels start hidden, the map has the room")

	dock.show_panel("a")
	dock.show_panel("b")
	dock.show_panel("c")
	await process_frame
	var right: TabContainer = dock.areas.right
	_check(dock.place_of("a") == "right" and dock.place_of("b") == "right" and right.get_tab_count() == 2, "two panels as tabs on the right")
	_check(right.current_tab == right.get_tab_idx_from_control(dock.panels.b.holder) and right.get_tab_title(0) == "A", "the last shown is in front, tabs have titles")
	_check(dock.place_of("c") == "bottom", "the bottom area")
	var free := dock.free_rect()
	_check(free.end.x < 1600 - 200 and free.end.y < 950 - 150 and free.position.x == 0, "the free middle shrinks for the right and bottom areas (%s)" % free)

	dock.dock("b", "left")
	await process_frame
	_check(dock.place_of("b") == "left" and right.get_tab_count() == 1 and dock.free_rect().position.x > 200, "moved to the left")
	_check(dock.areas.left.tabs_rearrange_group == right.tabs_rearrange_group and right.drag_to_rearrange_enabled, "tabs can be dragged between areas")

	var w := dock.detach("a")
	await process_frame
	_check(w != null and dock.place_of("a") == "window" and w.force_native and (dock.panels.a.holder as Node).get_parent() == w, "own OS window")
	_check(not (dock.areas.right.get_parent().get_parent() as Control).visible, "an empty area is hidden")
	w.position = Vector2i(120, 140)
	w.size = Vector2i(700, 500)
	w.close_requested.emit()
	await process_frame
	_check(dock.place_of("a") == "right", "closing the window docks it back")
	_check(dock.panels.a.rect == Rect2i(120, 140, 700, 500), "the window's rectangle is kept")

	dock.hide_panel("c")
	_check(not dock.is_shown("c"), "hidden")
	dock.show_panel("c")
	_check(dock.place_of("c") == "bottom", "shown again where it was")
	dock.detach("d")
	dock.sizes.left = 512.0
	_check(dock.save_layout() == OK, "layout saved")
	var saved := Dock.load_layout()
	_check(saved.panels.d.place == "window" and saved.panels.b.place == "left" and bool(saved.panels.c.open) and float(saved.sizes.left) == 512.0, "places, open panels and sizes in the file")

	# --- The next start: everything comes back ---------------------------------------------
	var again := Dock.new()
	host.add_child(again)
	await process_frame
	for id: String in ["a", "b", "c", "d"]:
		again.add_panel(id, id.to_upper(), Label.new(), "right")
	again.restore_open()
	await process_frame
	_check(again.place_of("a") == "right" and again.place_of("b") == "left" and again.place_of("c") == "bottom" and again.place_of("d") == "window", "layout restored (%s %s %s %s)" % [again.place_of("a"), again.place_of("b"), again.place_of("c"), again.place_of("d")])
	_check(float(again.sizes.left) == 512.0, "area sizes restored")
	_check(again.panels.a.rect == Rect2i(120, 140, 700, 500), "window rectangles restored")
	again.hide_all()
	_check(not again.panels.keys().any(func(id: String) -> bool: return again.is_shown(id)), "leaving puts every panel away")
	_check(bool(Dock.load_layout().panels.d.open), "...but remembers them as open")
	dock.hide_all()

	# --- Drag rules -----------------------------------------------------------------------------
	var potion := {"_kind": "items", "id": "potion", "name": "Potion"}
	var sheet := {"inventory": [{"item": "items/rope", "qty": 1}], "spells": ["spells/light"]}
	var c1 := EntryDrag.sheet_change(sheet, potion)
	_check(c1[0] == "inventory" and (c1[1] as Array).size() == 2 and int(c1[1][1].qty) == 1, "an item joins the inventory")
	sheet.inventory = c1[1]
	var c2 := EntryDrag.sheet_change(sheet, potion)
	_check((c2[1] as Array).size() == 2 and int(c2[1][1].qty) == 2, "the same item again: more of it")
	_check(EntryDrag.sheet_change(sheet, {"_kind": "spells", "id": "light"}).is_empty(), "a known spell is not added twice")
	_check(EntryDrag.sheet_change(sheet, {"_kind": "spells", "id": "shield"})[1] == ["spells/light", "spells/shield"], "a new spell joins the spells")
	_check(EntryDrag.sheet_change(sheet, {"_kind": "creatures", "id": "goblin"}).is_empty(), "a monster is not for the sheet")
	_check(EntryDrag.link(potion) == "[[items/potion|Potion]]", "a note gets a link")
	_check(EntryDrag.is_entry(EntryDrag.data(potion)) and EntryDrag.ref_of(EntryDrag.data(potion)) == "items/potion" and not EntryDrag.is_entry({"type": "x"}), "drag data")

	print("dock: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
