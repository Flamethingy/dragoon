extends SceneTree
## Fills the `effects` of spells, features and items in packages from their text (TASK-65, the
## regex parser: Effects.parse) and reports the coverage per kind. Entries that already have
## effects (hand edited, the AI pass) are kept. Without --write it only reports.
## godot --headless --path . -s tools/parse_effects.gd -- [packages dir] [--write] [--strip]
##   --strip: removes the parsed effects again (entries whose effects are marked "parsed").

const KINDS := ["spells", "features", "items"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := "res://data/packages"
	for a in args:
		if not a.begins_with("--"):
			dir = a
	var write := "--write" in args
	var strip := "--strip" in args
	var totals := {}
	for kind: String in KINDS:
		totals[kind] = {"total": 0, "with": 0, "attack": 0, "save": 0, "heal": 0, "area": 0, "scaling": 0, "kept": 0}
	var abs_dir := ProjectSettings.globalize_path(dir) if dir.begins_with("res://") or dir.begins_with("user://") else dir
	for pkg in DirAccess.get_directories_at(abs_dir):
		for kind: String in KINDS:
			var file := abs_dir.path_join(pkg).path_join(kind + ".json")
			if not FileAccess.file_exists(file):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
			if not data is Array:
				continue
			var changed := false
			for e: Variant in data:
				if not e is Dictionary:
					continue
				var entry: Dictionary = e
				if strip:
					if bool(entry.get("effects_parsed", false)):
						entry.erase("effects")
						entry.erase("effects_parsed")
						changed = true
					continue
				if entry.get("effects") is Array and not (entry.effects as Array).is_empty():
					totals[kind].kept += 1
					continue
				var fx := Effects.parse(entry)
				if not fx.is_empty():
					entry["effects"] = fx
					entry["effects_parsed"] = true  # the parser's (an editor or the AI pass may replace them)
					changed = true
			var cov := Effects.coverage(data)
			for k: String in cov:
				totals[kind][k] = int(totals[kind].get(k, 0)) + int(cov[k])
			if write and changed:
				var f := FileAccess.open(file, FileAccess.WRITE)
				f.store_string(JSON.stringify(EntryStore.whole_numbers(data), " ", false))
				f.close()
	for kind: String in KINDS:
		var t: Dictionary = totals[kind]
		print("%-9s %6d entries, %6d with effects (%4.1f%%): attack %d, save %d, heal %d, area %d, scaling %d%s" % [kind, int(t.total), int(t.with),
			100.0 * int(t.with) / maxi(int(t.total), 1), int(t.attack), int(t.save), int(t.heal), int(t.area), int(t.scaling),
			", %d kept as they were" % int(t.kept) if int(t.kept) > 0 else ""])
	print("written" if write else ("stripped" if strip else "dry run (--write to save)"))
	quit(0)
