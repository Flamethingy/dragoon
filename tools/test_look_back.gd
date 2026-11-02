extends SceneTree
## Headless check of looking back on the timeline (TASK-83): the table shows a past moment
## (positions, HP, conditions) on each screen on its own, tokens walk the trails they really
## took (backwards too), nothing is written to the log, live moves go on underneath, and a
## player looking back can't act (the host refuses too) until Now.
## godot --headless --path . -s tools/test_look_back.gd

const PORT := 47834
const ADDRESS := "127.0.0.1:47834"
const DIR := "user://test_look_back"
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
	await _until(func() -> bool: return bob.my_pc == BORIN and bob.grid.tokens.has(BORIN) and not bob.timeline_sync.data.is_empty())
	var log := dm.event_log
	var map := dm.grid.map_id
	var start := dm.grid.token_cell(BORIN)

	# history: an hour later Borin walks an L-shaped trail, then gets hurt and poisoned
	log.advance_time(log.day, maxi(log.time, 0) + 60, "walk")
	dm.say("off we go")
	var trail := [start, start + Vector2i(1, 0), start + Vector2i(2, 0), start + Vector2i(2, 1)]
	dm._handle_move(1, BORIN, start + Vector2i(2, 1), trail)
	var moved: Dictionary = log.events.back()
	_check(moved.type == "token.moved" and (moved.data.get("trail", []) as Array).size() == 4, "the move keeps its trail (%s)" % [moved.data.get("trail")])
	var walked := moved.id as int
	log.advance_time(log.day, log.time + 10, "ambush")
	var hp_before := int(dm.view_for("").tokens.filter(func(t: Dictionary) -> bool: return t.id == BORIN)[0].get("hp", 0))
	log.change_hp(BORIN, -5, hp_before - 5, "arrow")
	log.append("condition.applied", BORIN, {"condition": "poisoned"})
	await _frames(10)
	var count := log.events.size()

	# the view at the moment of the walk: after the move, before the arrow
	var past := dm.past_view("", walked, -1)
	var b: Dictionary = (past.tokens as Array).filter(func(t: Dictionary) -> bool: return t.id == BORIN)[0]
	_check(Vector2i(b.cell) == start + Vector2i(2, 1), "then Borin stood at the end of his walk (%s)" % [b.cell])
	_check(int(b.get("hp", 0)) == hp_before and "poisoned" not in (b.get("conditions", []) as Array), "unhurt and not poisoned yet (%s %s)" % [b.get("hp"), b.get("conditions", [])])
	var path: Array = (past.paths as Dictionary).get(BORIN, [])
	_check(path.is_empty(), "nothing moved between now and then (%s)" % [path])
	var before := dm.past_view("", walked - 1, walked)
	path = (before.paths as Dictionary).get(BORIN, [])
	_check(path == [start + Vector2i(2, 1), start + Vector2i(2, 0), start + Vector2i(1, 0), start], "going back he walks the trail backwards (%s)" % [path])
	var forward := dm.past_view("", walked, walked - 1)
	_check((forward.paths as Dictionary).get(BORIN, []) == trail, "and forwards along it")
	var live: Dictionary = dm.view_for("").tokens.filter(func(t: Dictionary) -> bool: return t.id == BORIN)[0]
	_check(int(live.get("hp", 0)) == hp_before - 5 and "poisoned" in (live.get("conditions", []) as Array), "the live view is untouched")

	# Bob looks back on his own screen
	var bar_moments: Array = bob.timeline_sync.data.moments
	var m_walk := -1
	for m: Dictionary in bar_moments:
		if walked >= int(m.first_id) and walked <= int(m.last_id):
			m_walk = int(m.last_id)
	_check(m_walk > 0, "Bob's bar has the walk's moment")
	bob.look_back(walked - 1)
	await _until(func() -> bool: return bob.grid.is_past())
	_check(bob.grid.is_past() and bob.grid.past.has(BORIN), "Bob sees the past")
	_check(bob.grid.past[BORIN].get_meta("cell") == start, "Borin is back at the start there (%s)" % [bob.grid.past[BORIN].get_meta("cell")])
	_check(not bob.grid.tokens[BORIN].visible, "the live token is hidden underneath")
	_check(not dm.grid.is_past(), "the DM's screen is not affected")
	_check(bob.grid.locked and bob.grid.key_step(KEY_D, false) == false, "Bob can't move or step")
	bob.look_back(m_walk)
	await _frames(3)
	_check(bob.grid.past[BORIN].get_meta("cell") == start + Vector2i(2, 1), "forward again: he stands at the end")
	await _frames(2)
	_check(not (bob.grid.past[BORIN].position as Vector2).is_equal_approx(bob.grid.cell_center(start + Vector2i(2, 1), 1.0)), "and walks there (animated)")

	# the host refuses Bob's moves while he looks back
	bob.request_move.rpc_id(1, BORIN, start + Vector2i(2, 2), [])
	await _frames(10)
	_check(log.events.size() == count, "his move is refused; looking back wrote nothing (%d events)" % log.events.size())

	# live events still arrive underneath: the DM moves Borin
	dm._handle_move(1, BORIN, start + Vector2i(3, 1), [])
	await _until(func() -> bool: return bob.grid.token_cell(BORIN) == start + Vector2i(3, 1))
	_check(bob.grid.token_cell(BORIN) == start + Vector2i(3, 1) and bob.grid.past[BORIN].get_meta("cell") == start + Vector2i(2, 1), "live moves arrive underneath, the past stays")

	# back to now
	bob.look_back(-1)
	await _frames(10)
	_check(not bob.grid.is_past() and bob.grid.tokens[BORIN].visible and not bob.grid.locked, "Now: the live table again")
	var n := log.events.size()
	bob.request_move.rpc_id(1, BORIN, start + Vector2i(3, 2), [])
	await _until(func() -> bool: return log.events.size() > n)
	_check(log.events.size() == n + 1, "at now Bob can move again")

	# real time: between two moments the tokens stand that far along their way
	dm.look_back(walked - 1, -1, walked, 0.0)
	await process_frame
	var cs := dm.grid.cell_center(start, 1.0)
	_check(dm.grid.is_past() and (dm.grid.past[BORIN].position as Vector2).is_equal_approx(cs), "at the start of the stretch: where he was (%s)" % dm.grid.past[BORIN].position)
	dm.look_back(walked - 1, -1, walked, 0.5)
	var half := dm.grid.cell_center(start + Vector2i(1, 0), 1.0).lerp(dm.grid.cell_center(start + Vector2i(2, 0), 1.0), 0.5)
	_check((dm.grid.past[BORIN].position as Vector2).is_equal_approx(half), "halfway: halfway along his trail (%s / %s)" % [dm.grid.past[BORIN].position, half])
	dm.look_back(walked - 1, -1, walked, 1.0)
	_check((dm.grid.past[BORIN].position as Vector2).is_equal_approx(dm.grid.cell_center(start + Vector2i(2, 1), 1.0)), "at the end: where he went")
	dm.look_back(-1)
	# a player too: one request per stretch, the rest on his own screen
	bob.look_back(walked - 1, -1, walked, 0.25)
	await _until(func() -> bool: return bob.grid.is_past() and bob.grid.past.has(BORIN))
	await _frames(2)
	var quarter := dm.grid.cell_center(start, 1.0).lerp(dm.grid.cell_center(start + Vector2i(2, 1), 1.0), 0.0)
	var pos_q: Vector2 = bob.grid.past[BORIN].position
	bob.look_back(walked - 1, -1, walked, 0.75)
	var pos_t: Vector2 = bob.grid.past[BORIN].position
	_check(not pos_q.is_equal_approx(pos_t) and not pos_q.is_equal_approx(quarter), "Bob's token moves with his cursor at once (%s -> %s)" % [pos_q, pos_t])
	bob.look_back(-1)
	await _frames(5)

	# the DM looks back too (acting there: test_past_edits)
	dm.look_back(walked)
	_check(dm.grid.is_past() and not dm.grid.locked, "the DM looks back (and may change it)")
	dm.look_back(-1)

	# the bar's cursor turns into a moment's last event
	var home := Control.new()
	home.size = Vector2(1600, 900)
	root.add_child(home)
	var bar := TimelineBar.new()
	bar.place_file = DIR + "/panels.cfg"
	home.add_child(bar)
	bar.follow(bob.timeline_sync, bob.notes.calendar)
	await _frames(2)
	var mw: Dictionary = {}
	for m: Dictionary in bar.line.moments():
		if int(m.last_id) == m_walk:
			mw = m
	bar.line.set_cursor(int(mw.at))
	_check(bar.cursor_event() == m_walk, "the cursor on the walk's box means its last event (%d)" % bar.cursor_event())
	bar.line.set_cursor(-1)
	_check(bar.cursor_event() == -1, "and now is -1")

	# the chat follows the cursor (Nico 2026-11-02)
	dm.say("hello there")
	await _until(func() -> bool: return bob.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")) == "hello there"))
	var chat := ChatBox.new()
	chat.table = bob
	home.add_child(chat)
	await _frames(2)
	var said := -1
	for i in bob.rolls.size():
		if str(bob.rolls[i].get("text", "")) == "off we go":
			said = i
	bar.line.set_cursor(int(mw.at))
	chat.follow_time(bar.happened())
	_check(said >= 0 and chat._until_last == said, "back at the walk: the chat goes to what was said by then (%d / %d)" % [chat._until_last, said])
	_check(not chat.log_text.scroll_following and chat.log_text.get_parsed_text().contains("hello there"), "later lines are still there (faint)")
	bar.line.set_cursor(-1)
	chat.follow_time(bar.happened())
	_check(chat.log_text.scroll_following and chat.until.is_empty(), "at now the chat follows new lines again")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("look back: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
