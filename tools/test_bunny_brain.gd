extends SceneTree
## Headless check of the Table Bunny's brain (TASK-95) with a fake API (no real call is ever
## made here): it sleeps without a key, a question runs the tool loop as the asking player
## and comes back as an answer, the key stays in its settings file (never in a request body,
## an answer or a status), the token limit and the cooldown work, one question at a time with
## a visible queue, and the history is per player and gone at the end of the session.
## godot --headless --path . -s tools/test_bunny_brain.gd

const PORT := 47851
const ADDRESS := "127.0.0.1:47851"
const DIR := "user://test_bunny_brain"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"
const KEY := "sk-ant-test-SECRET-123"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	BunnyBrain.settings_file = DIR.path_join("bunny_settings.cfg")
	await process_frame
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and dm.peers.size() == 1)
	var bob_peer: int = dm.peers.keys()[0]
	var brain := dm.bunny
	_check(brain != null and bob.bunny == null, "the brain lives on the host only")

	var answers := []
	var states := []
	brain.answered.connect(func(sender: int, text: String, error: bool) -> void: answers.append([sender, text, error]))
	brain.status_changed.connect(func(s: String, d: String, w: int) -> void: states.append([s, d, w]))
	var sent := []
	var replies := []
	brain.transport = func(body: Dictionary, key: String) -> Dictionary:
		sent.append([body.duplicate(true), key])
		return {"code": 200, "body": replies.pop_front()} if not replies.is_empty() else {"code": 500}

	# no key: asleep
	BunnyBrain.set_setting("cooldown", 0)
	_check(not brain.awake(), "no key: asleep")
	brain.ask(bob_peer, "Hi!")
	_check(answers.size() == 1 and bool(answers[0][2]) and "no brain" in str(answers[0][1]) and sent.is_empty(), "and says so, without a request")

	# a question with a tool round
	BunnyBrain.set_setting("api_key", KEY)
	_check(brain.awake(), "with a key: awake")
	answers.clear()
	replies.append({"stop_reason": "tool_use", "usage": {"input_tokens": 900, "output_tokens": 40},
		"content": [{"type": "text", "text": "Let me look."}, {"type": "tool_use", "id": "toolu_1", "name": "sheet_read", "input": {}},
			{"type": "tool_use", "id": "toolu_2", "name": "sheet_read", "input": {"character": "Mira"}}]})
	replies.append({"stop_reason": "end_turn", "usage": {"input_tokens": 1200, "output_tokens": 30},
		"content": [{"type": "text", "text": "Borin has plenty of hit points!"}]})
	brain.ask(bob_peer, "How many HP do I have?", {"ref": BORIN})
	await _until(func() -> bool: return not answers.is_empty())
	_check(answers.size() == 1 and int(answers[0][0]) == bob_peer and str(answers[0][1]) == "Borin has plenty of hit points!" and not bool(answers[0][2]), "Bob gets the answer (%s)" % [answers])
	_check(sent.size() == 2 and str(sent[0][0].model) == "claude-haiku-5-5" and (sent[0][0].tools as Array).size() == BunnyTools.names().size(), "Haiku by default, with the table's tools")
	var second: Array = sent[1][0].messages if sent.size() == 2 else []
	var results: Array = second[-1].content if not second.is_empty() else []
	_check(results.size() == 2 and results.all(func(r: Dictionary) -> bool: return r.type == "tool_result"), "both tool results in one message")
	_check(results.size() == 2 and "Borin" in str(results[0].content) and not results[0].has("is_error"), "his own sheet as the result")
	_check(results.size() == 2 and bool(results[1].get("is_error", false)) and "not allowed" in str(results[1].content), "Mira's sheet refused: an error for the model")
	_check(second.size() == 3 and (second[1].content as Array).size() == 3, "the assistant's turn went back whole")
	_check(brain.tokens_used == 2170, "tokens counted (%d)" % brain.tokens_used)
	_check("Borin" in str(sent[0][0].system) and "bob" in str(sent[0][0].system).to_lower(), "it knows who asks and their character")

	# the key: only as the transport's key, nowhere else
	_check(sent.all(func(s: Array) -> bool: return str(s[1]) == KEY and not (KEY in JSON.stringify(s[0]))), "the key goes only into the header, never the body")
	_check(not (KEY in JSON.stringify(answers)) and not (KEY in JSON.stringify(states)), "nor into an answer or a status")
	_check(not (KEY in str(brain._http_error({"code": 401}))), "nor into an error")
	_check(ProjectSettings.globalize_path(BunnyBrain.settings_file).begins_with(OS.get_user_data_dir()), "it is kept in user:// (%s)" % BunnyBrain.settings_file)

	# history per player
	_check((brain._history.get("bob", []) as Array).size() == 2 and not brain._history.has("dm"), "Bob's history: his question and the answer")
	replies.append({"stop_reason": "end_turn", "usage": {"input_tokens": 10, "output_tokens": 5}, "content": [{"type": "text", "text": "Yes."}]})
	answers.clear()
	brain.ask(bob_peer, "Really?")
	await _until(func() -> bool: return not answers.is_empty())
	_check((sent[-1][0].messages as Array).size() == 3, "the next question comes with it")

	# cooldown
	BunnyBrain.set_setting("cooldown", 30)
	answers.clear()
	var before := sent.size()
	brain.ask(bob_peer, "And now?")
	_check(answers.size() == 1 and bool(answers[0][2]) and "again in" in str(answers[0][1]) and sent.size() == before, "too soon: wait (%s)" % [answers])
	BunnyBrain.set_setting("cooldown", 0)

	# one at a time, the others wait (and everyone can see it)
	var gate := [false]
	brain.transport = func(body: Dictionary, _key: String) -> Dictionary:
		while not gate[0]:
			await process_frame
		return {"code": 200, "body": {"stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1},
			"content": [{"type": "text", "text": "Answer to %s" % str((body.messages as Array)[-1].content)}]}}
	answers.clear()
	states.clear()
	brain.ask(bob_peer, "one")
	brain.ask(1, "two")
	_check(brain.state == "thinking" and brain.waiting() == 1, "thinking for Bob, one waiting")
	_check(states.any(func(s: Array) -> bool: return s[0] == "thinking" and "Borin" in str(s[1]) or "Bob" in str(s[1])), "the status says for whom (%s)" % [states])
	_check(states[-1][2] == 1, "and how many wait")
	gate[0] = true
	await _until(func() -> bool: return answers.size() == 2)
	_check(answers.size() == 2 and str(answers[0][1]) == "Answer to one" and int(answers[1][0]) == 1 and str(answers[1][1]) == "Answer to two", "answered in order (%s)" % [answers])
	_check(brain.state == "idle" and brain.waiting() == 0, "idle again")

	# the token limit
	BunnyBrain.set_setting("token_limit", 1000)
	answers.clear()
	brain.ask(bob_peer, "More?")
	_check(not answers.is_empty() and bool(answers[0][2]) and "worn out" in str(answers[0][1]), "past the limit: worn out")
	_check(not brain.awake(), "asleep for the session")
	BunnyBrain.set_setting("token_limit", 200000)

	# the end of the session
	brain.end_session()
	_check(brain._history.is_empty() and brain.tokens_used == 0, "end of the session: the histories are gone")

	# the settings dialog never shows the key
	var dlg := BunnySettings.new()
	dlg.brain = brain
	root.add_child(dlg)
	dlg.fill()
	_check(dlg.key_edit.text == "" and dlg.key_edit.secret and "saved" in dlg.key_edit.placeholder_text, "the dialog doesn't show the key")
	dlg.key_edit.text = "sk-ant-new"
	dlg.limit.value = 5000
	dlg.save()
	_check(BunnyBrain.setting("api_key") == "sk-ant-new" and int(BunnyBrain.setting("token_limit")) == 5000, "a new key and limit saved")
	dlg.fill()
	dlg.save()
	_check(BunnyBrain.setting("api_key") == "sk-ant-new", "saving without typing keeps the key")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("bunny brain: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
