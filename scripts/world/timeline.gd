class_name Timeline
extends RefCounted
## One history of play in a world (backlog/docs/timelines.md), replacing the campaign folder:
## `data/worlds/<world>/timelines/<id>/` with timeline.json (name, players, dm, parent,
## fork_at, next_session), events.jsonl, notes.json and encounters.json.
##
## Like git: the world package is the base and is never changed by play. What exists in a
## timeline = the world's entries + entries created in the timeline (`entity.created` events
## with the full entry; `entity.edited` / `entity.deleted` change them; `entity.promoted` hands
## one over to the world). A fork (`parent`, `fork_at` = event id) starts with the parent's
## events up to that event (EventLog.inherited) and has its own after it.
## Entries are addressed by ref "<kind>/<id>"; a timeline entry hides the world entry with the
## same ref. The table gets compact player views from here (map_view / token_view).

const FORMAT := "dragoon-timeline"
const START_ID := "prologue"
const START_NAME := "Prologue"
## Kinds that can stand on a map.
## Characters are referenced (one entity, one health pool, every token of it is that one);
## creatures are copied for each token (5 goblins, 5 HP bars). TASK-43.
const CREATURES := ["characters", "creatures"]
## Token fields every player sees; owners also get OWNER_FIELDS of their own PC.
const TOKEN_FIELDS := ["name", "size", "token_style"]
const OWNER_FIELDS := ["hp", "ac"]
const ENTITY_EVENTS := ["entity.created", "entity.edited", "entity.deleted", "entity.promoted"]

var folder := ""
var world_dir := ""
var assets: AssetCache
var info := {}  ## timeline.json
var events_log: EventLog

var _world := {}  ## kind -> {id -> entry} (the world package's files)
var _created := {}  ## kind -> {id -> entry} built from the entity events
var _created_count := -1  ## events_log.events.size() when _created was built


func _init(timeline_folder: String, asset_cache: AssetCache = null) -> void:
	folder = timeline_folder.simplify_path()
	world_dir = folder.get_base_dir().get_base_dir()
	KindMigration.ensure(world_dir)  # characters + creatures (TASK-43)
	KindMigration.ensure(folder)
	assets = asset_cache
	info = _read(folder.path_join("timeline.json"), {})
	events_log = EventLog.open(events_path(), chain_events(world_dir, str(info.get("parent", "")), int(info.get("fork_at", 0))))


# --- Folders --------------------------------------------------------------------------

## True if the folder has a readable timeline.json of our format.
static func is_timeline(path: String) -> bool:
	var data: Variant = _read(path.path_join("timeline.json"), null)
	return data is Dictionary and str(data.get("format", "")) == FORMAT


## Creates a timeline in a world: a start timeline (no parent) or a fork of `parent` at the
## event `fork_at` (0 = before any event). Returns its folder.
static func create(world_folder: String, timeline_name: String, parent := "", fork_at := 0,
		players: Array = [], dm := {}, timeline_id := "") -> String:
	var base := timeline_id if timeline_id != "" else EntryStore.slug(timeline_name)
	var root := world_folder.path_join("timelines")
	var tid := base
	var n := 2
	while DirAccess.dir_exists_absolute(root.path_join(tid)):
		tid = "%s-%d" % [base, n]
		n += 1
	var dir := root.path_join(tid)
	DirAccess.make_dir_recursive_absolute(dir)
	var parent_info: Dictionary = _read(root.path_join(parent).path_join("timeline.json"), {}) if parent != "" else {}
	EntryStore._write(dir.path_join("timeline.json"), {"format": FORMAT, "format_version": 1, "id": tid,
		"name": timeline_name, "description": "", "parent": parent, "fork_at": fork_at,
		"players": players if not players.is_empty() else parent_info.get("players", []),
		"dm": dm if not dm.is_empty() else parent_info.get("dm", {"name": "DM", "color": "#7a3b8f"}),
		"next_session": int(parent_info.get("next_session", 1)) if parent != "" else 1,
		"created": Time.get_datetime_string_from_system()})
	FileAccess.open(dir.path_join("events.jsonl"), FileAccess.WRITE).close()
	EntryStore._write(dir.path_join("notes.json"), [])
	EntryStore._write(dir.path_join("encounters.json"), [])
	return dir


## The timelines of a world: [timeline.json + {_dir}], the start timeline first, then by name.
static func list(world_folder: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := world_folder.path_join("timelines")
	if not DirAccess.dir_exists_absolute(root):
		return out
	for d in DirAccess.get_directories_at(root):
		var t: Variant = _read(root.path_join(d).path_join("timeline.json"), null)
		if t is Dictionary and str(t.get("format", "")) == FORMAT:
			t["_dir"] = root.path_join(d)
			out.append(t)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (str(a.get("parent", "")) == "") != (str(b.get("parent", "")) == ""):
			return str(a.get("parent", "")) == ""
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower())
	return out


## The events a timeline inherits: its parent's (with the parent's own inheritance) up to and
## including the event `fork_at`.
static func chain_events(world_folder: String, parent: String, fork_at: int, depth := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if parent == "" or fork_at <= 0 or depth > 32:
		return out
	var pdir := world_folder.path_join("timelines").path_join(parent)
	var pinfo: Dictionary = _read(pdir.path_join("timeline.json"), {})
	if pinfo.is_empty():
		return out
	var up := chain_events(world_folder, str(pinfo.get("parent", "")), int(pinfo.get("fork_at", 0)), depth + 1)
	for e in EventLog.open(pdir.path_join("events.jsonl"), up).events:
		if int(e.id) <= fork_at:
			out.append(e)
	return out


func id() -> String:
	return str(info.get("id", folder.get_file()))


func world_id() -> String:
	return str(world_manifest().get("id", world_dir.get_file()))


func world_manifest() -> Dictionary:
	return _read(world_dir.path_join("package.json"), {})


## The world's rules settings (TASK-53): edition and house rules, defaults filled in.
func rules_settings() -> Dictionary:
	return Rules.settings_of(world_manifest().get("rules", {}))


## Saves the world's rules settings (into its package.json, "rules").
func set_rules_settings(settings: Dictionary) -> Error:
	var manifest := world_manifest()
	manifest["rules"] = settings
	var f := FileAccess.open(world_dir.path_join("package.json"), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(manifest, " ", false))
	return OK


func world_store() -> EntryStore:
	return EntryStore.open(world_dir)


func events_path() -> String:
	return folder.path_join("events.jsonl")


func encounters_path() -> String:
	return folder.path_join("encounters.json")


## A fork of this timeline at event `at` (default: its latest event). Returns the new folder.
func fork(fork_name: String, at := -1, players: Array = [], dm := {}) -> String:
	var last: int = events_log.events.back().id if not events_log.events.is_empty() else 0
	return create(world_dir, fork_name, id(), last if at < 0 else at, players, dm)


func save_info() -> Error:
	return EntryStore._write(folder.path_join("timeline.json"), info)


# --- Entries -------------------------------------------------------------------------

## All entries of a kind as id -> entry: the world's, with this timeline's own on top.
func entries(kind: String) -> Dictionary:
	var out: Dictionary = world_entries(kind).duplicate()
	out.merge(created(kind), true)
	return out


## The world package's entries of a kind (id -> entry, read once).
func world_entries(kind: String) -> Dictionary:
	if not _world.has(kind):
		var by_id := {}
		var data: Variant = _read(world_dir.path_join(kind + ".json"), [])
		if data is Array:
			for e: Variant in data:
				if e is Dictionary and e.has("id"):
					by_id[str(e.id)] = e
		_world[kind] = by_id
	return _world[kind]


## The entries made in this timeline (and before the fork in its parents), id -> entry.
func created(kind: String) -> Dictionary:
	events_log.refresh()
	if _created_count != events_log.events.size():
		_created = {}
		for e in events_log.effective():
			if e.type not in ENTITY_EVENTS or not "/" in str(e.entity):
				continue
			var k := str(e.entity).get_slice("/", 0)
			var eid := str(e.entity).get_slice("/", 1)
			var bucket: Dictionary = _created.get_or_add(k, {})
			match str(e.type):
				"entity.created", "entity.edited":
					if e.data.get("entry") is Dictionary:
						var entry: Dictionary = e.data.entry.duplicate(true)
						entry["id"] = eid
						bucket[eid] = entry
				_:
					bucket.erase(eid)
		_created_count = events_log.events.size()
	return _created.get(kind, {})


func is_created(ref: String) -> bool:
	return created(ref.get_slice("/", 0)).has(ref.get_slice("/", 1))


## An entry by ref "<kind>/<id>" ({} if there is none).
func entry(ref: String) -> Dictionary:
	if not "/" in ref:
		return {}
	var kind := ref.get_slice("/", 0)
	var id_part := ref.get_slice("/", 1)
	var mine := created(kind)
	return mine[id_part] if mine.has(id_part) else world_entries(kind).get(id_part, {})


func refs(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id_part: String in entries(kind):
		out.append("%s/%s" % [kind, id_part])
	out.sort()
	return out


func maps() -> PackedStringArray:
	return refs("maps")


## The characters players can play: those with owners or a class (NPCs have neither).
func pcs() -> PackedStringArray:
	var out := PackedStringArray()
	for ref in refs("characters"):
		var e := entry(ref)
		if not owners_of(e).is_empty() or (e.get("classes") is Array and not (e.classes as Array).is_empty()):
			out.append(ref)
	return out


## A character's owners (player ids; old entries: `player`).
static func owners_of(e: Dictionary) -> Array:
	if e.get("owners") is Array:
		return (e.owners as Array).map(func(o: Variant) -> String: return str(o)).filter(func(o: String) -> bool: return o != "")
	return [str(e.player)] if str(e.get("player", "")) != "" else []


func name_of(ref: String) -> String:
	return str(entry(ref).get("name", ref.get_file()))


## A free id for `entry_name` in `kind` (world and timeline entries both count).
func free_id(kind: String, entry_name: String) -> String:
	var base := EntryStore.slug(entry_name)
	var all := entries(kind)
	var out := base
	var n := 2
	while all.has(out):
		out = "%s-%d" % [base, n]
		n += 1
	return out


## Creates an entry in this timeline (an `entity.created` event with the full entry). Its
## pictures are copied from `from_dir` into the timeline's assets. Returns the entry.
func add_entry(kind: String, e: Dictionary, from_dir := "", by := "dm") -> Dictionary:
	var copy := EntryStore.strip(e).duplicate(true)
	var eid := str(copy.get("id", ""))
	if eid == "" or entries(kind).has(eid):
		eid = free_id(kind, str(copy.get("name", kind)))
	copy["id"] = eid
	if from_dir != "" and from_dir.simplify_path() != folder:
		for key in ["image", "token", "party_token"]:
			copy[key] = _copy_asset(from_dir, folder, str(copy.get(key, "")))
	events_log.append("entity.created", "%s/%s" % [kind, eid], {"entry": copy}, by)
	return copy


## The entity a compendium entry becomes on the map (TASK-34). Monsters get a numbered copy
## each time ("Goblin 1", "Goblin 2": their own entity, HP and events). NPCs and PCs of this
## timeline or its world are placed themselves; one from a book gets a single copy here.
## `e` is a PackageDB entry (with _kind, _package, _dir, _layer). Returns the ref.
func token_entity(e: Dictionary, by := "dm") -> String:
	var kind := str(e.get("_kind", ""))
	var eid := str(e.get("id", ""))
	if kind not in CREATURES or eid == "":
		return ""
	var layer := str(e.get("_layer", ""))
	var own := layer == "timeline" or (layer == "world" and str(e.get("_package", "")) == world_id())
	if own and kind != "creatures" and not entry("%s/%s" % [kind, eid]).is_empty():
		return "%s/%s" % [kind, eid]
	var source := "%s/%s/%s" % [e.get("_package", ""), kind, eid]
	var number := 0
	for c: Dictionary in created(kind).values():
		if str(c.get("copy_of", "")) == source:
			if kind != "creatures":
				return "%s/%s" % [kind, c.id]  # the one copy of this NPC/PC
			number = maxi(number, int(c.get("copy_number", 0)))
	var copy := EntryStore.strip(e).duplicate(true)
	copy.erase("id")
	copy["copy_of"] = source
	if kind == "creatures":
		copy["copy_number"] = number + 1
		copy["name"] = "%s %d" % [e.get("name", eid), number + 1]
	copy.erase("draft")
	var made := add_entry(kind, copy, str(e.get("_dir", "")), by)
	return "%s/%s" % [kind, made.id]


## Forgets the world files read so far (a map was added or its grid changed).
func reload_world() -> void:
	_world.clear()


## Replaces a timeline entry (`entity.edited`), or overrides a world entry in this timeline.
func edit_entry(kind: String, e: Dictionary, by := "dm") -> Dictionary:
	var copy := EntryStore.strip(e).duplicate(true)
	return events_log.append("entity.edited", "%s/%s" % [kind, copy.get("id", "")], {"entry": copy}, by)


func delete_entry(kind: String, entry_id: String, by := "dm") -> Dictionary:
	if not created(kind).has(entry_id):
		return {}
	return events_log.append("entity.deleted", "%s/%s" % [kind, entry_id], {}, by)


## Merges a timeline entry into the world package (same id), so every timeline can use it;
## its pictures and (for monsters) its timeline features go along. Returns {promoted: ref} or
## {error}.
func promote(ref: String, by := "dm") -> Dictionary:
	var kind := ref.get_slice("/", 0)
	if not is_created(ref):
		return {"error": "%s is not a timeline entry" % ref}
	var world := world_store()
	if world == null or world.is_read_only():
		return {"error": "The world package can't be written"}
	var e: Dictionary = created(kind)[ref.get_slice("/", 1)].duplicate(true)
	for key in ["image", "token", "party_token"]:
		e[key] = _copy_asset(folder, world_dir, str(e.get(key, "")))
	if e.get("image", "") == "":
		e.erase("image")
	for key in ["token", "party_token"]:
		if e.get(key, null) == "":
			e.erase(key)
	if kind == "creatures":
		for list_key in PackageDB.FEATURE_LISTS:
			for fid: Variant in (e.get(list_key, []) if e.get(list_key) is Array else []):
				if is_created("features/%s" % fid):
					promote("features/%s" % fid, by)
	var err := world.save(kind, e)
	if err != OK:
		return {"error": error_string(err)}
	_world.erase(kind)
	events_log.append("entity.promoted", ref, {"world": world_id()}, by)
	return {"promoted": ref}


static func _copy_asset(from_dir: String, to_dir: String, rel: String) -> String:
	if rel == "" or rel.is_absolute_path():
		return rel
	var src := from_dir.path_join(rel)
	var dst := to_dir.path_join(rel)
	if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		DirAccess.copy_absolute(src, dst)
	return rel


# --- Players -----------------------------------------------------------------------------

## [{id, name, color}] from timeline.json.
func players() -> Array:
	return info.get("players", []) if info.get("players") is Array else []


## The player id for a login name (matches id or name, any case); "" if unknown.
func player_id(login: String) -> String:
	var l := login.strip_edges().to_lower()
	for p: Dictionary in players():
		if str(p.get("id", "")).to_lower() == l or str(p.get("name", "")).to_lower() == l:
			return str(p.id)
	return ""


func player_name(player: String) -> String:
	for p: Dictionary in players():
		if p.get("id") == player:
			return str(p.get("name", player))
	return "DM" if player == "dm" else player


## Every account with its display name and color: players by id, the DM as "dm".
## {id: {name, color: "#rrggbb"}} (TASK-19).
func accounts() -> Dictionary:
	var out := {}
	for p: Dictionary in players():
		out[str(p.get("id", ""))] = {"name": str(p.get("name", p.get("id", ""))), "color": str(p.get("color", ""))}
	var dm: Dictionary = info.get("dm", {}) if info.get("dm") is Dictionary else {}
	out["dm"] = {"name": str(dm.get("name", "DM")), "color": str(dm.get("color", ""))}
	return out


## Sets an account's color ("#rrggbb") and saves timeline.json. False if unknown/invalid.
func set_color(account: String, color: String) -> bool:
	if not Color.html_is_valid(color):
		return false
	var hex := "#" + Color.html(color).to_html(false)
	if account == "dm":
		var dm: Dictionary = info.get("dm", {}) if info.get("dm") is Dictionary else {}
		dm["color"] = hex
		info["dm"] = dm
	else:
		var found := false
		for p: Dictionary in players():
			if str(p.get("id", "")) == account:
				p["color"] = hex
				found = true
		if not found:
			return false
	return save_info() == OK


## Who controls which character: ref -> [player ids] (`owners`); characters without
## owners are left out. The DM controls everything anyway.
func owners() -> Dictionary:
	var out := {}
	for ref in refs("characters"):
		var o := owners_of(entry(ref))
		if not o.is_empty():
			out[ref] = o
	for id: String in created("creatures"):  # TASK-74: a summon is its caster's players'
		var e: Dictionary = created("creatures")[id]
		if e.get("owners") is Array and not (e.owners as Array).is_empty():
			out["creatures/" + id] = (e.owners as Array).duplicate()
	return out


## Hash of an image path relative to the timeline (its own assets first, then the world's);
## "" if none.
func image_hash(rel: String) -> String:
	if rel == "" or assets == null:
		return ""
	var own := folder.path_join(rel)
	return assets.register(own if FileAccess.file_exists(own) else world_dir.path_join(rel))


# --- Player views ----------------------------------------------------------------------

## A map for the table: {id, name, image, grid: {size, offset}, kind ("world" or "local"),
## party_token, party_start, tokens: {ref: Vector2i}} (`tokens`: the world's starting layout).
func map_view(ref: String) -> Dictionary:
	var m := entry(ref)
	if m.is_empty():
		return {}
	var grid: Dictionary = m.get("grid", {}) if m.get("grid") is Dictionary else {}
	var tokens := {}
	for t: Variant in m.get("tokens", []):
		if t is Dictionary:
			tokens[str(t.get("entity", ""))] = _cell(t.get("at", [0, 0]))
	return {"id": ref, "name": str(m.get("name", ref)), "image": image_hash(str(m.get("image", ""))),
		"grid": {"size": float(grid.get("size", 70)), "offset": _vec(grid.get("offset", [0, 0]))},
		"kind": str(m.get("kind", "local")), "party_token": image_hash(str(m.get("party_token", ""))),
		"party_start": _cell(m.get("party_start", [1, 1])), "tokens": tokens}


## A token as players see it: {id, image, name, size, kind, owner, (owner only: hp, ac, class)}.
func token_view(ref: String, owner := "", for_owner := false) -> Dictionary:
	var e := entry(ref)
	if e.is_empty() or ref.get_slice("/", 0) not in CREATURES:
		return {}
	var token := str(e.get("token", ""))
	var view := {"id": ref, "image": image_hash(token if token != "" else str(e.get("image", ""))),
		"kind": ref.get_slice("/", 0), "owner": owner}
	for key: String in TOKEN_FIELDS:
		if e.has(key):
			view[key] = e[key]
	if not e.get("token_style") is Dictionary:  # a numbered copy: the look of what it was copied from
		var src := str(e.get("copy_of", "")).split("/")
		if src.size() == 3 and src[0] == world_id():
			var style: Variant = (world_entries(src[1]).get(src[2], {}) as Dictionary).get("token_style")
			if style is Dictionary:
				view["token_style"] = style
	if for_owner:
		for key: String in OWNER_FIELDS:
			if e.has(key):
				view[key] = e[key]
		if e.has("classes"):
			view["class"] = class_text(e)
	return view


## A whole entry as `viewer` (player id or "dm") may see it at a moment: <reveal> passages
## and %% comments they may not see are cut out (Reveal), with the reveal.changed events
## in `events` (e.g. EventLog.effective(ref, day, time)) applied. {} if there is none.
func entry_view(ref: String, viewer: String, events: Array = []) -> Dictionary:
	var e := entry(ref)
	if e.is_empty() or (EntryStore.is_draft(e) and viewer != Reveal.DM):
		return {}  # players never get drafts (TASK-30)
	var view := Reveal.filter_entry(e, viewer, Reveal.grants_from(events, ref))
	view["ref"] = ref
	return view


## "Ranger 3" or "Fighter 2 / Wizard 1" from a PC's classes.
func class_text(pc: Dictionary) -> String:
	var parts := PackedStringArray()
	for c: Variant in pc.get("classes", []):
		if c is Dictionary:
			var cls := str(c.get("class", "")).get_file().replace("-", " ").capitalize()
			parts.append("%s %d" % [cls, int(c.get("level", 1))])
	return " / ".join(parts)


## The PCs for the lobby picker: [{id, name, class, image, player, taken_by}].
## `taken_by` is the player's display name ("" = free to pick).
func pc_choices(owner_map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ref in pcs():
		var e := entry(ref)
		if EntryStore.is_draft(e):
			continue  # not finished: not offered to players
		var token := str(e.get("token", ""))
		var owned: Array = owner_map.get(ref, [])
		var owner: String = str(owned[0]) if not owned.is_empty() else ""
		out.append({"id": ref, "name": str(e.get("name", ref)), "class": class_text(e),
			"image": image_hash(token if token != "" else str(e.get("image", ""))),
			"player": owner, "taken_by": player_name(owner) if owner != "" else ""})
	return out


static func _cell(v: Variant) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1])) if v is Array and v.size() == 2 else Vector2i.ZERO


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO


static func _read(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data != null else fallback
