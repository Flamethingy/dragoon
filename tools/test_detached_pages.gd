extends SceneTree
## Headless check of detached sheet pages (TASK-92): a page pulled out of the program gets its
## own borderless window pinned to its character (it keeps updating when another one is
## active), several can be out, dragging one back over the program or its close button closes
## it, they come back next session (per player), and a player can't pull out pages of
## characters they don't control.
## godot --headless --path . -s tools/test_detached_pages.gd

const PORT := 47845
const ADDRESS := "127.0.0.1:47845"
const DIR := "user://test_detached_pages"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	root.size = Vector2i(1280, 720)  # headless starts with a tiny window
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and bob.grid.tokens.has(BORIN))
	var hud := _hud(dm)
	await process_frame
	var other := ""
	for id: String in dm.grid.tokens:
		if id != BORIN and id != NetTable.PARTY and id.get_slice("/", 0) in Timeline.CREATURES:
			other = id
	_check(other != "", "another creature on the map")

	# pulled out: its own window, pinned to Borin
	hud.set_active(BORIN)
	await process_frame
	var pages := hud.pages
	pages.open(1)
	var page_name := str(hud.page_list()[1].name)
	var dp := pages.detach(BORIN, 1)
	await process_frame
	_check(dp != null and dp.window != null and dp.window.borderless, "page 2 of Borin in its own borderless window")
	_check(dp != null and dp.window.find_child("WindowButtons", true, false) != null, "with minimise / maximise / close")
	_check(dp != null and dp.title_text() == "%s – %s" % [hud.label(BORIN), page_name] and dp.window.title == dp.title_text(), "titled with character and page (%s)" % (dp.title_text() if dp else ""))
	_check(not pages.visible, "the in-program page made way")
	_check(dp != null and dp.view.get_child_count() > 0 and dp.view.get_node_or_null("Waiting") == null, "it shows the page's pieces")

	# another one active: still Borin's, still live
	hud.set_active(other)
	await process_frame
	_check(dm.sheets.has(BORIN), "Borin's sheet stays open for it")
	_check(dp.pinned.active == BORIN and dp.ref == BORIN, "still pinned to Borin")
	var first := dp.view.get_child(0)
	var hp_before := int((dm.sheets[BORIN] as Dictionary).get("hp", 0))
	dm.change_hp(BORIN, -2)
	await process_frame
	_check(int((dm.sheets[BORIN] as Dictionary).get("hp", 0)) == hp_before - 2, "Borin hurt")
	_check(dp.view.get_child_count() > 0 and dp.view.get_child(0) != first, "the detached page was built again (live)")
	hud.set_active("")
	await process_frame
	_check(dm.sheets.has(BORIN) and is_instance_valid(dp) and dp.ref == BORIN, "nothing active: still there")
	var keys := InputEventKey.new()
	keys.keycode = KEY_3
	keys.physical_keycode = KEY_3
	keys.pressed = true
	hud.set_active(other)
	hud._input(keys)
	_check(dp.page == 1 and dp.ref == BORIN, "keys 1-9 leave it alone")

	# several at once
	var dp2 := pages.detach(other, 0)
	var dp3 := pages.detach(BORIN, 0)
	await process_frame
	_check(dp2 != null and dp3 != null and pages.detached.size() == 3, "three out at once (two of Borin's)")

	# remembered per player
	dp.window.position = Vector2i(2100, 120)
	dp.window.size = Vector2i(500, 600)
	await process_frame
	var cfg := ConfigFile.new()
	cfg.load(pages.detached_file())
	var saved: Array = cfg.get_value("detached", "dm", [])
	_check(saved.size() == 3 and str(saved[0].ref) == BORIN and int(saved[0].page) == 1 and (saved[0].win as Array) == [2100, 120, 500, 600], "saved: character, page, window (%s)" % [saved])

	# back over the program: closed (the in-program page opens for the active one)
	hud.set_active(BORIN)
	var main := root
	dp.drop_at(main.position + main.size / 2)
	await process_frame
	_check(not is_instance_valid(dp) or dp.ref == "", "let go over the program: closed")
	_check(pages.detached.size() == 2 and pages.visible and pages.current == 1, "and Borin's page 2 is open in the program")
	_check(dm.sheets.has(BORIN), "Borin still has a page out (and is active)")
	(dp2.window.find_child("Close", true, false) as Button).pressed.emit()
	await process_frame
	_check(pages.detached.size() == 1, "the close button closes it")
	_check(not dm.sheets.has(other) or other == dm.hud_ref, "its sheet isn't kept open any more")

	# next session: they come back
	var dp4 := pages.detach(other, 1)
	await process_frame
	var hud2 := _hud(dm)
	await process_frame
	hud2.pages.restore_detached()
	await process_frame
	var back := hud2.pages.detached
	_check(back.size() == 2 and back.any(func(d: DetachedPage) -> bool: return d.ref == other and d.page == 1) \
		and back.any(func(d: DetachedPage) -> bool: return d.ref == BORIN and d.page == 0), "reopened next time (%s)" % [back.map(func(d: DetachedPage) -> String: return "%s:%d" % [d.ref, d.page])])
	for d in back.duplicate():
		d.close_window()
	for d in pages.detached.duplicate():
		d.close_window()
	_check(dp4 != null, "a page of another creature, for the next session")

	# Bob: only his own character
	var bhud := _hud(bob)
	await process_frame
	_check(bhud.pages.may_detach(BORIN), "Bob may pull out Borin's pages")
	_check(not bhud.pages.may_detach(other) and bhud.pages.detach(other, 0) == null, "but not %s's" % other)
	var bdp := bhud.pages.detach(BORIN, 0)
	await _until(func() -> bool: return bdp != null and bdp.view.get_node_or_null("Waiting") == null and bdp.view.get_child_count() > 0)
	_check(bdp != null and bdp.view.get_node_or_null("Waiting") == null, "Bob's page gets Borin's sheet from the host")
	var bcfg := ConfigFile.new()
	bcfg.load(bhud.pages.detached_file())
	_check((bcfg.get_value("detached", "bob", []) as Array).size() == 1, "kept per player")
	bdp.close_window()

	# the gesture: the head dragged past the program's edge
	hud.set_active(BORIN)
	pages.open(0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	pages._tabs_input(press)
	root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	var m := InputEventMouseMotion.new()
	m.position = Vector2(-30, 200)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(m)
	await process_frame
	pages._tabs_input(m)
	_check(pages.detached.size() == 1 and pages.detached[0].ref == BORIN and pages.detached[0].page == 0, "dragging the head out pulls the page out")
	_check(pages.detached.size() == 1 and pages.detached[0]._carrying, "and it follows the mouse")
	pages.detached[0].close_window()

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("detached pages: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _hud(t: NetTable) -> CharacterHud:
	var ui := Control.new()
	ui.size = Vector2(1280, 720)
	t.get_parent().add_child(ui)
	var hud := CharacterHud.new()
	hud.table = t
	ui.add_child(hud)
	hud.pages = SheetPages.new()
	hud.pages.hud = hud
	ui.add_child(hud.pages)
	return hud


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
