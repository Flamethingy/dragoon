extends SceneTree
## Headless check of the 3D dice (TASK-61): the shapes (d4-d20), the dice of a roll card (a d100
## as two d10s, a natural 20 glows), physics dice landing on the host's numbers, every new
## roll card throwing them, the settings and a roll entered by hand.
## godot --headless --path . -s tools/test_dice3d.gd

const DIR := "user://test_dice3d"
const TIMELINE := DIR + "/worlds/westmarch/timelines/red-fang"

var _failed := 0


func _init() -> void:
	# --- Shapes ----------------------------------------------------------------------------------
	for sides: int in [4, 6, 8, 10, 12, 20]:
		var s := DieShapes.shape(sides)
		var outward := (s.faces as Array).all(func(f: Dictionary) -> bool: return (f.normal as Vector3).dot(f.center) > 0 and is_equal_approx((f.normal as Vector3).length(), 1.0))
		_check((s.faces as Array).size() == sides and outward and s.mesh is ArrayMesh, "d%d: %d faces, normals outward (%d)" % [sides, sides, (s.faces as Array).size()])

	# --- A roll card's dice ----------------------------------------------------------------------
	var list := DiceTray.dice_of({"results": [{"formula": "2d20kh1+5", "dice": [[20, 3]], "crit": "20"}, {"formula": "1d100", "dice": [[47]]},
		{"formula": "1d100", "dice": [[100]]}, {"formula": "3", "dice": []}]})
	_check(list.size() == 6 and list[0] == {"sides": 20, "value": 20, "glow": true} and list[1].value == 3 and not list[1].glow, "a d20 pair, the 20 glows (%s)" % [list])
	_check(list[2] == {"sides": 10, "value": 4, "tens": true} and list[3].value == 7 and list[4].value == 10 and list[4].tens and list[5].value == 10, "d100 = tens + units die (47, 100 = 00 + 0)")

	# --- Physics: they land on the host's numbers -------------------------------------------------
	DiceTray.settings_file = DIR + "/dice.cfg"
	DiceTray.force = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var holder := Control.new()
	holder.size = Vector2(1600, 900)
	root.add_child(holder)
	var tray := DiceTray.new()
	holder.add_child(tray)
	tray.size = Vector2(1600, 900)
	await process_frame
	var wanted := [{"sides": 4, "value": 3}, {"sides": 6, "value": 6}, {"sides": 8, "value": 1}, {"sides": 10, "value": 10},
		{"sides": 10, "value": 4, "tens": true}, {"sides": 12, "value": 11}, {"sides": 20, "value": 20, "glow": true}, {"sides": 20, "value": 1}]
	var dice := tray.throw(wanted, Color(0.2, 0.4, 0.8), 1.6, 0.2)
	await _until(func() -> bool: return dice.all(func(d: Die3D) -> bool: return d.is_settled), 1200)
	_check(dice.all(func(d: Die3D) -> bool: return d.is_settled), "they come to rest")
	for i in dice.size():
		_check(dice[i].value_up() == int(wanted[i].value), "d%d shows %d on top (%d)" % [dice[i].sides, wanted[i].value, dice[i].value_up()])
	_check(dice[3].labels[dice[3].up_face()].text == "0" and dice[4].labels[dice[4].up_face()].text == "40", "a d10's 10 reads 0, the tens die 40")
	_check(dice[6].get_child_count() > dice[7].get_child_count(), "the natural 20 lights up")
	var s0 := (dice[0].get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	_check(s0.albedo_color == Color(0.2, 0.4, 0.8), "in the roller's colour")
	await _until(func() -> bool: return not tray.busy(), 200)
	_check(not tray.busy(), "they leave after the linger time")

	# --- Settings -------------------------------------------------------------------------------
	_check(DiceTray.settings() == {"enabled": true, "speed": 1.0, "linger": 3.0}, "defaults: on, normal speed, 3 s")
	DiceTray.set_setting("enabled", false)
	tray.throw_entry({"results": [{"formula": "1d20", "dice": [[5]]}]})
	_check(not tray.busy(), "off: no dice")
	DiceTray.set_setting("enabled", true)
	holder.queue_free()

	# --- At the table: every roll card throws, a roll by hand -------------------------------------
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR + "/worlds"))
	Worlds.install_example(ProjectSettings.globalize_path(DIR + "/worlds"))
	var host := Node.new()
	host.name = "DM"
	root.add_child(host)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var dm := NetTable.new()
	dm.name = "Table"
	dm.auto_ui = true
	dm.timeline_dir = TIMELINE
	dm.cache_dir = DIR.path_join("cache")
	host.add_child(dm)
	await process_frame
	_check(dm.host(47803) == OK, "DM hosts")
	await process_frame
	dm.roll("1d20+2")
	_check(dm._ui.dice_tray.busy() and dm._ui.dice_tray.dice.size() == 1 and dm._ui.dice_tray.dice[0].sides == 20, "a roll card throws its dice")
	dm.roll("4d6kh3")
	_check(dm._ui.dice_tray.dice.size() == 4, "the next roll replaces them (4d6)")
	var chat := ChatBox.new()
	chat.table = dm
	dm._ui.add_child(chat)
	await process_frame
	_check(chat.find_child("DiceMenu", true, false) != null, "the chat has the small dice menu")
	var dlg := chat.manual_roll()
	(dlg.find_child("Value", true, false) as LineEdit).text = "17"
	dlg.confirmed.emit()
	_check(dm.rolls.any(func(r: Dictionary) -> bool: return str(r.get("text", "")) == "rolled by hand: 17"), "a roll by hand goes into the chat")
	dm.multiplayer.multiplayer_peer.close()
	host.queue_free()
	await process_frame
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	print("dice3d: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


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
