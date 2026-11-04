extends SceneTree
## Headless check of the Table Bunny on the clients (TASK-98) with a fake brain: it is on
## every client, sleeps without a brain, thinks (with its badge) while the host's brain works
## for someone, talks in a bubble when it answers me (long answers scroll), a click opens the
## chat with "/bunny ", and per client it can be quiet, big or hidden (the Esc menu brings it
## back). It walks along the bottom when idle. TASK-101: Tamago's rig and poses, puffs when
## it appears and vanishes, carried by the scruff and falling back, hops, and the host's look
## (colours, behaviour) on every screen.
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
	root.size = Vector2i(1280, 720)  # the headless window shrinks to 64 px on the first frame
	var red := ""
	for w: Dictionary in Worlds.list(app.worlds_root):
		red = str(w._dir).path_join("timelines/red-fang")
	_check(app.host(red, PORT) == OK, "hosted")
	await process_frame
	var bunny: TableBunny = app.table_ui.bunny
	_check(bunny != null and bunny.visible and absf(bunny.size.y - TableBunny.SIZES.normal) <= 1.0, "the bunny is at the DM's table, Tamago's size (%s)" % bunny.size)
	_check(bunny.anim == "sleep", "no brain: it sleeps (%s)" % bunny.anim)
	_check(bunny.rig != null and bunny.rig.get_child_count() >= 10, "Tamago's rig, all its parts (%d)" % bunny.rig.get_child_count())
	var ui0 := bunny.get_parent()
	_check(ui0.get_children().any(func(n: Node) -> bool: return n is BunnyPuff) and not bunny.body.visible, "it appears in a puff")
	await _until(func() -> bool: return bunny.body.visible, 60)
	_check(bunny.body.visible, "and is there when the smoke covers it")
	await process_frame
	_check(bunny.rig.anim == "sleep" and bunny.rig._variant.get("eye") == "eye_closed", "asleep: the sleep pose, eyes shut")
	var ui := bunny.get_parent() as Control
	_check(is_equal_approx(bunny.position.y + bunny.size.y + 6.0, ui.size.y), "at the bottom of the window (%s %s %s %s)" % [bunny.position, bunny.size, ui.size, bunny.state])

	# per client: big, hidden, back from the Esc menu
	bunny.set_size_name("small")
	_check(absf(bunny.size.y - TableBunny.SIZES.small) <= 1.0, "small")
	bunny.set_on(false)
	_check(bunny.visible and bunny.get_parent().get_children().any(func(n: Node) -> bool: return n is BunnyPuff), "switched off: it vanishes in a puff")
	await _until(func() -> bool: return not bunny.visible, 60)
	_check(not bunny.visible, "hidden")
	app.esc_menu.open()
	var show := app.esc_menu.button("Show the bunny")
	_check(show != null, "the Esc menu offers it back")
	if show != null:
		show.pressed.emit()
	_check(bunny.visible and bunny.is_on(), "and it's back")
	bunny.set_size_name("normal")

	# walking when idle
	bunny.anim = "idle"
	bunny._rest = 0.0
	var hops: float = bunny.behaviour.hop_chance
	bunny.behaviour.hop_chance = 0.0  # a hop in place instead of the walk made this flaky
	var x0 := bunny.position.x
	for i in 20:
		bunny._process(0.1)
	_check(bunny.anim in ["walk", "idle"] and bunny.position.x != x0, "it walks along the bottom")
	bunny.behaviour.hop_chance = hops
	bunny.anim = "walk"
	bunny._walk_left = 5.0
	bunny._process(0.05)
	_check(bunny.rig.anim == "walk", "with the walk pose")

	# carried by the scruff, dropped: it falls back down and lands
	var ground := bunny.position.y
	bunny.pick_up(bunny.global_position + Vector2(bunny.size.x * 0.5, bunny.size.y * 0.3))
	bunny.drag_to(Vector2(400, 200))
	bunny._process(0.016)
	_check(bunny.state == "dragged" and bunny.rig.anim == "dragged" and bunny.position.y < ground - 100.0, "picked up and carried (%s)" % bunny.position)
	var neck := bunny.global_position + bunny.body.position + bunny.rig.neck_position()
	_check(neck.distance_to(Vector2(400, 200)) < 2.0, "held by the neck (%s)" % neck)
	bunny.drop()
	bunny._process(0.05)
	_check(bunny.state == "air" and bunny.rig.anim == "fall", "let go: it falls")
	for i in 120:
		bunny._process(0.016)
	_check(bunny.state == "ground" and is_equal_approx(bunny.position.y, ground), "and lands at the bottom")
	bunny.hop()
	bunny._process(0.016)
	_check(bunny.state == "air" and bunny.rig.anim == "jump" and bunny.position.y < ground, "a hop")
	for i in 120:
		bunny._process(0.016)
	_check(bunny.state == "ground", "back down")

	# TASK-102: on a window top (BunnyDesk gives it Dragoon's window as a platform)
	_check(not BunnyDesk.available() and bunny.get_parent() == app.table_ui._root, "headless: it stays inside Dragoon")
	var top := ground + bunny.size.y - 200.0  # a window top 200 px above the floor
	bunny.platforms = [{"id": 1, "left": 0.0, "y": top, "segments": [Vector2(0, 1000)]}]
	bunny.anim = "idle"
	bunny.behaviour.hop_chance = 1.0
	bunny._rest = 0.0
	bunny._process(0.016)
	_check(bunny.state == "air" and bunny._vel_y < 0.0, "it jumps up onto the window")
	for i in 200:
		bunny._process(0.016)
		if bunny.state == "ground":
			break
	_check(bunny.state == "ground" and is_equal_approx(bunny.position.y + bunny.size.y, top), "and stands on it (%s)" % (bunny.position.y + bunny.size.y))
	bunny.behaviour.hop_chance = 0.0
	bunny._rest = 99.0
	var x1 := bunny.position.x
	bunny.platforms = [{"id": 1, "left": 30.0, "y": top, "segments": [Vector2(30, 1030)]}]
	bunny._process(0.016)
	_check(is_equal_approx(bunny.position.x, x1 + 30.0), "it rides along when the window moves")
	bunny.platforms = []
	bunny._process(0.016)
	_check(bunny.state == "air", "window gone: it falls")
	for i in 200:
		bunny._process(0.016)
	_check(bunny.state == "ground" and is_equal_approx(bunny.position.y, ground), "down to the floor")
	var poly := BunnyDesk.region_polygon(BunnyDesk.merge_overlapping([Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10), Rect2(40, 0, 10, 10)] as Array[Rect2]))
	_check(poly.size() == 10, "the click-through region: two boxes, one polygon (%d)" % poly.size())

	# the icon in the lower left corner: away and back, in puffs
	var icon := app.table_ui.bunny_button
	_check(icon != null and icon.visible and icon.texture_normal != null, "the bunny icon is there")
	_check(icon.position.x < 40 and icon.position.y > ui.size.y - 80, "in the lower left corner (%s)" % icon.position)
	icon.toggle()
	await _until(func() -> bool: return not bunny.visible, 60)
	_check(not bunny.visible and not bunny.is_on(), "a click sends it away")
	icon.toggle()
	await process_frame
	_check(bunny.visible and bunny.is_on() and ui.get_children().any(func(n: Node) -> bool: return n is BunnyPuff), "another calls it back, in a puff")

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
	# the host's look: on every screen
	BunnyBrain.set_setting("colors", {"fur": "#ff8800"})
	BunnyBrain.set_setting("behaviour", {"walk_speed": 90.0, "hop_chance": 0.0})
	dm.share_bunny_look()
	await _until(func() -> bool: return float(bb.behaviour.walk_speed) == 90.0)
	_check(float(bb.behaviour.walk_speed) == 90.0 and float(bb.behaviour.hop_chance) == 0.0, "Bob's bunny walks the host's way")
	_check(bb.rig._to.has(Color.html("#ff8800")) and dbunny.rig._to.has(Color.html("#ff8800")), "in the host's colours, everywhere")
	# the settings: colour pickers with a preview, saved and shared
	var dialog := BunnySettings.new()
	dialog.brain = dm.bunny
	root.add_child(dialog)
	dialog.fill()
	_check(dialog.color_pickers.size() == 4 and dialog.color_pickers.has("fur") and (dialog.color_pickers.fur as ColorPickerButton).color == Color.html("#ff8800"), "the settings show its colours")
	(dialog.color_pickers.hair as ColorPickerButton).color = Color.html("#22aa44")
	dialog._preview_colors()
	_check(dialog.preview._to.has(Color.html("#22aa44")), "the preview follows the picker")
	_check(str(dialog.picked_colors().eyes) == "", "untouched slots stay as drawn")
	dialog.walk_speed.value = 55
	dialog.save()
	await _until(func() -> bool: return float(bb.behaviour.walk_speed) == 55.0)
	_check(float(bb.behaviour.walk_speed) == 55.0 and bb.rig._to.has(Color.html("#22aa44")), "saved: Bob sees the new look")
	dialog.queue_free()
	await _until(func() -> bool: return bb.anim != "sleep")
	_check(bb.anim in ["idle", "walk"], "with a brain: awake (%s)" % bb.anim)
	bob.ask_bunny("what does grappled do?", false, BORIN)
	await _until(func() -> bool: return bb.anim == "think" and dbunny.anim == "think")
	_check(bb.anim == "think" and dbunny.anim == "think", "both bunnies think")
	await process_frame
	_check(bb.rig.anim == "thinking", "paw at its mouth")
	_check(bb.badge.visible and "Borin" in bb.badge.text, "the badge says for whom (%s)" % bb.badge.text)
	gate[0] = true
	await _until(func() -> bool: return bb.bubble.visible)
	_check(bb.bubble.visible and bb.bubble_text.text == "Grappled: speed 0!" and bb.mood == "happy", "Bob's bunny says it in a bubble, happily")
	await process_frame
	_check(bb.rig.talking and bb.rig.mood == "happy", "its mouth moves")
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
	await _until(func() -> bool: return bob.bunny_log.any(func(r: Dictionary) -> bool: return str(r.get("text", "")) == "Quietly."))
	_check(not bb.bubble.visible, "quiet: no bubble")
	_check(bob.bunny_log.any(func(r: Dictionary) -> bool: return str(r.get("text", "")) == "Quietly."), "but it's in the bunny chat")
	bb.set_quiet(false)

	# a click opens the chat, ready to ask
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	bb._gui_input(click)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	bb._gui_input(up)
	_check(bob_chat.visible and bob_chat.line.text == "/bunny ", "a click: the chat with /bunny (%s)" % bob_chat.line.text)
	bb.anim = "idle"
	bb._process(0.016)
	_check(bb.rig.anim == "listening" or not bob_chat.line.has_focus(), "typing to it: it listens")
	var menu := bb.settings_menu()
	_check(menu.item_count == 5, "a right click: its settings")

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
