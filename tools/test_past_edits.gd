extends SceneTree
## Headless check of changing the past (TASK-85) and setting the time back (TASK-88):
## the DM's actions while looking back go in right after that moment (`after`), in timeline
## order, without moving the clock, while the players' actions stay at now; the moment is
## marked as edited. Setting the time back asks once and deletes everything after the moment
## (file and memory), the clock goes back, every screen follows; forks that inherited deleted
## events get their own copy first; going back before a fork is refused; old logs with a
## `timeline.rewound` event are migrated.
## godot --headless --path . -s tools/test_past_edits.gd

const PORT := 47836
const ADDRESS := "127.0.0.1:47836"
const DIR := "user://test_past_edits"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame

	# ordering: an event with an `after` chain sorts right after its anchor
	var a := {"id": 5, "day": 1, "time": 10}
	var b := {"id": 6, "day": 1, "time": 10}
	var ins := {"id": 9, "day": 1, "time": 10, "after": [5]}
	var ins2 := {"id": 10, "day": 1, "time": 10, "after": [5, 9]}
	var list: Array = [b, ins2, a, ins]
	list.sort_custom(Replay.before)
	_check(list.map(func(e: Dictionary) -> int: return e.id) == [5, 9, 10, 6], "after chains sort in place (%s)" % [list.map(func(e: Dictionary) -> int: return e.id)])

	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and bob.grid.tokens.has(BORIN))
	var log := dm.event_log
	var map := dm.grid.map_id
	var start := dm.grid.token_cell(BORIN)

	# history: walk (moment A), an hour later a second walk (moment B)
	log.advance_time(log.day, maxi(log.time, 0) + 60, "walk")
	dm._handle_move(1, BORIN, start + Vector2i(2, 0), [start, start + Vector2i(1, 0), start + Vector2i(2, 0)])
	var walk_a := int(log.events.back().id)
	log.advance_time(log.day, log.time + 60, "on")
	dm._handle_move(1, BORIN, start + Vector2i(4, 0), [])
	var walk_b := int(log.events.back().id)
	await _frames(5)
	var clock := Vector2i(log.day, log.time)
	var a_ev := log.get_event(walk_a)

	# TASK-85: the DM looks back at moment A and moves Borin down there
	dm.look_back(walk_a)
	_check(not dm.grid.locked and log.insert_after == [walk_a], "looking back, the DM's actions go in after the moment (%s)" % [log.insert_after])
	dm._on_move_requested(BORIN, start + Vector2i(2, 2))
	var moved: Dictionary = log.events.back()
	_check(moved.type == "token.moved" and moved.get("after", []) == [walk_a], "the move goes into the past (%s)" % [moved.get("after")])
	_check(int(moved.day) == int(a_ev.day) and int(moved.time) == int(a_ev.time), "stamped with that moment's time")
	_check(Vector2i(log.day, log.time) == clock, "the clock stays at now")
	var order: Array = log.effective().map(func(e: Dictionary) -> int: return int(e.id))
	_check(order.find(int(moved.id)) == order.find(walk_a) + 1 and order.find(int(moved.id)) < order.find(walk_b), "in timeline order right after the walk, before the later one")
	await _until(func() -> bool: return dm.looking_back == int(moved.id))
	_check(dm.looking_back == int(moved.id) and dm.grid.past[BORIN].get_meta("cell") == start + Vector2i(2, 2), "the DM now sees it there")
	_check(dm.grid.token_cell(BORIN) == start + Vector2i(4, 0), "the present is unchanged (his later walk)")
	# a second one follows the first
	log.change_hp(BORIN, -2, 10, "a thorn")
	var hurt: Dictionary = log.events.back()
	_check(hurt.get("after", []) == [walk_a, int(moved.id)], "the next change follows it (%s)" % [hurt.get("after")])
	# Bob acts at now meanwhile: his move stays at now
	var n := log.events.size()
	bob.request_move.rpc_id(1, BORIN, start + Vector2i(4, 1), [])
	await _until(func() -> bool: return log.events.size() > n)
	_check(log.events.size() > n and not log.events.back().has("after"), "a player's move meanwhile stays at now (%s; %s)" % [log.events.back(), bob.status])
	await _frames(5)
	var edited := false
	for m: Dictionary in dm.timeline_sync.data.moments:
		if int(walk_a) >= int(m.first_id) and int(walk_a) <= int(m.last_id):
			edited = bool(m.get("edited", false))
	_check(edited, "the moment is marked as changed on the bar")
	dm.look_back(-1)
	_check(log.insert_after.is_empty(), "back at now: no more inserting")

	# reloading keeps the order and the clock
	var again := EventLog.open(log.path)
	_check(again.effective().map(func(e: Dictionary) -> int: return int(e.id)) == log.effective().map(func(e: Dictionary) -> int: return int(e.id)), "the order survives a reload")
	_check(Vector2i(again.day, again.time) == Vector2i(log.day, log.time), "and the clock (%s / %s)" % [Vector2i(again.day, again.time), Vector2i(log.day, log.time)])

	var home := Control.new()
	home.size = Vector2(1600, 900)
	root.add_child(home)

	# TASK-85: undo and correct from the Timeline list (a box's events)
	var view := TimelineView.new()
	view.event_log = log
	view.timeline = dm.timeline
	view.calendar = dm.notes.calendar
	var refreshed := [0]
	view.on_changed = func() -> void:
		refreshed[0] += 1
		dm.refresh_tokens()
	home.add_child(view)
	await _frames(2)
	view.show_moment([walk_a, int(moved.id), int(hurt.id)])
	_check(view.tree.get_root().get_child_count() == 3, "the list shows that moment's events (%d)" % view.tree.get_root().get_child_count())
	_pick(view, int(hurt.id))
	_check(not view.edit_button.disabled, "an event can be corrected")
	var hurt_at := log.effective().map(func(e: Dictionary) -> int: return int(e.id)).find(int(hurt.id))
	view.edit_selected()
	(view._fields["delta"] as LineEdit).text = "-6"
	(view._fields["hp"] as LineEdit).text = "6"
	view._save_correction()
	var fix: Dictionary = log.events.back()
	_check(int(fix.data.get("corrects", 0)) == int(hurt.id) and fix.data.delta is int and int(fix.data.delta) == -6, "a correction with the new values (%s)" % [fix.data])
	_check(log.is_undone(int(hurt.id)) and log.get_event(int(hurt.id)).data.delta == -2, "the original stays in the log, undone")
	_check(log.effective().map(func(e: Dictionary) -> int: return int(e.id)).find(int(fix.id)) == hurt_at, "the correction takes its place in the timeline")
	_check(Vector2i(log.day, log.time) == clock and refreshed[0] == 1, "the clock stays, the table is refreshed")
	# when it happened: the DM moves an event to another time
	view.show_moment([walk_a, int(moved.id), int(fix.id)])
	_pick(view, int(fix.id))
	_check(view.selected_id() == int(fix.id), "the correction can be picked")
	view.edit_selected()
	view.day_edit.value = int(fix.day)
	view.time_edit.text = "%02d:%02d" % [(int(fix.time) + 30) / 60, (int(fix.time) + 30) % 60]
	view._save_correction()
	var moved_t: Dictionary = log.events.back()
	_check(int(moved_t.time) == int(fix.time) + 30 and not moved_t.has("after") and log.is_undone(int(fix.id)) and int(moved_t.data.corrects) == int(fix.id), "the event moves to another time (%s)" % [moved_t])
	var order2: Array = log.effective().map(func(e: Dictionary) -> int: return int(e.id))
	_check(order2.find(int(moved_t.id)) > order2.find(walk_a), "sorted there in the timeline")
	_pick(view, int(moved.id))
	view.undo_selected()
	_check(log.is_undone(int(moved.id)), "an event of the past can be undone")
	_pick(view, int(moved.id))
	_check(view.undo_button.disabled, "an undone one can't be undone again")

	# TASK-88: forks, one before the later walk (untouched) and one after it (gets a copy)
	var early_dir := dm.timeline.fork("Early", walk_a)
	var later_dir := dm.timeline.fork("Later", walk_b)
	# the DM drags the current time back to just after moment A: asked once, then deleted
	var bar := TimelineBar.new()
	bar.place_file = DIR + "/panels.cfg"
	bar.dm = true
	home.add_child(bar)
	bar.follow(dm.timeline_sync, dm.notes.calendar)
	bar.preview = dm.set_back_preview
	bar.rewind_requested.connect(func(upto: int, _minutes: int) -> void: dm.set_back(upto))
	await _frames(3)
	var moment_a := {}
	for m: Dictionary in bar.line.moments():
		if (m.events as Array).has(walk_a):
			moment_a = m
	_check(not moment_a.is_empty(), "moment A is on the bar")
	_check(bar.split_at(int(moment_a.at) + 60) == moment_a and bar.split_at(int(bar.line.moments()[0].at) - 1).is_empty(), "setting back keeps the moment before (none before everything)")
	var upto := int(moment_a.last_id)
	var plan := log.set_back_plan(upto)
	var gone_ids: Array = plan.deleted
	_check(gone_ids.has(walk_b) and not gone_ids.has(walk_a), "the plan deletes what came after, not the moment (%s)" % [gone_ids])
	view.editor.hide()
	bar._ask_split(int(moment_a.at) + 60)
	var asked := bar.confirm.dialog_text
	_check(bar.confirm.visible and asked.begins_with("Set the time back") and asked.contains("%d events after it are deleted" % gone_ids.size()), "the DM is asked once, with how many go (%s)" % asked)
	_check(asked.contains("Later") and not asked.contains("Early"), "and which forks keep their own copy")
	bar.confirm.confirmed.emit()
	bar.confirm.hide()
	_check(log.get_event(walk_b).is_empty() and not log.get_event(walk_a).is_empty(), "the later events are gone from memory")
	var reread := EventLog.open(log.path)
	_check(reread.get_event(walk_b).is_empty() and reread.events.size() == log.events.size(), "and from the file (%d events)" % reread.events.size())
	_check(not FileAccess.get_file_as_string(log.path).contains("timeline.rewound"), "no rewound event, nothing to restore")
	_check(Vector2i(log.day, log.time) == Vector2i(int(a_ev.day), int(a_ev.time)), "the clock goes back (%s)" % Vector2i(log.day, log.time))
	_check(Vector2i(reread.day, reread.time) == Vector2i(log.day, log.time), "also after a reload")
	_check(dm.grid.token_cell(BORIN) == start + Vector2i(2, 0), "the table is at that moment (%s)" % dm.grid.token_cell(BORIN))
	await _until(func() -> bool: return bob.grid.token_cell(BORIN) == start + Vector2i(2, 0))
	_check(bob.grid.token_cell(BORIN) == start + Vector2i(2, 0), "on Bob's table too")
	await _frames(5)
	var last_dm: Dictionary = (dm.timeline_sync.data.moments as Array).back()
	_check(int(last_dm.last_id) == upto or (last_dm.events as Array).has(upto), "the bar ends at moment A")
	await _until(func() -> bool: return (bob.timeline_sync.data.moments as Array).size() == (dm.timeline_sync.data.moments as Array).size())
	_check((bob.timeline_sync.data.moments as Array).size() == (dm.timeline_sync.data.moments as Array).size(), "Bob's bar too")
	_check(not dm.timeline_sync.data.has("branches"), "no faded branches")
	# the forks
	var later_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(later_dir.path_join("timeline.json")))
	var later := Timeline.new(later_dir)
	_check(str(later_info.parent) == "" and str(later_info.forked_from.parent) == dm.timeline.id(), "the later fork stands on its own now (%s)" % [later_info.get("forked_from")])
	_check(not later.events_log.get_event(walk_b).is_empty() and later.events_log.inherited.is_empty(), "and still has the later walk")
	var early_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(early_dir.path_join("timeline.json")))
	_check(str(early_info.parent) == dm.timeline.id(), "the early fork still inherits")
	var early := Timeline.new(early_dir)
	_check(not early.events_log.get_event(walk_a).is_empty() and early.events_log.get_event(walk_b).is_empty(), "with the same events as before")
	_check(str(early.events_log.set_back_plan(0).error) != "", "a fork can't be set back before its fork point")
	# the next event continues; a single undo still works
	var after := log.change_hp(BORIN, -1, 9, "later")
	_check(int(after.id) > int(plan.last_kept), "new events get new ids (%d)" % int(after.id))
	_check(not log.undo(int(after.id)).is_empty() and log.is_undone(int(after.id)), "and can be undone")

	# an old log with a timeline.rewound event (TASK-86) is migrated once
	var old_path := ProjectSettings.globalize_path(DIR).path_join("old/events.jsonl")
	DirAccess.make_dir_recursive_absolute(old_path.get_base_dir())
	var f := FileAccess.open(old_path, FileAccess.WRITE)
	for e: Dictionary in [{"id": 1, "type": "time.advanced", "entity": "", "day": 1, "time": 60, "data": {}},
			{"id": 2, "type": "hp.changed", "entity": BORIN, "day": 1, "time": 60, "data": {"delta": -1, "hp": 9}},
			{"id": 3, "type": "time.advanced", "entity": "", "day": 1, "time": 120, "data": {}},
			{"id": 4, "type": "timeline.rewound", "entity": "", "day": 1, "time": 60, "data": {"to": 2, "ids": [3]}}]:
		f.store_line(JSON.stringify(e))
	f.close()
	var old := EventLog.open(old_path)
	_check(old.events.map(func(e: Dictionary) -> int: return int(e.id)) == [1, 2] and old.time == 60, "an old set-back: the cut-off events are deleted (%s)" % [old.events.map(func(e: Dictionary) -> int: return int(e.id))])
	_check(FileAccess.file_exists(old_path + ".bak-rewound"), "the old file is kept as a backup")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("past edits: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _pick(view: TimelineView, id: int) -> void:
	view.refresh()
	for it: TreeItem in view.tree.get_root().get_children():
		if int(it.get_metadata(0)) == id:
			it.select(0)
	view._update_actions()


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
