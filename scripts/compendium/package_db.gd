class_name PackageDB
extends RefCounted
## All core data packages (backlog/docs/package-format.md) in memory, loaded on a worker
## thread so the UI keeps running. Every entry gets a few bookkeeping keys:
## `_kind`, `_package` (id), `_package_name`, `_dir` (package folder, for images) and
## `_key` (lower-case name, for search and wikilinks).
## Worlds (timelines.md) are packages too: those in data/worlds next to the packages folder are
## loaded along (and world packages still in the packages folder).
## Unified index (TASK-6, TASK-32): with `timeline_dir` set, the entries made in that timeline
## are loaded too, and every entry gets `_layer` (timeline, world or core). Names and refs
## resolve timeline -> world (the timeline's own world first) -> core.

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
## A timeline folder to include ("" = packages only).
var timeline_dir := ""
var timeline_world := ""  ## the timeline's world package id
## Worlds folder ("" = data/worlds next to the packages folder).
var worlds_root := ""
## Which world packages are read: "*" every one, "" none (the core book, TASK-39), or one id.
var world_filter := "*"
## Whether the core packages (sources, homebrew) are read. The world's and the timeline's
## books leave them out: they show only what was imported into the world (Nico, 2026-11-01).
var include_core := true
const LAYERS := ["timeline", "world", "core"]
var packages: Array[Dictionary] = []  ## manifests, sorted by name
var entries := {}  ## kind -> Array[Dictionary], sorted by name (published entries only)
var drafts := {}  ## kind -> Array[Dictionary] of drafts (TASK-30): kept out of lists, search, links
var errors: PackedStringArray = []
var is_loaded := false
var load_msec := 0

var _by_name := {}  ## lower-case name -> Array of entries (all kinds)
var _by_id := {}  ## "package/kind/id" -> entry
var _task := -1
var _values := {}  ## "kind.key" -> field_values() (cleared when entries change)


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
	var folders := PackedStringArray()
	if DirAccess.dir_exists_absolute(root):
		for id in DirAccess.get_directories_at(root):
			folders.append(root.path_join(id))
	var worlds := worlds_root if worlds_root != "" else root.get_base_dir().path_join("worlds")
	if DirAccess.dir_exists_absolute(worlds) and worlds.simplify_path() != root.simplify_path():
		for id in DirAccess.get_directories_at(worlds):
			folders.append(worlds.path_join(id))
	if folders.is_empty() and not DirAccess.dir_exists_absolute(root):
		problems.append("Packages folder not found: %s" % root)
	var disabled := PackageManager.new(root)._disabled()
	for folder in folders:
		var id := folder.get_file()
		if id.begins_with(".") or id in disabled:
			continue  # being installed, or switched off in the Packages window
		var manifest: Variant = _read_json(folder.path_join("package.json"), problems)
		if not manifest is Dictionary:
			continue
		if str(manifest.get("kind", "")) == "world" and world_filter != "*" and str(manifest.get("id", id)) != world_filter:
			continue  # another world (or the core book: none)
		if str(manifest.get("kind", "")) != "world" and not include_core:
			continue  # a world's / timeline's book: the core stays in the compendium
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
			var layer := "world" if str(manifest.get("kind", "")) == "world" else "core"
			manifest["_layer"] = layer
			for e: Variant in list:
				if e is Dictionary:
					e["_kind"] = kind
					e["_package"] = str(manifest.get("id", id))
					e["_package_name"] = str(manifest.get("name", id))
					e["_dir"] = folder
					e["_layer"] = layer
					e["_key"] = str(e.get("name", "")).to_lower()
					bucket.append(e)
	var world := ""
	if timeline_dir != "" and Timeline.is_timeline(timeline_dir):
		var tl := Timeline.new(timeline_dir)
		world = tl.world_id()
		var tid := tl.id()
		var m := {"id": tid, "name": str(tl.info.get("name", tid)), "kind": "timeline", "_dir": timeline_dir, "_layer": "timeline"}
		found_packages.append(m)
		tl.created("")  # builds the timeline's entries
		for kind: String in tl._created:
			var bucket: Array = found.get_or_add(kind, [])
			for raw: Dictionary in tl.created(kind).values():
				if not raw.has("name"):
					continue
				var e: Dictionary = raw.duplicate(true)
				e["_kind"] = kind
				e["_package"] = tid
				e["_package_name"] = m.name
				e["_dir"] = timeline_dir
				e["_layer"] = "timeline"
				e["_key"] = str(e.get("name", "")).to_lower()
				bucket.append(e)
	var by_name_key := func(a: Dictionary, b: Dictionary) -> bool: return a["_key"] < b["_key"]
	var found_drafts := {}
	for kind: String in found:
		var all: Array = found[kind]
		var published := all.filter(func(x: Dictionary) -> bool: return not EntryStore.is_draft(x))
		if published.size() != all.size():
			found_drafts[kind] = all.filter(func(x: Dictionary) -> bool: return EntryStore.is_draft(x))
			found_drafts[kind].sort_custom(by_name_key)
		found[kind] = published
	for kind: String in found.keys():
		if found[kind].is_empty():
			found.erase(kind)
		else:
			found[kind].sort_custom(by_name_key)
	found_packages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower())
	var names := {}
	var ids := {}
	for kind: String in found:
		for e: Dictionary in found[kind]:
			names.get_or_add(e["_key"], []).append(e)
			ids["%s/%s/%s" % [e["_package"], kind, e.get("id", "")]] = e
	for kind: String in found_drafts:
		for e: Dictionary in found_drafts[kind]:
			ids["%s/%s/%s" % [e["_package"], kind, e.get("id", "")]] = e  # reachable by id, not by name
	# Hand over in one go (the main thread only reads after `loaded`).
	packages = found_packages
	timeline_world = world
	entries = found
	drafts = found_drafts
	_by_name = names
	_by_id = ids
	errors = problems
	load_msec = Time.get_ticks_msec() - started
	if _task >= 0:
		_finish.call_deferred()


func _finish() -> void:
	_values.clear()
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


## The entries of a kind, with its drafts if asked (sorted by name).
func list(kind: String, with_drafts := false) -> Array:
	var out: Array = entries.get(kind, [])
	if not with_drafts or not drafts.has(kind):
		return out
	out = out + drafts[kind]
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["_key"] < b["_key"])
	return out


## Kinds with entries (or drafts, if asked), in display order.
func kinds_with(with_drafts: bool) -> PackedStringArray:
	var out := kinds()
	if with_drafts:
		for k: String in drafts:
			if k not in out:
				out.append(k)
	return out


## Every draft of every package and the timeline.
func all_drafts() -> Array:
	var out := []
	for k: String in drafts:
		out.append_array(drafts[k])
	return out


func draft_count() -> int:
	var n := 0
	for k: String in drafts:
		n += drafts[k].size()
	return n


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
		rank += layer_rank(e) * 1000
		if rank < best_rank:
			best_rank = rank
			best = e
	return best


## 0 timeline, 1 the timeline's world, 2 other worlds, 3 core.
func layer_rank(e: Dictionary) -> int:
	match str(e.get("_layer", "core")):
		"timeline":
			return 0
		"world":
			return 1 if e.get("_package") == timeline_world else 2
	return 3


## A ref (data-layout.md): "kind/id" searches timeline -> world -> core; "world:kind/id" and
## "core:<package>/kind/id" skip the search. {} if nothing matches.
func resolve_ref(ref: String) -> Dictionary:
	if ref.begins_with("core:"):
		var parts := ref.substr(5).split("/")
		return get_entry(parts[0], parts[1], parts[2]) if parts.size() == 3 else {}
	var layer_only := ""
	var plain := ref
	if ref.begins_with("world:"):
		layer_only = "world"
		plain = ref.substr(6)
	var kind := plain.get_slice("/", 0)
	var id := plain.get_slice("/", 1)
	var best := {}
	for e: Dictionary in entries.get(kind, []):
		if str(e.get("id", "")) != id or (layer_only != "" and e.get("_layer") != layer_only):
			continue
		if best.is_empty() or layer_rank(e) < layer_rank(best):
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


# --- Edits (TASK-21) -------------------------------------------------------------------

## Adds or replaces an entry after an edit, without reloading everything. `old_id`: its id
## before a rename. Returns the entry as the book holds it (with bookkeeping keys).
## The values a field has across the loaded entries of a kind (TASK-29), most used first:
## [{value, count}]. Strings and the strings in lists count; different spellings of the same
## value ("Very Rare", "very rare") count as one, shown in its most used spelling.
func field_values(kind: String, key: String) -> Array:
	var cache_key := kind + "." + key
	if _values.has(cache_key):
		return _values[cache_key]
	var counts := {}  ## lower -> {spelling: count}
	for e: Dictionary in entries.get(kind, []):
		var v: Variant = e.get(key)
		var items: Array = v if v is Array else [v]
		for x: Variant in items:
			if not x is String or str(x).strip_edges() == "":
				continue
			var s := str(x).strip_edges()
			var spellings: Dictionary = counts.get(s.to_lower(), {})
			spellings[s] = int(spellings.get(s, 0)) + 1
			counts[s.to_lower()] = spellings
	var out := []
	for low: String in counts:
		var spellings: Dictionary = counts[low]
		var best := ""
		var total := 0
		for s: String in spellings:
			total += int(spellings[s])
			if best == "" or int(spellings[s]) > int(spellings[best]):
				best = s
		out.append({"value": best, "count": total})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.count > b.count if a.count != b.count else str(a.value).to_lower() < str(b.value).to_lower())
	_values[cache_key] = out
	return out


func put_entry(entry: Dictionary, kind: String, store: EntryStore, old_id := "") -> Dictionary:
	_values.clear()
	remove_entry(store.id, kind, old_id if old_id != "" else str(entry.get("id", "")))
	remove_entry(store.id, kind, str(entry.get("id", "")))  # renamed onto an id that was there
	var e := EntryStore.strip(entry).duplicate(true)
	e["_kind"] = kind
	e["_package"] = store.id
	e["_package_name"] = store.name
	e["_dir"] = store.folder
	e["_layer"] = "timeline" if store.layer == EntryStore.TIMELINE else "world" if store.layer == EntryStore.WORLD else "core"
	e["_key"] = str(e.get("name", "")).to_lower()
	var draft := EntryStore.is_draft(e)
	var bucket: Array = (drafts if draft else entries).get_or_add(kind, [])
	var at := bucket.bsearch_custom(e, func(a: Dictionary, b: Dictionary) -> bool: return a["_key"] < b["_key"])
	bucket.insert(at, e)
	if not draft:
		_by_name.get_or_add(e["_key"], []).append(e)
	_by_id["%s/%s/%s" % [store.id, kind, e.get("id", "")]] = e
	return e


func remove_entry(package_id: String, kind: String, id: String) -> void:
	_values.clear()
	var key := "%s/%s/%s" % [package_id, kind, id]
	var old: Dictionary = _by_id.get(key, {})
	if old.is_empty():
		return
	_by_id.erase(key)
	for bucket: Dictionary in [entries, drafts]:
		var list: Array = bucket.get(kind, [])
		var i := list.find(old)
		if i >= 0:
			list.remove_at(i)
			if list.is_empty() and is_same(bucket, drafts):
				bucket.erase(kind)
	var same: Array = _by_name.get(old["_key"], [])
	same.erase(old)
	if same.is_empty():
		_by_name.erase(old["_key"])


## Entry names for [[ suggestions: names starting with `prefix` first, then containing it.
func suggest(prefix: String, limit := 12) -> PackedStringArray:
	var p := prefix.strip_edges().to_lower()
	var starts := PackedStringArray()
	var contains := PackedStringArray()
	if p == "":
		return starts
	for key: String in _by_name:
		if key.begins_with(p):
			starts.append(str(_by_name[key][0].get("name", key)))
		elif contains.size() < limit and key.contains(p):
			contains.append(str(_by_name[key][0].get("name", key)))
	starts.sort()
	starts.append_array(contains)
	return starts.slice(0, limit)
