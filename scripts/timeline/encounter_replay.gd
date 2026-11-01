class_name EncounterReplay
extends RefCounted
## Plays an encounter back (TASK-35): the state of its map at any step of its range. Step 0
## is the moment before the combat started; step i is after the i-th event of the range.
## Only reads the log: nothing is ever appended or changed.

var timeline: Timeline
var events_log: EventLog
var encounter := {}
var steps: Array[Dictionary] = []  ## the range's events that count (no undone ones, no undos)
var _before: Array[Dictionary] = []  ## effective events before the range


func _init(tl: Timeline, log_: EventLog, enc: Dictionary) -> void:
	timeline = tl
	events_log = log_
	encounter = enc
	var lo := int(enc.get("start_event", 0))
	var hi := int(enc.get("end_event", lo))
	for e: Dictionary in log_.effective():
		if int(e.id) < lo:
			_before.append(e)
		elif int(e.id) <= hi:
			steps.append(e)


func count() -> int:
	return steps.size()


## {tokens: {ref: Vector2i}, creatures: {ref: {name, hp, max_hp, conditions}}, round, turn,
## active, event (the last applied, {} at step 0)} after `step` events (0..count()).
func state_at(step: int) -> Dictionary:
	step = clampi(step, 0, steps.size())
	var applied: Array[Dictionary] = _before.duplicate()
	applied.append_array(steps.slice(0, step))
	var map := str(encounter.get("map", ""))
	var tokens := {}
	var view := timeline.map_view(map) if map != "" else {}
	if not view.is_empty():
		tokens = (view.tokens as Dictionary).duplicate()
	tokens.merge(Replay.tokens_on(map, applied), true)
	var creatures := {}
	var refs: Array = tokens.keys()
	for r: Variant in encounter.get("participants", []):
		if str(r) not in refs:
			refs.append(str(r))
	for ref: String in refs:
		var e := timeline.entry(ref)
		if e.is_empty():
			continue
		var base := {"hp": e.get("hp", 0), "conditions": []}
		var mine := applied.filter(func(x: Dictionary) -> bool: return x.entity == ref)
		var now := Replay.entity_state(base, mine)
		creatures[ref] = {"name": str(e.get("name", ref)), "hp": now.get("hp"), "max_hp": e.get("hp", 0),
			"conditions": now.get("conditions", [])}
	var w := Replay.world_state(applied)
	return {"tokens": tokens, "creatures": creatures, "round": int(w.combat.round), "turn": int(w.combat.turn),
		"active": bool(w.combat.active), "event": steps[step - 1] if step > 0 else {}}


## The step after the next change of round (combat.turn with a higher round), or the end.
func next_round(step: int) -> int:
	var now := int(state_at(step).round)
	for i in range(step, steps.size()):
		var e := steps[i]
		if e.type == "combat.turn" and int(e.data.get("round", 0)) > now:
			return i + 1
		if e.type == "combat.ended":
			return i + 1
	return steps.size()


## The step where the current round began (or the one before, if already there).
func previous_round(step: int) -> int:
	for i in range(mini(step, steps.size()) - 2, -1, -1):
		var e := steps[i]
		if e.type == "combat.started" or (e.type == "combat.turn" and int(e.data.get("round", 0)) != int(state_at(i).round)):
			return i + 1
	return 0


## The step that shows event `id` (after it), -1 if it is not in the range.
func step_of(id: int) -> int:
	for i in steps.size():
		if int(steps[i].id) == id:
			return i + 1
	return -1
