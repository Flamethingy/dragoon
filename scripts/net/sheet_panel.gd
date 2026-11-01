class_name SheetPanel
extends PanelContainer
## A creature's sheet at the table (TASK-10), opened by clicking its token. Our fixed layout:
## HP, AC, speed, the six abilities, saves, skills, senses, then the info page (description).
## Owners and the DM get the whole sheet with HP and AC controls; everything goes through
## NetTable (change_hp / change_field) and becomes an event, the campaign file stays as it is.
## Others only see the info page.

var table: NetTable
var ref := ""
var sheet := {}

var _title: Label
var _body: RichTextLabel
var _controls: VBoxContainer
var _amount: SpinBox
var _temp: SpinBox
var _ac: SpinBox
var _filling := false


func _init() -> void:
	theme_type_variation = UISkin.V_PAGE
	anchor_bottom = 1.0
	offset_left = 12
	offset_right = 400
	offset_top = 112
	offset_bottom = -12
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = UISkin.V_HEADING
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_sheet)
	head.add_child(close)

	_controls = VBoxContainer.new()
	col.add_child(_controls)
	var hp_row := HBoxContainer.new()
	_controls.add_child(hp_row)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 999
	_amount.value = 1
	_amount.tooltip_text = "How many hit points"
	hp_row.add_child(_amount)
	var damage := Button.new()
	damage.name = "Damage"
	damage.text = "Damage"
	damage.pressed.connect(func() -> void: table.change_hp(ref, -int(_amount.value)))
	hp_row.add_child(damage)
	var heal := Button.new()
	heal.name = "Heal"
	heal.text = "Heal"
	heal.pressed.connect(func() -> void: table.change_hp(ref, int(_amount.value)))
	hp_row.add_child(heal)
	var row := HBoxContainer.new()
	_controls.add_child(row)
	_temp = _number(row, "Temp HP", 0, 999)
	_temp.value_changed.connect(func(v: float) -> void:
		if not _filling:
			table.change_field(ref, "temp_hp", int(v)))
	_ac = _number(row, "AC", 0, 40)
	_ac.value_changed.connect(func(v: float) -> void:
		if not _filling:
			table.change_field(ref, "ac", int(v)))

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.selection_enabled = true
	col.add_child(_body)


func _number(row: HBoxContainer, label: String, lo: int, hi: int) -> SpinBox:
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var box := SpinBox.new()
	box.name = label.replace(" ", "")
	box.min_value = lo
	box.max_value = hi
	row.add_child(box)
	return box


func show_sheet(s: Dictionary) -> void:
	sheet = s
	ref = str(s.get("ref", ""))
	_title.text = str(s.get("name", ref))
	_controls.visible = bool(s.get("_editable", false))
	_filling = true
	_temp.value = int(s.get("temp_hp", 0))
	_ac.value = int(s.get("ac", 0))
	_filling = false
	_body.text = to_bbcode(s)
	show()


func close_sheet() -> void:
	if ref != "":
		table.close_sheet(ref)
	ref = ""
	hide()


## The fixed sheet layout as BBCode.
static func to_bbcode(s: Dictionary) -> String:
	var subtitle := str(s.get("_class", ""))
	if subtitle == "":
		subtitle = " ".join(PackedStringArray([str(s.get("size", "")), str(s.get("type", ""))])).strip_edges()
	if str(s.get("_owner", "")) != "":
		subtitle += (" · " if subtitle != "" else "") + "played by " + str(s._owner)
	var bb := StatBlock._title(s, subtitle) + StatBlock._rule()
	if bool(s.get("_full", false)):
		var hp := "%d / %d" % [int(s.get("hp", 0)), int(s.get("_hp_max", s.get("hp", 0)))]
		if int(s.get("temp_hp", 0)) > 0:
			hp += " (+%d temp)" % int(s.temp_hp)
		bb += StatBlock._field("Hit Points", hp)
		bb += StatBlock._field("Armor Class", StatBlock._num(s.get("ac")))
		bb += StatBlock._field("Speed", StatBlock._speed(s))
		if s.get("proficiency_bonus") != null:
			bb += StatBlock._field("Proficiency", StatBlock._signed(int(s.proficiency_bonus)))
		bb += StatBlock._rule()
		var stats: Dictionary = s.get("stats", {}) if s.get("stats") is Dictionary else {}
		bb += "[table=6]"
		for a: String in StatBlock.ABILITIES:
			bb += "[cell padding=2,2,2,0][center][b]%s[/b][/center][/cell]" % a.to_upper()
		for a: String in StatBlock.ABILITIES:
			var score := int(stats.get(a, 10))
			bb += "[cell padding=2,0,2,2][center]%d (%s)[/center][/cell]" % [score, StatBlock._signed(floori((score - 10) / 2.0))]
		bb += "[/table]\n" + StatBlock._rule()
		bb += StatBlock._bonuses("Saving Throws", s.get("saves"))
		bb += StatBlock._bonuses("Skills", s.get("skills"))
		var senses := StatBlock._join(s.get("senses", []))
		if s.get("passive_perception") != null:
			senses += ("" if senses == "" else ", ") + "passive Perception %s" % StatBlock._num(s.passive_perception)
		if senses != "":
			bb += StatBlock._field("Senses", Markdown.inline(senses))
		if s.get("languages") is Array and not s.languages.is_empty():
			bb += StatBlock._field("Languages", Markdown.inline(StatBlock._join(s.languages)))
		var items := PackedStringArray()
		var inv: Variant = s.get("inventory")
		if inv is Array:  # the file: [{item, qty}]
			for it: Variant in inv:
				if it is Dictionary:
					items.append(_item(str(it.get("item", "?")), int(it.get("qty", 1))))
		elif inv is Dictionary:  # after item events (Replay): {item: qty}
			for item: Variant in inv:
				items.append(_item(str(item), int(inv[item])))
		if not items.is_empty():
			bb += StatBlock._field("Inventory", Markdown.escape(", ".join(items)))
	elif str(s.get("race", "")) != "":
		bb += StatBlock._field("Race", Markdown.escape(str(s.race).get_file().replace("-", " ").capitalize()))
	if str(s.get("description", "")).strip_edges() != "":
		bb += StatBlock._heading("About") + Markdown.to_bbcode(str(s.description))
	if not bool(s.get("_full", false)):
		bb += "\n\n[color=#%s][i]Only its player and the DM see the stats.[/i][/color]" % Markdown.MUTED.to_html(false)
	return bb


static func _item(ref: String, qty: int) -> String:
	return ref.get_file().replace("-", " ").capitalize() + (" ×%d" % qty if qty > 1 else "")
