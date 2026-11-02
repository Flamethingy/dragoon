extends SceneTree
## Headless check of "Show everyone" (TASK-84): the DM's cursor pulls every player's table to
## that moment live, players can't scrub away or act meanwhile (a late joiner is pulled too),
## and switching it off gives them their own timeline back at now.
## godot --headless --path . -s tools/test_show_everyone.gd

const PORT := 47835
const ADDRESS := "127.0.0.1:47835"
const DIR := "user://test_show_everyone"
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
	await _until(func() -> bool: return bob.my_pc == BORIN and bob.grid.tokens.has(BORIN))
	var log := dm.event_log
	var start := dm.grid.token_cell(BORIN)
	log.advance_time(log.day, maxi(log.time, 0) + 60, "walk")
	dm._handle_move(1, BORIN, start + Vector2i(2, 0), [start, start + Vector2i(1, 0), start + Vector2i(2, 0)])
	var walked := int(log.events.back().id)
	log.advance_time(log.day, log.time + 30, "later")
	dm._handle_move(1, BORIN, start + Vector2i(4, 0), [])
	await _frames(10)

	# the bars (as TableUI wires them)
	var dbar := _bar(dm)
	var bbar := _bar(bob)
	await _frames(3)
	dbar.open_menu(Vector2(100, 100))
	var mi := dbar.menu.get_item_index(2)
	_check(not dbar.menu.is_item_disabled(mi), "the DM's bar menu has Show everyone")
	dbar.menu.hide()
	bbar.open_menu(Vector2(100, 100))
	_check(bbar.menu.is_item_disabled(bbar.menu.get_item_index(2)), "a player's not")
	bbar.menu.hide()

	# on: Bob follows the DM's cursor
	dbar._on_menu(2)
	await _frames(5)
	_check(dm.showing and bob.showing, "Show everyone is on for both")
	var m := _moment_with(dbar, walked)
	dbar.line.set_cursor(int(m.at))
	await _until(func() -> bool: return bob.grid.is_past() and bob.grid.past.has(BORIN))
	_check(bob.grid.is_past() and bob.grid.past[BORIN].get_meta("cell") == start + Vector2i(2, 0), "Bob's table shows the DM's moment")
	_check(bbar.line.cursor_at == int(m.at), "his cursor sits where the DM's is (%d / %d)" % [bbar.line.cursor_at, int(m.at)])
	_check(bbar.line.hint.begins_with("The DM is showing"), "with a hint (%s)" % bbar.line.hint)
	_check(bob.grid.locked, "he can't act")

	# he can't scrub away
	bob.look_back(0)
	bbar.line.scrub_to(5.0)
	await _frames(5)
	_check(bob.looking_back == walked, "Bob can't look elsewhere (%d)" % bob.looking_back)
	var n := log.events.size()
	bob.request_move.rpc_id(1, BORIN, start + Vector2i(5, 1), [])
	await _frames(10)
	_check(log.events.size() == n, "nor move")

	# the DM moves on: Bob follows, back to before the walk
	var first: Dictionary = dbar.line.moments()[int(m.index) - 1]
	dbar.line.set_cursor(int(first.at))
	await _until(func() -> bool: return bob.grid.past.has(BORIN) and bob.grid.past[BORIN].get_meta("cell") == start)
	_check(bob.grid.past[BORIN].get_meta("cell") == start, "the DM scrubs, Bob's table goes along")

	# a late joiner is pulled in too
	var cara := _table("Ann", "ann")
	await process_frame
	cara.join(ADDRESS, "Ann")
	await _until(func() -> bool: return cara.showing and cara.grid.is_past())
	_check(cara.showing and cara.looking_back == dm.looking_back, "Ann joins late and sees the DM's moment")

	# off: everyone back at now with their own cursor
	dbar._on_menu(2)
	await _until(func() -> bool: return not bob.showing and not bob.grid.is_past())
	_check(not bob.showing and bob.looking_back == -1 and not bob.grid.is_past() and not bob.grid.locked, "off: Bob is back at now")
	_check(bbar.line.cursor_at == -1 and not bbar.shown, "with his own cursor again")
	_check(dm.looking_back >= 0, "the DM still looks back on their own")
	n = log.events.size()
	bob.request_move.rpc_id(1, BORIN, start + Vector2i(5, 1), [])
	await _until(func() -> bool: return log.events.size() > n)
	_check(log.events.size() == n + 1, "Bob can move again")
	bob.look_back(walked, int(m.at))
	await _until(func() -> bool: return bob.grid.is_past())
	_check(bob.grid.is_past(), "and look back on his own")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("show everyone: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## A TimelineBar wired to `t` like TableUI does it.
func _bar(t: NetTable) -> TimelineBar:
	var home := Control.new()
	home.size = Vector2(1600, 900)
	root.add_child(home)
	var bar := TimelineBar.new()
	bar.place_file = DIR + "/panels_%s.cfg" % t.get_parent().name
	home.add_child(bar)
	bar.follow(t.timeline_sync, t.notes.calendar)
	bar.line.size = Vector2(1500, 60)
	bar.line.fit()
	bar.dm = t.is_dm()
	bar.cursor_changed.connect(func(at: int) -> void: t.look_back(bar.cursor_event(), at))
	bar.show_toggled.connect(func(on: bool) -> void: t.show_everyone(on))
	t.showing_changed.connect(func() -> void:
		bar.set_showing(t.showing, t.is_dm())
		if not t.is_dm():
			bar.line.set_cursor(t.looking_at))
	return bar


func _moment_with(bar: TimelineBar, id: int) -> Dictionary:
	for m: Dictionary in bar.line.moments():
		if id >= int(m.first_id) and id <= int(m.last_id):
			return m
	return {}


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
