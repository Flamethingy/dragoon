extends SceneTree
## Headless check of KindMigration (TASK-43): an old folder with monsters.json, pcs.json and
## npcs.json becomes creatures.json + characters.json, PCs get `owners`, clashing NPC ids
## get "-npc", refs in entries and events are rewritten, backups kept, done only once.
## godot --headless --path . -s tools/test_kind_migration.gd

const DIR := "user://test_kind_migration"

var _failed := 0


func _init() -> void:
	var root := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(root)
	DirAccess.make_dir_recursive_absolute(root.path_join("timelines/t1"))
	_put(root.path_join("package.json"), '{"id": "old", "counts": {"monsters": 1, "pcs": 1, "npcs": 2}}')
	_put(root.path_join("monsters.json"), '[{"id": "goblin", "name": "Goblin", "traits": ["nimble"]}]')
	_put(root.path_join("pcs.json"), '[{"id": "aria", "name": "Aria", "player": "ann", "classes": []}]')
	_put(root.path_join("npcs.json"), '[{"id": "mira", "name": "Mira", "description": "Knows [[monsters/goblin]]."}, {"id": "aria", "name": "Aria the Elder"}]')
	_put(root.path_join("places.json"), '[{"id": "camp", "name": "Camp", "residents": ["npcs/mira", "pcs/aria"]}]')
	_put(root.path_join("timelines/t1/events.jsonl"), '{"entity":"monsters/goblin","type":"token.moved"}\n{"entity":"npcs/aria","type":"note"}\n{"data":{"origin":{"kind": "monsters"}},"entity":"core:pkg/monsters/wolf"}\n')

	_check(KindMigration.needs(root), "an old folder needs the migration")
	KindMigration.ensure(root)
	_check(not FileAccess.file_exists(root.path_join("monsters.json")) and not FileAccess.file_exists(root.path_join("pcs.json")) and not FileAccess.file_exists(root.path_join("npcs.json")), "old kind files gone")
	_check(FileAccess.file_exists(root.path_join("npcs.json.bak")) and FileAccess.file_exists(root.path_join("timelines/t1/events.jsonl.bak")), "backups kept")
	var creatures: Array = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("creatures.json")))
	_check(creatures.size() == 1 and creatures[0].id == "goblin", "monsters are creatures")
	var chars: Array = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("characters.json")))
	var by_id := {}
	for c: Dictionary in chars:
		by_id[c.id] = c
	_check(by_id.size() == 3 and by_id.has("aria") and by_id.has("mira") and by_id.has("aria-npc"), "PCs and NPCs are characters (%s)" % [by_id.keys()])
	_check(by_id.aria.owners == ["ann"] and not by_id.aria.has("player"), "a PC's player becomes its owner")
	_check(str(by_id.mira.description).contains("[[creatures/goblin]]"), "links rewritten")
	var places := FileAccess.get_file_as_string(root.path_join("places.json"))
	_check(places.contains('"characters/mira"') and places.contains('"characters/aria"'), "refs rewritten")
	var events := FileAccess.get_file_as_string(root.path_join("timelines/t1/events.jsonl"))
	_check(events.contains('"creatures/goblin"') and events.contains('"characters/aria-npc"') and events.contains("core:pkg/creatures/wolf") and events.contains('"kind": "creatures"'), "events rewritten (%s)" % events)
	var manifest := FileAccess.get_file_as_string(root.path_join("package.json"))
	_check(manifest.contains('"creatures"') and manifest.contains('"characters"') and not manifest.contains("monsters"), "package counts renamed")
	_check(FileAccess.file_exists(root.path_join(KindMigration.MARKER)) and FileAccess.file_exists(root.path_join("timelines/t1/" + KindMigration.MARKER)), "marked as done")
	_check(not KindMigration.needs(root), "nothing left to do")

	# a second open does not touch the files again
	_put(root.path_join("monsters.json"), '[{"id": "late"}]')
	KindMigration._done.clear()
	KindMigration.ensure(root)
	_check(FileAccess.file_exists(root.path_join("monsters.json")), "the marker stops a second run")

	# EntryStore opens old folders converted
	var old2 := root.path_join("old2")
	DirAccess.make_dir_recursive_absolute(old2)
	_put(old2.path_join("package.json"), '{"id": "old2", "name": "Old", "layer": "world"}')
	_put(old2.path_join("pcs.json"), '[{"id": "bo", "name": "Bo", "player": "bob"}]')
	var store := EntryStore.open(old2)
	_check(store != null and store.has("characters", "bo") and Timeline.owners_of(store.find("characters", "bo")) == ["bob"], "EntryStore.open converts")
	_check(Timeline.owners_of({"player": "x"}) == ["x"] and Timeline.owners_of({"owners": ["a", ""]}) == ["a"], "owners_of reads old and new")

	PackageManager._delete_tree(root)
	print("kind migration: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
