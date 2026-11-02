class_name ChatBox
extends DockPanel
## The chat of the calm table (TASK-46, Nico 2026-11-01): the session's messages and rolls in
## one feed (NetTable.rolls) and a line to write in. Enter sends and gives the keys back to the
## map; "/r 2d6+3" or "/r perception" rolls (for the active character when there is one).
## It docks, floats and pops out like every DockPanel (TASK-50, TASK-80). Where it is belongs
## to the player, not the character: it is saved on this computer (`place_file`) and stays
## when the active character changes.

var table: NetTable
var active_ref := Callable()  ## -> String: who "/r" rolls for (the HUD's active one)
var log_text: RichTextLabel
var line: LineEdit
## Looking back on the timeline (Nico 2026-11-02): the events that had happened by then (id ->
## true); later messages are faint and the chat scrolls to the last one said by then. {} = now.
var until := {}
var _until_last := -2  ## the entry scrolled to, so dragging only rebuilds when it changes


func _init() -> void:
	super()
	name = "Chat"
	section = "chat"
	window_title = "Dragoon · Chat"
	place_file = ""
	title_label.text = "Chat"
	_head.add_child(_dice_menu())
	log_text = RichTextLabel.new()
	log_text.name = "Log"
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.selection_enabled = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.meta_clicked.connect(func(meta: Variant) -> void:
		if str(meta).begins_with("cond:") and table != null:  # a roll card's creature: its conditions (TASK-56)
			table.condition_menu_requested.emit(str(meta).substr(5))
		elif str(meta).begins_with("init:") and table != null:  # an initiative prompt (TASK-58)
			table.answer_initiative(str(meta).substr(5))
		elif str(meta).begins_with("conc:") and table != null:  # a concentration save (TASK-59)
			table.answer_concentration(str(meta).substr(5))
		elif str(meta).begins_with("endconc:") and table != null:
			table.end_concentration(str(meta).substr(8), "failed the save")
		elif str(meta).begins_with("death:") and table != null:  # a death save prompt (TASK-57)
			table.roll_death_save(str(meta).substr(6))
		elif str(meta).begins_with("save:") and table != null:  # a save prompt (TASK-55)
			table.answer_save(int(str(meta).get_slice(":", 1)), str(meta).substr(str(meta).find(":", 5) + 1))
		elif str(meta).begins_with("undo:") and table != null:  # an attack card's damage (TASK-54)
			table.undo_card(int(str(meta).substr(5)))
		elif str(meta).begins_with("apply:") and table != null:
			table.apply_card(int(str(meta).get_slice(":", 1)), str(meta).substr(str(meta).find(":", 6) + 1))
		else:
			RollTables.handle_meta(str(meta)))
	body.add_child(log_text)
	line = LineEdit.new()
	line.name = "Line"
	line.placeholder_text = "Write something...  (/r 1d20+3 rolls)"
	line.text_submitted.connect(func(_t: String) -> void: send())
	body.add_child(line)


## The dice menu (TASK-61): 3D dice on / off, fast, how long they stay, and (Nico: no physical
## dice, so only here) a roll entered by hand.
const _DICE_ON := 0
const _DICE_FAST := 1
const _MANUAL := 10
const _LINGER := {2: 2.0, 3: 4.0, 4: 8.0}

var dice_menu: MenuButton


func _dice_menu() -> MenuButton:
	dice_menu = MenuButton.new()
	dice_menu.name = "DiceMenu"
	dice_menu.text = "Dice"
	dice_menu.flat = true
	dice_menu.focus_mode = Control.FOCUS_NONE
	dice_menu.add_theme_font_size_override("font_size", 12)
	dice_menu.tooltip_text = "3D dice settings, a roll by hand"
	var pop := dice_menu.get_popup()
	pop.add_check_item("3D dice", _DICE_ON)
	pop.add_check_item("Fast dice", _DICE_FAST)
	pop.add_separator("They stay")
	for id: int in _LINGER:
		pop.add_radio_check_item("%d seconds" % int(_LINGER[id]), id)
	pop.add_separator()
	pop.add_item("Enter a roll by hand...", _MANUAL)
	pop.about_to_popup.connect(_sync_dice_menu)
	pop.id_pressed.connect(_on_dice_menu)
	return dice_menu


func _sync_dice_menu() -> void:
	var s := DiceTray.settings()
	var pop := dice_menu.get_popup()
	pop.set_item_checked(pop.get_item_index(_DICE_ON), bool(s.enabled))
	pop.set_item_checked(pop.get_item_index(_DICE_FAST), float(s.speed) > 1.0)
	for id: int in _LINGER:
		pop.set_item_checked(pop.get_item_index(id), is_equal_approx(float(s.linger), float(_LINGER[id])))


func _on_dice_menu(id: int) -> void:
	var s := DiceTray.settings()
	match id:
		_DICE_ON:
			DiceTray.set_setting("enabled", not bool(s.enabled))
		_DICE_FAST:
			DiceTray.set_setting("speed", 1.0 if float(s.speed) > 1.0 else 1.6)
		_MANUAL:
			manual_roll()
		_:
			if _LINGER.has(id):
				DiceTray.set_setting("linger", _LINGER[id])
	_sync_dice_menu()


var manual_dialog: ConfirmationDialog

## "I rolled: __": posted in the chat as a roll by hand.
func manual_roll() -> ConfirmationDialog:
	if manual_dialog == null:
		manual_dialog = ConfirmationDialog.new()
		manual_dialog.name = "ManualRoll"
		manual_dialog.title = "A roll by hand"
		var edit := LineEdit.new()
		edit.name = "Value"
		edit.placeholder_text = "I rolled... (e.g. 17, or 1d20+5 = 17)"
		manual_dialog.add_child(edit)
		manual_dialog.register_text_enter(edit)
		manual_dialog.confirmed.connect(func() -> void:
			var t := edit.text.strip_edges()
			if t != "" and table != null:
				table.say("rolled by hand: %s" % t, str(active_ref.call()) if active_ref.is_valid() else "")
			edit.text = "")
		add_child(manual_dialog)
	manual_dialog.popup_centered(Vector2i(360, 100))
	return manual_dialog


func _ready() -> void:
	if table != null and not table.rolls_changed.is_connected(refresh):
		table.rolls_changed.connect(refresh)
		table.accounts_changed.connect(refresh)
	if place_file == "":
		place_file = "user://chat.cfg" if table == null or table.cache_dir == "user://cache/assets" else table.cache_dir.path_join("chat.cfg")
	super()
	refresh()


## Sends the line: a message, or a roll with "/r".
func send() -> void:
	var text := line.text.strip_edges()
	line.text = ""
	line.release_focus()  # the map gets its keys back (WASD, Q / E)
	if text == "" or table == null:
		return
	table.say(text, str(active_ref.call()) if active_ref.is_valid() else "")


## Follows the timeline's cursor: `happened` as from TimelineBar.happened() ({} = now).
func follow_time(happened: Dictionary) -> void:
	until = happened
	var last := -1 if not until.is_empty() else -2
	if table != null and not until.is_empty():
		for i in table.rolls.size():
			if until.has(int(table.rolls[i].get("id", 0))):
				last = i
	if last == _until_last:
		return
	_until_last = last
	refresh()


func refresh() -> void:
	if table == null:
		return
	if table.rolls.is_empty():
		log_text.text = "[color=#%s]Nothing said yet.[/color]" % Markdown.MUTED.to_html(false)
		return
	log_text.clear()
	log_text.scroll_following = until.is_empty()
	var at_par := 0
	var faint := "[color=#%s]" % Color(Markdown.MUTED, 0.6).to_html(true)
	for i in table.rolls.size():
		var r: Dictionary = table.rolls[i]
		if i > 0:
			log_text.append_text("\n\n")
		if i == _until_last:
			at_par = log_text.get_paragraph_count() - 1
		var later := not until.is_empty() and not until.has(int(r.get("id", 0)))
		var text := NetTable.roll_bbcode(r, table.notes.names)
		log_text.append_text(faint + _plain(text) + "[/color]" if later else text)
	if not until.is_empty():
		log_text.scroll_to_paragraph(at_par if _until_last >= 0 else 0)


## A message said after the moment looked at: its words without colours or links.
static func _plain(bb: String) -> String:
	var re := RegEx.create_from_string("\\[/?(color|url|b|i|u|font_size|bgcolor|hint)[^\\]]*\\]")
	return re.sub(bb, "", true)
