extends SceneTree
## Headless check of the shared table (TASK-5/7/8/13/14/20): a DM and players in one
## process (each table with its own MultiplayerAPI) talk over ENet on localhost. The DM hosts
## a copy of the example timeline; in the copy Borin has no player, so Bob picks him.
## godot --headless --path . -s tools/test_net_table.gd

const PORT := 47777
const ADDRESS := "127.0.0.1:47777"
const DIR := "user://test_net"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	_set_player(TIMELINE, "borin", "")  # a free PC to pick in the lobby
	await process_frame  # the tree is ready from the first frame on
	var dm := _table("DM", "dm")
	var ann := _table("Ann", "ann")
	var bob := _table("Bob", "bob", true)  # with the UI, so the screens get built too
	await process_frame

	# --- Lobby: host, join with a player name, own PC from the timeline ---------------------
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(dm.grid.map_id == "maps/forest-road", "DM shows the first map (%s)" % dm.grid.map_id)
	_check(dm.owners == {"pcs/aria": "ann"}, "owners from the PCs (%s)" % [dm.owners])
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.my_pc == "pcs/aria" and ann.grid.tokens.has("pcs/aria"))
	_check(ann.my_pc == "pcs/aria" and ann.my_player == "ann", "Ann (player ann) plays Aria right away")
	_check(ann.pc_choices.size() == 2, "the PC list arrives too")
	await _until(func() -> bool: return ann.pc_choices.all(func(c: Dictionary) -> bool: return ann.assets.has(c.image)))
	_check(ann.pc_choices.all(func(c: Dictionary) -> bool: return ann.assets.texture(c.image) != null), "PC portraits arrive")
	_check(ann.grid.map_id == "maps/forest-road" and ann.grid.grid_size.x > 0, "Ann sees the map with its grid")
	_check(ann.grid.tokens.has("monsters/goblin-chief") and ann.grid.tokens.has("monsters/dire-wolf"), "Ann sees the monsters")
	_check(ann.grid.token_cell("pcs/aria") == Vector2i(3, 6), "Aria at the party start")
	_check(dm.grid.tokens.has("pcs/aria"), "Aria's token is on the DM's table too")
	var aria_info: Dictionary = ann.grid.tokens["pcs/aria"].get_meta("info")
	var chief_info: Dictionary = ann.grid.tokens["monsters/goblin-chief"].get_meta("info")
	_check(aria_info.get("hp") == 27 and aria_info.get("owner") == "ann" and aria_info.get("class") == "Ranger 3", "own PC with HP, class and owner (%s)" % aria_info)
	_check(chief_info.get("name") == "Goblin Chief" and not chief_info.has("hp"), "monster: name only, no HP")

	# --- DM-only content never reaches players ----------------------------------------
	var seen := JSON.stringify([ann._state, ann.pc_choices]) + var_to_str(ann.grid.tokens.values().map(
		func(t: Sprite2D) -> Dictionary: return t.get_meta("info")))
	for secret in ["reveal", "stolen caravan", "brother", "Leader of the", "Half-elf ranger", "[[Red Fang", "Chain Shirt"]:
		_check(not seen.contains(secret), "player data has no '%s'" % secret)

	# --- Logins: only the timeline's players, once; free PCs can be picked --------------------
	bob.join(ADDRESS, "Carl")
	await _until(func() -> bool: return bob.status.begins_with("Can't join"))
	_check(bob.status.contains("isn't a player"), "an unknown name is refused (%s)" % bob.status)
	await _until(func() -> bool: return not bob.is_online())
	bob.join(ADDRESS, "ann")
	await _until(func() -> bool: return bob.status.begins_with("Can't join") and bob.status.contains("already"))
	_check(bob.status.contains("already at the table"), "a player already there is refused (%s)" % bob.status)
	await _until(func() -> bool: return not bob.is_online())
	_check(not bob.is_online(), "refused player is back at the start screen")
	bob.join(ADDRESS, "Bob")
	await _until(func() -> bool: return bob.pc_choices.size() == 2)
	_check(bob.my_pc == "" and bob.my_player == "bob", "Bob has no PC yet")
	var aria_choice: Array = bob.pc_choices.filter(func(c: Dictionary) -> bool: return c.id == "pcs/aria")
	_check(not aria_choice.is_empty() and aria_choice[0].taken_by == "Ann", "Bob sees Aria is taken by Ann")
	bob.claim_pc("pcs/aria")
	await _until(func() -> bool: return bob.status.contains("already plays"))
	_check(bob.status.contains("already plays") and bob.my_pc == "", "taken PC refused")
	bob.claim_pc("pcs/borin")
	await _until(func() -> bool: return bob.my_pc == "pcs/borin" and ann.grid.tokens.has("pcs/borin") and bob.grid.tokens.has("pcs/aria"))
	_check(ann.grid.tokens.has("pcs/borin") and bob.grid.tokens.has("pcs/aria"), "both PCs on both tables")
	var ann_bob_info: Dictionary = ann.grid.tokens["pcs/borin"].get_meta("info")
	_check(not ann_bob_info.has("hp") and ann_bob_info.get("owner") == "bob", "Ann doesn't get Borin's HP")

	# --- Moves: own token only, tweened, logged ------------------------------------------
	var start := ann.grid.token_cell("pcs/aria")
	var to := start + Vector2i(0, 2)
	_check(ann._may_drag("pcs/aria") and not ann._may_drag("monsters/dire-wolf") and not ann._may_drag("pcs/borin"), "Ann may only drag Aria")
	ann.grid.move_requested.emit("pcs/aria", to)
	await _until(func() -> bool: return bob.grid.token_cell("pcs/aria") == to)
	_check(bob.grid.token_cell("pcs/aria") == to and dm.grid.token_cell("pcs/aria") == to, "Aria's move reaches everyone")
	var token: Sprite2D = bob.grid.tokens["pcs/aria"]
	var target := bob.grid.cell_center(to, 1.0)
	_check(token.position.distance_to(target) > 1.0, "the token glides (not there yet)")
	await _until(func() -> bool: return token.position.is_equal_approx(target), 2000)
	_check(token.position.is_equal_approx(target), "and snaps onto the cell")
	var e: Dictionary = dm.event_log.events.back()
	_check(e.type == "token.moved" and e.entity == "pcs/aria" and e.by == "ann", "move logged as Ann's (%s)" % e.get("by"))
	var events_before := dm.event_log.events.size()
	ann.request_move.rpc_id(1, "monsters/dire-wolf", Vector2i(1, 1))  # bypassing the UI check
	await _until(func() -> bool: return ann.status.contains("not your token"))
	_check(ann.status.contains("not your token") and dm.event_log.events.size() == events_before, "moving someone else's token is refused")
	dm.grid.move_requested.emit("monsters/dire-wolf", Vector2i(2, 2))
	await _until(func() -> bool: return ann.grid.token_cell("monsters/dire-wolf") == Vector2i(2, 2))
	_check(ann.grid.token_cell("monsters/dire-wolf") == Vector2i(2, 2), "the DM moves anything")

	# --- Map change: images by hash, only new ones are sent -------------------------------
	var received := ann.assets_received
	dm.show_map_to_all("maps/old-mill")
	await _until(func() -> bool: return ann.grid.map_id == "maps/old-mill" and bob.grid.map_id == "maps/old-mill")
	_check(ann.grid.map_id == "maps/old-mill", "players see the new map")
	_check(ann.assets_received == received + 1, "only the new map image was sent (%d)" % (ann.assets_received - received))
	_check(ann.grid.tokens.has("pcs/aria") and not ann.grid.tokens.has("monsters/goblin-chief"), "PCs come along, the chief stays behind")
	_check(ann.grid.token_cell("pcs/aria") == Vector2i(2, 6), "Aria at the party start (%s)" % ann.grid.token_cell("pcs/aria"))
	received = ann.assets_received
	dm.show_map_to_all("maps/forest-road")
	await _until(func() -> bool: return ann.grid.map_id == "maps/forest-road")
	_check(ann.assets_received == received, "the old map comes from the cache")
	_check(ann.grid.token_cell("pcs/aria") == to, "Aria back where she was on this map")

	# --- World map: the party travels as one token (TASK-13) ------------------------------
	dm.show_map_to_all("maps/westmarch")
	await _until(func() -> bool: return ann.grid.map_id == "maps/westmarch" and ann.grid.tokens.has("party") and bob.grid.tokens.has("party"))
	_check(ann.grid.tokens.has("party") and not ann.grid.tokens.has("pcs/aria") and not ann.grid.tokens.has("pcs/borin"), "one party token instead of the PCs")
	var party: Dictionary = ann.grid.tokens["party"].get_meta("info") if ann.grid.tokens.has("party") else {}
	_check(str(party.get("name", "")).contains("Aria Windrunner") and str(party.get("name", "")).contains("Borin Stoneshield"), "named after its members (%s)" % party.get("name"))
	_check(ann.grid.token_cell("party") == Vector2i(4, 9), "starts at the party start")
	_check(ann._may_drag("party") and bob._may_drag("party"), "every member may move the party")
	var before_travel := dm.event_log.events.size()
	ann.grid.move_requested.emit("party", Vector2i(8, 6))
	await _until(func() -> bool: return bob.grid.token_cell("party") == Vector2i(8, 6))
	_check(bob.grid.token_cell("party") == Vector2i(8, 6), "the party token moves for everyone")
	var travel := dm.event_log.events.slice(before_travel)
	_check(travel.size() == 2, "one event per member (%d)" % travel.size())
	var movers := travel.map(func(ev: Dictionary) -> String: return ev.entity)
	movers.sort()
	_check(movers == ["pcs/aria", "pcs/borin"], "events for Aria and Borin (%s)" % [movers])
	_check(travel.all(func(ev: Dictionary) -> bool: return ev.type == "token.moved" and ev.data.get("group") == "party" 		and ev.data.get("to") == [8, 6] and ev.by == "ann"), "token.moved with group party, by Ann")
	dm.show_map_to_all("maps/forest-road")
	await _until(func() -> bool: return ann.grid.map_id == "maps/forest-road" and ann.grid.tokens.has("pcs/aria"))
	_check(ann.grid.tokens.has("pcs/aria") and ann.grid.tokens.has("pcs/borin") and not ann.grid.tokens.has("party"), "a local map shows the members one by one")
	_check(ann.grid.token_cell("pcs/aria") == to, "at their own positions on this map")
	dm.show_map_to_all("maps/westmarch")
	await _until(func() -> bool: return ann.grid.map_id == "maps/westmarch")
	_check(ann.grid.token_cell("party") == Vector2i(8, 6), "back on the world map the party is where it travelled to")
	dm.show_map_to_all("maps/forest-road")
	await _until(func() -> bool: return ann.grid.map_id == "maps/forest-road" and bob.grid.map_id == "maps/forest-road")

	# --- Disconnect and rejoin without restarting the host ---------------------------------
	ann.multiplayer.multiplayer_peer.close()
	await _until(func() -> bool: return dm.peers.size() == 1)
	_check(dm.peers.size() == 1 and dm.grid.tokens.has("pcs/aria"), "Ann left, Aria stays")
	var ann2 := _table("Ann2", "ann")  # same cache folder: a restarted client
	await process_frame
	ann2.join(ADDRESS, "Ann")
	await _until(func() -> bool: return ann2.my_pc == "pcs/aria" and ann2.grid.tokens.has("pcs/aria"))
	_check(ann2.my_pc == "pcs/aria", "Ann gets Aria back by name")
	_check(ann2.grid.token_cell("pcs/aria") == to, "at her last position")
	_check(ann2.assets_received == 0, "everything from the disk cache (%d downloads)" % ann2.assets_received)

	# --- Notes (TASK-14) ----------------------------------------------------------------
	var prep := dm.notes.entries.size()  # the example timeline has a prep note
	_check(ann2.notes.entries.size() == prep, "joining players get the session's notes (%d)" % prep)
	bob.add_note("We hide in the **barn**.")
	await _until(func() -> bool: return ann2.notes.entries.size() == prep + 1 and dm.notes.entries.size() == prep + 1)
	_check(ann2.notes.entries.size() == prep + 1 and dm.notes.entries.size() == prep + 1, "note reaches DM and players")
	if ann2.notes.entries.size() == prep + 1:
		var n: Dictionary = ann2.notes.entries.back()
		_check(n.by == "bob" and n.session == dm.event_log.session, "note stamped by the DM (%s)" % n)
		_check(ann2.notes.heading(n).contains(" · Prep · ") and ann2.notes.heading(n).ends_with(" · Bob"), "player formats the heading (%s)" % ann2.notes.heading(n))
	_check(FileAccess.get_file_as_string(TIMELINE.path_join("notes.json")).contains("We hide in the **barn**."), "note saved in notes.json")
	dm.start_next_session()
	await _until(func() -> bool: return bob.notes.session == 1)
	_check(bob.notes.session == 1 and bob.notes.entries.is_empty(), "next session: new empty notes for everyone")
	dm.add_note("Session one begins.")
	await _until(func() -> bool: return bob.notes.entries.size() == 1)
	_check(bob.notes.entries.size() == 1 and bob.notes.entries[0].session == 1, "DM note in session 1")
	dm.add_note("Mira lied. %% She works for the clan. %% <reveal id=\"rn\" for=\"bob\">Bob saw her.</reveal>")
	await _until(func() -> bool: return bob.notes.entries.size() == 2 and ann2.notes.entries.size() == 2)
	var bob_note: String = bob.notes.entries.back().text if bob.notes.entries.size() == 2 else ""
	var ann_note: String = ann2.notes.entries.back().text if ann2.notes.entries.size() == 2 else ""
	_check(bob_note.contains("Bob saw her") and not bob_note.contains("clan"), "notes filtered for Bob (%s)" % bob_note)
	_check(ann_note.begins_with("Mira lied.") and not ann_note.contains("Bob saw") and not ann_note.contains("clan"), "notes filtered for Ann (%s)" % ann_note)
	_check(dm.notes.entries.back().text.contains("clan"), "the DM keeps the whole note")

	# --- Reveals: the host cuts each player's view, changes arrive live (TASK-18) -----------
	const AMULET := "items/moonstone-amulet"
	ann2.open_entry(AMULET)
	bob.open_entry(AMULET)
	await _until(func() -> bool: return ann2.entries.has(AMULET) and bob.entries.has(AMULET))
	var ann_desc: String = ann2.entries.get(AMULET, {}).get("description", "")
	var bob_desc: String = bob.entries.get(AMULET, {}).get("description", "")
	_check(ann_desc.contains("**Function:**") and not ann_desc.contains("Curse"), "Ann gets the function, not the curse")
	_check(bob_desc.begins_with("A silver amulet") and not bob_desc.contains("Function") and not bob_desc.contains("Curse"), "Bob gets neither")
	dm.change_reveal(AMULET, "r7", ["bob"])
	await _until(func() -> bool: return str(bob.entries[AMULET].get("description", "")).contains("Function"))
	_check(str(bob.entries[AMULET].description).contains("for=\"ann,bob\""), "Bob sees the function now, framed for both")
	_check(dm.event_log.effective(AMULET).back().type == "reveal.changed", "logged as reveal.changed")
	_check(not str(bob.entries[AMULET].description).contains("Curse"), "the curse stays hidden")

	# --- Account colors (TASK-19) ---------------------------------------------------------------
	_check(bob.accounts.get("ann", {}).get("color") == "#2e6e60" and bob.accounts.has("dm"), "players get the account colors")
	ann2.set_my_color(Color.html("#ff8800"))
	await _until(func() -> bool: return bob.accounts.get("ann", {}).get("color") == "#ff8800")
	_check(bob.accounts.ann.color == "#ff8800", "Ann's new color reaches Bob")
	_check(FileAccess.get_file_as_string(ProjectSettings.globalize_path(TIMELINE).path_join("timeline.json")).contains("#ff8800"), "saved in timeline.json")
	dm.set_my_color(Color.html("#334455"))
	await _until(func() -> bool: return ann2.accounts.get("dm", {}).get("color") == "#334455")
	_check(ann2.accounts.dm.color == "#334455", "the DM's color too")

	# --- A restarted host continues: positions, players and map ------------------------------
	var dm2 := _table("DM2", "dm")
	await process_frame
	dm.multiplayer.multiplayer_peer.close()
	dm2.host(PORT + 1)
	_check(dm2.owners.get("pcs/aria") == "ann" and dm2.owners.get("pcs/borin") == "bob", "who plays whom is kept (%s)" % [dm2.owners])
	_check(dm2.grid.token_cell("pcs/aria") == to, "positions restored from the log")
	_check(dm2.grid.token_cell("monsters/dire-wolf") == Vector2i(2, 2), "the DM's moves too")

	print("net table: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## A NetTable under its own branch with its own MultiplayerAPI (so several can talk).
func _table(branch: String, cache: String, ui := false) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = ui
	t.timeline_dir = TIMELINE
	t.cache_dir = DIR.path_join("cache_" + cache)
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


## Sets a PC's player in the timeline (an entity.edited event, as the editor would).
func _set_player(timeline_dir: String, pc: String, player: String) -> void:
	var tl := Timeline.new(ProjectSettings.globalize_path(timeline_dir))
	var e := tl.entry("pcs/" + pc).duplicate(true)
	e["player"] = player
	tl.edit_entry("pcs", e)