class_name RulesView
extends PanelContainer
## The world's rules page for the DM (TASK-60): the edition, the house rules (TASK-53) and how
## much the table does by itself per category: Off (nothing, the DM does it by hand), Assist
## (the result is posted for the DM to apply) or Auto (applied right away; undo or rewind
## corrects it, Nico's decision 1). Every change is saved into the world at once.

var table: NetTable
var heading: Label
var _rows: VBoxContainer
var _filling := false


func _ready() -> void:
	theme_type_variation = UISkin.V_PAGE
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	refresh()


## Builds the page again from the world's settings.
func refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)  # the new rows take the same names
		c.queue_free()
	_filling = true
	var s := table.rules_settings()
	heading = Label.new()
	heading.theme_type_variation = UISkin.V_HEADING
	heading.text = "Rules"
	_rows.add_child(heading)
	_row("Edition", "edition", "", {"2014": "2014 rules", "2024": "2024 rules"}, str(s.edition),
		"The world's edition; an entry from a book of the other edition keeps its own")
	var house: Dictionary = Rules.core().get("house_rules", {})
	for id: String in house:
		var h: Dictionary = house[id]
		_row(str(h.label), "house_rules", id, h.options, str((s.house_rules as Dictionary).get(id, h.default)), "")
	var sub := Label.new()
	sub.theme_type_variation = UISkin.V_HEADING
	sub.text = "Automation"
	_rows.add_child(sub)
	var note := Label.new()
	note.theme_type_variation = UISkin.V_MUTED
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Off: you do it by hand. Assist: the table posts what it would do, you apply it. Auto: applied right away, undo corrects it."
	_rows.add_child(note)
	for cat: String in Rules.AUTOMATION:
		_row(str(Rules.AUTOMATION[cat].label), "automation", cat, Rules.AUTOMATION_LEVELS, Rules.automation(s, cat), str(Rules.AUTOMATION[cat].tip))
	_filling = false


func _row(label: String, group: String, key: String, options: Dictionary, current: String, tip: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + (key if key != "" else group)
	row.tooltip_text = tip
	_rows.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 190
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	var pick := OptionButton.new()
	pick.name = "Pick"
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.tooltip_text = tip
	for id: String in options:
		pick.add_item(str(options[id]))
		pick.set_item_metadata(pick.item_count - 1, id)
		if id == current:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i: int) -> void: set_value(group, key, str(pick.get_item_metadata(i))))
	row.add_child(pick)


## Changes one setting ("edition", or a house rule / automation category) and saves the world.
func set_value(group: String, key: String, value: String) -> void:
	if _filling:
		return
	var s := table.rules_settings().duplicate(true)
	if key == "":
		s[group] = value
	else:
		if not s.get(group) is Dictionary:
			s[group] = {}
		(s[group] as Dictionary)[key] = value
	table.set_rules_settings(s)
