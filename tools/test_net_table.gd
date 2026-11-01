extends SceneTree
## Headless check of the shared table (TASK-5/7/8/14): a DM and players in one process
## (each table with its own MultiplayerAPI) talk over ENet on localhost.
## godot --headless --path . -s tools/test_net_table.gd

const PORT := 47777
const ADDRESS := "127.0.0.1:47777"
const DIR := "user://test_net"
const LOG := DIR + "/campaign/events.jsonl"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	await process_frame  # the tree is ready from the first frame on
	var dm := _table("DM", "dm")
	var ann := _table("Ann", "ann")
	var bob := _table("Bob", "bob", true)  # with the UI, so the screens get built too
	await process_frame

	# --- Lobby: host, join with a name, pick a PC -----------------------------------
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(dm.grid.map_id == "maps/forest-road", "DM shows the first map (%s)" % dm.grid.map_id)
	_check(ann.join(ADDRESS, "Ann") == OK, "Ann joins")
	await _until(func() -> bool: return ann.pc_choices.size() == 2)
	_check(ann.pc_choices.size() == 2 and ann.my_pc == "", "Ann gets the PCs to pick from")
	await _until(func() -> bool: return ann.pc_choices.all(func(c: Dictionary) -> bool: return ann.assets.has(c.image)))
	_check(ann.pc_choices.all(func(c: Dictionary) -> bool: return ann.assets.texture(c.image) != null), "PC portraits arrive")
	ann.claim_pc("pcs/aria")
	await _until(func() -> bool: return ann.my_pc == "pcs/aria" and ann.grid.tokens.has("pcs/aria"))
	_check(ann.my_pc == "pcs/aria", "Ann plays Aria")
	_check(ann.grid.map_id == "maps/forest-road" and ann.grid.grid_size.x > 0, "Ann sees the map with its grid")
	_check(ann.grid.tokens.has("monsters/goblin-chief") and ann.grid.tokens.has("monsters/dire-wolf"), "Ann sees the monsters")
	_check(dm.grid.tokens.has("pcs/aria"), "Aria's token is on the DM's table too")
	var aria_info: Dictionary = ann.grid.tokens["pcs/aria"].get_meta("info")
	var chief_info: Dictionary = ann.grid.tokens["monsters/goblin-chief"].get_meta("info")
	_check(aria_info.get("hp") == 27 and aria_info.get("owner") == "Ann", "own PC with HP and owner")
	_check(chief_info.get("name") == "Goblin Chief" and not chief_info.has("hp"), "monster: name only, no HP")

	# --- DM-only content never reaches players ----------------------------------------
	var seen := JSON.stringify([ann._state, ann.pc_choices]) + var_to_str(ann.grid.tokens.values().map(
		func(t: Sprite2D) -> Dictionary: return t.get_meta("info")))
	for secret in ["dm_notes", "stolen caravan", "brother", "Leader of the", "Half-elf ranger", "[[Red Fang"]:
		_check(not seen.contains(secret), "player data has no '%s'" % secret)
	var stripped := Secrets.strip_entity(Frontmatter.load_file("res://examples/campaign/pcs/aria.md"))
	_check(not stripped.frontmatter.has("dm_notes") and stripped.frontmatter.has("hp"), "Secrets drops dm_ keys")
	_check(not stripped.body.contains("brother") and stripped.body.contains("Half-elf"), "Secrets drops %% comments %%")
	var body := "Intro\n## DM only\nhidden\n### deeper\nhidden too\n## Public\nshown\n> [!dm] Twist\n> secret line\nafter"
	var clean := Secrets.strip_body(body)
	_check(clean == "Intro\n## Public\nshown\nafter", "Secrets drops DM sections and callouts (%s)" % clean.c_escape())

	# --- A second player: names are unique, PCs too -------------------------------------
	bob.join(ADDRESS, "Ann")
	await _until(func() -> bool: return bob.status.begins_with("Can't join"))
	_check(bob.status.begins_with("Can't join"), "a taken name is refused (%s)" % bob.status)
	await _until(func() -> bool: return not bob.is_online())
	_check(not bob.is_online(), "refused player is back at the start screen")
	bob.join(ADDRESS, "Bob")
	await _until(func() -> bool: return bob.pc_choices.size() == 2)
	var aria_choice: Array = bob.pc_choices.filter(func(c: Dictionary) -> bool: return c.id == "pcs/aria")
	_check(not aria_choice.is_empty() and aria_choice[0].taken_by == "Ann", "Bob sees Aria is taken")
	bob.claim_pc("pcs/aria")
	await _until(func() -> bool: return bob.status.contains("already plays"))
	_check(bob.status.contains("already plays") and bob.my_pc == "", "taken PC refused")
	bob.claim_pc("pcs/borin")
	await _until(func() -> bool: return bob.my_pc == "pcs/borin" and ann.grid.tokens.has("pcs/borin") and bob.grid.tokens.has("pcs/aria"))
	_check(ann.grid.tokens.has("pcs/borin") and bob.grid.tokens.has("pcs/aria"), "both PCs on both tables")
	var ann_bob_info: Dictionary = ann.grid.tokens["pcs/borin"].get_meta("info")
	_check(not ann_bob_info.has("hp") and ann_bob_info.get("owner") == "Bob", "Ann doesn't get Borin's HP")

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
	_check(e.type == "token.moved" and e.entity == "pcs/aria" and e.by == "player:Ann", "move logged as Ann's (%s)" % e.get("by"))
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
	bob.add_note("We hide in the **barn**.")
	await _until(func() -> bool: return ann2.notes.entries.size() == 1 and dm.notes.entries.size() == 1)
	_check(ann2.notes.entries.size() == 1 and dm.notes.entries.size() == 1, "note reaches DM and players")
	if ann2.notes.entries.size() == 1:
		var n: Dictionary = ann2.notes.entries[0]
		_check(n.by == "Bob" and n.session == dm.event_log.session, "note stamped by the DM (%s)" % n)
		_check(ann2.notes.heading(n).contains(" · Prep · "), "player formats the heading")
	_check(FileAccess.get_file_as_string(SessionNotes.path_for(LOG.get_base_dir(), 0)).contains("**barn**"), "note saved as markdown")
	dm.start_next_session()
	await _until(func() -> bool: return bob.notes.session == 1)
	_check(bob.notes.session == 1 and bob.notes.entries.is_empty(), "next session: new empty notes for everyone")
	dm.add_note("Session one begins.")
	await _until(func() -> bool: return bob.notes.entries.size() == 1)
	_check(bob.notes.entries.size() == 1 and bob.notes.entries[0].session == 1, "DM note in session 1")

	# --- A restarted host continues: positions, players and map ------------------------------
	var dm2 := _table("DM2", "dm")
	await process_frame
	dm.multiplayer.multiplayer_peer.close()
	dm2.host(PORT + 1)
	_check(dm2.owners.get("pcs/aria") == "Ann" and dm2.owners.get("pcs/borin") == "Bob", "who plays whom is kept")
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
	t.log_path = LOG
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
