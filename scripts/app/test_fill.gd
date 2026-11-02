class_name TestFill
extends RefCounted
## A test helper for the DM (Nico, 2026-11-02, Esc menu "Test: fill with random events"):
## plays a stretch of a session on the current map so the chat and the timeline fill up:
## time passing, tokens walking, skill checks, chat lines, a few hits and heals. It goes
## through the table like the DM would (every event is real and in the timeline's log).

const SKILLS := ["perception", "stealth", "athletics", "investigation", "insight", "survival", "acrobatics"]
const LINES := [
	"Did anyone else hear that?", "Let's keep moving.", "I check the walls for traps.",
	"Smells like goblins.", "We should rest soon.", "Who has the map?", "Quiet... something's ahead.",
	"I'll take the lead.", "That door wasn't open before.", "Anyone got a torch?",
	"I don't like this place.", "Look, footprints!", "Stay close.", "I'm hungry.",
]


## Plays `steps` random things (one per frame, so the table keeps up). Returns how many events
## were written.
static func fill(table: NetTable, steps := 80, seed := -1) -> int:
	if table == null or not table.is_dm() or table.in_combat():
		return 0
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var before := table.event_log.events.size()
	table.look_back(-1)  # all of it happens now
	for i in steps:
		var ids: Array = table.grid.tokens.keys().filter(func(id: String) -> bool: return id != NetTable.PARTY)
		var pick := rng.randf()
		if pick < 0.12:
			table.advance_clock([5, 10, 15, 30, 60, 120, 240, 480][rng.randi() % 8], ["exploring", "a short rest", "walking", "searching", ""][rng.randi() % 5])
		elif pick < 0.55 and not ids.is_empty():
			_walk(table, str(ids[rng.randi() % ids.size()]), rng)
		elif pick < 0.72 and not ids.is_empty():
			var who := str(ids[rng.randi() % ids.size()])
			if who.begins_with("characters/"):
				table.roll(SKILLS[rng.randi() % SKILLS.size()], who)
			else:
				table.roll("1d20+%d" % rng.randi_range(0, 5), who)
		elif pick < 0.9:
			table.say(LINES[rng.randi() % LINES.size()])
		elif not ids.is_empty():
			var who := str(ids[rng.randi() % ids.size()])
			table.change_hp(who, rng.randi_range(-4, 4) if rng.randf() < 0.5 else rng.randi_range(-3, -1), ["a trap", "a fall", "a potion", "a thorn bush", "a short rest"][rng.randi() % 5])
		await table.get_tree().process_frame
	return table.event_log.events.size() - before


## A short walk of 1 to 5 squares in some direction, if there's room.
static func _walk(table: NetTable, id: String, rng: RandomNumberGenerator) -> void:
	var from := table.grid.token_cell(id)
	for attempt in 6:
		var to := from + Vector2i(rng.randi_range(-5, 5), rng.randi_range(-5, 5))
		if to == from or to.x < 0 or to.y < 0 or to.x >= table.grid.grid_size.x or to.y >= table.grid.grid_size.y:
			continue
		if not table.grid.can_place(id, to):
			continue
		var path: Array = [from] + Vision.path_cells(from, to)
		table._handle_move(1, id, to, path)
		return
