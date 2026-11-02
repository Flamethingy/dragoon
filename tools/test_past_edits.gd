extends SceneTree
## Headless check of changing the past (TASK-85) and setting the timeline back (TASK-86):
## the DM's actions while looking back go in right after that moment (`after`), in timeline
## order, without moving the clock, while the players' actions stay at now; the moment is
## marked as edited. Setting back cuts off everything after a moment (one restorable event,
## the clock goes back), shows the cut-off branch faded, and restoring brings it all back.
## Both survive reloading the log.
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

	# TASK-86: set the timeline back to moment A (after the DM's changes there)
	var upto := int(hurt.id)
	var before_count := log.effective().size()
	var rw := dm.rewind_to(upto)
	_check(not rw.is_empty() and rw.type == "timeline.rewound", "set back: one event (%s)" % rw.get("type", ""))
	_check(log.is_undone(walk_b) and not log.is_undone(walk_a) and not log.is_undone(int(moved.id)), "what came after is cut off, the moment itself stays")
	_check(Vector2i(log.day, log.time) == Vector2i(int(a_ev.day), int(a_ev.time)), "the clock goes back to it (%s)" % Vector2i(log.day, log.time))
	_check(dm.grid.token_cell(BORIN) == start + Vector2i(2, 2), "the table shows that moment as now (%s)" % dm.grid.token_cell(BORIN))
	await _until(func() -> bool: return bob.grid.token_cell(BORIN) == start + Vector2i(2, 2))
	_check(bob.grid.token_cell(BORIN) == start + Vector2i(2, 2), "on Bob's table too")
	await _frames(5)
	var branches: Array = dm.timeline_sync.data.get("branches", [])
	_check(branches.size() == 1 and not (branches[0].moments as Array).is_empty(), "the cut-off part is a branch on the DM's bar")
	_check(not bob.timeline_sync.data.has("branches"), "players don't get it")
	var again2 := EventLog.open(log.path)
	_check(again2.is_undone(walk_b) and Vector2i(again2.day, again2.time) == Vector2i(log.day, log.time), "the set-back survives a reload")

	# the bar: the faded branch can be hit, and Set back shows for the DM looking back
	var home := Control.new()
	home.size = Vector2(1600, 900)
	root.add_child(home)
	var bar := TimelineBar.new()
	bar.place_file = DIR + "/panels.cfg"
	bar.dm = true
	home.add_child(bar)
	bar.follow(dm.timeline_sync, dm.notes.calendar)
	bar.line.size = Vector2(1500, 60)
	bar.line.span = 4 * 3600.0
	bar.line.view_from = float(branches[0].at) - 3600.0
	var bm: Dictionary = (branches[0].moments as Array)[0]
	var hit := bar.line.branch_box_at(Vector2(bar.line.x_of(float(bm.at)), bar.line._line_y() - TimelineLine.BRANCH_UP))
	_check(int(hit.get("rewind", 0)) == int(rw.id), "the faded box belongs to the set-back")
	var ms := bar.line.moments()
	bar.line.set_cursor(int(ms[0].at))
	_check(bar.back_button.visible, "looking back, the DM gets Set back to here")
	dm.look_back(-1)

	# restore
	dm.restore(int(rw.id))
	_check(not log.is_undone(walk_b), "restored: the cut-off events count again")
	_check(Vector2i(log.day, log.time) == clock, "and the clock is back (%s / %s)" % [Vector2i(log.day, log.time), clock])
	await _frames(5)
	_check((dm.timeline_sync.data.get("branches", []) as Array).is_empty(), "no branch anymore")
	_check(log.effective().size() == before_count, "all events back (%d / %d)" % [log.effective().size(), before_count])

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
