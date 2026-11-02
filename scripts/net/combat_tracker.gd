class_name CombatTracker
extends PanelContainer
## The initiative order while a combat runs (TASK-58), at the top of the table for everyone:
## one row per creature or group (its members under it), the current turn marked. The DM
## drags rows to change the order (ties, or their call), rolls for a creature that still
## waits, groups the selected tokens, marks surprise and goes on to the next turn.

var table: NetTable
var _rows: VBoxContainer
var _head: Label
var _buttons: HBoxContainer


func _ready() -> void:
	name = "CombatTracker"
	theme_type_variation = UISkin.V_PAGE
	anchor_left = 0.5
	anchor_right = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = 8
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_head = Label.new()
	_head.name = "Head"
	_head.theme_type_variation = UISkin.V_HEADING
	col.add_child(_head)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)
	_buttons = HBoxContainer.new()
	_buttons.name = "Buttons"
	col.add_child(_buttons)
	_button("Next turn", "The next creature's turn", func() -> void: table.next_turn())
	_button("Group selected", "The selected tokens share one initiative roll and one turn", func() -> void:
		table.group_creatures(table.grid.selection().filter(func(id: String) -> bool: return "/" in id)))
	_button("End combat", "End the combat; it is saved as an encounter", func() -> void: table.end_combat())
	table.table_changed.connect(refresh)
	refresh()


func _button(text: String, tip: String, action: Callable) -> void:
	var b := Button.new()
	b.name = text.replace(" ", "")
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_buttons.add_child(b)


## Builds the rows from the table's combat (hidden when there is none).
func refresh() -> void:
	if _rows == null or table == null:
		return
	var c := table.combat_view()
	visible = table.is_online() and bool(c.get("active", false))
	if not visible:
		return
	var dm := table.is_dm()
	_buttons.visible = dm
	_head.text = "Round %d" % int(c.get("round", 1))
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var order: Array = c.get("order", [])
	for i in order.size():
		_rows.add_child(_row(order[i], i, dm, int(c.get("round", 1))))


func _row(o: Dictionary, index: int, dm: bool, round_now: int) -> Control:
	var box := VBoxContainer.new()
	box.name = "Row_%s" % str(o.entity).validate_node_name()
	box.add_theme_constant_override("separation", 0)
	box.set_meta("entity", o.entity)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	box.add_child(line)
	var mark := Label.new()
	mark.text = "▶" if bool(o.get("current", false)) else "  "
	mark.custom_minimum_size.x = 16
	line.add_child(mark)
	var init := Label.new()
	init.name = "Initiative"
	init.text = str(int(o.initiative)) if bool(o.get("rolled", true)) else "—"
	init.custom_minimum_size.x = 28
	line.add_child(init)
	var who := Label.new()
	who.name = "Name"
	who.text = str(o.get("name", o.entity))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(o.get("current", false)):
		who.theme_type_variation = UISkin.V_HEADING
	line.add_child(who)
	var usage: Dictionary = o.get("usage", {}) if o.get("usage") is Dictionary else {}
	if dm and usage.get("legendary") is Dictionary:  # TASK-63: legendary actions / resistance, a click spends one
		var la: Dictionary = usage.legendary
		_small(line, "LA %d/%d" % [int(la.left), int(la.max)], "Legendary actions left this round (a click spends one; back at the start of its turn)",
			func() -> void: table.mark_action(str(o.entity), "legendary", true, ""))
	if dm and usage.get("legendary_resistance") is Dictionary:
		var lr: Dictionary = usage.legendary_resistance
		_small(line, "LR %d/%d" % [int(lr.left), int(lr.max)], "Legendary Resistance left today (a click spends one: a failed save succeeds)",
			func() -> void: table.mark_action(str(o.entity), "legendary_resistance", true, ""))
	if dm and not (usage.get("spent", []) as Array).is_empty():
		var tag := Label.new()
		tag.name = "Spent"
		tag.text = "spent: " + ", ".join(usage.spent)
		tag.tooltip_text = "Rolls to recharge at the start of its turn"
		tag.theme_type_variation = UISkin.V_MUTED
		line.add_child(tag)
	if bool(o.get("surprised", false)) and round_now <= 1:
		var tag := Label.new()
		tag.text = "surprised"
		tag.theme_type_variation = UISkin.V_MUTED
		line.add_child(tag)
	if dm:
		if not bool(o.get("rolled", true)):
			_small(line, "Roll", "Roll initiative for it (e.g. an absent player)", func() -> void: table.roll_initiative(str(o.entity)))
		if o.has("members"):
			_small(line, "Ungroup", "Each one takes its own turn again", func() -> void: table.ungroup(str(o.entity)))
		elif round_now <= 1:
			_small(line, "Surprise", "Caught unaware (2014: no turn in round 1, 2024: disadvantage on initiative)",
				func() -> void: table.set_surprised(str(o.entity), not bool(o.get("surprised", false))))
		box.set_drag_forwarding(func(_at: Vector2) -> Variant: return {"combat_row": index},
			func(_at: Vector2, data: Variant) -> bool: return data is Dictionary and data.has("combat_row"),
			func(_at: Vector2, data: Variant) -> void: move(int(data.combat_row), index))
		box.mouse_filter = Control.MOUSE_FILTER_STOP
	for m: Variant in o.get("members", []):
		var l := Label.new()
		l.text = "        · " + str((m as Dictionary).get("name", ""))
		l.theme_type_variation = UISkin.V_MUTED
		box.add_child(l)
	return box


func _small(row: Control, text: String, tip: String, action: Callable) -> void:
	var b := Button.new()
	b.name = text.get_slice(" ", 0).validate_node_name()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	row.add_child(b)


## DM: moves the row at `from` to `to` (a drop on another row).
func move(from: int, to: int) -> void:
	var ids: Array = (table.combat_view().get("order", []) as Array).map(func(o: Dictionary) -> String: return str(o.entity))
	if from < 0 or from >= ids.size() or to < 0 or to >= ids.size() or from == to:
		return
	var id: String = ids[from]
	ids.remove_at(from)
	ids.insert(to, id)
	table.set_order(ids)
