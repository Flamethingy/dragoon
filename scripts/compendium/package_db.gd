class_name PackageDB
extends RefCounted
## All core data packages (backlog/docs/package-format.md) in memory, loaded on a worker
## thread so the UI keeps running. Every entry gets a few bookkeeping keys:
## `_kind`, `_package` (id), `_package_name`, `_dir` (package folder, for images) and
## `_key` (lower-case name, for search and wikilinks).

signal loaded

## Kinds in display order (others found in packages are appended).
const KINDS := ["monsters", "features", "spells", "items", "classes", "subclasses", "races", "subraces",
	"backgrounds", "feats", "invocations", "infusions", "conditions", "diseases", "rules", "tables"]
## Kind order for resolving a wikilink name that exists in several kinds.
const LINK_PRIORITY := ["classes", "spells", "monsters", "items", "races", "subclasses",
	"subraces", "feats", "conditions", "rules", "backgrounds", "invocations", "infusions",
	"diseases", "tables", "features"]
## Monster keys that list feature ids (in this order in a stat block).
const FEATURE_LISTS := ["traits", "actions", "bonus_actions", "reactions", "legendary_actions"]

var root := ""
var packages: Array[Dictionary] = []  ## manifests, sorted by name
var entries := {}  ## kind -> Array[Dictionary], sorted by name
var errors: PackedStringArray = []
var is_loaded := false
var load_msec := 0

var _by_name := {}  ## lower-case name -> Array of entries (all kinds)
var _by_id := {}  ## "package/kind/id" -> entry
var _task := -1


## The packages folder: res://data/packages when running from the project, else
## data/packages next to the executable.
static func default_root() -> String:
	if DirAccess.dir_exists_absolute("res://data/packages"):
		return ProjectSettings.globalize_path("res://data/packages")
	return OS.get_executable_path().get_base_dir().path_join("data/packages")


## Starts loading in the background; `loaded` is emitted on the main thread when done.
func load_async(folder := "") -> void:
	root = folder if folder != "" else default_root()
	_task = WorkerThreadPool.add_task(_load_all, false, "Load packages")


## Loads on the calling thread (tests, tools).
func load_now(folder := "") -> void:
	root = folder if folder != "" else default_root()
	_load_all()
	_finish()


func _load_all() -> void:
	var started := Time.get_ticks_msec()
	var found_packages: Array[Dictionary] = []
	var found := {}
	var problems := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		problems.append("Packages folder not found: %s" % root)
	else:
		for id in dir.get_directories():
			var folder := root.path_join(id)
			var manifest: Variant = _read_json(folder.path_join("package.json"), problems)
			if not manifest is Dictionary:
				continue
			manifest["_dir"] = folder
			found_packages.append(manifest)
			for file in DirAccess.get_files_at(folder):
				if not file.ends_with(".json") or file == "package.json":
					continue
				var kind := file.get_basename()
				var list: Variant = _read_json(folder.path_join(file), problems)
				if not list is Array:
					continue
				var bucket: Array = found.get_or_add(kind, [])
				for e: Variant in list:
					if e is Dictionary:
						e["_kind"] = kind
						e["_package"] = str(manifest.get("id", id))
						e["_package_name"] = str(manifest.get("name", id))
						e["_dir"] = folder
						e["_key"] = str(e.get("name", "")).to_lower()
						bucket.append(e)
	var by_name_key := func(a: Dictionary, b: Dictionary) -> bool: return a["_key"] < b["_key"]
	for kind: String in found:
		found[kind].sort_custom(by_name_key)
	found_packages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower())
	var names := {}
	var ids := {}
	for kind: String in found:
		for e: Dictionary in found[kind]:
			names.get_or_add(e["_key"], []).append(e)
			ids["%s/%s/%s" % [e["_package"], kind, e.get("id", "")]] = e
	# Hand over in one go (the main thread only reads after `loaded`).
	packages = found_packages
	entries = found
	_by_name = names
	_by_id = ids
	errors = problems
	load_msec = Time.get_ticks_msec() - started
	if _task >= 0:
		_finish.call_deferred()


func _finish() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	is_loaded = true
	loaded.emit()


static func _read_json(path: String, problems: PackedStringArray) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		problems.append("Can't read %s" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		problems.append("%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Kinds that have entries, in display order.
func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for k in KINDS:
		if entries.has(k):
			out.append(k)
	var rest: Array = entries.keys().filter(func(k: String) -> bool: return k not in KINDS)
	rest.sort()
	out.append_array(PackedStringArray(rest))
	return out


func count() -> int:
	var n := 0
	for k: String in entries:
		n += entries[k].size()
	return n


## The entry a wikilink target names (case-insensitive), or {}. Prefers `prefer_package`,
## then kinds in LINK_PRIORITY order. Targets like "Fireball.pdf" find nothing.
func resolve(target: String, prefer_package := "") -> Dictionary:
	var found: Array = _by_name.get(target.strip_edges().to_lower(), [])
	if found.is_empty():
		return {}
	var best: Dictionary = {}
	var best_rank := 1 << 30
	for e: Dictionary in found:
		var rank := LINK_PRIORITY.find(e["_kind"])
		if rank < 0:
			rank = LINK_PRIORITY.size()
		if e["_package"] != prefer_package:
			rank += 100
		if rank < best_rank:
			best_rank = rank
			best = e
	return best


## An entry by package, kind and id, or {}.
func get_entry(package_id: String, kind: String, id: String) -> Dictionary:
	return _by_id.get("%s/%s/%s" % [package_id, kind, id], {})


## A monster feature (features.json of that package) by id, or {}.
func feature(package_id: String, id: String) -> Dictionary:
	return get_entry(package_id, "features", id)


## A monster's feature list (FEATURE_LISTS key) as feature dicts; ids that don't
## resolve become {"name": id, "_missing": true}. Inline dicts (old format) pass through.
func features_of(monster: Dictionary, list_key: String) -> Array:
	var out := []
	var list: Variant = monster.get(list_key)
	if not list is Array:
		return out
	for f: Variant in list:
		if f is Dictionary:
			out.append(f)
		else:
			var found := feature(str(monster.get("_package", "")), str(f))
			out.append(found if not found.is_empty() else {"name": str(f), "_missing": true})
	return out


func package_name(id: String) -> String:
	for p in packages:
		if str(p.get("id", "")) == id:
			return str(p.get("name", id))
	return id
