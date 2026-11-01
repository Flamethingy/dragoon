extends SceneTree
## Headless check of PackageManager (export, inspect, install with conflicts, disable,
## remove) on a temporary packages folder; the real data/packages is only read.
## godot --headless --path . -s tools/test_packages.gd

const SOURCE := "avaricium"  ## a small package with assets
const TEMP := "user://test_packages"

var _failed := 0


func _init() -> void:
	var temp := ProjectSettings.globalize_path(TEMP)
	PackageManager._delete_tree(temp)
	DirAccess.make_dir_recursive_absolute(temp.path_join("packages"))
	var real := PackageManager.new()
	var mgr := PackageManager.new(temp.path_join("packages"))

	# Export: one file with manifest, kinds and assets.
	var file := temp.path_join("%s.%s" % [SOURCE, PackageManager.EXTENSION])
	_check(real.export_package(SOURCE, file) == OK, "export writes a file")
	var info := mgr.inspect(file)
	_check(info.ok, "exported file inspects OK (%s)" % info.error)
	var src_files := PackageManager._files_under(real.root.path_join(SOURCE), "")
	var zipped := Array(info.files).filter(func(f: String) -> bool: return not f.ends_with("/"))
	_check(zipped.size() == src_files.size(), "all %d files in the export (got %d)" % [src_files.size(), zipped.size()])
	_check(Array(info.files).any(func(f: String) -> bool: return f.contains("/assets/")), "assets included")
	_check(info.manifest.get("counts") is Dictionary, "manifest counts readable before install")
	_check(not info.exists, "not installed yet")

	# Install, then the same id again: cancel / keep both / replace.
	var r := mgr.install(file)
	_check(r.ok and r.id == SOURCE, "installed (%s)" % r.error)
	_check(mgr.inspect(file).exists, "now it exists")
	r = mgr.install(file, PackageManager.Conflict.CANCEL)
	_check(not r.ok, "cancel leaves it alone")
	r = mgr.install(file, PackageManager.Conflict.KEEP_BOTH)
	_check(r.ok and r.id == SOURCE + "-2", "keep both installs as %s-2 (got %s)" % [SOURCE, r.id])
	var second: Variant = JSON.parse_string(FileAccess.get_file_as_string(mgr.root.path_join(SOURCE + "-2/package.json")))
	_check(second.id == SOURCE + "-2" and str(second.name).ends_with("(2)"), "keep both rewrites id and name")
	r = mgr.install(file, PackageManager.Conflict.REPLACE)
	_check(r.ok and r.id == SOURCE, "replace works")
	_check(DirAccess.get_directories_at(temp.path_join("removed")).size() == 1, "replaced copy kept in removed/")

	# The compendium loads them; disabled ones are skipped.
	var db := PackageDB.new()
	db.load_now(mgr.root)
	var both := db.count()
	_check(db.packages.size() == 2, "both packages load")
	mgr.set_enabled(SOURCE + "-2", false)
	db.load_now(mgr.root)
	_check(db.packages.size() == 1 and db.count() * 2 == both, "disabled package skipped")
	_check(mgr.list().size() == 2 and not mgr.list().filter(func(m: Dictionary) -> bool: return m._folder == SOURCE + "-2")[0]._enabled, "list shows it as disabled")
	mgr.set_enabled(SOURCE + "-2", true)

	# Remove moves it out of the packages folder.
	_check(mgr.remove(SOURCE + "-2") == OK, "remove")
	_check(not DirAccess.dir_exists_absolute(mgr.root.path_join(SOURCE + "-2")), "removed from packages")
	_check(DirAccess.get_directories_at(temp.path_join("removed")).size() == 2, "removed copy kept")

	# Bad files are refused with a reason.
	var bad := temp.path_join("bad.%s" % PackageManager.EXTENSION)
	var zip := ZIPPacker.new()
	zip.open(bad)
	zip.start_file("x/package.json")
	zip.write_file(JSON.stringify({"format": "dragoon-package", "format_version": 99, "id": "x"}).to_utf8_buffer())
	zip.close_file()
	zip.close()
	info = mgr.inspect(bad)
	_check(not info.ok and info.error.contains("version"), "newer format version refused (%s)" % info.error)
	_check(not mgr.inspect(temp.path_join("nope.zip")).ok, "missing file refused")

	print("packages: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
