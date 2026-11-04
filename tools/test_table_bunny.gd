extends SceneTree
## Headless check of the Table Bunny on the clients (TASK-98) with a fake brain: it is on
## every client, sleeps without a brain, thinks (with its badge) while the host's brain works
## for someone, talks in a bubble when it answers me (long answers scroll), a click opens the
## chat with "/bunny ", and per client it can be quiet, big or hidden (the Esc menu brings it
## back). It walks along the bottom when idle.
## godot --headless --path . -s tools/test_table_bunny.gd

const DIR := "user://test_table_bunny"
const PORT := 47855
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("packages"))
	App.settings_file = DIR.path_join("app.cfg")
	ServerStatus.servers_file = DIR.path_join("servers.json")
	Dock.layout_file = DIR.path_join("layout.json")
	BunnyBrain.settings_file = DIR.path_join("bunny_settings.cfg")
	TableBunny.settings_file = DIR.path_join("bunny_client.cfg")
	BunnyBrain.set_setting("cooldown", 0)
	root.size = Vector2i(1280, 720)
	var app := App.new()
	app.worlds_root = base.path_join("worlds")
	app.packages_root = base.path_join("packages")
	root.add_child(app)
	await process_frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	_check(app.host(red, PORT) == OK, "hosted")
	await process_frame
	var bunny: TableBunny = app.table_ui.bunny
	_check(bunny != null and bunny.visible and bunny.size.x == TableBunny.SIZES.small, "the bunny is at the DM's table")
	_check(bunny.anim == "sleep", "no brain: it sleeps (%s)" % bunny.anim)
	await process_frame
	var ui := bunny.get_parent() as Control
	_check(is_equal_approx(bunny.position.y + bunny.size.y + 6.0, ui.size.y), "at the bottom of the window")

	# per client: big, hidden, back from the Esc menu
	bunny.set_size_name("big")
	_check(bunny.size.x == TableBunny.SIZES.big, "big")
	bunny.set_on(false)
	_check(not bunny.visible, "hidden")
	app.esc_menu.open()
	var show := app.esc_menu.button("Show the bunny")
	_check(show != null, "the Esc menu offers it back")
	if show != null:
		show.pressed.emit()
	_check(bunny.visible and bunny.is_on(), "and it's back")
	bunny.set_size_name("small")

	# walking when idle
	bunny.anim = "idle"
	bunny._rest = 0.0
	var x0 := bunny.position.x
	for i in 20:
		bunny._process(0.1)
	_check(bunny.anim in ["walk", "idle"] and bunny.position.x != x0, "it walks along the bottom")

	app.esc_menu.open()
	app.esc_menu.button("End the session").pressed.emit()
	await process_frame
	await process_frame

	# two clients (the DM's and Bob's tables, each with its bunny)
	var dm := _table("DM", "dm")
	var dm_ui := _ui(dm)
	var dbunny: TableBunny = dm_ui[1]
	var bob := _table("Bob", "bob")
	var bob_ui := _ui(bob)
	var bob_chat: ChatBox = bob_ui[0]
	var bb: TableBunny = bob_ui[1]
	await process_frame
	_check(dm.host(PORT + 1) == OK, "DM hosts")
	_check(bob.join("127.0.0.1:%d" % (PORT + 1), "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and bb.visible)
	_check(bb.visible and bb.anim == "sleep", "on Bob's screen too, asleep")

	# a (fake) brain: it thinks for Bob, everyone sees it, then it answers Bob
	BunnyBrain.set_setting("api_key", "sk-ant-test")
	var gate := [false]
	var reply := ["Grappled: speed 0!"]
	dm.bunny.transport = func(_body: Dictionary, _key: String) -> Dictionary:
		while not gate[0]:
			await process_frame
		return {"code": 200, "body": {"stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1},
			"content": [{"type": "text", "text": reply[0]}]}}
	dm.bunny._set_state("idle", "")
	await _until(func() -> bool: return bb.anim != "sleep")
	_check(bb.anim in ["idle", "walk"], "with a brain: awake (%s)" % bb.anim)
	bob.ask_bunny("what does grappled do?", false, BORIN)
	await _until(func() -> bool: return bb.anim == "think" and dbunny.anim == "think")
	_check(bb.anim == "think" and dbunny.anim == "think", "both bunnies think")
	_check(bb.badge.visible and "Borin" in bb.badge.text, "the badge says for whom (%s)" % bb.badge.text)
	gate[0] = true
	await _until(func() -> bool: return bb.bubble.visible)
	_check(bb.bubble.visible and bb.bubble_text.text == "Grappled: speed 0!" and bb.mood == "happy", "Bob's bunny says it in a bubble, happily")
	_check(not dbunny.bubble.visible, "the DM's bunny doesn't (it was Bob's question)")
	_check(bb.bubble.position.y + bb.position.y >= 0.0, "the bubble stays inside the window")
	await _until(func() -> bool: return bb.anim == "talk" or bb.anim == "idle")
	_check(not bb.badge.visible, "the badge goes when it's done")

	# a long answer scrolls in a small panel
	reply[0] = "Grappling, step by step. ".repeat(20)
	bob.ask_bunny("explain all of grappling", false, BORIN)
	await _until(func() -> bool: return bb.bubble_text.text.begins_with("Grappling, step"))
	_check(bb.bubble_text.scroll_active and bb.bubble_text.custom_minimum_size.y > 0, "a long answer: a scrolling panel")
	bb.hide_bubble()

	# quiet: the chat only
	bb.set_quiet(true)
	reply[0] = "Quietly."
	bob.ask_bunny("psst", false, BORIN)
	await _until(func() -> bool: return bob.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")) == "Quietly."))
	_check(not bb.bubble.visible, "quiet: no bubble")
	_check(bob.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")) == "Quietly."), "but it's in the chat")
	bb.set_quiet(false)

	# a click opens the chat, ready to ask
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	bb._gui_input(click)
	_check(bob_chat.visible and bob_chat.line.text == "/bunny ", "a click: the chat with /bunny (%s)" % bob_chat.line.text)
	var menu := bb.settings_menu()
	_check(menu.item_count == 4, "a right click: its settings")

	# the host's brain gone to sleep: so does it
	BunnyBrain.set_setting("api_key", "")
	dm.bunny._set_state("sleeping", "")
	await _until(func() -> bool: return bb.anim == "sleep")
	_check(bb.anim == "sleep" and dbunny.anim == "sleep", "no brain: asleep again")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(base)
	print("table bunny: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _table(branch: String, cache: String) -> NetTable:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var t := NetTable.new()
	t.name = "Table"
	t.timeline_dir = DIR + "/worlds/westmarch/timelines/red-fang"
	t.cache_dir = DIR.path_join("cache_" + cache)
	t.auto_ui = false
	holder.add_child(t)
	return t


## A screen for a table: [its chat, its bunny].
func _ui(t: NetTable) -> Array:
	var ui := Control.new()
	ui.size = Vector2(1280, 720)
	t.get_parent().add_child(ui)
	var chat := ChatBox.new()
	chat.table = t
	ui.add_child(chat)
	var b := TableBunny.new()
	b.table = t
	b.chat = chat
	ui.add_child(b)
	return [chat, b]


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
