class_name Worlds
extends RefCounted
## Worlds and their timelines on disk (backlog/docs/timelines.md): `data/worlds/<world>/` is a
## world package (package.json kind "world", one JSON array per kind, assets/) with
## `timelines/<id>/`. Creating a world creates its start timeline ("Prologue").
## Also the migration from the old layout (data/campaigns/<id> + world packages in
## data/packages) into worlds with timelines.

const EXAMPLE := "res://examples/worlds/westmarch"
const EXAMPLE_TIMELINE := "red-fang"
## Campaign files that aren't entry kinds.
const CAMPAIGN_FILES := ["campaign", "notes", "table", "encounters"]
## Kinds that belong to the world even when a campaign made them (maps belong to the world).
const WORLD_KINDS := ["maps"]


## data/worlds next to data/packages.
static func default_root() -> String:
	return PackageDB.default_root().get_base_dir().path_join("worlds")


## The worlds in `root`: [package.json + {_dir}], by name.
static func list(root := "") -> Array[Dictionary]:
	var dir_root := root if root != "" else default_root()
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir_root):
		return out
	for d in DirAccess.get_directories_at(dir_root):
		if d.begins_with("."):
			continue
		var m: Variant = Timeline._read(dir_root.path_join(d).path_join("package.json"), null)
		if m is Dictionary and str(m.get("kind", "")) == "world":
			m["_dir"] = dir_root.path_join(d)
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower())
	return out


## A new world package with its start timeline. Returns the world folder.
static func create(world_name: String, calendar := "default", root := "") -> String:
	var dir_root := root if root != "" else default_root()
	DirAccess.make_dir_recursive_absolute(dir_root)
	var store := EntryStore.create_world(dir_root, world_name)
	store.manifest["calendar"] = calendar
	store.manifest["created"] = Time.get_datetime_string_from_system()
	store._save_manifest()
	Timeline.create(store.folder, Timeline.START_NAME, "", 0, [], {}, Timeline.START_ID)
	return store.folder


## The start timeline of a world (the one without a parent), creating it if missing.
static func start_timeline(world_dir: String) -> String:
	for t in Timeline.list(world_dir):
		if str(t.get("parent", "")) == "":
			return str(t._dir)
	return Timeline.create(world_dir, Timeline.START_NAME, "", 0, [], {}, Timeline.START_ID)


## Copies the example world (westmarch with its Prologue and the red-fang timeline) into
## `root` unless it is there. Returns the folder of the example timeline.
static func install_example(root := "") -> String:
	var dir_root := root if root != "" else default_root()
	var world := dir_root.path_join(EXAMPLE.get_file())
	if not FileAccess.file_exists(world.path_join("package.json")):
		copy_tree(EXAMPLE, world)
	return world.path_join("timelines").path_join(EXAMPLE_TIMELINE)


static func copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		if not f.ends_with(".import"):
			DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		copy_tree(from.path_join(d), to.path_join(d))


# --- Migration -------------------------------------------------------------------------

## Moves the old layout under `data_root` (the folder holding packages/) into worlds: world
## packages from packages/ to worlds/, every campaigns/<id> into a timeline of its world (the
## old folder is kept in campaigns-migrated/). Safe to run again. Returns what it did.
static func migrate_data(data_root: String) -> PackedStringArray:
	var done := PackedStringArray()
	var packages := data_root.path_join("packages")
	var worlds := data_root.path_join("worlds")
	if DirAccess.dir_exists_absolute(packages):
		for d in DirAccess.get_directories_at(packages):
			var m: Variant = Timeline._read(packages.path_join(d).path_join("package.json"), null)
			if m is Dictionary and str(m.get("kind", "")) == "world" and not DirAccess.dir_exists_absolute(worlds.path_join(d)):
				DirAccess.make_dir_recursive_absolute(worlds)
				if DirAccess.rename_absolute(packages.path_join(d), worlds.path_join(d)) == OK:
					start_timeline(worlds.path_join(d))
					done.append("world %s moved to worlds/" % d)
	var campaigns := data_root.path_join("campaigns")
	if not DirAccess.dir_exists_absolute(campaigns):
		return done
	for c in DirAccess.get_directories_at(campaigns):
		var cdir := campaigns.path_join(c)
		var cinfo: Variant = Timeline._read(cdir.path_join("campaign.json"), null)
		if not cinfo is Dictionary:
			continue
		var wid := str(cinfo.get("world", ""))
		if wid == EXAMPLE.get_file() and c == EXAMPLE_TIMELINE and not DirAccess.dir_exists_absolute(worlds.path_join(wid)):
			install_example(worlds)  # the example campaign: take the migrated example world
		elif wid == "" or not DirAccess.dir_exists_absolute(worlds.path_join(wid)):
			var made := create(str(cinfo.get("name", c)) + " world" if wid == "" else wid.capitalize(), str(cinfo.get("calendar", "default")), worlds)
			if wid != "" and made.get_file() != wid:
				DirAccess.rename_absolute(made, worlds.path_join(wid))
				made = worlds.path_join(wid)
			wid = made.get_file()
		var wdir := worlds.path_join(wid)
		start_timeline(wdir)
		if not DirAccess.dir_exists_absolute(wdir.path_join("timelines").path_join(str(cinfo.get("id", c)))):
			migrate_campaign(cdir, wdir)
		var keep := data_root.path_join("campaigns-migrated")
		DirAccess.make_dir_recursive_absolute(keep)
		DirAccess.rename_absolute(cdir, keep.path_join(c))
		done.append("campaign %s is now a timeline of %s" % [c, wid])
	if DirAccess.get_directories_at(campaigns).is_empty() and DirAccess.get_files_at(campaigns).is_empty():
		DirAccess.remove_absolute(campaigns)
	return done


## Turns a campaign folder into a timeline of `world_dir`, forked from the start timeline:
## - copies of world entries ("sent", origin layer world) become plain refs (dropped);
## - maps (and the places they show) go into the world; their token layout becomes
##   token.placed events in the timeline;
## - everything else made or copied in the campaign becomes an entity.created event;
## - events.jsonl follows after those (ids shifted), notes.json and assets/ are copied.
## Returns the timeline folder.
static func migrate_campaign(campaign_dir: String, world_dir: String) -> String:
	var cinfo: Dictionary = Timeline._read(campaign_dir.path_join("campaign.json"), {})
	var start := start_timeline(world_dir).get_file()
	var tdir := Timeline.create(world_dir, str(cinfo.get("name", campaign_dir.get_file())), start, 0,
		cinfo.get("players", []), cinfo.get("dm", {}), str(cinfo.get("id", campaign_dir.get_file())))
	var tinfo: Dictionary = Timeline._read(tdir.path_join("timeline.json"), {})
	for key in ["description", "next_session", "created"]:
		if cinfo.has(key):
			tinfo[key] = cinfo[key]
	EntryStore._write(tdir.path_join("timeline.json"), tinfo)
	if FileAccess.file_exists(campaign_dir.path_join("notes.json")):
		DirAccess.copy_absolute(campaign_dir.path_join("notes.json"), tdir.path_join("notes.json"))
	var world := EntryStore.open(world_dir)
	var lines := PackedStringArray()
	var next := 1
	var stamp := Time.get_datetime_string_from_system(true) + "Z"
	var placed := []  # [entity, map ref, cell]
	var to_world := {}  # "kind/id" -> true
	var kinds := {}
	for file in DirAccess.get_files_at(campaign_dir):
		if file.ends_with(".json") and file.get_basename() not in CAMPAIGN_FILES:
			var data: Variant = Timeline._read(campaign_dir.path_join(file), [])
			if data is Array:
				kinds[file.get_basename()] = data
	for m: Variant in kinds.get("maps", []):
		if m is Dictionary and str(m.get("place", "")) != "":
			to_world[str(m.place)] = true
	for kind: String in kinds:
		for e: Variant in kinds[kind]:
			if not e is Dictionary or not e.has("id"):
				continue
			var ref := "%s/%s" % [kind, e.id]
			var origin: Dictionary = e.get("origin", {}) if e.get("origin") is Dictionary else {}
			if str(origin.get("layer", "")) == "world" and world.has(kind, str(e.id)):
				continue  # a sent copy of the world entry: the world has it
			if kind in WORLD_KINDS or to_world.has(ref):
				var copy: Dictionary = e.duplicate(true)
				for t: Variant in copy.get("tokens", []):
					if t is Dictionary:
						placed.append([str(t.get("entity", "")), ref, t.get("at", [0, 0])])
				if copy.has("tokens"):
					copy["tokens"] = []
				for key in ["image", "token", "party_token"]:
					Timeline._copy_asset(campaign_dir, world_dir, str(copy.get(key, "")))
				if not world.has(kind, str(e.id)):
					world.save(kind, copy)
				continue
			var entry: Dictionary = e.duplicate(true)
			for key in ["image", "token", "party_token"]:
				Timeline._copy_asset(campaign_dir, tdir, str(entry.get(key, "")))
			lines.append(JSON.stringify({"id": next, "type": "entity.created", "entity": ref, "day": 0, "time": -1,
				"real": stamp, "session": 0, "by": "dm", "data": {"entry": EntryStore.whole_numbers(entry)}}))
			next += 1
	for p: Array in placed:
		lines.append(JSON.stringify({"id": next, "type": "token.placed", "entity": p[0], "day": 0, "time": -1,
			"real": stamp, "session": 0, "by": "dm", "data": {"map": p[1], "at": EntryStore.whole_numbers(p[2])}}))
		next += 1
	var shift := next - 1
	var old := EventLog.open(campaign_dir.path_join("events.jsonl"))
	for e in old.events:
		var copy: Dictionary = e.duplicate(true)
		copy.id = int(copy.id) + shift
		if copy.has("undoes"):
			copy.undoes = int(copy.undoes) + shift
		lines.append(JSON.stringify(copy))
	var f := FileAccess.open(tdir.path_join("events.jsonl"), FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	return tdir
