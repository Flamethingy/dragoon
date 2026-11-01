extends SceneTree
## Headless check of worlds with timelines (TASK-32, timelines.md): a new world gets its start
## timeline; forks share the parent's events up to the fork point and have their own after it;
## entries made in a timeline are entity.created events, seen only there and in later forks,
## and Promote puts one into the world; play never writes world files; the migration of an old
## data folder (world package in packages/, campaign in campaigns/) into worlds with timelines.
## godot --headless --path . -s tools/test_timelines.gd

const DIR := "user://test_timelines"

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	var worlds := base.path_join("worlds")

	# --- A new world and its start timeline ----------------------------------------------------
	var world := Worlds.create("Sunken Coast", "default", worlds)
	_check(FileAccess.file_exists(world.path_join("package.json")) and Worlds.list(worlds).size() == 1, "world package in worlds/")
	var start := world.path_join("timelines/prologue")
	_check(Timeline.is_timeline(start), "the start timeline Prologue is created with it")
	for f in ["timeline.json", "events.jsonl", "notes.json", "encounters.json"]:
		_check(FileAccess.file_exists(start.path_join(f)), "timeline has " + f)
	var store := EntryStore.open(world)
	store.save("npcs", {"id": "mira", "name": "Mira", "hp": 10, "description": "The smith."})
	var world_files := _snapshot(world)

	# --- Prologue: shared prep -------------------------------------------------------------------
	var pro := Timeline.new(start)
	var lantern := pro.add_entry("items", {"name": "Storm Lantern", "description": "Never goes out."})
	pro.events_log.place_token("npcs/mira", "maps/coast", Vector2i(2, 3))
	var fork_point: int = pro.events_log.events.back().id
	pro.events_log.change_hp("npcs/mira", -4, 6)  # after the fork point: only the prologue has it

	# --- Two forks ("campaign A and B") ----------------------------------------------------------
	var a := Timeline.new(pro.fork("Campaign A", fork_point, [{"id": "ann", "name": "Ann", "color": "#2e6e60"}]))
	var b := Timeline.new(pro.fork("Campaign B", fork_point))
	_check(a.info.parent == "prologue" and int(a.info.fork_at) == fork_point, "fork remembers parent and point")
	_check(a.events_log.inherited.size() == fork_point, "the fork shares the events up to the fork (%d)" % a.events_log.inherited.size())
	_check(not a.entry("items/" + str(lantern.id)).is_empty() and not b.entry("items/" + str(lantern.id)).is_empty(), "both see what the prologue made before the fork")
	_check(Replay.tokens_on("maps/coast", a.events_log.effective()).get("npcs/mira") == Vector2i(2, 3), "and the token placed before it")
	_check(a.events_log.effective("npcs/mira").all(func(e: Dictionary) -> bool: return e.type != "hp.changed"), "not the prologue's events after the fork")
	_check(a.players().size() == 1 and b.players().is_empty() or b.players() == pro.players(), "players per timeline")

	var sword := a.add_entry("items", {"name": "Sea Glass Sword", "description": "Found in A."})
	var ref := "items/" + str(sword.id)
	_check(a.events_log.events.back().type == "entity.created" and a.events_log.events.back().id == fork_point + 1, "made in A: entity.created, ids go on after the fork")
	_check(not a.entry(ref).is_empty() and b.entry(ref).is_empty() and pro.entry(ref).is_empty(), "only A has it")
	a.events_log.move_token("npcs/mira", "maps/coast", Vector2i(2, 3), Vector2i(7, 7))
	b.events_log.move_token("npcs/mira", "maps/coast", Vector2i(2, 3), Vector2i(0, 1))
	_check(Replay.tokens_on("maps/coast", a.events_log.effective())["npcs/mira"] == Vector2i(7, 7)
		and Replay.tokens_on("maps/coast", b.events_log.effective())["npcs/mira"] == Vector2i(0, 1), "the same map, different positions per timeline")
	var a2 := Timeline.new(a.fork("A: what if", -1))
	_check(not a2.entry(ref).is_empty(), "a later fork of A has it too")

	# A world entry changed in a timeline: an override, the world file stays.
	var mira := a.entry("npcs/mira").duplicate(true)
	mira["description"] = "The smith, now in debt."
	a.edit_entry("npcs", mira)
	_check(a.entry("npcs/mira").description == "The smith, now in debt." and b.entry("npcs/mira").description == "The smith.", "override only in A")

	# Editing through the store (the compendium's way).
	var astore := EntryStore.open(a.folder)
	_check(astore.layer == EntryStore.TIMELINE and astore.list("items").size() == 2, "the timeline as a store lists its own entries (and those made before the fork)")
	var made := astore.create("npcs", "Harbour Master")
	_check(made.draft and Timeline.new(a.folder).is_created("npcs/" + str(made.id)), "a new entry in the timeline is an event")
	astore.delete("npcs", str(made.id))
	_check(Timeline.new(a.folder).entry("npcs/" + str(made.id)).is_empty(), "deleting it is an event too")

	# Play never writes the world.
	a.events_log.start_session(1)
	a.events_log.change_hp("npcs/mira", -3, 7)
	a.events_log.end_session()
	_check(_snapshot(world) == world_files, "the world files are unchanged by play")

	# --- Promote into the world ---------------------------------------------------------------------
	var r := a.promote(ref)
	_check(r.has("promoted") and EntryStore.open(world).has("items", str(sword.id)), "promoted into the world package (%s)" % r)
	_check(not Timeline.new(b.folder).entry(ref).is_empty(), "now B sees it too (same ref and id)")
	_check(not a.is_created(ref) and not a.entry(ref).is_empty(), "A uses the world entry from now on")

	# --- The book with a timeline ---------------------------------------------------------------
	var db := PackageDB.new()
	db.timeline_dir = a.folder
	db.load_now(base.path_join("packages"))
	_check(db.get_entry("sunken-coast", "npcs", "mira").get("_layer") == "world", "world loaded from worlds/")
	_check(db.resolve_ref("npcs/mira").get("_layer") == "timeline", "the timeline's override wins")

	# --- Migration of the old layout ----------------------------------------------------------------
	var data := base.path_join("old")
	var vale := data.path_join("packages/vale")
	DirAccess.make_dir_recursive_absolute(vale)
	EntryStore._write(vale.path_join("package.json"), {"format": "dragoon-package", "format_version": 1, "id": "vale", "name": "Vale", "kind": "world"})
	EntryStore._write(vale.path_join("npcs.json"), [{"id": "elda", "name": "Elda"}])
	var camp := data.path_join("campaigns/hunt")
	DirAccess.make_dir_recursive_absolute(camp.path_join("assets/tokens"))
	EntryStore._write(camp.path_join("campaign.json"), {"format": "dragoon-campaign", "id": "hunt", "name": "The Hunt", "world": "vale",
		"players": [{"id": "ann", "name": "Ann", "color": "#2e6e60"}], "dm": {"name": "Nico", "color": "#7a3b8f"}, "next_session": 3})
	EntryStore._write(camp.path_join("npcs.json"), [{"id": "elda", "name": "Elda", "origin": {"layer": "world", "package": "vale"}}])
	EntryStore._write(camp.path_join("pcs.json"), [{"id": "kip", "name": "Kip", "player": "ann", "token": "assets/tokens/kip.png"}])
	FileAccess.open(camp.path_join("assets/tokens/kip.png"), FileAccess.WRITE).store_string("png")
	EntryStore._write(camp.path_join("maps.json"), [{"id": "den", "name": "Den", "tokens": [{"entity": "pcs/kip", "at": [1, 2]}]}])
	var old_log := EventLog.open(camp.path_join("events.jsonl"))
	old_log.change_hp("pcs/kip", -2, 8)
	old_log.undo(1)
	var done := Worlds.migrate_data(data)
	_check(done.size() == 2, "migration report (%s)" % [done])
	var hunt_dir := data.path_join("worlds/vale/timelines/hunt")
	_check(Timeline.is_timeline(hunt_dir) and Timeline.is_timeline(data.path_join("worlds/vale/timelines/prologue")), "the campaign is a timeline of its world, beside the Prologue")
	_check(not DirAccess.dir_exists_absolute(data.path_join("packages/vale")) and DirAccess.dir_exists_absolute(data.path_join("campaigns-migrated/hunt")), "world moved, old campaign kept aside")
	var hunt := Timeline.new(hunt_dir)
	_check(hunt.info.parent == "prologue" and int(hunt.info.next_session) == 3 and hunt.players().size() == 1, "timeline.json from campaign.json")
	_check(not hunt.is_created("npcs/elda") and hunt.entry("npcs/elda").name == "Elda", "a sent copy became a plain ref to the world")
	_check(hunt.is_created("pcs/kip") and FileAccess.file_exists(hunt_dir.path_join("assets/tokens/kip.png")), "the PC is an entity.created event, its token copied")
	_check(EntryStore.open(data.path_join("worlds/vale")).has("maps", "den"), "maps go into the world")
	_check(Replay.tokens_on("maps/den", hunt.events_log.effective()).get("pcs/kip") == Vector2i(1, 2), "the map's token layout became token.placed")
	var hp_events := hunt.events_log.events.filter(func(e: Dictionary) -> bool: return e.type == "hp.changed")
	_check(hp_events.size() == 2 and hunt.events_log.is_undone(hp_events[0].id), "old events follow, undo still points at the right event")
	_check(Worlds.migrate_data(data).is_empty(), "running it again changes nothing")

	print("timelines: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## file name -> content of the world's own files (not its timelines).
func _snapshot(folder: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(folder):
		out[f] = FileAccess.get_file_as_string(folder.path_join(f))
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
