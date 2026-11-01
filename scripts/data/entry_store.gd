class_name EntryStore
extends RefCounted
## One folder of entries the VTT can edit (TASK-21): a package (package.json, kind "source" or
## "world") or a campaign (campaign.json). Both keep one JSON array per kind (data-layout.md).
##
## - Source packages are read-only unless unlocked (`unlock()`; remembered as
##   `"editable": true` in package.json). The usual way is "edit a copy": copy_entry() into a
##   world package or campaign.
## - Writes are atomic (temp file, then rename); bookkeeping keys starting with "_" (added by
##   PackageDB) are never written.
## - commit() is the editor's save: in a campaign during a running session, changes to
##   creatures' sheet fields become `sheet.changed` events (doc-1: play state never goes back
##   into the files); everything else is saved to JSON.

const SOURCE := "source"
const WORLD := "world"
const CAMPAIGN := "campaign"
const CREATURES := ["pcs", "npcs", "monsters"]
## Creature fields that stay entity edits even during a session (what something *is*).
const TEXT_FIELDS := ["id", "name", "description", "image", "token", "tags", "origin", "source"]

var folder := ""
var layer := ""  ## source, world or campaign
var id := ""
var name := ""
var manifest := {}  ## package.json or campaign.json
var _kinds := {}  ## kind -> Array (file order)


## The store for a package or campaign folder; null if it is neither.
static func open(path: String) -> EntryStore:
	var s := EntryStore.new()
	s.folder = path
	if FileAccess.file_exists(path.path_join("package.json")):
		s.manifest = _read(path.path_join("package.json"), {})
		s.layer = str(s.manifest.get("kind", SOURCE))
	elif FileAccess.file_exists(path.path_join("campaign.json")):
		s.manifest = _read(path.path_join("campaign.json"), {})
		s.layer = CAMPAIGN
	else:
		return null
	s.id = str(s.manifest.get("id", path.get_file()))
	s.name = str(s.manifest.get("name", s.id))
	return s


## A new, empty world package in `packages_root`/<id>.
static func create_world(packages_root: String, world_name: String) -> EntryStore:
	var world_id := slug(world_name)
	var path := packages_root.path_join(world_id)
	var n := 2
	while DirAccess.dir_exists_absolute(path):
		path = packages_root.path_join("%s-%d" % [world_id, n])
		n += 1
	DirAccess.make_dir_recursive_absolute(path.path_join("assets"))
	var m := {"format": "dragoon-package", "format_version": 1, "id": path.get_file(), "name": world_name,
		"kind": WORLD, "version": "0.1.0", "description": "", "calendar": "default", "counts": {}}
	_write(path.path_join("package.json"), m)
	return open(path)


func is_read_only() -> bool:
	return layer == SOURCE and not manifest.get("editable", false)


## Makes a source package editable (asked for explicitly in the editor).
func unlock() -> void:
	manifest["editable"] = true
	_save_manifest()


# --- Reading ---------------------------------------------------------------------------

func list(kind: String) -> Array:
	if not _kinds.has(kind):
		var data: Variant = _read(folder.path_join(kind + ".json"), [])
		_kinds[kind] = data if data is Array else []
	return _kinds[kind]


func find(kind: String, entry_id: String) -> Dictionary:
	for e: Variant in list(kind):
		if e is Dictionary and str(e.get("id", "")) == entry_id:
			return e
	return {}


func has(kind: String, entry_id: String) -> bool:
	return not find(kind, entry_id).is_empty()


## A slug id for `entry_name` that is free in `kind` (goblin, goblin-2 ...).
func free_id(kind: String, entry_name: String) -> String:
	var base := slug(entry_name)
	var out := base
	var n := 2
	while has(kind, out):
		out = "%s-%d" % [base, n]
		n += 1
	return out


static func slug(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif not out.ends_with("-") and out != "":
			out += "-"
	out = out.trim_suffix("-")
	return out if out != "" else "entry"


# --- Writing ---------------------------------------------------------------------------

## Creates a new entry from the kind's template (Schema.blank) and saves it.
func create(kind: String, entry_name: String) -> Dictionary:
	var e := Schema.blank(kind)
	e["id"] = free_id(kind, entry_name)
	e["name"] = entry_name
	if layer != CAMPAIGN and e.has("source"):
		e["source"] = name
	save(kind, e)
	return e


## Saves an entry (replaces the one with the same id, or appends). `old_id`: the id it had
## before, if it was renamed. Returns OK or an error.
func save(kind: String, entry: Dictionary, old_id := "") -> Error:
	if is_read_only():
		return ERR_FILE_NO_PERMISSION
	var clean := strip(entry)
	var items := list(kind)
	var look := old_id if old_id != "" else str(clean.get("id", ""))
	var at := -1
	for i in items.size():
		if items[i] is Dictionary and str(items[i].get("id", "")) == look:
			at = i
			break
	if at >= 0:
		items[at] = clean
	else:
		items.append(clean)
	return _save_kind(kind)


func delete(kind: String, entry_id: String) -> Error:
	if is_read_only():
		return ERR_FILE_NO_PERMISSION
	var items := list(kind)
	for i in items.size():
		if items[i] is Dictionary and str(items[i].get("id", "")) == entry_id:
			items.remove_at(i)
			return _save_kind(kind)
	return ERR_DOES_NOT_EXIST


## A copy of an entry in the same store under a new id ("Goblin (copy)").
func duplicate_entry(kind: String, entry_id: String) -> Dictionary:
	var e := find(kind, entry_id)
	if e.is_empty() or is_read_only():
		return {}
	var copy: Dictionary = strip(e).duplicate(true)
	copy["name"] = str(e.get("name", entry_id)) + " (copy)"
	copy["id"] = free_id(kind, str(copy.name))
	save(kind, copy)
	return copy


## Copies an entry from another store into this one ("edit a copy"). Monsters bring their
## features along (into this store's features.json, ids kept unless taken by different
## ones); images are copied into assets/. Returns the new entry.
func copy_entry(from: EntryStore, kind: String, entry_id: String) -> Dictionary:
	var e := from.find(kind, entry_id)
	if e.is_empty() or is_read_only():
		return {}
	var copy: Dictionary = strip(e).duplicate(true)
	copy["id"] = free_id(kind, str(copy.get("name", entry_id))) if has(kind, entry_id) else entry_id
	if from.layer != layer or from.id != id:
		copy["origin"] = {"layer": "core" if from.layer == SOURCE else from.layer, "package": from.id,
			"kind": kind, "id": entry_id, "version": str(from.manifest.get("version", ""))}
	for key in ["image", "token", "party_token"]:
		if str(copy.get(key, "")) != "":
			copy[key] = _copy_asset(from, str(copy[key]))
	if kind == "monsters":
		for list_key in PackageDB.FEATURE_LISTS:
			var ids: Array = copy.get(list_key, []) if copy.get(list_key) is Array else []
			for i in ids.size():
				ids[i] = _copy_feature(from, str(ids[i]))
	save(kind, copy)
	return copy


## "Send into the campaign" (TASK-11): a campaign copy of one core/world entry that keeps its
## origin and drifts freely from then on; logged as entity.sent if a log is given.
func send(from: EntryStore, kind: String, entry_id: String, events_log: EventLog = null) -> Dictionary:
	if layer != CAMPAIGN:
		return {}
	var copy := copy_entry(from, kind, entry_id)
	if not copy.is_empty() and events_log != null:
		events_log.append("entity.sent", "%s/%s" % [kind, copy.id], {"source": source_ref(from, kind, entry_id),
			"layer": "core" if from.layer == SOURCE else from.layer})
	return copy


## Sends a whole world package: every entry the campaign doesn't have yet (same id) is
## copied. Returns {sent: ["kind/id"], skipped: ["kind/id"]}.
func send_world(world: EntryStore, events_log: EventLog = null) -> Dictionary:
	var out := {"sent": [], "skipped": []}
	if layer != CAMPAIGN:
		return out
	for file in DirAccess.get_files_at(world.folder):
		var kind := file.get_basename()
		if not file.ends_with(".json") or kind == "package":
			continue
		for e: Variant in world.list(kind):
			if not e is Dictionary or not e.has("id"):
				continue
			var ref := "%s/%s" % [kind, e.id]
			if has(kind, str(e.id)):
				out.skipped.append(ref)
				continue
			var copy := send(world, kind, str(e.id), events_log)
			if not copy.is_empty():
				out.sent.append("%s/%s" % [kind, copy.id])
	return out


## The qualified ref of an entry in a package (entity.sent `source`).
static func source_ref(from: EntryStore, kind: String, entry_id: String) -> String:
	if from.layer == SOURCE:
		return "core:%s/%s/%s" % [from.id, kind, entry_id]
	return "%s:%s/%s" % [from.layer, kind, entry_id]


func _copy_feature(from: EntryStore, feature_id: String) -> String:
	var f := from.find("features", feature_id)
	if f.is_empty():
		return feature_id
	var mine := find("features", feature_id)
	var clean := strip(f)
	clean.erase("used_by")
	if not mine.is_empty():
		var same := strip(mine)
		same.erase("used_by")
		if same == clean:
			return feature_id
		clean["id"] = free_id("features", str(clean.get("name", feature_id)))
	save("features", clean)
	return str(clean.id)


func _copy_asset(from: EntryStore, rel: String) -> String:
	var src := from.folder.path_join(rel)
	if not FileAccess.file_exists(src) or FileAccess.file_exists(folder.path_join(rel)):
		return rel
	DirAccess.make_dir_recursive_absolute(folder.path_join(rel).get_base_dir())
	DirAccess.copy_absolute(src, folder.path_join(rel))
	return rel


## Copies a picked image file into assets/<kind>/ and returns its relative path.
func import_image(file: String, kind: String) -> String:
	var rel := "assets/%s/%s" % [kind, file.get_file()]
	DirAccess.make_dir_recursive_absolute(folder.path_join(rel).get_base_dir())
	if file != folder.path_join(rel):
		DirAccess.copy_absolute(file, folder.path_join(rel))
	return rel


## The editor's save. `before`: the entry as it was opened; `after`: as edited. In a
## campaign during a session (log.in_session()), sheet fields of creatures are logged as
## sheet.changed events and the file keeps its values; all other changes are saved.
## Returns {saved: bool, events: [ ... ], error}.
func commit(kind: String, before: Dictionary, after: Dictionary, events_log: EventLog = null, by := "dm") -> Dictionary:
	var out := {"saved": false, "events": [], "error": OK}
	if is_read_only():
		out.error = ERR_FILE_NO_PERMISSION
		return out
	var file_version := strip(after)
	if layer == CAMPAIGN and events_log != null and events_log.in_session() and kind in CREATURES and not before.is_empty():
		var old := strip(before)
		var ref := "%s/%s" % [kind, old.get("id", "")]
		for change: Array in diff(old, file_version):
			var path: String = change[0]
			if path.get_slice(".", 0) in TEXT_FIELDS:
				continue
			out.events.append(events_log.change_sheet(ref, path, change[1], change[2], "edited", by))
			_set_path(file_version, path, change[1])  # the file keeps the starting value
	if file_version != strip(before):
		out.error = save(kind, file_version, str(before.get("id", "")))
		out.saved = out.error == OK
	return out


## Changes between two entries as [[dotted path, from, to]] (dicts are walked, lists and
## values compared whole).
static func diff(a: Dictionary, b: Dictionary, prefix := "") -> Array:
	var out := []
	var keys := {}
	for k: Variant in a:
		keys[k] = true
	for k: Variant in b:
		keys[k] = true
	for k: Variant in keys:
		var path := prefix + str(k)
		var va: Variant = a.get(k)
		var vb: Variant = b.get(k)
		if va is Dictionary and vb is Dictionary:
			out.append_array(diff(va, vb, path + "."))
		elif typeof(va) != typeof(vb) or va != vb:
			if not (_is_number(va) and _is_number(vb) and float(va) == float(vb)):
				out.append([path, va, vb])
	return out


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func _set_path(d: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var at := d
	for i in parts.size() - 1:
		if not at.get(parts[i]) is Dictionary:
			at[parts[i]] = {}
		at = at[parts[i]]
	if value == null:
		at.erase(parts[-1])
	else:
		at[parts[-1]] = value


## The entry without bookkeeping keys ("_kind", "_package" ...).
static func strip(e: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in e:
		if not str(k).begins_with("_"):
			out[k] = e[k]
	return out


func _save_kind(kind: String) -> Error:
	var err := _write(folder.path_join(kind + ".json"), list(kind))
	if err == OK and layer != CAMPAIGN:
		var counts: Dictionary = manifest.get("counts", {}) if manifest.get("counts") is Dictionary else {}
		counts[kind] = list(kind).size()
		manifest["counts"] = counts
		_save_manifest()
	return err


func _save_manifest() -> void:
	_write(folder.path_join("campaign.json" if layer == CAMPAIGN else "package.json"), manifest)


static func _read(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data != null else fallback


## JSON reads every number as float; whole ones are written back as ints (17, not 17.0).
static func whole_numbers(v: Variant) -> Variant:
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = whole_numbers(v[k])
		return d
	if v is Array:
		return v.map(whole_numbers)
	return v


static func _write(path: String, data: Variant) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(whole_numbers(data), " ", false))
	f.close()
	return DirAccess.rename_absolute(tmp, path)
