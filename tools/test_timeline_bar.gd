extends SceneTree
## Headless check of the timeline bar (TASK-82): the host's moments reach the player (without
## what happened under fog of war), new events and undos update them live, the bar docks at
## the top (pushing a side dock down), zooms, pans, shows a box's changes on hover, scrubs
## and asks for a moment's events.
## godot --headless --path . -s tools/test_timeline_bar.gd

const PORT := 47833
const ADDRESS := "127.0.0.1:47833"
const DIR := "user://test_timeline_bar"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

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
	await _until(func() -> bool: return bob.my_pc == BORIN and not bob.timeline_sync.data.is_empty())
	var start := (dm.timeline_sync.data.moments as Array).size()
	_check(start == (bob.timeline_sync.data.moments as Array).size(), "Bob got the moments when he joined (%d)" % start)

	# new events: a clock step and a move -> a new moment everywhere
	var log := dm.event_log
	log.advance_time(log.day, maxi(log.time, 0) + 60, "test hour")
	log.move_token(BORIN, dm.grid.map_id, Vector2i(1, 1), Vector2i(3, 1))
	await _until(func() -> bool: return (bob.timeline_sync.data.moments as Array).size() == start + 1)
	var last: Dictionary = (bob.timeline_sync.data.moments as Array).back()
	_check(" ".join(last.lines).contains("moves 2 squares"), "Bob sees the new moment's summary (%s)" % [last.lines])
	_check(" ".join(last.lines).contains("1 hour passes (test hour)"), "and the time passing")
	_check(int(bob.timeline_sync.data.now_at) >= int(last.at), "now is at (or after) the last moment")

	# fog of war: a creature on a fogged map shows to the DM only
	dm.edit_map({"fog": true})
	await _frames(5)
	log.advance_time(log.day, log.time + 10, "sneaking")
	log.move_token("creatures/test-spy", dm.grid.map_id, Vector2i(5, 5), Vector2i(6, 6))
	await _frames(10)
	var dm_last: Dictionary = (dm.timeline_sync.data.moments as Array).back()
	var bob_last: Dictionary = (bob.timeline_sync.data.moments as Array).back()
	_check(" ".join(dm_last.lines).contains("Test spy"), "the DM sees the spy (%s)" % [dm_last.lines])
	_check(not " ".join(bob_last.lines).contains("Test spy"), "Bob doesn't (%s)" % [bob_last.lines])
	dm.edit_map({"fog": false})

	# an undo rebuilds
	var hit := log.change_hp(BORIN, -4, 8, "trap")
	await _frames(5)
	_check(" ".join(((dm.timeline_sync.data.moments as Array).back()).lines).contains("takes 4 damage"), "the hit is there")
	log.undo(int(hit.id))
	await _frames(5)
	_check(not " ".join(((dm.timeline_sync.data.moments as Array).back()).lines).contains("takes 4 damage"), "after the undo it's gone")

	# the bar: docked at the top, a side panel below it
	var home := Control.new()
	home.size = Vector2(1600, 900)
	root.add_child(home)
	var side := DockPanel.new()
	side.place_file = DIR + "/panels.cfg"
	side.section = "side"
	side.place = {"dock": "right", "side": 10, "bottom": 7, "top": 3, "r": [30, 6, 12, 16], "window": false}
	home.add_child(side)
	var side_top := side.position.y
	var bar := TimelineBar.new()
	bar.place_file = DIR + "/panels.cfg"
	home.add_child(bar)
	bar.follow(dm.timeline_sync, dm.notes.calendar)
	await _frames(3)
	var cell := bar.cell()
	_check(bar.place.dock == "top" and absf(bar.position.y - DockPanel.TOP * cell.y) < 6 and bar.size.x > 1500, "the bar is docked at the top, full width (%s %s)" % [bar.position, bar.size])
	_check(side.position.y > side_top + cell.y * 2, "the side dock moved below it (%d -> %d)" % [side_top, side.position.y])
	bar.dock("float", Rect2i(8, 6, 30, 4))
	await _frames(2)
	_check(absf(side.position.y - side_top) < 2, "floating, the side dock gets its room back")
	bar.dock("top")
	await _frames(2)

	# the line: fit, boxes by time, hover, zoom, scrub, list
	var line := bar.line
	line.size = Vector2(1500, 60)
	line.fit()
	var ms := line.moments()
	_check(ms.size() >= 3, "the bar has the moments (%d)" % ms.size())
	var a: Dictionary = ms[ms.size() - 3]
	var b: Dictionary = ms[ms.size() - 2]
	_check(line.x_of(b.at) > line.x_of(a.at), "later moments sit further right")
	var tip := line._get_tooltip(Vector2(line.x_of(b.at), line._line_y()))
	_check(tip.contains("Borin") or tip.contains("hour"), "hovering a box shows what changed (%s)" % tip.replace("\n", " | "))
	var span := line.span
	line.zoom(0.5, line.x_of(b.at))
	_check(absf(line.span - span * 0.5) < 1.0 and absf(line.x_of(b.at) - line.x_of(b.at)) < 0.01, "zooming in keeps the time under the mouse")
	var seen := []
	bar.cursor_changed.connect(func(at: int) -> void: seen.append(at))
	line.scrub_to(line.x_of(a.at) + 2)
	_check(not seen.is_empty() and int(seen.back()) == int(a.at) and bar.now_button.visible, "scrubbing snaps to a box and shows Now (%s)" % [seen])
	_check(bar.when_label.text.begins_with("looking back"), "the head says we look back (%s)" % bar.when_label.text)
	bar.now_button.pressed.emit()
	_check(int(seen.back()) == -1 and not bar.now_button.visible, "Now goes back to the present")
	var asked := []
	bar.list_requested.connect(func(f: int, l: int) -> void: asked.append([f, l]))
	line.list_requested.emit(b)
	_check(asked.size() == 1 and asked[0][0] == int(b.first_id), "a box asks for its events in the list")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("timeline bar: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


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
