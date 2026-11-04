extends SceneTree
## Headless check of the Table Bunny's tools (TASK-96): every tool has a schema, runs as the
## asking player and refuses what that player couldn't do by hand; changes are events that
## can be undone.
## godot --headless --path . -s tools/test_bunny_tools.gd

const PORT := 47849
const ADDRESS := "127.0.0.1:47849"
const DIR := "user://test_bunny_tools"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"
const MIRA := "characters/mira"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and dm.peers.size() == 1)
	var bob_peer: int = dm.peers.keys()[0]

	# the registry
	var names := BunnyTools.names()
	_check(names.size() == 8 and BunnyTools.schemas().all(func(t: Dictionary) -> bool:
		return str(t.get("description", "")) != "" and t.get("input_schema") is Dictionary and t.input_schema.type == "object"), "8 tools, each with a description and a schema")
	_check(BunnyTools.run(dm, "shell", {"cmd": "dir"}, 1).has("error"), "no tool that isn't in the list")
	_check(BunnyTools.run(bob, "rules_lookup", {"query": "grappled"}, 1).has("error"), "only on the host")

	# rules_lookup
	var r := BunnyTools.run(dm, "rules_lookup", {"query": "grappled"}, bob_peer)
	_check(r.has("result") and str(r.result[0].name) == "Grappled" and str(r.result[0].text) != "", "rules_lookup finds a condition (%s)" % [r])

	# compendium_search / compendium_get: drafts and DM-only passages stay hidden
	r = BunnyTools.run(dm, "compendium_search", {"query": "goblin", "kind": "creatures"}, bob_peer)
	_check(r.has("result") and (r.result as Array).any(func(x: Dictionary) -> bool: return str(x.name).to_lower() == "goblin"), "search finds the goblin")
	var store := EntryStore.open(dm.timeline.world_dir)  # a place the DM hasn't finished
	store.save("places", {"id": "secret-mill", "name": "Secret Mill", "draft": true})
	dm.timeline.reload_world()
	r = BunnyTools.run(dm, "compendium_search", {"query": "mill", "kind": "places"}, 1)
	var dm_mill := (r.get("result", []) as Array).size()
	r = BunnyTools.run(dm, "compendium_search", {"query": "mill", "kind": "places"}, bob_peer)
	_check(dm_mill > 0 and (r.get("result", []) as Array).size() == dm_mill - 1, "a draft place: the DM finds it, Bob doesn't (%d / %s)" % [dm_mill, r])
	var as_dm := JSON.stringify(BunnyTools.run(dm, "compendium_get", {"ref": MIRA}, 1))
	var as_bob := JSON.stringify(BunnyTools.run(dm, "compendium_get", {"ref": MIRA}, bob_peer))
	_check("caravan iron" in as_dm and not ("caravan iron" in as_bob) and "Mira" in as_bob, "Mira's DM-only passage: the DM reads it, Bob doesn't")
	_check(BunnyTools.run(dm, "compendium_get", {"ref": "places/secret-mill"}, bob_peer).has("error"), "a draft looks like a missing entry to Bob")

	# sheet_read
	r = BunnyTools.run(dm, "sheet_read", {}, bob_peer)
	_check(r.has("result") and str(r.result.ref) == BORIN and r.result.has("hp") and not (r.result as Dictionary).keys().any(func(k: Variant) -> bool: return str(k).begins_with("_")), "Bob reads his own sheet")
	_check(BunnyTools.run(dm, "sheet_read", {"character": "Mira"}, bob_peer).has("error"), "but not Mira's")
	_check(BunnyTools.run(dm, "sheet_read", {"character": MIRA}, 1).has("result"), "the DM reads any")

	# add_to_sheet: the TASK-94 path, an event that can be undone
	var before := dm.event_log.events.size()
	r = BunnyTools.run(dm, "add_to_sheet", {"kind": "items", "entry": "Potion of Healing"}, bob_peer)
	_check(r.has("result") and "Potion of Healing" in str(r.result), "Bob adds a potion to Borin (%s)" % [r])
	_check(dm.event_log.events.size() == before + 1 and str(dm.event_log.events[-1].by) == "bob", "one event, in Bob's name")
	_check(_qty(dm.sheet_for(Reveal.DM, BORIN), "items/potion-of-healing") == 1, "it's in the inventory")
	dm.event_log.undo(int(dm.event_log.events[-1].id))
	_check(_qty(dm.sheet_for(Reveal.DM, BORIN), "items/potion-of-healing") == 0, "undone: gone again")
	before = dm.event_log.events.size()
	_check(BunnyTools.run(dm, "add_to_sheet", {"character": "Mira", "kind": "items", "entry": "Potion of Healing"}, bob_peer).has("error"), "Bob can't add to Mira")
	_check(BunnyTools.run(dm, "add_to_sheet", {"kind": "classes", "entry": "Wizard"}, bob_peer).has("error"), "no classes")
	_check(BunnyTools.run(dm, "add_to_sheet", {"kind": "spells", "entry": "No Such Spell"}, bob_peer).has("error"), "an unknown entry")
	_check(dm.event_log.events.size() == before, "refused: no events")
	r = BunnyTools.run(dm, "add_to_sheet", {"character": "Mira", "kind": "spells", "entry": "fire-bolt"}, 1)
	_check(r.has("result"), "the DM adds to Mira (%s)" % [r])

	# roll
	before = dm.event_log.events.size()
	r = BunnyTools.run(dm, "roll", {"query": "Perception"}, bob_peer)
	_check(r.has("result") and str(r.result.get("result", "")) != "" and dm.event_log.events.size() == before + 1, "Bob rolls Borin's Perception (%s)" % [r])
	_check(BunnyTools.run(dm, "roll", {"query": "Perception", "character": "Mira"}, bob_peer).has("error"), "not for Mira")
	_check(BunnyTools.run(dm, "roll", {"query": "2d6+3"}, bob_peer).has("result"), "a plain formula")

	# combat_state: HP only where the asker may see it
	_check(BunnyTools.run(dm, "combat_state", {}, bob_peer).result.active == false, "no combat yet")
	dm.start_combat()
	await process_frame
	r = BunnyTools.run(dm, "combat_state", {}, bob_peer)
	var rows: Array = r.result.get("order", []) if r.has("result") else []
	_check(r.has("result") and r.result.active and rows.size() > 1, "the order (%s)" % [r])
	var borin_row := rows.filter(func(o: Dictionary) -> bool: return str(o.name) == dm.timeline.name_of(BORIN))
	_check(not borin_row.is_empty() and borin_row[0].has("hp"), "Bob sees Borin's HP")
	_check(rows.filter(func(o: Dictionary) -> bool: return o.has("hp")).size() == borin_row.size(), "and no one else's")
	_check(BunnyTools.run(dm, "combat_state", {}, 1).result.order.all(func(o: Dictionary) -> bool: return o.has("hp")), "the DM sees all HP")

	# note_write
	var notes_before := dm.notes.entries.size()
	_check(BunnyTools.run(dm, "note_write", {"text": "The mill is haunted"}, bob_peer).has("result"), "Bob writes a note")
	_check(dm.notes.entries.size() == notes_before + 1 and str(dm.notes.entries[-1].by) == "bob", "in his name")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("bunny tools: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _qty(sheet: Dictionary, item: String) -> int:
	var inv: Variant = sheet.get("inventory", [])
	if inv is Dictionary:
		return int((inv as Dictionary).get(item, 0))
	for it: Variant in inv:
		if it is Dictionary and str(it.get("item", "")) == item:
			return int(it.get("qty", 1))
	return 0


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.timeline_dir = TIMELINE
	t.cache_dir = DIR.path_join("cache_" + cache)
	t.auto_ui = false
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 400) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
