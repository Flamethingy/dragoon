extends SceneTree
## Headless check of asking the Table Bunny over the network (TASK-97) with a fake API: a
## player's "/bunny" question reaches the host's brain (with their own character only) and the
## answer comes back to that player alone; "/bunny!" answers everyone (and they see the
## question); everyone sees the bunny's busy status while it thinks; no key: it says it sleeps.
## TASK-103: each one's conversation is in their own bunny chat log (on their computer, per table
## and player), not in the table's chat; only what is for everyone also goes there. The bunny
## chat window shows my log and asks.
## godot --headless --path . -s tools/test_bunny_net.gd

const PORT := 47853
const ADDRESS := "127.0.0.1:47853"
const DIR := "user://test_bunny_net"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"
const MIRA := "characters/mira"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	BunnyBrain.settings_file = DIR.path_join("bunny_settings.cfg")
	BunnyBrain.set_setting("cooldown", 0)
	BunnyBrain.set_setting("name", "Hops")
	NetTable.bunny_log_dir = DIR.path_join("bunny_chat")
	await process_frame
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and dm.peers.size() == 1)
	await _until(func() -> bool: return bob.bunny_name == "Hops")
	_check(bob.bunny_state == "sleeping" and bob.bunny_name == "Hops", "a newcomer learns the bunny's state and name (%s)" % bob.bunny_state)

	# no key: it says so
	var heard := []
	bob.bunny_message.connect(func(e: Dictionary) -> void: heard.append(e))
	bob.say("/bunny hello?", BORIN)
	await _until(func() -> bool: return not heard.is_empty())
	_check(not heard.is_empty() and "no brain" in str(heard[0].text) and heard[0].mood == "sleepy", "no key: the bunny sleeps (%s)" % [heard])
	_check(bob.bunny_log.any(func(r: Dictionary) -> bool: return r.role == "user" and str(r.text) == "hello?"), "Bob's question is in his bunny chat")
	_check(not bob.rolls.any(func(r: Dictionary) -> bool: return "hello?" in str(r.get("text", ""))), "not in the table's chat")

	# with a (fake) brain
	BunnyBrain.set_setting("api_key", "sk-ant-test")
	var gate := [false]
	var asked := []
	dm.bunny.transport = func(body: Dictionary, _key: String) -> Dictionary:
		asked.append(body.duplicate(true))
		while not gate[0]:
			await process_frame
		return {"code": 200, "body": {"stop_reason": "end_turn", "usage": {"input_tokens": 5, "output_tokens": 5},
			"content": [{"type": "text", "text": "Grappling: your speed becomes 0!"}]}}
	dm.bunny._set_state("idle", "")
	heard.clear()
	var dm_before := dm.rolls.size()
	bob.say("/bunny how does grappling work?", MIRA)  # not his character: not used as context
	await _until(func() -> bool: return bob.bunny_state == "thinking")
	_check(bob.bunny_state == "thinking" and "Bob" in bob.bunny_detail, "Bob sees it thinking for him (%s)" % bob.bunny_detail)
	_check(dm.bunny_state == "thinking", "so does the DM")
	_check(not asked.is_empty() and not ("Mira" in str(asked[0].system)), "someone else's character isn't given as context")
	var chat := ChatBox.new()
	chat.table = bob
	root.add_child(chat)
	chat.show_bunny_status()
	_check(chat.bunny_line.visible and "Hops is thinking for" in chat.bunny_line.text, "the chat shows it (%s)" % chat.bunny_line.text)
	gate[0] = true
	await _until(func() -> bool: return not heard.is_empty())
	_check(heard.size() == 1 and "speed becomes 0" in str(heard[0].text) and heard[0].mood == "happy" and str(heard[0].by) == "Hops", "the answer comes back to Bob (%s)" % [heard])
	_check(str(bob.bunny_log[-1].role) == "bunny" and "speed becomes 0" in str(bob.bunny_log[-1].text), "in his bunny chat")
	_check(not bob.rolls.any(func(r: Dictionary) -> bool: return "speed becomes 0" in str(r.get("text", ""))), "a private answer isn't in the table's chat")
	await process_frame
	_check(dm.rolls.size() == dm_before, "the DM doesn't get Bob's private answer")
	await _until(func() -> bool: return bob.bunny_state == "idle")
	chat.show_bunny_status()
	_check(bob.bunny_state == "idle" and not chat.bunny_line.visible, "idle again: the status line goes")

	# for everyone
	heard.clear()
	var dm_heard := []
	dm.bunny_message.connect(func(e: Dictionary) -> void: dm_heard.append(e))
	bob.say("/bunny! explain grappling to everyone", BORIN)
	await _until(func() -> bool: return not heard.is_empty() and not dm_heard.is_empty())
	_check(heard.size() == 1 and dm_heard.size() == 1 and str(dm_heard[0].to) == "all", "a public answer reaches everyone")
	_check(bob.rolls.any(func(r: Dictionary) -> bool: return bool(r.get("bunny", false))) and dm.rolls.any(func(r: Dictionary) -> bool: return bool(r.get("bunny", false))), "and is in the table's chat")
	_check(bool(bob.bunny_log[-1].public) and bool(dm.bunny_log[-1].public), "and in both bunny chats, marked for everyone")
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return bool(r.get("bunny_question", false)) and "explain grappling" in str(r.text)), "the DM sees the question too")
	_check("Borin" in str(asked[-1].system), "his own character is the context")

	# the DM's private question stays with the DM
	heard.clear()
	dm_heard.clear()
	var bob_before := bob.rolls.size()
	dm.say("/bunny secret plan for the boss fight")
	await _until(func() -> bool: return not dm_heard.is_empty())
	await process_frame
	await process_frame
	_check(dm_heard.size() == 1 and heard.is_empty() and bob.rolls.size() == bob_before, "the DM's private answer stays with the DM")
	_check(dm.bunny_log.any(func(r: Dictionary) -> bool: return "secret plan" in str(r.text)) and not bob.bunny_log.any(func(r: Dictionary) -> bool: return "secret plan" in str(r.text)), "the DM's question is in the DM's log only")
	_check(dm.bunny_log_file() != bob.bunny_log_file() and dm.bunny_log_file().ends_with("-dm.json") and bob.bunny_log_file().ends_with("-bob.json"), "a log per player (%s, %s)" % [dm.bunny_log_file(), bob.bunny_log_file()])
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(bob.bunny_log_file()))
	_check(saved is Array and (saved as Array).size() == bob.bunny_log.size(), "Bob's log is kept on his computer")

	# the bunny chat window: my log, and asking from it
	var win := BunnyChat.new()
	win.table = bob
	root.add_child(win)
	await process_frame
	win.open_at(Vector2i(100, 600))
	await process_frame
	_check(win.visible and win.log_box.get_child_count() == mini(BunnyChat.PAGE, bob.bunny_log.size()), "the chat window shows my log (%d)" % win.log_box.get_child_count())
	_check("Hops" in win.title, "talking to Hops")
	heard.clear()
	var n := bob.bunny_log.size()
	win.input.text = "from the window"
	win.submit()
	await _until(func() -> bool: return not heard.is_empty())
	_check(bob.bunny_log.size() == n + 2 and str(bob.bunny_log[n].text) == "from the window" and win.input.text == "", "asked from the window: question and answer in my log")
	_check(win.log_box.get_child_count() >= mini(BunnyChat.PAGE, n) + 1, "and in the window")
	win.queue_free()

	# a long job: everyone sees it working, questions wait with a hint, the DM can stop it
	var stopped := []
	dm.bunny.job_cancelled.connect(func(job: String) -> void: stopped.append(job))
	_check(dm.bunny.start_job("importing Deep Magic"), "a job starts")
	dm.bunny.job_progress(40)
	await _until(func() -> bool: return bob.bunny_state == "working" and "40%" in bob.bunny_detail)
	chat.show_bunny_status()
	_check(bob.bunny_state == "working" and chat.bunny_line.visible and "importing Deep Magic 40%" in chat.bunny_line.text, "Bob sees it working (%s)" % chat.bunny_line.text)
	heard.clear()
	gate[0] = false
	bob.say("/bunny are you there?", BORIN)
	await _until(func() -> bool: return not heard.is_empty())
	_check(heard.size() == 1 and bool(heard[0].get("hint", false)) and "number 1 in line" in str(heard[0].text), "busy: Bob hears he's next (%s)" % [heard])
	await _until(func() -> bool: return bob.bunny_waiting == 1)
	_check(bob.bunny_waiting == 1, "everyone sees one waiting")
	dm.say("/bunny stop")
	_check(stopped == ["importing Deep Magic"], "the DM stops the job")
	await _until(func() -> bool: return bob.bunny_state == "thinking")
	_check(bob.bunny_state == "thinking", "then Bob's question is answered")
	heard.clear()
	dm.cancel_bunny()  # and stops that answer too
	gate[0] = true
	await _until(func() -> bool: return not heard.is_empty())
	_check(heard.size() == 1 and "stopped" in str(heard[0].text) and bool(heard[0].error), "an answer stopped by the DM: Bob hears so (%s)" % [heard])
	await _until(func() -> bool: return bob.bunny_state == "idle")
	_check(bob.bunny_state == "idle", "idle again")

	chat.queue_free()
	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("bunny net: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
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
