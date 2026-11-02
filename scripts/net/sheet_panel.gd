class_name SheetPanel
extends PanelContainer
## A creature's sheet at the table (TASK-10), opened by clicking its token. Our fixed layout:
## HP, AC, speed, the six abilities, saves, skills, senses, then the info page (description).
## Owners and the DM get the whole sheet with HP and AC controls; everything goes through
## NetTable (change_hp / change_field) and becomes an event, the entry stays as it is.
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
	_body.meta_clicked.connect(_on_meta)
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


## Links in the sheet: "roll:<name>" rolls it for this creature.
func _on_meta(meta: Variant) -> void:
	var m := str(meta)
	if m.begins_with(RollTables.ROLL) or m.begins_with(RollTables.ROW):
		RollTables.handle_meta(m)
	elif m.begins_with("roll:") and table != null:
		table.roll(m.substr(5), ref, Input.is_key_pressed(KEY_SHIFT) and table.is_dm())
	elif m.begins_with("attack:") and table != null:  # TASK-54: pick targets, then roll
		table.begin_attack(ref, m.substr(7), m == "attack:multiattack")
	elif m.begins_with("saveact:") and table != null:  # TASK-55: a save-based action
		table.begin_attack(ref, m.substr(8), false, "save")
	elif m == "death" and table != null:  # TASK-57
		table.roll_death_save(ref)
	elif m == "cond:add" and table != null:  # TASK-56: the condition menu
		table.condition_menu_requested.emit(ref)
	elif m.begins_with("cond:off:") and table != null:
		table.set_condition(ref, m.substr(9), false)


## A compendium item, spell or feature dropped on the sheet joins its list (TASK-37):
## inventory (item.gained), spells or features (sheet.changed), through the table.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return ref != "" and bool(sheet.get("_editable", false)) and EntryDrag.is_entry(data) 		and EntryDrag.SHEET_LISTS.has(str(EntryDrag.entry_of(data).get("_kind", "")))


func _drop_data(_at: Vector2, data: Variant) -> void:
	add_entry(EntryDrag.entry_of(data))


## Adds an item / spell / feature to this sheet; false if it can't (or has it already).
## An item is an item.gained event (TASK-51), spells and features change their list.
func add_entry(e: Dictionary) -> bool:
	if str(e.get("_kind", "")) == "items" and table != null and ref != "" and str(e.get("id", "")) != "":
		table.change_item(ref, "items/%s" % e.id, 1)
		return true
	var change := EntryDrag.sheet_change(sheet, e)
	if change.is_empty() or table == null:
		return false
	table.change_field(ref, change[0], change[1])
	return true


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
		var d := Rules.derived(s)  # TASK-53: computed; a stored value wins and gets a marker
		bb += StatBlock._field("Armor Class", _derived(d, "ac", false))
		bb += StatBlock._field("Speed", StatBlock._speed(s))
		bb += StatBlock._field("Proficiency", _derived(d, "proficiency"))
		bb += StatBlock._field("Initiative", "[url=roll:initiative]%s[/url]" % _derived(d, "initiative"))
		if d.has("spell_dc"):
			bb += StatBlock._field("Spellcasting", "DC %s · attack %s · %s" % [_derived(d, "spell_dc", false), _derived(d, "spell_attack"), Rules.casting_ability(s).to_upper()])
		# State from the TASK-17 events.
		bb += _conditions(s)
		if s.get("death_saves") is Dictionary or (int(s.get("hp", 1)) == 0 and str(s.get("_kind", "characters")) == "characters" and s.has("classes")):
			var ds: Dictionary = s.get("death_saves", {}) if s.get("death_saves") is Dictionary else {}
			var done := int(ds.get("successes", 0)) >= 3 or "dead" in (s.get("conditions", []) as Array)
			bb += StatBlock._field("Death Saves", "%d successes, %d failures%s" % [int(ds.get("successes", 0)), int(ds.get("failures", 0)),
				"" if done or int(s.get("hp", 1)) > 0 else " · [url=death]roll[/url]"])
		if s.get("resources_used") is Dictionary and not s.resources_used.is_empty():
			var used := PackedStringArray()
			for r: Variant in s.resources_used:
				used.append("%s %d" % [str(r).replace("_", " ").replace(".", " ").capitalize(), int(s.resources_used[r])])
			bb += StatBlock._field("Used", Markdown.escape(", ".join(used)))
		if s.get("currency") is Dictionary and not s.currency.is_empty():
			var coins := PackedStringArray()
			for coin in ["pp", "gp", "ep", "sp", "cp"]:
				if int(s.currency.get(coin, 0)) != 0:
					coins.append("%d %s" % [int(s.currency[coin]), coin])
			bb += StatBlock._field("Coins", ", ".join(coins))
		bb += StatBlock._rule()
		var stats: Dictionary = s.get("stats", {}) if s.get("stats") is Dictionary else {}
		bb += "[table=6]"
		for a: String in StatBlock.ABILITIES:
			bb += "[cell padding=2,2,2,0][center][b][url=roll:%s check]%s[/url][/b][/center][/cell]" % [a, a.to_upper()]
		for a: String in StatBlock.ABILITIES:
			var score := int(stats.get(a, 10))
			bb += "[cell padding=2,0,2,2][center]%d (%s)[/center][/cell]" % [score, StatBlock._signed(floori((score - 10) / 2.0))]
		bb += "[/table]\n" + StatBlock._rule()
		var saves := PackedStringArray()
		for a: String in StatBlock.ABILITIES:
			saves.append("[url=roll:%s save]%s %s[/url]" % [a, a.to_upper(), _derived(d, "save_" + a)])
		bb += StatBlock._field("Saving Throws", ", ".join(saves))
		var skills := PackedStringArray()
		for sk: String in Dice.SKILLS:  # the ones it is good at (proficient, expertise, stored)
			if Rules._has(s, "skills", sk) or sk in Rules._list(s, "expertise") or bool(d["skill_" + sk].override):
				skills.append("[url=roll:%s]%s %s[/url]" % [sk.replace("_", " "), sk.replace("_", " ").capitalize(), _derived(d, "skill_" + sk)])
		if not skills.is_empty():
			bb += StatBlock._field("Skills", ", ".join(skills))
		bb += StatBlock._field("Rolls", "[url=roll:initiative]Initiative[/url]" + _attacks(s))
		var senses := StatBlock._join(s.get("senses", []))
		senses += ("" if senses == "" else ", ") + "passive Perception %s, Insight %s, Investigation %s" % [_derived(d, "passive_perception", false),
			_derived(d, "passive_insight", false), _derived(d, "passive_investigation", false)]
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


## The conditions, each with its rules text as a tooltip and (if it may change them) a ×
## to take it off, then "+ condition" (TASK-56).
static func _conditions(s: Dictionary) -> String:
	var list: Array = s.get("conditions", []) if s.get("conditions") is Array else []
	var editable := bool(s.get("_editable", false))
	if list.is_empty() and not editable:
		return ""
	var edition := Rules.edition_of(s, {})
	var parts := PackedStringArray()
	for c: Variant in list:
		var id := str(c)
		var lvl := int(s.get("exhaustion", 1))
		var cond := Rules.condition(id, edition, lvl)
		var name := str(cond.get("name", id.capitalize())) + (" %d" % lvl if id == "exhaustion" else "")
		var hint := str(cond.get("text", "")).replace("[", "(").replace("]", ")").replace("\"", "'")
		var color := str(cond.get("color", "#666666")).trim_prefix("#")
		var bit := "[color=#%s]●[/color] [hint=\"%s\"]%s[/hint]" % [color, hint, Markdown.escape(name)]
		if editable:
			bit += " [url=cond:off:%s]×[/url]" % id
		parts.append(bit)
	if editable:
		parts.append("[url=cond:add]+ condition[/url]")
	return StatBlock._field("Conditions", "  ".join(parts))


## A derived number as text ("+5"), with a marker (*) where a stored value overrides it.
static func _derived(d: Dictionary, key: String, signed := true) -> String:
	var v: Dictionary = d.get(key, {"value": 0, "override": false})
	var text := StatBlock._signed(int(v.value)) if signed else str(int(v.value))
	return text + ("[color=#%s]*[/color]" % UISkin.WINE.to_html(false) if bool(v.override) else "")


## "Saving Throws DEX +5, WIS +2" with each one a roll link.
static func _roll_list(label: String, values: Variant, suffix: String) -> String:
	if not values is Dictionary or values.is_empty():
		return ""
	var parts := PackedStringArray()
	for k: String in values:
		var name := k.to_upper() if k in StatBlock.ABILITIES else k.replace("_", " ").capitalize()
		parts.append("[url=roll:%s%s]%s %s[/url]" % [k.replace("_", " "), suffix, name, StatBlock._signed(int(values[k]))])
	return StatBlock._field(label, ", ".join(parts))


## Attack links for the sheet's features that have an attack (needs StatBlock.db or the
## sheet's `_attacks` names from the host).
static func _attacks(s: Dictionary) -> String:
	var out := ""
	if bool(s.get("_multiattack", false)):
		out += ", [url=attack:multiattack]Multiattack[/url]"
	for name: Variant in s.get("_attacks", []):
		out += ", [url=attack:%s]%s[/url]" % [str(name).to_lower(), Markdown.escape(str(name))]
	for name: Variant in s.get("_save_actions", []):
		out += ", [url=saveact:%s]%s[/url]" % [str(name), Markdown.escape(str(name))]
	return out


static func _item(ref: String, qty: int) -> String:
	return ref.get_file().replace("-", " ").capitalize() + (" ×%d" % qty if qty > 1 else "")
