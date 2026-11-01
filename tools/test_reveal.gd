extends SceneTree
## Headless check of Reveal (TASK-18): <reveal> tags (inline, block, nested), %% comments,
## visibility from tag `for` + reveal.changed events at a moment (rewinding hides again),
## and per-recipient filtering with the example's Moonstone Amulet.
## godot --headless --path . -s tools/test_reveal.gd

const DIR := "user://test_reveal"

var _failed := 0


func _init() -> void:
	# --- Parsing and filtering ------------------------------------------------------------
	var inline := "A <reveal id=\"a\" for=\"ann\">secret</reveal> word."
	_eq(Reveal.filter(inline, "bob"), "A  word.", "inline: hidden from others")
	_eq(Reveal.filter(inline, "ann"), "A <reveal id=\"a\" for=\"ann\">secret</reveal> word.", "inline: tag kept for its viewer")
	_eq(Reveal.filter(inline, "dm"), Reveal.filter(inline, "ann"), "the DM sees everything")
	var block := "Top.\n\n<reveal id=\"b\" for=\"party\">\n**All** players\n\n- list\n</reveal>\n\nEnd."
	_check(Reveal.filter(block, "bob").contains("- list"), "block for party: every player")
	_check(not Reveal.filter(block, "").contains("All"), "block for party: not without a player id")
	var nested := "<reveal id=\"o\" for=\"ann,bob\">outer <reveal id=\"i\" for=\"bob\">inner</reveal></reveal>"
	_check(Reveal.filter(nested, "ann").contains("outer") and not Reveal.filter(nested, "ann").contains("inner"), "nested: inner tag narrows")
	_check(Reveal.filter(nested, "bob").contains("inner"), "nested: both allow bob")
	var cut := "<reveal id=\"o\" for=\"bob\">outer <reveal id=\"i\" for=\"ann\">inner</reveal></reveal>"
	_check(not Reveal.filter(cut, "ann").contains("inner"), "nested: intersection, outer hides inner too")
	var comment := "Seen. %% DM only %% Also seen."
	_eq(Reveal.filter(comment, "ann"), "Seen.  Also seen.", "%% comments are DM-only")
	_eq(Reveal.filter(comment, "dm"), comment, "the DM keeps %% comments")
	_check(not Reveal.filter("Open <reveal id=\"x\" for=\"dm\">never closed", "ann").contains("never"), "unclosed tag stays hidden")
	_eq(Reveal.filter("a </reveal> b", "ann"), "a  b", "stray closing tag dropped")
	_eq(Reveal.filter("<reveal id='q' for=' Ann , BOB '>x</reveal>", "bob"), "<reveal id=\"q\" for=\"ann,bob\">x</reveal>", "single quotes, blanks, case")
	_eq(Reveal.filter("<reveal id=\"n\">x</reveal>", "ann"), "", "no `for` = DM only")
	_check(Reveal.passages(nested) == {"o": PackedStringArray(["ann", "bob"]), "i": PackedStringArray(["bob"])}, "passages() lists ids")

	# --- Visibility from events at a moment -------------------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(DIR)
	var campaign_dir := Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var campaign := Timeline.new(campaign_dir, AssetCache.new(DIR + "/cache"))
	var elog := campaign.events_log
	const AMULET := "items/moonstone-amulet"
	var start := campaign.entry_view(AMULET, "ann")
	_check(start.description.contains("**Function:**") and not start.description.contains("Curse"), "Ann: function yes, curse no")
	_check(not campaign.entry_view(AMULET, "bob").description.contains("Function"), "Bob: neither")
	_check(campaign.entry_view(AMULET, "dm").description.contains("Curse"), "DM: both")
	_check(campaign.entry_view(AMULET, "bob").description.begins_with("A silver amulet"), "untagged text for everyone")

	elog.day = 100
	elog.time = 600
	elog.change_reveal(AMULET, "r8", "description", ["ann"])
	elog.advance_time(101, 480)
	elog.change_reveal(AMULET, "r7", "description", ["bob"], ["ann"])
	var ev: Dictionary = elog.effective(AMULET).back()
	_check(ev.type == "reveal.changed" and ev.data == {"reveal": "r7", "field": "description", "add": ["bob"], "remove": ["ann"]}, "reveal.changed in the log (%s)" % ev)

	var now := elog.effective(AMULET)
	_check(campaign.entry_view(AMULET, "ann", now).description.contains("Curse"), "now: Ann sees the curse")
	_check(not campaign.entry_view(AMULET, "ann", now).description.contains("Function"), "now: function taken from Ann")
	_check(campaign.entry_view(AMULET, "bob", now).description.contains("Function"), "now: Bob sees the function")
	_check(campaign.entry_view(AMULET, "ann", now).description.contains("for=\"dm,ann\""), "visible tag carries the current `for`")
	var day100 := elog.effective(AMULET, 100, 700)
	_check(campaign.entry_view(AMULET, "ann", day100).description.contains("Function") \
		and campaign.entry_view(AMULET, "ann", day100).description.contains("Curse"), "day 100: Ann still had both")
	var before := elog.effective(AMULET, 100, 500)
	_check(not campaign.entry_view(AMULET, "ann", before).description.contains("Curse"), "rewound before the reveal: hidden again")
	var other_field := elog.effective(AMULET)
	other_field.append({"type": "reveal.changed", "entity": AMULET, "data": {"reveal": "r8", "field": "notes", "add": ["bob"]}})
	_check(not campaign.entry_view(AMULET, "bob", other_field).description.contains("Curse"), "grants only for their field")

	# --- No leftovers of the old markers -------------------------------------------------
	_check(not FileAccess.file_exists("res://scripts/net/secrets.gd"), "secrets.gd is gone")
	_check(not FileAccess.get_file_as_string(campaign_dir.path_join("events.jsonl")).contains("dm_"), "no dm_ keys in the example")

	print("reveal: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _eq(got: String, want: String, what: String) -> void:
	_check(got == want, "%s (got %s)" % [what, JSON.stringify(got)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
