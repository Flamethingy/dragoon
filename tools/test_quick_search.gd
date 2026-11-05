extends SceneTree
## Headless check of the quick search (TASK-104): prefixes, fuzzy scores, grouped results,
## the popup (Ctrl+K, typing, arrow keys, Enter opens, Esc closes, recent searches) and what a
## player may find (no drafts, no hidden names; over the network from the host).
## godot --headless --path . -s tools/test_quick_search.gd

const PORT := 47791
const ADDRESS := "127.0.0.1:47791"
const DIR := "user://test_quick_search"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	QuickSearch.recent_file = "user://test_quick_search.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(QuickSearch.recent_file))
	# --- Matching --------------------------------------------------------------------------------
	_check(QuickSearch.parse("s: Fire Bolt") == {"kind": "spells", "text": "fire bolt"} and QuickSearch.parse("rope") == {"kind": "", "text": "rope"}
		and QuickSearch.parse("x: rope").kind == "", "prefixes filter the kind")
	_check(QuickSearch.score("fireball", "fireball") > QuickSearch.score("fireball", "fire") and QuickSearch.score("fire bolt", "bolt") > QuickSearch.score("firebolt", "bolt")
		and QuickSearch.score("fireball", "fbl") > 0 and QuickSearch.score("fireball", "xyz") < 0, "exact > start > word > inside > fuzzy")
	var items := [{"name": "Fireball", "kind": "spells", "ref": "spells/fireball"}, {"name": "Fire Bolt", "kind": "spells", "ref": "spells/fire-bolt"},
		{"name": "Fire Giant", "kind": "creatures", "ref": "creatures/fire-giant"}, {"name": "Rope, Hempen", "kind": "items", "ref": "items/rope"},
		{"name": "Flame Tongue", "kind": "items", "ref": "items/flame-tongue"}, {"name": "Wildfire", "kind": "spells", "ref": "spells/wildfire"}]
	var found := QuickSearch.search(items, "fire")
	var names := found.map(func(it: Dictionary) -> String: return it.name)
	_check(names == ["Fireball", "Fire Bolt", "Wildfire", "Fire Giant"], "grouped by kind, best first (%s)" % [names])
	_check(QuickSearch.search(items, "c: fire").map(func(it: Dictionary) -> String: return it.name) == ["Fire Giant"], "c: only creatures")
	_check(QuickSearch.search(items, "fltng").size() == 1, "fuzzy (%s)" % [QuickSearch.search(items, "fltng")])

	# --- The popup -------------------------------------------------------------------------------
	root.size = Vector2i(1280, 720)
	var qs := QuickSearch.new()
	root.add_child(qs)
	await process_frame
	qs._db = PackageDB.new()  # no packages read in the test: the index is set by hand
	qs._db.is_loaded = true
	var fake := items.map(func(it: Dictionary) -> Dictionary:
		var d := it.duplicate()
		d["low"] = str(it.name).to_lower()
		d["source"] = "Test"
		d["entry"] = {"_kind": it.kind, "id": str(it.ref).get_file(), "name": it.name, "description": "A test entry."}
		return d)
	qs._remote = fake  # no table: the index is these
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_K
	key.physical_keycode = KEY_K
	key.ctrl_pressed = true
	qs._input(key)
	_check(qs.visible, "Ctrl+K opens it")
	var opened := []
	qs.opened_entry.connect(func(ref: String) -> void: opened.append(ref))
	qs._field.text = "fire"
	qs._field.text_changed.emit("fire")
	_check(qs._rows.size() == 4 and qs.selected().get("name") == "Fireball", "results while typing, the first selected (%d)" % qs._rows.size())
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_DOWN
	qs._on_key(down)
	_check(qs.selected().get("name") == "Fire Bolt", "arrow down")
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	qs._on_key(enter)
	_check(opened == ["spells/fire-bolt"] and not qs.visible, "Enter opens the entry and closes")
	var win := root.find_child("EntryWindow", true, false) as EntryWindow
	_check(win != null and win.title == "Fire Bolt", "its view in a window")
	_check(not QuickSearch.recent().is_empty() and QuickSearch.recent()[0] == "fire", "the search is remembered (%s)" % [QuickSearch.recent()])
	qs.open()
	_check(qs._list.get_child_count() >= 1 and (qs._list.get_child(0) as Button).text.contains("fire"), "empty field: the recent searches")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	qs._input(esc)
	_check(not qs.visible, "Esc closes it")
	qs.open("rope")
	var dragged: Variant = qs._drag(0)
	_check(EntryDrag.is_entry(dragged) and EntryDrag.ref_of(dragged) == "items/rope", "a result drags like a Book card")
	EntryDrag.carrying = {}

	# --- What a player may find --------------------------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var tl := Timeline.new(ProjectSettings.globalize_path(TIMELINE))
	tl.edit_entry("places", {"id": "secret-cave", "name": "<reveal id=\"r1\" for=\"dm\">Secret Cave</reveal>"})
	tl.edit_entry("places", {"id": "old-mill", "name": "Old Mill"})
	tl.edit_entry("places", {"id": "draft-tower", "name": "Draft Tower", "draft": true})
	await process_frame
	var dm := _table("DM", "dm")
	var ann := _table("Ann", "ann")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	var dm_names := dm.quick_index_for(Reveal.DM).map(func(it: Dictionary) -> String: return it.name)
	_check("Secret Cave" in dm_names and "Old Mill" in dm_names and not "Draft Tower" in dm_names, "the DM finds hidden names, no drafts (%s)" % [dm_names])
	var ann_names := dm.quick_index_for("ann").map(func(it: Dictionary) -> String: return it.name)
	_check("Old Mill" in ann_names and not "Secret Cave" in ann_names and not "Draft Tower" in ann_names and "Aria Windrunner" in ann_names,
		"a player: no hidden names, no drafts (%s)" % [ann_names])
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc != "")
	var got := []
	ann.quick_index_received.connect(func(list: Array) -> void: got.append_array(list))
	ann.request_quick_index()
	await _until(func() -> bool: return not got.is_empty())
	_check(got.any(func(it: Dictionary) -> bool: return it.name == "Old Mill") and not got.any(func(it: Dictionary) -> bool: return it.name == "Secret Cave"), "Ann gets her names from the host")
	var aqs := QuickSearch.new()
	aqs.table = ann
	root.add_child(aqs)
	aqs.set_remote(got)
	_check(QuickSearch.search(aqs.index, "p: mill").size() == 1 and QuickSearch.search(aqs.index, "secret").is_empty(), "and finds only those")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(QuickSearch.recent_file))
	print("quick search: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = false
	t.timeline_dir = TIMELINE
	t.cache_dir = DIR.path_join("cache_" + cache)
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
