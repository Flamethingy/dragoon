class_name PackageManager
extends RefCounted
## Source packages as single files (TASK-16): export a package folder (manifest, JSON per
## kind, assets) as one zip file (EXTENSION), inspect and install such a file, enable or
## disable packages, and remove them. Removing moves the folder to `<root>/../removed/`
## so nothing is lost by a wrong click.

enum Conflict { REPLACE, KEEP_BOTH, CANCEL }

const EXTENSION := "dragoonpkg"
const FORMAT := "dragoon-package"
const FORMAT_VERSION := 1  ## newest version this VTT understands
const SETTINGS := "user://packages.cfg"

var root := ""  ## the packages folder
var worlds_root := ""  ## the worlds folder (timelines.md): data/worlds next to the packages


func _init(packages_root := "") -> void:
	root = packages_root if packages_root != "" else PackageDB.default_root()
	worlds_root = root.get_base_dir().path_join("worlds")


## The folder of package `id`: in the packages folder, else in the worlds folder.
func folder_of(id: String) -> String:
	if id != "" and not DirAccess.dir_exists_absolute(root.path_join(id)) and DirAccess.dir_exists_absolute(worlds_root.path_join(id)):
		return worlds_root.path_join(id)
	return root.path_join(id)


# --- Export --------------------------------------------------------------------------

## Writes the package folder `id` into one file. Returns OK or an error.
func export_package(id: String, file: String) -> Error:
	var folder := folder_of(id)
	if not DirAccess.dir_exists_absolute(folder):
		return ERR_FILE_NOT_FOUND
	var zip := ZIPPacker.new()
	var err := zip.open(file)
	if err != OK:
		return err
	for rel in _files_under(folder, ""):
		var data := FileAccess.get_file_as_bytes(folder.path_join(rel))
		zip.start_file(id + "/" + rel)
		zip.write_file(data)
		zip.close_file()
	return zip.close()


static func _files_under(folder: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(folder.path_join(prefix)):
		out.append(prefix.path_join(f) if prefix != "" else f)
	for d in DirAccess.get_directories_at(folder.path_join(prefix)):
		out.append_array(_files_under(folder, prefix.path_join(d) if prefix != "" else d))
	return out


# --- Import --------------------------------------------------------------------------

## Reads a package file without installing it:
## {ok, error, manifest, top (folder in the zip, may be ""), files, exists (id installed)}.
func inspect(file: String) -> Dictionary:
	var result := {"ok": false, "error": "", "manifest": {}, "top": "", "files": PackedStringArray(), "exists": false}
	var zip := ZIPReader.new()
	if zip.open(file) != OK:
		result.error = "Not a package file (can't open it as a zip)"
		return result
	var files := zip.get_files()
	zip.close()
	result.files = files
	# The manifest is package.json at the top or inside one top folder.
	var manifest_path := ""
	for f in files:
		if f == "package.json" or (f.count("/") == 1 and f.ends_with("/package.json")):
			manifest_path = f
			break
	if manifest_path == "":
		result.error = "No package.json in the file"
		return result
	for f in files:
		if f.begins_with("/") or f.contains("..") or f.contains(":") or f.contains("\\"):
			result.error = "Unsafe path in the file: %s" % f
			return result
	zip.open(file)
	var manifest: Variant = JSON.parse_string(zip.read_file(manifest_path).get_string_from_utf8())
	zip.close()
	if not manifest is Dictionary:
		result.error = "package.json is not valid JSON"
		return result
	if str(manifest.get("format", "")) != FORMAT:
		result.error = "Not a Dragoon package (format \"%s\")" % manifest.get("format", "")
		return result
	var version := int(manifest.get("format_version", 0))
	if version < 1 or version > FORMAT_VERSION:
		result.error = "Package format version %d is not supported (this VTT reads up to %d)" % [version, FORMAT_VERSION]
		return result
	var id := str(manifest.get("id", ""))
	if id == "" or not id.is_valid_filename() or id.contains(" "):
		result.error = "The package has no usable id"
		return result
	result.manifest = manifest
	result.top = manifest_path.get_base_dir()
	result.exists = DirAccess.dir_exists_absolute(folder_of(id))
	result.ok = true
	return result


## Installs a package file. With an existing id: REPLACE it, KEEP_BOTH (the new one gets
## a free id like "<id>-2" and "(2)" in its name) or CANCEL. Returns
## {ok, error, id} (id = the installed package's id).
func install(file: String, conflict := Conflict.CANCEL) -> Dictionary:
	var info := inspect(file)
	if not info.ok:
		return {"ok": false, "error": info.error, "id": ""}
	var manifest: Dictionary = info.manifest
	var id := str(manifest.id)
	if info.exists:
		match conflict:
			Conflict.CANCEL:
				return {"ok": false, "error": "A package with the id \"%s\" is already installed" % id, "id": id}
			Conflict.KEEP_BOTH:
				var n := 2
				while DirAccess.dir_exists_absolute(folder_of("%s-%d" % [id, n])):
					n += 1
				manifest["id"] = "%s-%d" % [id, n]
				manifest["name"] = "%s (%d)" % [manifest.get("name", id), n]
				id = manifest.id
	# Unpack into a temporary folder first, so a broken file never leaves half a package.
	var home := worlds_root if str(manifest.get("kind", "")) == "world" else root
	DirAccess.make_dir_recursive_absolute(home)
	var temp := home.path_join(".installing-" + id)
	_delete_tree(temp)
	DirAccess.make_dir_recursive_absolute(temp)
	var zip := ZIPReader.new()
	zip.open(file)
	var top: String = info.top
	for f: String in info.files:
		if f.ends_with("/"):
			continue
		var rel := f.substr(top.length() + 1) if top != "" else f
		if top != "" and not f.begins_with(top + "/"):
			continue
		var dest := temp.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			zip.close()
			_delete_tree(temp)
			return {"ok": false, "error": "Can't write %s" % dest, "id": id}
		out.store_buffer(zip.read_file(f))
		out.close()
	zip.close()
	# The manifest may have a new id / name (keep both).
	var mf := FileAccess.open(temp.path_join("package.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "  "))
	mf.close()
	var target := home.path_join(id)
	if DirAccess.dir_exists_absolute(folder_of(id)):
		var moved := remove(id)  # replace: the old one goes to removed/
		if moved != OK:
			_delete_tree(temp)
			return {"ok": false, "error": "Can't replace the installed package (%s)" % error_string(moved), "id": id}
	var err := DirAccess.rename_absolute(temp, target)
	if err != OK:
		_delete_tree(temp)
		return {"ok": false, "error": "Can't install: %s" % error_string(err), "id": id}
	set_enabled(id, true)
	return {"ok": true, "error": "", "id": id}


# --- Enable, disable, remove ---------------------------------------------------------

func is_enabled(id: String) -> bool:
	return id not in _disabled()


func set_enabled(id: String, enabled: bool) -> void:
	var list := _disabled()
	if enabled:
		list.erase(id)
	elif id not in list:
		list.append(id)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("disabled", _key(), list)
	cfg.save(SETTINGS)


func _disabled() -> PackedStringArray:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return PackedStringArray(cfg.get_value("disabled", _key(), PackedStringArray()))


## Settings are kept per packages folder (tests use their own).
func _key() -> String:
	return root.simplify_path().replace("/", "|").replace(":", "")


## Moves the package folder to `<root>/../removed/<id>-<timestamp>`.
func remove(id: String) -> Error:
	var folder := folder_of(id)
	if not DirAccess.dir_exists_absolute(folder):
		return ERR_FILE_NOT_FOUND
	var trash := root.get_base_dir().path_join("removed")
	DirAccess.make_dir_recursive_absolute(trash)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	return DirAccess.rename_absolute(folder, trash.path_join("%s-%s" % [id, stamp]))


## Manifests of every installed package, enabled or not: [{manifest..., "_enabled"}].
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var folders := Array(DirAccess.get_directories_at(root)).map(func(d: String) -> String: return root.path_join(d))
	if DirAccess.dir_exists_absolute(worlds_root) and worlds_root.simplify_path() != root.simplify_path():
		folders.append_array(Array(DirAccess.get_directories_at(worlds_root)).map(func(d: String) -> String: return worlds_root.path_join(d)))
	for folder: String in folders:
		var id := folder.get_file()
		if id.begins_with("."):
			continue
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("package.json")))
		if m is Dictionary:
			m["_folder"] = id
			m["_enabled"] = is_enabled(id)
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower())
	return out


# --- Manifest, size, documents (TASK-23) ------------------------------------------------

func manifest(id: String) -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder_of(id).path_join("package.json")))
	return m if m is Dictionary else {}


## Bytes of everything in the package folder (what an export packs, PDFs included).
func package_size(id: String) -> int:
	var folder := folder_of(id)
	var total := 0
	for rel in _files_under(folder, ""):
		var f := FileAccess.open(folder.path_join(rel), FileAccess.READ)
		if f:
			total += f.get_length()
	return total


## The manifest's documents: [{file, title, size, pages?, exists}] (exists: the file is there).
func documents(id: String) -> Array:
	var out := []
	for d: Variant in manifest(id).get("documents", []):
		if d is Dictionary and str(d.get("file", "")) != "":
			var doc: Dictionary = d.duplicate()
			doc["exists"] = FileAccess.file_exists(folder_of(id).path_join(str(d.file)))
			out.append(doc)
	return out


## Copies a PDF (or any document) into the package's docs/ folder and lists it in the
## manifest. Returns the new document entry, or {"error": text}.
func add_document(id: String, path: String, title := "") -> Dictionary:
	var folder := folder_of(id)
	if not FileAccess.file_exists(folder.path_join("package.json")):
		return {"error": "No package \"%s\"" % id}
	if not FileAccess.file_exists(path):
		return {"error": "No file %s" % path}
	DirAccess.make_dir_recursive_absolute(folder.path_join("docs"))
	var file_name := path.get_file()
	var n := 2
	while FileAccess.file_exists(folder.path_join("docs").path_join(file_name)):
		file_name = "%s (%d).%s" % [path.get_file().get_basename(), n, path.get_extension()]
		n += 1
	var err := DirAccess.copy_absolute(path, folder.path_join("docs").path_join(file_name))
	if err != OK:
		return {"error": "Can't copy the file: %s" % error_string(err)}
	var doc := {"file": "docs/" + file_name, "title": title if title != "" else path.get_file().get_basename(),
		"size": FileAccess.open(folder.path_join("docs").path_join(file_name), FileAccess.READ).get_length()}
	var m := manifest(id)
	var list: Array = m.get("documents", []) if m.get("documents") is Array else []
	list.append(doc)
	m["documents"] = list
	EntryStore._write(folder.path_join("package.json"), m)
	return doc


## "1.2 GB", "340 KB".
static func size_text(bytes: int) -> String:
	if bytes >= 1 << 30:
		return "%.1f GB" % (bytes / float(1 << 30))
	if bytes >= 1 << 20:
		return "%.1f MB" % (bytes / float(1 << 20))
	if bytes >= 1 << 10:
		return "%d KB" % (bytes >> 10)
	return "%d bytes" % bytes


static func _delete_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_delete_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


## "322 monsters, 349 spells, ..." from a manifest's counts.
static func counts_text(counts: Variant) -> String:
	if not counts is Dictionary or counts.is_empty():
		return "no entries"
	var parts := PackedStringArray()
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
	for k: Variant in keys:
		parts.append("%d %s" % [int(counts[k]), k])
	return ", ".join(parts)
