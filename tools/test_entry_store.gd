extends SceneTree
## Headless check of EntryStore and Schema (TASK-21, data side): create / edit / rename /
## duplicate / delete in a world package, read-only source packages and "edit a copy",
## timeline edits during a session as sheet.changed events.
## godot --headless --path . -s tools/test_entry_store.gd

const DIR := "user://test_store"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(DIR + "/packages")
	var root := ProjectSettings.globalize_path(DIR + "/packages")

	# --- A new world package: create, edit, rename, duplicate, delete -------------------
	var world := EntryStore.create_world(root, "Sunken Coast")
	_check(world != null and world.layer == "world" and world.id == "sunken-coast", "world package created")
	_check(not world.is_read_only(), "world packages are editable")
	for kind in ["monsters", "pcs", "npcs", "places", "factions", "items", "maps", "lore", "notes", "features", "spells"]:
		var e := world.create(kind, "Test %s" % kind)
		_check(e.id == "test-%s" % kind and world.has(kind, e.id), "create %s" % kind)
		for f in Schema.fields(kind, e):
			_check(e.has(f.key), "%s blank has '%s'" % [kind, f.key])
	var mira := world.create("npcs", "Mira")
	mira["role"] = "Smith"
	mira["description"] = "Soot to the elbows.\n\n<reveal id=\"r1\" for=\"dm\">Buys stolen iron.</reveal>"
	_check(world.save("npcs", mira) == OK, "save edited NPC")
	var again := EntryStore.open(world.folder)
	_check(again.find("npcs", "mira").role == "Smith", "edit read back from disk")
	_check(not FileAccess.get_file_as_string(world.folder.path_join("npcs.json")).contains("_kind"), "no bookkeeping keys on disk")
	var renamed := again.find("npcs", "mira").duplicate()
	renamed["id"] = "mira-smith"
	again.save("npcs", renamed, "mira")
	_check(again.has("npcs", "mira-smith") and not again.has("npcs", "mira"), "id change replaces, no duplicate")
	var copy := again.duplicate_entry("npcs", "mira-smith")
	_check(copy.name == "Mira (copy)" and copy.id == "mira-copy" and again.has("npcs", "mira-copy"), "duplicate gets a new id (%s)" % copy.get("id"))
	_check(again.create("npcs", "Mira").id == "mira", "ids are reused once free")
	_check(again.create("npcs", "Mira").id == "mira-2", "taken ids get a number")
	_check(again.delete("npcs", "mira-copy") == OK and not EntryStore.open(world.folder).has("npcs", "mira-copy"), "delete")
	_check(int(EntryStore.open(world.folder).manifest.counts.npcs) == again.list("npcs").size(), "package counts kept up to date")
	var raw := FileAccess.get_file_as_string(world.folder.path_join("monsters.json"))
	_check(raw.contains("\"str\": 10") and not raw.contains("10.0"), "whole numbers stay ints")

	# --- Source packages are read-only; edit a copy ----------------------------------------
	var core := EntryStore.open(PackageDB.default_root().path_join("5e-core-rules"))
	_check(core.layer == "source" and core.is_read_only(), "source package is read-only")
	_check(core.save("monsters", {"id": "x", "name": "X"}) == ERR_FILE_NO_PERMISSION, "saving into it is refused")
	var goblin := world.copy_entry(core, "monsters", "goblin")
	_check(goblin.get("name") == "Goblin" and world.has("monsters", "goblin"), "goblin copied into the world")
	_check(goblin.origin == {"layer": "core", "package": "5e-core-rules", "kind": "monsters", "id": "goblin", "version": str(core.manifest.get("version", ""))}, "copy keeps its origin (%s)" % goblin.get("origin"))
	var feature_ids: Array = goblin.get("actions", []) + goblin.get("traits", [])
	_check(not feature_ids.is_empty() and feature_ids.all(func(f: String) -> bool: return world.has("features", f)), "its features came along (%s)" % [feature_ids])
	var second := world.copy_entry(core, "monsters", "goblin")
	_check(second.id == "goblin-2" and second.actions == goblin.actions, "second copy: new id, same shared features")

	# --- Unlocking a (copied) source package -------------------------------------------------
	var src_dir := ProjectSettings.globalize_path(DIR + "/packages/mini-source")
	DirAccess.make_dir_recursive_absolute(src_dir)
	EntryStore._write(src_dir.path_join("package.json"), {"id": "mini-source", "name": "Mini", "kind": "source"})
	var mini := EntryStore.open(src_dir)
	_check(mini.is_read_only(), "a source package starts read-only")
	mini.unlock()
	_check(not EntryStore.open(src_dir).is_read_only(), "unlocked explicitly (kept in package.json)")

	# --- Timeline: prep edits are entity events, session edits sheet.changed ------------------
	var tl_dir := Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var camp := EntryStore.open(tl_dir)
	_check(camp.layer == EntryStore.TIMELINE, "a timeline folder opens as a store")
	var world_file := tl_dir.get_base_dir().get_base_dir().path_join("monsters.json")
	var elog := camp.timeline.events_log
	var chief_before := camp.find("monsters", "goblin-chief").duplicate(true)
	var chief := chief_before.duplicate(true)
	chief["hp"] = 30
	var r := camp.commit("monsters", chief_before, chief, elog)
	_check(r.saved and r.events.is_empty() and EntryStore.open(tl_dir).find("monsters", "goblin-chief").hp == 30, "prep edit saved (entity.edited)")
	_check(elog.events.back().type == "entity.edited" and not FileAccess.file_exists(world_file), "as an event, no world file written")
	elog.start_session(1)
	_check(elog.in_session(), "session running")
	var before := EntryStore.open(tl_dir).find("monsters", "goblin-chief").duplicate(true)
	var after := before.duplicate(true)
	after["hp"] = 12
	after["stats"]["str"] = 16
	after["description"] = "Now missing an ear."
	r = camp.commit("monsters", before, after, elog)
	var types: Array = r.events.map(func(e: Dictionary) -> String: return "%s %s %d>%d" % [e.type, e.data.path, e.data.from, e.data.to])
	_check(r.events.size() == 2, "two sheet.changed events (%s)" % [types])
	_check(types.has("sheet.changed hp 30>12") and types.has("sheet.changed stats.str %d>16" % before.stats.str), "hp and stats.str logged")
	var on_disk := EntryStore.open(tl_dir).find("monsters", "goblin-chief")
	_check(on_disk.hp == 30 and on_disk.stats.str == before.stats.str, "play state not written into the entry")
	_check(on_disk.description == "Now missing an ear.", "the description is an entity edit: saved")
	elog.end_session()
	_check(not elog.in_session(), "session ended")
	_check(EntryStore.diff({"a": 1, "b": {"c": 2}}, {"a": 1.0, "b": {"c": 3}, "d": []}) == [["b.c", 2, 3], ["d", null, []]], "diff walks dicts")

	print("entry store: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
