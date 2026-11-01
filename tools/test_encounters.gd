extends SceneTree
## Headless check of encounters (TASK-35): ending a combat at the table saves an encounter
## {id, name, map, start_event, end_event, session, day, participants} in encounters.json;
## it can be renamed and its range moved; the replay shows tokens, HP and conditions at each
## step (per event, per round, jump to an event, play with a speed) and never writes events;
## the encounter list groups them by session.
## godot --headless --path . -s tools/test_encounters.gd

const DIR := "user://test_encounters"
const PORT := 47811

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	var red := Worlds.install_example(base.path_join("worlds"))
	await process_frame
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var table := NetTable.new()
	table.name = "Table"
	table.timeline_dir = red
	table.cache_dir = DIR.path_join("cache")
	table.auto_ui = false
	holder.add_child(table)
	await process_frame
	_check(table.host(PORT) == OK, "DM hosts")
	var fighters: Array = table.grid.tokens.keys().filter(func(id: String) -> bool: return "/" in id)
	_check(fighters.size() >= 2, "creatures on the map (%s)" % [fighters])
	var a: String = fighters[0]
	var b: String = fighters[1]
	var a_from := table.grid.token_cell(a)
	var b_hp := int(table.timeline.entry(b).get("hp", 0))

	# --- A combat at the table -------------------------------------------------------------------
	var started := table.start_combat()
	_check(started.type == "combat.started" and table.in_combat() and (started.data.order as Array).size() == fighters.size(), "combat starts with the creatures on the map")
	table._handle_move(1, a, a_from + Vector2i(1, 0))
	table.change_hp(b, -3, "bite")
	table.event_log.append("condition.applied", b, {"condition": "prone"})
	for i in fighters.size():
		table.next_turn()  # through the order: round 2
	_check(int(Replay.world_state(table.event_log.effective()).combat.round) == 2, "next turn goes round by round")
	table.change_hp(b, -2, "claw")
	table.event_log.append("condition.removed", b, {"condition": "prone"})
	var enc := table.end_combat("they fled")
	_check(not table.in_combat() and not enc.is_empty(), "ending the combat saves an encounter")
	for key in ["id", "name", "map", "start_event", "end_event", "session", "day", "participants"]:
		_check(enc.has(key), "encounter has " + key)
	_check(int(enc.start_event) == int(started.id) and int(enc.end_event) == int(table.event_log.events.back().id) and enc.map == table.map_id, "its range and map")
	_check(a in enc.participants and b in enc.participants, "participants (%s)" % [enc.participants])
	var stored := Encounters.open(red)
	_check(stored.list.size() == 1 and stored.list[0].id == enc.id, "in encounters.json")
	_check(stored.sync(table.event_log, table.timeline).is_empty() and Encounters.open(red).list.size() == 1, "not saved twice")
	_check(stored.rename(enc.id, "Ambush at the road") and Encounters.open(red).get_encounter(enc.id).name == "Ambush at the road", "renamed")

	# --- Replay ---------------------------------------------------------------------------------
	var log_before := FileAccess.get_file_as_string(table.timeline.events_path())
	var enc_before := FileAccess.get_file_as_string(red.path_join(Encounters.FILE))
	var events_before := table.event_log.events.size()
	var r := EncounterReplay.new(table.timeline, table.event_log, Encounters.open(red).get_encounter(enc.id))
	var s0 := r.state_at(0)
	_check(s0.tokens[a] == a_from and int(s0.creatures[b].hp) == b_hp, "before the fight: start cells and HP")
	var moved := r.step_of(int(started.id) + 1)
	_check(r.state_at(moved).tokens[a] == a_from + Vector2i(1, 0), "the move at its step")
	var s3 := r.state_at(4)  # started, move, hp, condition
	_check(int(s3.creatures[b].hp) == b_hp - 3 and "prone" in s3.creatures[b].conditions, "HP and condition after them (%s)" % [s3.creatures[b]])
	var r2 := r.next_round(1)
	_check(int(r.state_at(r2).round) == 2 and int(r.state_at(r2 - 1).round) == 1, "step per round (%d)" % r2)
	_check(r.previous_round(r.count()) == r2, "back to the round's start")
	var end := r.state_at(r.count())
	_check(int(end.creatures[b].hp) == b_hp - 5 and not "prone" in end.creatures[b].conditions and not end.active, "the end state")

	# The view: map, controls, event list.
	var view := ReplayView.new()
	view.assets = table.assets
	view.size = Vector2(1200, 700)
	root.add_child(view)
	view.open(r)
	await process_frame
	_check(view.grid.tokens.has(a) and view.grid.token_cell(a) == a_from, "replay map shows the start")
	_check(view.events_tree.get_root().get_child_count() == r.count() + 1, "event list beside it")
	view._items[moved].select(1)
	_check(view.step == moved and view.grid.token_cell(a) == a_from + Vector2i(1, 0), "clicking an event jumps there")
	view.go(3)
	_check(view.creatures_text.text.contains("HP %d" % (b_hp - 3)) or view.creatures_text.text.contains(str(b_hp - 3)), "HP shown (%s)" % view.creatures_text.text)
	view.go(0)
	view.speed = 4.0
	view.toggle_play()
	for i in 200:
		view._process(0.1)
	_check(view.step == r.count() and not view.playing, "play runs to the end and stops")
	_check(FileAccess.get_file_as_string(table.timeline.events_path()) == log_before and table.event_log.events.size() == events_before
		and FileAccess.get_file_as_string(red.path_join(Encounters.FILE)) == enc_before, "replay writes nothing")

	# --- Range and the list ---------------------------------------------------------------------
	var list := EncountersView.new()
	list.timeline = table.timeline
	list.events_log = table.event_log
	list.calendar = table.notes.calendar
	list.assets = table.assets
	root.add_child(list)
	await process_frame
	var session_item := list.tree.get_root().get_child(0)
	_check(session_item != null and session_item.get_child_count() == 1 and session_item.get_child(0).get_text(0) == "Ambush at the road", "listed by session")
	list.select(enc.id)
	list.start_spin.value = int(enc.start_event) + 1
	list.name_edit.text = "Road ambush"
	_check(list.apply(), "range and name saved")
	var changed := Encounters.open(red).get_encounter(enc.id)
	_check(int(changed.start_event) == int(enc.start_event) + 1 and changed.name == "Road ambush", "the new range (%s)" % [changed])
	_check(list.replay(enc.id) != null and list.replay_view.visible and list.replay_view.replay.count() == r.count() - 1, "replay from the list")
	_check(FileAccess.get_file_as_string(table.timeline.events_path()) == log_before, "still no events written")

	table.multiplayer.multiplayer_peer.close()
	print("encounters: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
