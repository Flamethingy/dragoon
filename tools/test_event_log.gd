extends SceneTree
## Headless check of EventLog and Replay: godot --headless --path . -s tools/test_event_log.gd

const FILE := "user://test_event_log/events.jsonl"

var _failed := 0


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var elog := EventLog.open(FILE)
	_eq(elog.events.size(), 0, "new log is empty")
	elog.start_session(3)
	elog.advance_time(152, 14 * 60, "morning travel")
	elog.place_token("pc/thalia", "maps/thornwick", Vector2i(4, 7), "player:anna")
	var move := elog.move_token("pc/thalia", "maps/thornwick", Vector2i(4, 7), Vector2i(9, 7), "player:anna")
	elog.gain_item("pc/thalia", "core:items/flame-tongue", 1, "npc/mira")
	elog.change_hp("pc/thalia", -9, 15, "goblin scimitar")
	elog.change_sheet("pc/thalia", "stats.str", 14, 16, "belt of giant strength")
	elog.advance_time(152, 15 * 60)
	var wrong := elog.change_hp("pc/thalia", -20, -5, "typo")
	elog.undo(wrong.id)
	_eq(move.session, 3, "events carry the session")
	_eq(move.day, 152, "events carry the in-world day")
	_eq(move.time, 14 * 60, "events carry the in-world time")
	_eq(str(move.real).ends_with("Z"), true, "events carry the real date (UTC)")

	# Restart: everything comes back from disk.
	var again := EventLog.open(FILE)
	_eq(again.events.size(), elog.events.size(), "reloaded all events")
	_eq(again.session, 3, "session restored")
	_eq([again.day, again.time], [152, 15 * 60], "clock restored")
	_eq(again.is_undone(wrong.id), true, "undo restored")
	var lines := FileAccess.get_file_as_string(FILE).strip_edges().split("\n").size()
	_eq(lines, elog.events.size(), "one line per event (append-only)")

	var base := {"name": "Thalia", "hp": 24, "stats": {"str": 14, "dex": 16}}
	var now := Replay.entity_state(base, again.effective("pc/thalia"))
	_eq(now.hp, 15, "hp rebuilt (the undone -20 is ignored)")
	_eq(now.stats.str, 16, "sheet change rebuilt")
	_eq(now.inventory, {"core:items/flame-tongue": 1}, "inventory rebuilt")
	_eq(now.token, {"map": "maps/thornwick", "at": Vector2i(9, 7)}, "token position rebuilt")
	_eq(base.hp, 24, "the base entity is never changed")

	# Rewind: just after the token was placed.
	var then := Replay.entity_state(base, again.effective("pc/thalia", 152, 14 * 60 - 1))
	_eq(then.hp, 24, "rewound before the hit")
	_eq(then.has("token"), false, "rewound before the token existed")
	_eq(Replay.tokens_on("maps/thornwick", again.effective()), {"pc/thalia": Vector2i(9, 7)}, "tokens on a map")

	# A damaged line doesn't lose the rest.
	var f := FileAccess.open(FILE, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line("{broken")
	f.close()
	var damaged := EventLog.open(FILE)
	_eq(damaged.events.size(), elog.events.size(), "damaged line skipped")
	var next := damaged.change_hp("pc/thalia", 5, 20, "healing word")
	_eq(next.id, wrong.id + 2, "ids continue after reload")

	print("event log: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if str(got) != str(want):
		_failed += 1
		printerr("FAIL: %s: got %s, want %s" % [what, got, want])
