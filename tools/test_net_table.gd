extends SceneTree
## Headless check of the TASK-5 spike: a DM table and a player table in one process
## (each with its own MultiplayerAPI) talk over ENet on localhost.
## godot --headless --path . -s tools/test_net_table.gd

const PORT := 47777
const LOG := "user://test_net/events.jsonl"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(LOG.get_base_dir()))
	await process_frame  # the tree is ready from the first frame on
	var dm := _table("DM")
	var player := _table("Player")
	await process_frame

	_check(dm.host(PORT) == OK, "DM hosts")
	_check(player.join("127.0.0.1:%d" % PORT) == OK, "player joins")
	if not await _until(func() -> bool: return player.status.begins_with("Joined")):
		_check(false, "player connected (status: %s)" % player.status)
	var wolf := "monsters/dire-wolf"
	var start: Vector2i = dm.grid.token_cell(wolf)

	# A player's move is only a request: nothing changes until the DM says so.
	player.grid.move_requested.emit(wolf, start + Vector2i(0, 3))
	_check(player.grid.token_cell(wolf) == start, "player doesn't move it on its own")
	await _until(func() -> bool: return dm.grid.token_cell(wolf) != start and player.grid.token_cell(wolf) != start)
	_check(dm.grid.token_cell(wolf) == start + Vector2i(0, 3), "DM sees the move")
	_check(player.grid.token_cell(wolf) == start + Vector2i(0, 3), "player sees the move")

	# The move is in the event log (TASK-2 format).
	var e: Dictionary = dm.event_log.events.back() if not dm.event_log.events.is_empty() else {}
	_check(e.get("type") == "token.moved" and e.get("entity") == wolf, "token.moved event logged")
	_check(str(e.get("by", "")).begins_with("player:"), "logged as the player's move")
	_check(e.get("data", {}).get("to") == [start.x, start.y + 3], "event has the target cell")
	var on_disk := EventLog.open(LOG)
	_check(on_disk.events.size() == dm.event_log.events.size(), "event is on disk")
	for key in ["id", "type", "entity", "day", "time", "real", "session", "by", "data"]:
		_check(e.has(key), "event has '%s'" % key)

	# A blocked move is refused and changes nothing.
	var chief := "monsters/goblin-chief"
	player.grid.move_requested.emit(wolf, dm.grid.token_cell(chief))
	await _until(func() -> bool: return player.status.begins_with("Can't move"))
	_check(player.status.begins_with("Can't move"), "blocked move denied (status: %s)" % player.status)
	_check(dm.event_log.events.size() == 1, "denied move not logged")

	# The DM moves directly.
	dm.grid.move_requested.emit(chief, Vector2i(2, 2))
	await _until(func() -> bool: return player.grid.token_cell(chief) == Vector2i(2, 2))
	_check(player.grid.token_cell(chief) == Vector2i(2, 2), "player sees the DM's move")

	# Notes: a player's note is stamped and saved by the DM and shown to everyone.
	player.add_note("We hide in the **barn**.")
	await _until(func() -> bool: return player.notes.entries.size() == 1 and dm.notes.entries.size() == 1)
	_check(dm.notes.entries.size() == 1 and player.notes.entries.size() == 1, "note reaches DM and player")
	if player.notes.entries.size() == 1:
		var n: Dictionary = player.notes.entries[0]
		_check(str(n.by).begins_with("Player ") and n.session == dm.event_log.session, "note stamped by the DM (%s)" % n)
		_check(player.notes.heading(n).contains(" · Prep · "), "player formats the heading")
	_check(FileAccess.get_file_as_string(SessionNotes.path_for(LOG.get_base_dir(), 0)).contains("**barn**"), "note saved as markdown")
	dm.start_next_session()
	await _until(func() -> bool: return player.notes.session == 1)
	_check(player.notes.session == 1 and player.notes.entries.is_empty(), "next session: new empty notes for everyone")
	dm.add_note("Session one begins.")
	await _until(func() -> bool: return player.notes.entries.size() == 1)
	_check(player.notes.entries.size() == 1 and player.notes.entries[0].session == 1, "DM note in session 1")

	# A second DM start continues from the log.
	var dm2 := _table("DM2")
	await process_frame
	dm.multiplayer.multiplayer_peer.close()
	dm2.host(PORT + 1)
	_check(dm2.grid.token_cell(wolf) == start + Vector2i(0, 3), "restarted DM restores token positions from the log")

	print("net table: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## A NetTable under its own branch with its own MultiplayerAPI (so two can talk).
func _table(branch: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.auto_ui = false
	t.log_path = LOG
	holder.add_child(t)
	return t


func _until(done: Callable, frames := 300) -> bool:
	for i in frames:
		if done.call():
			return true
		await process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
