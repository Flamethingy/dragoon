extends SceneTree
## Headless check of the reveal UI (TASK-19): tag editing (spans, apply, ids), colored frames
## and hover hints in Markdown, the "Visible for" popup, and the editor writing tags in prep
## and reveal.changed events during a session.
## godot --headless --path . -s tools/test_reveal_ui.gd

const DIR := "user://test_reveal_ui"

var _failed := 0


func _init() -> void:
	# --- Editing tags ---------------------------------------------------------------------
	var md := "The amulet is cold. It curses its wearer."
	var from := md.find("It curses")
	var r := Reveal.apply(md, from, md.length(), PackedStringArray(["ann"]), Reveal.next_id([md]))
	_eq(r.text, "The amulet is cold. <reveal id=\"r1\" for=\"ann\">It curses its wearer.</reveal>", "wrap the selection")
	var inner_from: int = r.text.find("It curses")
	var inner_to: int = r.text.find("</reveal>")
	_check(Reveal.span_at(r.text, inner_from, inner_to).get("id") == "r1", "selecting the content finds the passage")
	_check(Reveal.span_at(r.text, inner_from + 3, inner_from + 3).get("id") == "r1", "the caret inside finds it too")
	var edited := Reveal.apply(r.text, inner_from, inner_to, PackedStringArray(["ann", "bob"]), "r9")
	_eq(edited.text, "The amulet is cold. <reveal id=\"r1\" for=\"ann,bob\">It curses its wearer.</reveal>", "edit keeps the id")
	_check(edited.old_for == PackedStringArray(["ann"]), "old viewers returned")
	var e_text: String = edited.text
	var removed := Reveal.apply(e_text, e_text.find("It curses"), e_text.find("</reveal>"), PackedStringArray(), "r9")
	_eq(removed.text, md, "visible to all removes the tag")
	_eq(Reveal.next_id([r.text, "<reveal id='r7' for='dm'>x</reveal>"]), "r8", "new ids are past all used ones")
	var nested := Reveal.apply(r.text, inner_from, inner_from + 9, PackedStringArray(["dm"]), "r2")
	_check(nested.text.contains("<reveal id=\"r1\" for=\"ann\"><reveal id=\"r2\" for=\"dm\">It curses</reveal>"), "part of a passage: nested tag")

	# --- Frames and hints ---------------------------------------------------------------------
	Markdown.reveal_accounts = {"ann": {"name": "Ann", "color": "#2e6e60"}, "bob": {"name": "Bob", "color": "#b8783c"},
		"dm": {"name": "Nico", "color": "#7a3b8f"}}
	Markdown.reveal_viewer = "dm"
	var bb := Markdown.to_bbcode("Cold. <reveal id=\"r7\" for=\"ann\">**Function:** see in the dark.</reveal> End.")
	_check(bb.contains("[hint=\"Only you and Ann can see this\"]"), "inline: hover hint for the DM (%s)" % bb)
	_check(bb.contains("[bgcolor=#2e6e60"), "inline: Ann's color")
	_check(bb.contains("[b]Function:[/b]") and not bb.contains("&lt;reveal") and not bb.contains("<reveal"), "Markdown inside, no raw tag")
	var block := Markdown.to_bbcode("Top.\n\n<reveal id=\"r8\" for=\"ann,bob\">\nFirst para.\n\nSecond para.\n</reveal>\n\nBottom.")
	_check(block.contains("[cell border=#2e6e60") and block.contains("[cell border=#b8783c"), "block for two: two frames (%s)" % block)
	_check(block.find("Top.") < block.find("[table") and block.find("Bottom.") > block.rfind("[/table]"), "frame between the paragraphs")
	var dm_only := Markdown.to_bbcode("A %% secret %% b")
	_check(dm_only.contains("[bgcolor=#7a3b8f") and dm_only.contains("Only you can see this"), "%% comment: DM color and hint")
	_check(not Markdown.to_bbcode("<reveal id=\"p\" for=\"party\">all</reveal>").contains("[hint"), "party passages have no frame")
	Markdown.reveal_viewer = "ann"
	_check(Markdown.to_bbcode("<reveal id=\"x\" for=\"ann,bob\">x</reveal>").contains("Only you and Bob can see this"), "player sees 'you and Bob'")
	Markdown.reveal_viewer = "dm"

	# --- The popup ---------------------------------------------------------------------------
	var popup := RevealPopup.new()
	popup.setup(Markdown.reveal_accounts, PackedStringArray(["ann"]))
	root.add_child(popup)
	_check(popup.chosen() == PackedStringArray(["ann"]), "popup starts with the passage's viewers")
	popup.tick("bob")
	_check(popup.chosen() == PackedStringArray(["ann", "bob"]), "tick Bob")
	popup.tick("party")
	_check(popup.chosen() == PackedStringArray(["party"]), "Party wins over single players")
	popup.tick("dm")
	_check(popup.chosen() == PackedStringArray(["dm"]), "DM only wins")
	var got := []
	popup.applied.connect(func(who: PackedStringArray) -> void: got.append(who))
	popup._apply(popup.chosen())
	_check(got == [PackedStringArray(["dm"])], "applied gives the viewers")

	# --- Editor: prep edits the text, a session logs events -----------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var campaign_dir := Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var store := EntryStore.open(campaign_dir)
	var elog := store.timeline.events_log
	var form := EntryEditor.new()
	form.event_log = elog
	form.accounts = Markdown.reveal_accounts
	form.setup(store, "items", store.find("items", "moonstone-amulet"))
	root.add_child(form)
	var text: CodeEdit = form.find_child("Field_description", true, false).find_child("Text", true, false)
	var start := text.text.find("A silver")
	form.apply_reveal("description", text, start, start + 15, PackedStringArray(["bob"]))
	_check(text.text.begins_with("<reveal id=\"r9\" for=\"bob\">A silver amulet</reveal>"), "prep: selection wrapped with a fresh id (%s)" % text.text.left(60))
	var preview: RichTextLabel = form.find_child("Field_description", true, false).find_child("Preview", true, false)
	_check(preview.text.contains("[bgcolor=#b8783c"), "preview shows Bob's frame")
	form.save()
	_check(store.find("items", "moonstone-amulet").description.contains("id=\"r9\""), "tag saved")

	elog.start_session(1)
	var r7 := text.text.find("**Function:**")
	form.apply_reveal("description", text, r7, r7, PackedStringArray(["ann", "bob"]))
	var ev: Dictionary = elog.events.back()
	_check(ev.type == "reveal.changed" and ev.entity == "items/moonstone-amulet" and ev.data.reveal == "r7" \
		and ev.data.add == ["bob"] and ev.data.remove == [], "session: reveal.changed for Bob (%s)" % ev.get("data"))
	_check(text.text.contains("<reveal id=\"r7\" for=\"ann\">"), "the text keeps the starting viewers")
	var camp := Timeline.new(campaign_dir, AssetCache.new(DIR + "/cache"))
	_check(camp.entry_view("items/moonstone-amulet", "bob", elog.effective("items/moonstone-amulet")).description.contains("Function"), "Bob now gets the function")
	form.apply_reveal("description", text, r7, r7, PackedStringArray(["ann", "bob"]))
	_check(elog.events.back().id == ev.id, "no event when nothing changes")

	# --- Account colors in the timeline ----------------------------------------------------------
	_check(camp.accounts().ann.color == "#2e6e60" and camp.accounts().dm.name == "Nico", "accounts from timeline.json")
	_check(camp.set_color("ann", "#112233") and Timeline.new(campaign_dir, null).accounts().ann.color == "#112233", "color saved")
	_check(not camp.set_color("carl", "#112233") and not camp.set_color("ann", "nope"), "unknown account / bad color refused")

	print("reveal ui: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _eq(got: String, want: String, what: String) -> void:
	_check(got == want, "%s (got %s)" % [what, JSON.stringify(got)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
