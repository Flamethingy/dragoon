class_name KindMigration
extends RefCounted
## Characters and Creatures (TASK-43, Nico 2026-11-01): `monsters` are now `creatures`, PCs
## and NPCs are one kind, `characters` (with `owners`: the players who control one; the
## DM controls everything). Old folders are converted the first time they are opened:
## - monsters.json -> creatures.json; pcs.json + npcs.json -> characters.json (a PC's
##   `player` becomes `owners: [player]`; an NPC whose id a PC already has gets "-npc")
## - refs in every .json / .jsonl below the folder (entries, maps, timeline.json, events,
##   encounters): "monsters/x" -> "creatures/x", "pcs/x" and "npcs/x" -> "characters/x",
##   also inside "pkg/monsters/x", "core:pkg/monsters/x" and [[monsters/x]] links
## - the replaced files are kept next to it as *.bak; a `.kinds2` file marks it as done.

const MARKER := ".kinds2"
const KIND_RENAMES := {"monsters": "creatures", "pcs": "characters", "npcs": "characters"}

static var _done := {}  ## folders checked in this run


## Converts `folder` (a package, world or timeline) once. Cheap when already done.
static func ensure(folder: String) -> void:
	if folder == "" or _done.has(folder):
		return
	_done[folder] = true
	if not DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder.path_join(MARKER)):
		return
	if not needs(folder):
		_mark(folder)
		return
	migrate(folder)


## True if something in the folder still uses the old kinds.
static func needs(folder: String) -> bool:
	for old: String in KIND_RENAMES:
		if FileAccess.file_exists(folder.path_join(old + ".json")):
			return true
	for path in _json_files(folder):
		var text := FileAccess.get_file_as_string(path)
		if _rewrite(text, {}) != text:
			return true
	return false


## Converts the folder (and everything below it). Returns the ids renamed on the way
## ("npcs/x" -> "characters/x-npc").
static func migrate(folder: String) -> Dictionary:
	var renamed := {}
	_merge_kind_files(folder, renamed)
	for path in _json_files(folder):
		var text := FileAccess.get_file_as_string(path)
		var out := _rewrite(text, renamed)
		if path.get_file() == "package.json":
			for old: String in KIND_RENAMES:
				out = out.replace('"%s":' % old, '"%s":' % KIND_RENAMES[old])
		if out != text:
			_backup(path)
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(out)
	for dir in _dirs(folder):
		_mark(dir)
	return renamed


static func _merge_kind_files(folder: String, renamed: Dictionary) -> void:
	for sub in _dirs(folder):
		var creatures := _take(sub.path_join("monsters.json"))
		if not creatures.is_empty():
			var have := _read_list(sub.path_join("creatures.json"))
			have.append_array(creatures)
			_write(sub.path_join("creatures.json"), have)
		var pcs := _take(sub.path_join("pcs.json"))
		var npcs := _take(sub.path_join("npcs.json"))
		if pcs.is_empty() and npcs.is_empty():
			continue
		var chars := _read_list(sub.path_join("characters.json"))
		var ids := {}
		for c: Variant in chars:
			if c is Dictionary:
				ids[str(c.get("id", ""))] = true
		for pc: Variant in pcs:
			if not pc is Dictionary:
				continue
			var player := str(pc.get("player", ""))
			if not pc.has("owners"):
				pc["owners"] = [player] if player != "" else []
			pc.erase("player")
			ids[str(pc.get("id", ""))] = true
			chars.append(pc)
		for npc: Variant in npcs:
			if not npc is Dictionary:
				continue
			var id := str(npc.get("id", ""))
			if ids.has(id):
				var new_id := id + "-npc"
				renamed["npcs/" + id] = "characters/" + new_id
				npc["id"] = new_id
				id = new_id
			ids[id] = true
			chars.append(npc)
		_write(sub.path_join("characters.json"), chars)


## The old refs in a text replaced (`renamed`: refs whose id changed too).
static func _rewrite(text: String, renamed: Dictionary) -> String:
	var out := text
	for old_ref: String in renamed:
		for pre in ['"', "/", ":", "[["]:
			out = out.replace(pre + old_ref + '"', pre + str(renamed[old_ref]) + '"')
			out = out.replace(pre + old_ref + "]", pre + str(renamed[old_ref]) + "]")
			out = out.replace(pre + old_ref + "|", pre + str(renamed[old_ref]) + "|")
	for old: String in KIND_RENAMES:
		var new: String = KIND_RENAMES[old]
		for pre in ['"', "/", ":", "[["]:
			out = out.replace(pre + old + "/", pre + new + "/")
		out = out.replace('"kind": "%s"' % old, '"kind": "%s"' % new)
		out = out.replace('"_kind": "%s"' % old, '"_kind": "%s"' % new)
	return out


## Reads a kind file and moves it aside (.bak); [] if there is none.
static func _take(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var list := _read_list(path)
	_backup(path)
	DirAccess.remove_absolute(path)
	return list


static func _read_list(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Array else []


static func _write(path: String, list: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(list, "\t"))


static func _backup(path: String) -> void:
	if not FileAccess.file_exists(path + ".bak"):
		DirAccess.copy_absolute(path, path + ".bak")


static func _mark(folder: String) -> void:
	var f := FileAccess.open(folder.path_join(MARKER), FileAccess.WRITE)
	if f != null:
		f.store_string("characters + creatures (TASK-43)\n")


## The folder and every folder below it (not assets, not hidden ones).
static func _dirs(folder: String) -> PackedStringArray:
	var out := PackedStringArray([folder])
	for d in DirAccess.get_directories_at(folder):
		if d.begins_with(".") or d == "assets":
			continue
		out.append_array(_dirs(folder.path_join(d)))
	return out


static func _json_files(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for dir in _dirs(folder):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json") or f.ends_with(".jsonl"):
				out.append(dir.path_join(f))
	return out
