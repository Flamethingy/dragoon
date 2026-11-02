extends SceneTree
## Splits class and subclass pages into feature entries (TASK-69, ClassFeatures.split) and adds
## them to each package's features.json (kind "class"; earlier split ones are replaced, hand
## edited ones, marked `edited`, kept). Reports per class how many it found and which have no
## level yet (level 0: the DM sets it in the editor). Without --write it only reports.
## godot --headless --path . -s tools/split_class_features.gd -- [packages dir] [--write] [--verbose]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := "res://data/packages"
	for a in args:
		if not a.begins_with("--"):
			dir = a
	var write := "--write" in args
	var verbose := "--verbose" in args
	var abs_dir := ProjectSettings.globalize_path(dir) if dir.begins_with("res://") or dir.begins_with("user://") else dir
	var total := 0
	var unknown := 0
	for pkg in DirAccess.get_directories_at(abs_dir):
		var base := abs_dir.path_join(pkg)
		var classes := _read(base.path_join("classes.json"))
		var subclasses := _read(base.path_join("subclasses.json"))
		if classes.is_empty() and subclasses.is_empty():
			continue
		var made := []
		var class_ids := {}
		for c: Variant in classes:
			if c is Dictionary:
				class_ids[ClassFeatures.slug(str(c.get("name", "")))] = str(c.id)
				made.append_array(ClassFeatures.split(c, str(c.id)))
		for s: Variant in subclasses:
			if s is Dictionary:
				var cname := ClassFeatures.slug(str(s.get("class", "")).get_file())
				made.append_array(ClassFeatures.split(s, str(class_ids.get(cname, cname)), str(s.id)))
		if made.is_empty():
			continue
		var by_class := {}
		for f: Dictionary in made:
			var key := "%s%s" % [f["class"], "/" + str(f.subclass) if str(f.subclass) != "" else ""]
			if not by_class.has(key):
				by_class[key] = [0, []]
			by_class[key][0] += 1
			if int(f.level) == 0:
				(by_class[key][1] as Array).append(str(f.name))
				unknown += 1
		total += made.size()
		print("%s: %d features" % [pkg, made.size()])
		if verbose:
			for key: String in by_class:
				print("  %-40s %3d%s" % [key, int(by_class[key][0]), "  no level: " + ", ".join(by_class[key][1]) if not (by_class[key][1] as Array).is_empty() else ""])
		if write:
			var file := base.path_join("features.json")
			var existing := _read(file)
			var keep := {}
			for f: Variant in existing:
				if f is Dictionary and str(f.get("kind", "")) == "class" and bool(f.get("edited", false)):
					keep[str(f.id)] = true
			var out := existing.filter(func(f: Variant) -> bool: return not (f is Dictionary and str(f.get("kind", "")) == "class" and not keep.has(str(f.id))))
			var ids := {}
			for f: Variant in out:
				if f is Dictionary:
					ids[str(f.id)] = true
			for f: Dictionary in made:
				if not ids.has(str(f.id)):
					f["draft"] = false
					out.append(f)
			var w := FileAccess.open(file, FileAccess.WRITE)
			w.store_string(JSON.stringify(EntryStore.whole_numbers(out), " ", false))
			w.close()
	print("%d class features, %d without a level (%s)" % [total, unknown, "written" if write else "dry run (--write to save)"])
	quit(0)


func _read(file: String) -> Array:
	if not FileAccess.file_exists(file):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return data if data is Array else []
