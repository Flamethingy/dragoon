extends SceneTree
## Merges a job folder written by the real tools/import_agent.py into a scratch package (TASK-27)
## and checks what arrives: drafts with origin, source page, picture and their features.
## godot --headless --path . -s tools/check_real_import.gd -- <job dir>

const DIR := "user://check_real_import"


func _init() -> void:
	var src: String = OS.get_cmdline_user_args()[0]
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	var pkg_root := base.path_join("data/packages")
	DirAccess.make_dir_recursive_absolute(pkg_root)
	Worlds.copy_tree(src, base.path_join("data/imports/job1"))
	var jobs := ImportJobs.new(pkg_root)
	var r := jobs.merge("job1")
	print("merge: ", r)
	var failed := 0
	var store := EntryStore.open(pkg_root.path_join(str(r.get("package", ""))))
	for kind in ["creatures", "spells", "items", "features", "tables"]:
		var list := store.list(kind)
		var drafts := list.filter(func(e: Dictionary) -> bool: return EntryStore.is_draft(e))
		print("%s: %d (%d drafts)" % [kind, list.size(), drafts.size()])
		if drafts.size() != list.size():
			failed += 1
		for e: Dictionary in list:
			if kind in ["creatures", "spells", "items"]:
				var pic := str(e.get("image", ""))
				var page := str(e.get("source_page", ""))
				var ok := (pic == "" or FileAccess.file_exists(store.folder.path_join(pic))) \
					and (page == "" or FileAccess.file_exists(store.folder.path_join(page))) and e.has("origin")
				if not ok:
					failed += 1
					printerr("FAIL: ", kind, "/", e.id, " image=", pic, " page=", page)
			if kind == "creatures":
				for f: String in e.get("actions", []):
					if store.find("features", f).is_empty():
						failed += 1
						printerr("FAIL: missing feature ", f)
	print("real import: %s" % ("all good" if failed == 0 else "%d failed" % failed))
	quit(1 if failed > 0 else 0)
