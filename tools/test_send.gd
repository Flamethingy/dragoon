extends SceneTree
## Headless check of "send into the campaign" (TASK-11): one core/world entity or a whole world
## becomes a campaign copy with its origin (and an entity.sent event); the copy doesn't follow
## later changes of the original; two campaigns hold different versions.
## godot --headless --path . -s tools/test_send.gd

const DIR := "user://test_send"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var root := ProjectSettings.globalize_path(DIR + "/packages")
	Campaign._copy_tree("res://examples/packages/westmarch", root.path_join("westmarch"))
	var world := EntryStore.open(root.path_join("westmarch"))
	var core := EntryStore.open(PackageDB.default_root().path_join("5e-core-rules"))
	var a_dir := _blank_campaign("camp-a")
	var b_dir := _blank_campaign("camp-b")
	var a := EntryStore.open(a_dir)
	var b := EntryStore.open(b_dir)
	var alog := EventLog.open(a_dir.path_join("events.jsonl"))

	# --- One entity --------------------------------------------------------------------------
	var gob := a.send(core, "monsters", "goblin", alog)
	_check(gob.get("name") == "Goblin" and a.has("monsters", "goblin"), "core goblin sent")
	_check(gob.origin.layer == "core" and gob.origin.package == "5e-core-rules" and gob.origin.id == "goblin", "origin kept (%s)" % gob.get("origin"))
	var ev: Dictionary = alog.events.back()
	_check(ev.type == "entity.sent" and ev.entity == "monsters/goblin" and ev.data.source == "core:5e-core-rules/monsters/goblin" and ev.data.layer == "core", "entity.sent logged (%s)" % ev.get("data"))
	_check(a.has("features", str(gob.actions[0])), "its features came along")
	var gob2 := a.send(core, "monsters", "goblin", alog)
	_check(gob2.id == "goblin-2", "sending again makes a second copy (two goblins)")
	var mira := a.send(world, "npcs", "mira", alog)
	_check(mira.origin.layer == "world" and alog.events.back().data.source == "world:npcs/mira", "world NPC sent with world: source")

	# --- The copy drifts freely ---------------------------------------------------------------------
	var orig := world.find("npcs", "mira").duplicate(true)
	orig["description"] = "Changed in the world later."
	world.save("npcs", orig)
	_check(EntryStore.open(a_dir).find("npcs", "mira").description != "Changed in the world later.", "changing the original doesn't touch the copy")

	# --- Two campaigns, two versions ---------------------------------------------------------------
	b.send(world, "npcs", "mira")
	var in_a := a.find("npcs", "mira").duplicate(true)
	in_a["role"] = "Guild master"
	a.save("npcs", in_a)
	_check(EntryStore.open(a_dir).find("npcs", "mira").role == "Guild master" and EntryStore.open(b_dir).find("npcs", "mira").role != "Guild master", "campaigns hold different versions")

	# --- A whole world ---------------------------------------------------------------------------------
	var r := b.send_world(world)
	_check(r.skipped == ["npcs/mira"], "already sent entries are skipped (%s)" % [r.skipped])
	_check(r.sent.has("places/thornwick") and r.sent.has("factions/red-fang-clan") and r.sent.has("maps/westmarch"), "the rest of the world sent (%s)" % [r.sent])
	var map := EntryStore.open(b_dir).find("maps", "westmarch")
	_check(FileAccess.file_exists(b_dir.path_join(str(map.image))), "map image copied into the campaign (%s)" % map.get("image"))

	# --- In the compendium -------------------------------------------------------------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	get_root().add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	book.campaign_dir = a_dir
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	var thornwick := book.db.resolve_ref("world:places/thornwick")
	var view := book.open_tab(thornwick)
	_check(view.send_button.visible, "world entries show 'Send to campaign'")
	view.send_requested.emit(view.entry)
	var key := book.current_tab_key()
	_check(key == "camp-a/places/thornwick" and book.db.resolve_ref("places/thornwick").get("_layer") == "campaign", "sent copy opens and wins in the index (%s)" % key)
	_check(not book.open_view(key).send_button.visible, "campaign entries have no send button")
	book.send_world_to_campaign(world)
	await book.db.loaded
	await process_frame
	_check(not book.db.get_entry("camp-a", "factions", "red-fang-clan").is_empty(), "Send world from the book")

	print("send: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _blank_campaign(id: String) -> String:
	var dir := ProjectSettings.globalize_path(DIR + "/" + id)
	DirAccess.make_dir_recursive_absolute(dir)
	EntryStore._write(dir.path_join("campaign.json"), {"format": "dragoon-campaign", "format_version": 1, "id": id,
		"name": id.capitalize(), "world": "westmarch", "players": [], "dm": {"name": "DM", "color": "#7a3b8f"}})
	return dir


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
