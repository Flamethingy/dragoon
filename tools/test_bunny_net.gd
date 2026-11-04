extends SceneTree
## Headless check of asking the Table Bunny over the network (TASK-97) with a fake API: a
## player's "/bunny" question reaches the host's brain (with their own character only) and the
## answer comes back to that player alone; "/bunny!" answers everyone (and they see the
## question); everyone sees the bunny's busy status while it thinks; no key: it says it sleeps.
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
	_check(bob.rolls.any(func(r: Dictionary) -> bool: return bool(r.get("bunny_question", false)) and "hello?" in str(r.text)), "Bob's question is in his chat")

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
	_check(bob.rolls[-1].get("bunny", false) and "speed becomes 0" in NetTable.roll_bbcode(bob.rolls[-1]), "in his chat feed")
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
