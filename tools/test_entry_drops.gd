extends SceneTree
## Headless check of dropping Book entries on a character (TASK-94): an item, spell and feature
## dropped on a token join that creature's lists (another item raises the count, a spell or
## feature already there is not added twice and the dropper is told), a player may only drop
## on what they may change, and the HUD takes drops for its active character.
## godot --headless --path . -s tools/test_entry_drops.gd

const PORT := 47841
const ADDRESS := "127.0.0.1:47841"
const DIR := "user://test_entry_drops"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"
const BORIN := "characters/borin"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	await process_frame
	root.size = Vector2i(1280, 720)  # headless starts with a tiny window
	var dm := _table("DM", "dm")
	var bob := _table("Bob", "bob")
	await process_frame
	_check(dm.host(PORT) == OK, "DM hosts")
	_check(bob.join(ADDRESS, "bob") == OK, "Bob joins")
	await _until(func() -> bool: return bob.my_pc == BORIN and bob.grid.tokens.has(BORIN))

	var sword := {"_kind": "items", "id": "longsword", "name": "Longsword"}
	var bolt := {"_kind": "spells", "id": "fire-bolt", "name": "Fire Bolt"}
	var feat := {"_kind": "features", "id": "second-wind", "name": "Second Wind"}
	var goblin := {"_kind": "creatures", "id": "goblin", "name": "Goblin"}

	# the DM drops on Borin's token
	var drop := MapDrop.new()
	drop.table = dm
	dm.get_parent().add_child(drop)
	drop.size = Vector2(1280, 720)
	await process_frame
	var at := _token_at(drop, dm, BORIN)
	_check(drop.token_ref_at(at) == BORIN, "the token under the mouse is found")
	for e: Dictionary in [sword, bolt, feat]:
		_check(drop._can_drop_data(at, EntryDrag.data(e)), "%s may be dropped on Borin" % e.name)
		drop._drop_data(at, EntryDrag.data(e))
	await process_frame
	var sheet := dm.sheet_for(Reveal.DM, BORIN)
	_check(_qty(sheet, "items/longsword") == 1, "the sword is in the inventory (%s)" % [sheet.get("inventory")])
	_check((sheet.get("spells", []) as Array).has("spells/fire-bolt"), "the spell in the spell list")
	_check((sheet.get("features", []) as Array).has("features/second-wind"), "the feature in the features")
	_check(dm.status == "Second Wind added to %s's features" % str(sheet.name), "the DM is told (%s)" % dm.status)
	drop._drop_data(at, EntryDrag.data(sword))
	drop._drop_data(at, EntryDrag.data(bolt))
	sheet = dm.sheet_for(Reveal.DM, BORIN)
	_check(dm.status.ends_with("already knows Fire Bolt"), "a spell already there: said so (%s)" % dm.status)
	_check(_qty(sheet, "items/longsword") == 2 and (sheet.spells as Array).count("spells/fire-bolt") == 1, "a second sword counts up, the spell stays once")
	_check(not drop._can_drop_data(Vector2(-500, -500), EntryDrag.data(sword)), "beside the tokens: no drop")
	_check(drop._can_drop_data(_free_spot(drop, dm), EntryDrag.data(goblin)), "a creature is still dropped on the map to spawn")

	# Bob: only his own character
	var bob_drop := MapDrop.new()
	bob_drop.table = bob
	bob.get_parent().add_child(bob_drop)
	bob_drop.size = Vector2(1280, 720)
	await process_frame
	var other := ""
	for id: String in bob.grid.tokens:
		if id != BORIN and id != NetTable.PARTY and id.get_slice("/", 0) in Timeline.CREATURES and not bob.may_change(id):
			other = id
	_check(other != "", "a creature Bob doesn't control is on the map")
	if other != "":
		_check(not bob_drop._can_drop_data(_token_at(bob_drop, bob, other), EntryDrag.data(sword)), "Bob can't drop on %s" % other)
	var bat := _token_at(bob_drop, bob, BORIN)
	_check(bob_drop._can_drop_data(bat, EntryDrag.data(sword)), "Bob may drop on Borin")
	bob_drop._drop_data(bat, EntryDrag.data(sword))
	await _until(func() -> bool: return _qty(dm.sheet_for(Reveal.DM, BORIN), "items/longsword") == 3)
	_check(_qty(dm.sheet_for(Reveal.DM, BORIN), "items/longsword") == 3, "Bob's sword arrives on the host")
	await _until(func() -> bool: return bob.status.contains("Longsword added"))
	_check(bob.status.contains("Longsword added to"), "Bob is told (%s)" % bob.status)

	# the HUD (and every Control in it) takes drops for its active character
	var hud := Control.new()
	hud.size = Vector2(300, 200)
	root.add_child(hud)
	var piece := PanelContainer.new()
	piece.size = Vector2(100, 100)
	hud.add_child(piece)
	EntryDrag.accept_on(hud, dm, func() -> String: return BORIN)
	var late := Button.new()  # added later: takes them too
	late.position = Vector2(150, 20)
	late.size = Vector2(80, 40)
	hud.add_child(late)
	await process_frame
	var shield := {"_kind": "items", "id": "shield", "name": "Shield"}
	_drag_drop(EntryDrag.data(shield), Vector2(50, 50))
	await process_frame
	_check(_qty(dm.sheet_for(Reveal.DM, BORIN), "items/shield") == 1, "dropped on a HUD piece: added (%s)" % dm.status)
	_drag_drop(EntryDrag.data(shield), Vector2(190, 40))
	await process_frame
	_check(_qty(dm.sheet_for(Reveal.DM, BORIN), "items/shield") == 2, "also on a control added later")

	dm.multiplayer.multiplayer_peer.close()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("entry drops: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _qty(sheet: Dictionary, item: String) -> int:
	var inv: Variant = sheet.get("inventory", [])
	if inv is Dictionary:
		return int((inv as Dictionary).get(item, 0))
	for it: Variant in inv:
		if it is Dictionary and str(it.get("item", "")) == item:
			return int(it.get("qty", 1))
	return 0


## Where `ref`'s token is, in `drop`'s coordinates.
func _token_at(drop: MapDrop, t: NetTable, ref: String) -> Vector2:
	var token: Sprite2D = t.grid.tokens[ref]
	var screen := t.grid.get_canvas_transform() * token.global_position
	return drop.get_global_transform_with_canvas().affine_inverse() * screen


func _free_spot(drop: MapDrop, t: NetTable) -> Vector2:
	for x in range(20, 1260, 40):
		for y in range(20, 700, 40):
			if drop.token_ref_at(Vector2(x, y)) == "":
				return Vector2(x, y)
	return Vector2(5, 5)


## A real GUI drag and drop at `at` (the root's pixels).
func _drag_drop(data: Variant, at: Vector2) -> void:
	root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	var start := Label.new()
	root.add_child(start)
	start.force_drag(data, null)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(m)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	up.global_position = at
	root.push_input(up)
	start.queue_free()


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
