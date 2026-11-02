extends SceneTree
## Headless check of the timeline's moments (TASK-81): events grouped by world time and
## combat round, summaries, maps, sessions, undone events left out, live additions.
## godot --headless --path . -s tools/test_moments.gd

const FILE := "user://test_moments/events.jsonl"

var _failed := 0


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var log := EventLog.open(FILE)
	log.advance_time(10, 480, "start")  # day 10, 08:00
	log.start_session(1)
	log.place_token("characters/borin", "maps/road", Vector2i(1, 1))
	log.move_token("characters/borin", "maps/road", Vector2i(1, 1), Vector2i(4, 1))
	log.gain_item("characters/borin", "core:5e/items/potion-of-healing", 2)
	log.advance_time(10, 600, "walk to the camp")  # 10:00
	log.move_token("characters/borin", "maps/camp", Vector2i(0, 0), Vector2i(2, 2))
	log.move_token("creatures/goblin-1", "maps/camp", Vector2i(9, 9), Vector2i(7, 7), "dm")
	# a fight: round 1 and 2 at the same minute
	log.append("combat.started", "", {"map": "maps/camp", "order": []})
	log.append("combat.turn", "", {"round": 1, "turn": 0})
	log.change_hp("creatures/goblin-1", -7, 0, "axe")
	var oops := log.change_hp("characters/borin", -50, 0, "mistake")
	log.undo(int(oops.id))
	log.append("combat.turn", "", {"round": 1, "turn": 1})
	log.append("condition.applied", "characters/borin", {"condition": "poisoned"})
	log.append("combat.turn", "", {"round": 2, "turn": 0})
	log.change_hp("characters/borin", -3, 9, "poison")
	log.append("combat.ended", "", {})
	log.lose_item("characters/borin", "core:5e/items/potion-of-healing", 1)  # after the fight, same minute
	log.end_session()

	var names := func(ref: String) -> String: return {"characters/borin": "Borin"}.get(ref, "")
	var m := TimelineMoments.build(log.effective(), 24, names)
	var ms := m.moments
	_check(ms.size() == 5, "5 moments: start, camp, round 1, round 2, after the fight (%d)" % ms.size())
	if ms.size() == 5:
		_check(ms[0].day == 10 and ms[0].time == 480 and ms[0].round == 0, "the first is day 10, 08:00")
		_check(" ".join(ms[0].lines).contains("Borin: appears, moves 3 squares, +2 Potion of healing"), "its summary (%s)" % [ms[0].lines])
		_check(ms[0].maps == ["maps/road"], "on the road map")
		_check(ms[1].at - ms[0].at == 2 * 3600 and ms[1].maps == ["maps/camp"], "the camp is 2 h later, on one map (%s)" % [ms[1].maps])
		_check(" ".join(ms[1].lines).begins_with("2 hours pass (walk to the camp)"), "time passing is said first (%s)" % [ms[1].lines])
		_check(ms[2].round == 1 and ms[2].combat and ms[2].at == ms[1].at + 6, "round 1 is its own moment, 6 s on")
		_check(" ".join(ms[2].lines).contains("Goblin 1: takes 7 damage, drops to 0 HP"), "round 1 summary (%s)" % [ms[2].lines])
		_check(not " ".join(ms[2].lines).contains("50"), "the undone hit isn't there")
		_check(ms[3].round == 2 and ms[3].at == ms[2].at + 6 and " ".join(ms[3].lines).contains("Borin: takes 3 damage"), "round 2 (%s)" % [ms[3].lines])
		_check(" ".join(ms[3].lines).contains("Combat ends"), "the fight ends in round 2")
		_check(ms[4].round == 0 and not ms[4].combat and " ".join(ms[4].lines).contains("−1 Potion"), "after the fight: a moment of its own (%s)" % [ms[4].lines])
	_check(m.sessions.size() == 1 and m.sessions[0].start_real != "" and m.sessions[0].end_real != "", "one session with real start and end (%s)" % [m.sessions])
	_check(m.moment_at(ms[0].at + 60) == 0 and m.moment_at(ms[0].at - 1) == -1, "moment_at finds the moment before a time")

	# live: a new event at the end goes into the last moment or starts a new one
	var before := ms.size()
	m.add(log.advance_time(11, 480, "long rest"))
	m.add(log.change_hp("characters/borin", 10, 19, "rest"))
	_check(m.moments.size() == before + 1 and " ".join(m.moments.back().lines).contains("Borin: heals 10"), "live additions (%s)" % [m.moments.back().lines])
	_check(" ".join(m.moments.back().lines).contains("1 day passes") or " ".join(m.moments.back().lines).contains("hours pass"), "the rest's time")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("moments: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
