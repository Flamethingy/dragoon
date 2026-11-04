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
	var close := DockPanel.WindowButton.new()  # TASK-100: the X of the window bar (TASK-91)
	close.kind = "close"
	close.name = "Close"
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
	elif m.begins_with("gear:") and table != null:  # TASK-70: gear:<flag>:<on|off>:<item>
		var p := m.split(":", true, 3)
		if p.size() == 4:
			table.flag_item(ref, p[3], p[1], p[2] == "on")
	elif m.begins_with("res:") and table != null:  # TASK-64: a use spent / back
		table.use_resource(ref, m.substr(8), 1 if m.begins_with("res:use:") else -1)
	elif m == "form:end" and table != null:  # TASK-74
		table.end_form(ref)
	elif (m == "form:wild_shape" or m == "form:polymorph" or m == "summon") and table != null:
		creature_picker(m.trim_prefix("form:"))
	elif m == "dismiss" and table != null:
		table.dismiss(ref)
	elif m == "levelup" and table != null:  # TASK-71
		level_up_dialog()
	elif m == "rest:short" and table != null:
		short_rest_dialog()
	elif m == "rest:long" and table != null and table.is_dm():
		table.long_rest()
	elif m == "cond:add" and table != null:  # TASK-56: the condition menu
		table.condition_menu_requested.emit(ref)
	elif m.begins_with("cond:off:") and table != null:
		table.set_condition(ref, m.substr(9), false)


## A compendium item, spell or feature dropped on the sheet joins its list (TASK-37):
## inventory (item.gained), spells or features (sheet.changed), through the table.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return ref != "" and bool(sheet.get("_editable", false)) and EntryDrag.is_entry(data) \
		and EntryDrag.SHEET_LISTS.has(str(EntryDrag.entry_of(data).get("_kind", "")))


func _drop_data(_at: Vector2, data: Variant) -> void:
	add_entry(EntryDrag.entry_of(data))


## Adds an item / spell / feature to this sheet; false if it can't (or has it already).
## An item is an item.gained event (TASK-51), spells and features change their list. The
## table does it (NetTable.add_entry_to, TASK-94: the same as a drop on the token or the HUD).
func add_entry(e: Dictionary) -> bool:
	if table == null or ref == "" or not EntryDrag.SHEET_LISTS.has(str(e.get("_kind", ""))):
		return false
	if str(e.get("_kind", "")) != "items" and EntryDrag.sheet_change(sheet, e).is_empty():
		table.add_entry_to(ref, e)  # says it's already there
		return false
	table.add_entry_to(ref, e)
	return true


var rest_dialog: ConfirmationDialog
var level_dialog: ConfirmationDialog
var picker: ConfirmationDialog

## The short rest (TASK-64): how many of each hit die to spend.
func short_rest_dialog() -> ConfirmationDialog:
	if rest_dialog != null:
		rest_dialog.queue_free()
	rest_dialog = ConfirmationDialog.new()
	rest_dialog.name = "ShortRest"
	rest_dialog.title = "Short rest: %s" % str(sheet.get("name", ""))
	var box := VBoxContainer.new()
	rest_dialog.add_child(box)
	var spins := {}
	for r: Dictionary in sheet.get("_resources", []):
		if str(r.id).begins_with("hit_dice."):
			var row := HBoxContainer.new()
			box.add_child(row)
			var l := Label.new()
			l.text = "%s, %d left" % [r.name, int(r.max) - int(r.used)]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var sp := SpinBox.new()
			sp.name = "Dice_" + str(r.id).get_slice(".", 1)
			sp.max_value = int(r.max) - int(r.used)
			row.add_child(sp)
			spins[int(str(r.id).get_slice(".d", 1))] = sp
	if spins.is_empty():
		var l := Label.new()
		l.text = "No hit dice (short rest uses still come back)."
		box.add_child(l)
	rest_dialog.confirmed.connect(func() -> void:
		var dice := {}
		for sides: int in spins:
			if int(spins[sides].value) > 0:
				dice[sides] = int(spins[sides].value)
		table.short_rest(ref, dice))
	add_child(rest_dialog)
	rest_dialog.popup_centered(Vector2i(320, 120))
	return rest_dialog


## The level-up dialog (TASK-71): the class (or a new one), HP (average or roll), and what the
## level brings: features, slots, an ability score increase or feat, the subclass, spells.
func level_up_dialog(cls := "") -> ConfirmationDialog:
	if level_dialog != null:
		level_dialog.queue_free()
	level_dialog = ConfirmationDialog.new()
	level_dialog.name = "LevelUp"
	level_dialog.title = "Level up: %s" % str(sheet.get("name", ""))
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	level_dialog.add_child(box)
	var classes := OptionButton.new()
	classes.name = "Class"
	var ids := []
	for c: Variant in sheet.get("classes", []):
		if c is Dictionary:
			ids.append(str(c.get("class", "")))
			classes.add_item("%s %d → %d" % [HudWidgets._name_of(c.get("class", "")), int(c.get("level", 0)), int(c.get("level", 0)) + 1])
	for e: Variant in table.catalog_list("classes"):
		var r := "classes/" + str((e as Dictionary).get("id", ""))
		if e is Dictionary and not ids.any(func(i: String) -> bool: return Rules._class_id(i) == Rules._class_id(r)) and not EntryStore.is_draft(e):
			ids.append(r)
			classes.add_item("New: %s (multiclass)" % str(e.get("name", r)))
	box.add_child(classes)
	var hp := OptionButton.new()
	hp.name = "Hp"
	box.add_child(hp)
	var info := RichTextLabel.new()
	info.name = "Plan"
	info.bbcode_enabled = true
	info.fit_content = true
	box.add_child(info)
	var sub := OptionButton.new()
	sub.name = "Subclass"
	box.add_child(sub)
	var asi_row := HBoxContainer.new()
	asi_row.name = "Asi"
	box.add_child(asi_row)
	var asi_a := OptionButton.new()
	asi_a.name = "AsiA"
	var asi_b := OptionButton.new()
	asi_b.name = "AsiB"
	for o: OptionButton in [asi_a, asi_b]:
		o.add_item("—")
		for ab: String in Rules.ABILITIES:
			o.add_item("+1 " + ab.to_upper())
		asi_row.add_child(o)
	var feat := LineEdit.new()
	feat.name = "Feat"
	feat.placeholder_text = "or a feat instead (feats/...)"
	feat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asi_row.add_child(feat)
	var state := {"plan": {}}  # lambdas capture by value: the plan lives in here
	var refresh := func() -> void:
		var i := classes.selected
		var plan: Dictionary = table.level_up_plan(ref, str(ids[i]) if i >= 0 and i < ids.size() else "")
		state.plan = plan
		hp.clear()
		if plan.is_empty():
			return
		hp.add_item("HP: average %d" % int(plan.hp_average))
		hp.add_item("HP: roll 1d%d %+d" % [int(plan.hit_die), int(plan.con)])
		var lines := PackedStringArray()
		if not (plan.features as Array).is_empty():
			lines.append("[b]New:[/b] " + Markdown.escape(", ".join(PackedStringArray(plan.features))))
		if plan.slots_after != plan.slots_before:
			lines.append("[b]Spell slots:[/b] %s" % ", ".join(PackedStringArray((plan.slots_after as Array).map(func(n: Variant) -> String: return str(n)))))
		if bool(plan.caster):
			lines.append("New spells: drop them on the sheet, or prepare them after a long rest.")
		if not bool(plan.ready):
			lines.append("[color=#%s]Not enough XP / no milestone yet (the DM is told).[/color]" % UISkin.ORANGE.to_html(false))
		info.text = "\n".join(lines) if not lines.is_empty() else "Nothing new besides the hit points."
		sub.clear()
		sub.visible = bool(plan.subclass) and not (plan.subclasses as Array).is_empty()
		sub.add_item("Subclass: choose later")  # never picked for the player
		sub.set_item_metadata(0, "")
		for s: Dictionary in plan.subclasses:
			sub.add_item(str(s.name))
			sub.set_item_metadata(sub.item_count - 1, "subclasses/" + str(s.id))
		asi_row.visible = bool(plan.asi)
	classes.item_selected.connect(func(_i: int) -> void: refresh.call())
	var start := ids.find(cls)
	classes.select(start if start >= 0 else 0)
	refresh.call()
	level_dialog.confirmed.connect(func() -> void:
		var plan: Dictionary = state.plan
		if plan.is_empty():
			return
		var choices := {"class": str(plan.class), "hp": "roll" if hp.selected == 1 else "average"}
		if sub.visible and sub.selected > 0:
			choices["subclass"] = str(sub.get_item_metadata(sub.selected))
		if asi_row.visible:
			if feat.text.strip_edges() != "":
				choices["feat"] = feat.text.strip_edges()
			else:
				var asi := {}
				for o: OptionButton in [asi_a, asi_b]:
					if o.selected > 0:
						var ab: String = Rules.ABILITIES[o.selected - 1]
						asi[ab] = int(asi.get(ab, 0)) + 1
				if not asi.is_empty():
					choices["asi"] = asi
		table.level_up(ref, choices))
	add_child(level_dialog)
	level_dialog.popup_centered(Vector2i(420, 260))
	return level_dialog


## Picks a creature (TASK-74): "wild_shape" (beasts up to the Wild Shape CR), "polymorph"
## (beasts up to the target's level or CR) or "summon" (any creature), filtered by name.
func creature_picker(mode: String) -> ConfirmationDialog:
	if picker != null:
		picker.queue_free()
	picker = ConfirmationDialog.new()
	picker.name = "CreaturePicker"
	picker.title = {"wild_shape": "Wild Shape", "polymorph": "Polymorph", "summon": "Summon"}.get(mode, mode)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 300)
	picker.add_child(box)
	var filter := LineEdit.new()
	filter.name = "Filter"
	filter.placeholder_text = "Name..."
	box.add_child(filter)
	var list := ItemList.new()
	list.name = "Creatures"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var limit := Rules.wild_shape_cr(sheet) if mode == "wild_shape" else (float(maxi(Rules.level(sheet), 0)) if mode == "polymorph" else 99.0)
	if mode == "polymorph" and limit <= 0:
		limit = Rules.cr_of(sheet)
	var all := table.catalog_list("creatures").filter(func(e: Variant) -> bool:
		return e is Dictionary and not EntryStore.is_draft(e) and str((e as Dictionary).get("copy_of", "")) == "" \
			and (mode == "summon" or "beast" in str(e.get("type", "")).to_lower()) and Rules.cr_of(e) <= limit + 0.001)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name))
	var fill := func(text: String) -> void:
		list.clear()
		for e: Dictionary in all:
			if text == "" or text.to_lower() in str(e.name).to_lower():
				list.add_item("%s (CR %s)" % [str(e.name), Rules.cr_text(Rules.cr_of(e))])
				list.set_item_metadata(list.item_count - 1, "creatures/" + str(e.id))
				if list.item_count >= 200:
					break
	filter.text_changed.connect(func(t: String) -> void: fill.call(t))
	fill.call("")
	picker.confirmed.connect(func() -> void:
		var sel := list.get_selected_items()
		if sel.is_empty():
			return
		var creature := str(list.get_item_metadata(sel[0]))
		if mode == "summon":
			table.summon(ref, creature)
		else:
			table.assume_form(ref, creature, mode))
	add_child(picker)
	picker.popup_centered(Vector2i(380, 380))
	return picker


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
		bb += _resources(s)
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
		if s.get("_gear") is Array:  # TASK-70: with what is equipped and attuned
			inv = null
			bb += _gear(s)
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


## Uses, hit dice and charges as pips (TASK-64): a click on the name spends one, + gets one
## back; then the rests.
static func _resources(s: Dictionary) -> String:
	var res: Array = s.get("_resources", [])
	var parts := PackedStringArray()
	for r: Dictionary in res:
		var left := int(r.max) - int(r.used)
		var pips := "●".repeat(left) + "○".repeat(int(r.used)) if int(r.max) <= 10 else "%d/%d" % [left, int(r.max)]
		parts.append("[url=res:use:%s]%s[/url] %s [url=res:back:%s]+[/url]" % [r.id, Markdown.escape(str(r.name)), pips, r.id])
	var bb := ""
	if not parts.is_empty():
		bb += StatBlock._field("Uses", " · ".join(parts))
	if str(s.get("_kind", "")) == "characters":
		bb += StatBlock._field("Rest", "[url=rest:short]Short rest[/url] · [url=rest:long]Long rest (party, DM)[/url]")
	var shapes := PackedStringArray()  # TASK-74
	if s.get("_form") is Dictionary:
		var f: Dictionary = s._form
		shapes.append("%s%s · [url=form:end]Back to own shape[/url]" % [Markdown.escape(str(f.name)), " (own HP %d/%d)" % [int(f.own.hp), int(f.own.max)] if f.has("hp") else ""])
	elif str(s.get("_kind", "")) == "characters":
		if Rules.wild_shape_cr(s) > 0:
			shapes.append("[url=form:wild_shape]Wild Shape...[/url]")
		shapes.append("[url=form:polymorph]Polymorph...[/url]")
		shapes.append("[url=summon]Summon...[/url]")
	if str(s.get("summoned_by", "")) != "":
		shapes.append("summoned by %s · [url=dismiss]Dismiss[/url]" % Markdown.escape(HudWidgets._name_of(s.summoned_by)))
	if not shapes.is_empty():
		bb += StatBlock._field("Shape", " · ".join(shapes))
	var lv: Dictionary = s.get("_level", {})
	if not lv.is_empty():  # TASK-71
		var xp := "XP %d / %d · " % [int(lv.xp), int(lv.next)] if str(lv.mode) == "xp" else ""
		var link := "[url=levelup]Level up[/url]" + (" [color=#%s](ready)[/color]" % UISkin.ORANGE.to_html(false) if bool(lv.ready) else "")
		bb += StatBlock._field("Level %d" % int(lv.level), xp + link)
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
		if id == "concentrating" and s.get("concentration") is Dictionary:  # TASK-59: on what
			name += " (%s)" % str(s.concentration.get("name", ""))
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


## The inventory (TASK-70): weapons, armor and magic items with equip / attune links (on an
## editable sheet), the attunement count (orange past 3).
static func _gear(s: Dictionary) -> String:
	var editable := bool(s.get("_editable", false)) or bool(s.get("_full", false))
	var parts := PackedStringArray()
	for g: Dictionary in s._gear:
		var label := Markdown.escape(str(g.get("name", _item(str(g.item), 1)))) + (" ×%d" % int(g.qty) if int(g.get("qty", 1)) > 1 else "")
		var wearable := not (g.get("weapon", {}) as Dictionary).is_empty() or not (g.get("armor", {}) as Dictionary).is_empty() or int(g.get("ac_bonus", 0)) > 0
		var tags := PackedStringArray()
		if wearable:
			tags.append(("[url=gear:equipped:off:%s]equipped[/url]" if bool(g.get("equipped", false)) else "[url=gear:equipped:on:%s]equip[/url]") % g.item if editable else ("equipped" if bool(g.get("equipped", false)) else ""))
		if bool(g.get("attunement", false)):
			tags.append(("[url=gear:attuned:off:%s]attuned[/url]" if bool(g.get("attuned", false)) else "[url=gear:attuned:on:%s]attune[/url]") % g.item if editable else ("attuned" if bool(g.get("attuned", false)) else "not attuned"))
		var shown := Array(tags).filter(func(t: String) -> bool: return t != "")
		parts.append(label + (" (%s)" % ", ".join(PackedStringArray(shown)) if not shown.is_empty() else ""))
	var bb := StatBlock._field("Inventory", ", ".join(parts)) if not parts.is_empty() else ""
	var att: Dictionary = s.get("_attunement", {})
	if int(att.get("count", 0)) > 0:
		var over := int(att.count) > int(att.get("max", 3))
		bb += StatBlock._field("Attunement", ("[color=#%s]%d / %d: too many[/color]" % [UISkin.ORANGE.to_html(false), int(att.count), int(att.max)]) if over else "%d / %d" % [int(att.count), int(att.get("max", 3))])
	return bb


static func _item(ref: String, qty: int) -> String:
	return ref.get_file().replace("-", " ").capitalize() + (" ×%d" % qty if qty > 1 else "")
