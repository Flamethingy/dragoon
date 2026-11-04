class_name OnUseFlow
extends VBoxContainer
## The "On Use" editor (TASK-108, Nico 2026-11-04): the `effects` as a simple flow of coloured
## nodes, top to bottom, connected by short lines. Target blue, roll purple, damage red, heal
## green, condition orange, modifier gold, uses grey; duration and scaling are small grey tags.
## Branches only where a roll has two outcomes (failure / success, hit), side by side. A click
## on a node opens a small form under it; "+" adds (roll, damage, heal, condition, modifier) to
## a branch or after a step, × removes. It reads and writes the `effects` list (OnUse,
## package-format.md); `changed` carries the new list.

signal changed(effects: Array)

const ADD := ["Roll", "Damage", "Heal", "Condition", "Modifier"]
const STEP_PRESETS := {
	"Attack roll": {"roll": "attack", "to_hit": "spell", "range": "ranged", "damage": [{"dice": "1d10", "type": "fire"}]},
	"Save": {"roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}]}, "on_success": "half"},
	"Check": {"roll": "check", "skill": "athletics", "ability": "str", "dc": 15, "by": "self", "on_success": {"note": "it works"}},
	"Heal": {"heal": "2d4+2"},
	"Damage (no roll)": {"damage": [{"dice": "1d4+1", "type": "force"}]},
	"Condition": {"apply": "condition", "condition": "frightened", "duration": {"rounds": 10}},
	"Modifier": {"modifier": {"target": "ac", "op": "add", "value": 2}, "duration": {"rounds": 10}},
	"Uses": {"resource": {"id": "uses", "max": 1, "reset": "long"}},
}
const CONDITIONS := ["blinded", "charmed", "deafened", "frightened", "grappled", "incapacitated", "invisible",
	"paralyzed", "petrified", "poisoned", "prone", "restrained", "stunned", "unconscious", "exhaustion"]
const DAMAGE_TYPES := ["acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic", "piercing",
	"poison", "psychic", "radiant", "slashing", "thunder"]
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

var effects: Array = []
var entry: Dictionary = {}  ## for the targets the effects don't name (range, kind)
var _open := ""  ## the node whose form is open (kept over a rebuild)
var _count := 0


func setup(list: Array, e := {}) -> void:
	effects = list.duplicate(true)
	entry = e
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_count = 0
	add_theme_constant_override("separation", 0)
	if effects.is_empty():
		var none := Label.new()
		none.text = "No automation yet: add a step, or fill it from the text."
		none.theme_type_variation = UISkin.V_MUTED
		add_child(none)
	for i in effects.size():
		if i > 0:
			add_child(_gap(14))
		_step(effects[i], self, effects, i)
	add_child(_gap(8))
	var add := MenuButton.new()
	add.name = "AddStep"
	add.text = "+ Add a step"
	add.flat = false
	add.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var names: Array = STEP_PRESETS.keys()
	for n in names.size():
		add.get_popup().add_item(str(names[n]), n)
	add.get_popup().id_pressed.connect(func(n: int) -> void:
		effects.append((STEP_PRESETS[names[n]] as Dictionary).duplicate(true))
		_changed(true))
	add_child(add)


func _changed(rebuild_now := false) -> void:
	changed.emit(effects)
	if rebuild_now:
		rebuild.call_deferred()


# --- Steps -------------------------------------------------------------------------------------

## One effect into `into`: target, roll, results (branches where needed), its follow-ups.
func _step(fx: Dictionary, into: Container, owner_list: Array, index: int) -> void:
	var remove_step := func() -> void:
		owner_list.remove_at(index)
		_changed(true)
	var state := {"first": true}  # (a lambda can't change a local)
	var link := func() -> void:
		if not state.first:
			into.add_child(_line())
		state.first = false
	if not fx.has("resource"):
		var t := OnUse.target_of(fx, entry)
		if not t.is_empty() or fx.has("target"):
			link.call()
			into.add_child(_node("target", func() -> String: return _target_line(fx), _target_form.bind(fx), remove_step, [], "Remove this step"))
	var roll := str(fx.get("roll", ""))
	if roll in ["attack", "save", "check"] or fx.has("heal"):
		link.call()
		into.add_child(_node("roll", func() -> String: return _roll_line(fx), _roll_form.bind(fx), remove_step, _tags(fx), "Remove this step"))
	match roll:
		"attack":
			_branches(into, fx, [["hit", "On a hit", fx]])
		"save":
			if not fx.get("on_fail") is Dictionary:
				fx["on_fail"] = {}
			_branches(into, fx, [["fail", "On a failure", fx.on_fail], ["success", "On a success", fx]])
		"check":
			for k: String in ["on_success", "on_fail"]:
				if not fx.get(k) is Dictionary:
					fx[k] = {}
			_branches(into, fx, [["success", "On a success", fx.on_success], ["fail", "On a failure", fx.on_fail]])
		_:
			if fx.has("heal"):
				into.add_child(_line())
				into.add_child(_node("heal", func() -> String: return "regains that many HP", Callable(), Callable(), []))
			elif fx.get("apply", "") == "condition" or fx.has("condition"):
				link.call()
				into.add_child(_node("condition", func() -> String: return str(fx.get("condition", "?")).capitalize(), _condition_form.bind(fx, "condition"), remove_step, _tags(fx), "Remove this step"))
			elif fx.get("modifier") is Dictionary:
				link.call()
				into.add_child(_node("modifier", func() -> String: return OnUse.modifier_text(fx.modifier), _modifier_form.bind(fx.modifier), remove_step, _tags(fx), "Remove this step"))
			elif fx.get("resource") is Dictionary:
				link.call()
				into.add_child(_node("time", func() -> String: return "%s use(s) · back after a %s rest" % [str(fx.resource.get("max", 1)), str(fx.resource.get("reset", "long"))],
					_resource_form.bind(fx.resource), remove_step, [], "Remove this step"))
			elif fx.get("damage") is Array:
				for d: Dictionary in fx.damage:
					link.call()
					into.add_child(_damage_node(d, fx.damage))
			for t: Variant in _then(fx, "always"):
				into.add_child(_line())
				_step(t, into, fx.then, (fx.then as Array).find(t))
			into.add_child(_line(6))
			into.add_child(_plus(func(what: String) -> void: _add_after(fx, what)))


## Branches side by side under a roll: [[when, label, results dict], ...]. A save's success is
## its on_success ("half" / "none") on `fx`.
func _branches(into: Container, fx: Dictionary, list: Array) -> void:
	into.add_child(_line())
	var row := HBoxContainer.new()
	row.name = "Branches"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	into.add_child(row)
	for b: Array in list:
		var col := VBoxContainer.new()
		col.name = "Branch_" + str(b[0])
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		var head := Label.new()
		head.text = str(b[1])
		head.theme_type_variation = UISkin.V_MUTED
		head.add_theme_font_size_override("font_size", 12)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var r: Dictionary = b[2]
		if str(fx.get("roll", "")) == "save" and str(b[0]) == "success":
			col.add_child(_node("damage" if str(fx.get("on_success", "none")) == "half" else "time",
				func() -> String: return "half damage" if str(fx.get("on_success", "none")) == "half" else "nothing",
				func(form: VBoxContainer) -> void: _option(form, "On a success", ["half", "none"], str(fx.get("on_success", "none")), func(v: String) -> void:
					fx["on_success"] = v
					_changed(true)), Callable(), []))
			continue
		_results(col, r, fx, str(b[0]))


## A branch's results: damage, healing, conditions, a modifier, follow-ups; "+" at its end.
func _results(col: VBoxContainer, r: Dictionary, fx: Dictionary, when: String) -> void:
	var any := false
	if r.get("damage") is Array:
		for d: Dictionary in r.damage:
			if any:
				col.add_child(_line())
			col.add_child(_damage_node(d, r.damage))
			any = true
	if r.has("heal"):
		if any:
			col.add_child(_line())
		col.add_child(_node("heal", func() -> String: return OnUse._formula(str(r.heal)) + " healing",
			func(form: VBoxContainer) -> void: _text(form, "Healing", str(r.heal), func(v: String) -> void: r["heal"] = v),
			func() -> void:
				r.erase("heal")
				_changed(true), []))
		any = true
	if r.get("conditions") is Array:
		var conds: Array = r.conditions
		for i in conds.size():
			if any:
				col.add_child(_line())
			col.add_child(_node("condition", func() -> String: return str(conds[i]).capitalize(),
				func(form: VBoxContainer) -> void: _option(form, "Condition", CONDITIONS, str(conds[i]), func(v: String) -> void:
					conds[i] = v
					_changed(true)),
				func() -> void:
					conds.remove_at(i)
					_changed(true), []))
			any = true
	if r.get("modifier") is Dictionary:
		if any:
			col.add_child(_line())
		col.add_child(_node("modifier", func() -> String: return OnUse.modifier_text(r.modifier), _modifier_form.bind(r.modifier),
			func() -> void:
				r.erase("modifier")
				_changed(true), []))
		any = true
	if str(r.get("note", "")) != "":
		if any:
			col.add_child(_line())
		col.add_child(_node("time", func() -> String: return str(r.note),
			func(form: VBoxContainer) -> void: _text(form, "What happens", str(r.note), func(v: String) -> void: r["note"] = v),
			func() -> void:
				r.erase("note")
				_changed(true), []))
		any = true
	for t: Variant in _then(fx, when):
		col.add_child(_line())
		_step(t, col, fx.then, (fx.then as Array).find(t))
	col.add_child(_line(6))
	col.add_child(_plus(func(what: String) -> void: _add_to(r, fx, when, what)))


func _then(fx: Dictionary, when: String) -> Array:
	var out := []
	for t: Variant in fx.get("then", []):
		if t is Dictionary and str(t.get("when", "always")) == when:
			out.append(t)
	return out


## "+" in a branch: damage / healing / a condition / a modifier go into its results, a roll
## becomes a follow-up step (`then` with `when`).
func _add_to(r: Dictionary, fx: Dictionary, when: String, what: String) -> void:
	match what:
		"Damage":
			if not r.get("damage") is Array:
				r["damage"] = []
			(r.damage as Array).append({"dice": "1d6", "type": "fire"})
		"Heal":
			r["heal"] = "1d8"
		"Condition":
			if not r.get("conditions") is Array:
				r["conditions"] = []
			(r.conditions as Array).append("prone")
		"Modifier":
			r["modifier"] = {"target": "ac", "op": "add", "value": -2}
		"Roll":
			_add_then(fx, when, {"roll": "save", "ability": "con", "dc": "spell", "on_fail": {"conditions": ["poisoned"]}, "on_success": "none"})
			return
	_changed(true)


## "+" after a step without branches: a follow-up step.
func _add_after(fx: Dictionary, what: String) -> void:
	var step: Dictionary = {"Roll": STEP_PRESETS["Save"], "Damage": STEP_PRESETS["Damage (no roll)"], "Heal": STEP_PRESETS["Heal"],
		"Condition": STEP_PRESETS["Condition"], "Modifier": STEP_PRESETS["Modifier"]}[what]
	_add_then(fx, "always", step.duplicate(true))


func _add_then(fx: Dictionary, when: String, step: Dictionary) -> void:
	step["when"] = when
	if not fx.get("then") is Array:
		fx["then"] = []
	(fx.then as Array).append(step)
	_changed(true)


# --- Node lines ----------------------------------------------------------------------------------

func _target_line(fx: Dictionary) -> String:
	var t := OnUse.target_of(fx, entry)
	var bits := PackedStringArray()
	match str(t.get("kind", "creature")):
		"self":
			return "Yourself"
		"area":
			bits.append("All creatures")
			bits.append(OnUse.area_text(fx.get("area", {}) if fx.get("area") is Dictionary else {}))
		"creatures":
			bits.append("Up to %d creatures" % int(t.get("count", 1)) if int(t.get("count", 0)) > 0 else "Any number of creatures")
		_:
			bits.append("You or a creature" if bool(t.get("self", false)) else "A creature")
	if t.get("range_m") != null:
		bits.append("touch" if float(t.range_m) <= 0 else StatBlock._metres(t.range_m))
	return " · ".join(bits)


func _roll_line(fx: Dictionary) -> String:
	match str(fx.get("roll", "")):
		"attack":
			var hit: Variant = fx.get("to_hit", "spell")
			return ("Spell attack" if str(hit) == "spell" else "Attack " + OnUse._signed(int(hit))) + " · " + str(fx.get("range", "ranged"))
		"save":
			return "%s save · %s" % [OnUse._ability(fx.get("ability", "dex")), "spell DC" if str(fx.get("dc", "spell")) == "spell" else "DC %s" % str(fx.dc)]
		"check":
			return "%s · %s · %s" % [OnUse.check_name(fx), "spell DC" if str(fx.get("dc", 10)) == "spell" else "DC %s" % str(fx.get("dc", 10)),
				"you roll" if str(fx.get("by", "self")) == "self" else "the target rolls"]
	return OnUse._formula(str(fx.get("heal", "")))


func _tags(fx: Dictionary) -> Array:
	var out := []
	if fx.get("duration") is Dictionary and not (fx.duration as Dictionary).is_empty():
		out.append(OnUse.duration_text(fx.duration))
	if bool(fx.get("concentration", false)):
		out.append("concentration")
	if fx.get("scaling") is Dictionary and not (fx.scaling as Dictionary).is_empty():
		out.append(OnUse.scaling_text(fx.scaling))
	return out


func _damage_node(d: Dictionary, list: Array) -> Control:
	return _node("damage", func() -> String: return "%s %s" % [OnUse._formula(str(d.get("dice", "?"))), str(d.get("type", ""))],
		func(form: VBoxContainer) -> void:
			_text(form, "Dice", str(d.get("dice", "")), func(v: String) -> void: d["dice"] = v.replace(" ", ""))
			_option(form, "Type", DAMAGE_TYPES, str(d.get("type", "fire")), func(v: String) -> void:
				d["type"] = v
				_changed(true)),
		func() -> void:
			list.erase(d)
			_changed(true), [])


# --- Forms ---------------------------------------------------------------------------------------

func _target_form(form: VBoxContainer, fx: Dictionary) -> void:
	var t: Dictionary = OnUse.target_of(fx, entry).duplicate()
	var keep := func() -> void:
		fx["target"] = t
		_changed()
	_option(form, "Who", ["self", "creature", "creatures", "area"], str(t.get("kind", "creature")), func(v: String) -> void:
		t["kind"] = v
		if v == "area" and not fx.get("area") is Dictionary:
			fx["area"] = {"shape": "sphere", "size_m": 6}
		fx["target"] = t
		_changed(true))
	if str(t.get("kind", "")) == "creatures":
		_number(form, "How many (0 = any)", float(t.get("count", 2)), func(v: float) -> void:
			t["count"] = int(v)
			keep.call())
	if str(t.get("kind", "")) == "creature":
		var you := CheckBox.new()
		you.text = "Or yourself"
		you.button_pressed = bool(t.get("self", false))
		you.toggled.connect(func(on: bool) -> void:
			t["self"] = on
			keep.call())
		form.add_child(you)
	if str(t.get("kind", "")) == "area" and fx.get("area") is Dictionary:
		var a: Dictionary = fx.area
		_option(form, "Shape", Effects.SHAPES, str(a.get("shape", "sphere")), func(v: String) -> void:
			a["shape"] = v
			_changed())
		_number(form, "Size (m)", float(a.get("size_m", 6)), func(v: float) -> void:
			a["size_m"] = v
			_changed())
	if str(t.get("kind", "")) != "self":
		_number(form, "Range in m (0 = touch)", float(t.get("range_m", 0)) if t.get("range_m") != null else 0.0, func(v: float) -> void:
			t["range_m"] = v
			keep.call())


func _roll_form(form: VBoxContainer, fx: Dictionary) -> void:
	match str(fx.get("roll", "")):
		"attack":
			_text(form, "To hit (\"spell\" or a number)", str(fx.get("to_hit", "spell")), func(v: String) -> void: fx["to_hit"] = v if v == "spell" or not v.is_valid_int() else int(v))
			_option(form, "Range", ["melee", "ranged"], str(fx.get("range", "ranged")), func(v: String) -> void:
				fx["range"] = v
				_changed())
		"save":
			_option(form, "Save", ABILITIES, str(fx.get("ability", "dex")), func(v: String) -> void:
				fx["ability"] = v
				_changed())
			_text(form, "DC (\"spell\" or a number)", str(fx.get("dc", "spell")), func(v: String) -> void: fx["dc"] = v if v == "spell" or not v.is_valid_int() else int(v))
		"check":
			_text(form, "Skill (empty: ability only)", str(fx.get("skill", "")), func(v: String) -> void:
				if v.strip_edges() == "":
					fx.erase("skill")
				else:
					fx["skill"] = v.strip_edges().to_lower().replace(" ", "_"))
			_option(form, "Ability", ABILITIES, str(fx.get("ability", "str")), func(v: String) -> void:
				fx["ability"] = v
				_changed())
			_text(form, "DC", str(fx.get("dc", 10)), func(v: String) -> void: fx["dc"] = v if v == "spell" or not v.is_valid_int() else int(v))
			_option(form, "Who rolls", ["self", "target"], str(fx.get("by", "self")), func(v: String) -> void:
				fx["by"] = v
				_changed(true))
		_:
			_text(form, "Healing dice (+mod = your modifier)", str(fx.get("heal", "")), func(v: String) -> void: fx["heal"] = v.replace(" ", ""))
	_text(form, "Lasts rounds (empty: instant; 10 = a minute)", str(fx.duration.get("rounds", "")) if fx.get("duration") is Dictionary else "", func(v: String) -> void:
		if v.is_valid_int() and int(v) > 0:
			if not fx.get("duration") is Dictionary:
				fx["duration"] = {}
			fx.duration["rounds"] = int(v)
		elif fx.get("duration") is Dictionary:
			fx.duration.erase("rounds")
			if (fx.duration as Dictionary).is_empty():
				fx.erase("duration"))


func _condition_form(form: VBoxContainer, fx: Dictionary, key: String) -> void:
	_option(form, "Condition", CONDITIONS, str(fx.get(key, "frightened")), func(v: String) -> void:
		fx[key] = v
		_changed(true))
	_text(form, "Lasts rounds (10 = a minute)", str(fx.duration.get("rounds", "")) if fx.get("duration") is Dictionary else "", func(v: String) -> void:
		if v.is_valid_int():
			fx["duration"] = {"rounds": int(v)})


func _modifier_form(form: VBoxContainer, m: Dictionary) -> void:
	_text(form, "Of (ac, attack, save, speed ...)", str(m.get("target", "ac")), func(v: String) -> void: m["target"] = v.strip_edges().to_lower())
	_option(form, "How", ["add", "set"], str(m.get("op", "add")), func(v: String) -> void:
		m["op"] = v
		_changed())
	_text(form, "Value (a number or dice like 1d4)", str(m.get("value", 0)), func(v: String) -> void: m["value"] = int(v) if v.is_valid_int() else v)


func _resource_form(form: VBoxContainer, r: Dictionary) -> void:
	_number(form, "Uses", float(r.get("max", 1)) if str(r.get("max", 1)).is_valid_float() else 1.0, func(v: float) -> void:
		r["max"] = int(v)
		_changed())
	_option(form, "Back after", ["short", "long"], str(r.get("reset", "long")), func(v: String) -> void:
		r["reset"] = v
		_changed())


## A text field: `apply` on every change (the node's line follows).
func _text(form: VBoxContainer, label: String, value: String, apply: Callable) -> void:
	var row := _field(form, label)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(150, 0)
	e.text_changed.connect(func(v: String) -> void:
		apply.call(v)
		_changed()
		_relabel(form))
	row.add_child(e)


func _option(form: VBoxContainer, label: String, values: Array, value: String, apply: Callable) -> void:
	var row := _field(form, label)
	var o := OptionButton.new()
	for v: Variant in values:
		o.add_item(str(v).replace("_", " "))
	o.selected = maxi(values.find(value), 0)
	o.item_selected.connect(func(i: int) -> void:
		apply.call(str(values[i]))
		_relabel(form))
	row.add_child(o)


func _number(form: VBoxContainer, label: String, value: float, apply: Callable) -> void:
	var row := _field(form, label)
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 9999
	s.step = 0.5
	s.value = value
	s.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		_relabel(form))
	row.add_child(s)


func _relabel(form: VBoxContainer) -> void:
	if form.has_meta("node") and is_instance_valid(form.get_meta("node")):
		(form.get_meta("node") as FlowNode).relabel()


func _field(form: VBoxContainer, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = UISkin.V_MUTED
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	form.add_child(row)
	return row


# --- Pieces --------------------------------------------------------------------------------------

## A node: a rounded card in its kind's colour with an icon, one line and grey tags; a click
## opens its form (`fill` builds it), × calls `remove`.
func _node(kind: String, line: Callable, fill: Callable, remove: Callable, tags: Array, remove_tip := "Remove") -> Control:
	_count += 1
	var id := "n%d" % _count
	var box := FlowNode.new()
	box.name = "Node_%s_%d" % [kind, _count]
	box.kind = kind
	box.line = line
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 2)
	var card := Button.new()
	card.name = "Card"
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(200, 34)
	var c := OnUse.color(kind)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.lerp(UISkin.CREAM, 0.8)
	sb.border_color = c
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = c.lerp(UISkin.CREAM, 0.62)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	box.add_child(card)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -6
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := Label.new()
	icon.text = str(OnUse.ICONS.get(kind, "•"))
	icon.add_theme_font_size_override("font_size", 14)
	row.add_child(icon)
	var text := Label.new()
	text.name = "Line"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("font_color", c.darkened(0.4))
	text.add_theme_font_size_override("font_size", 14)
	row.add_child(text)
	box.label = text
	box.card = card
	box.row = row
	for t: Variant in tags:
		var tag := Label.new()
		tag.text = str(t)
		var ts := StyleBoxFlat.new()
		ts.bg_color = OnUse.GREY.lerp(UISkin.CREAM, 0.75)
		ts.set_corner_radius_all(6)
		ts.content_margin_left = 4
		ts.content_margin_right = 4
		tag.add_theme_stylebox_override("normal", ts)
		tag.add_theme_color_override("font_color", OnUse.GREY.darkened(0.3))
		tag.add_theme_font_size_override("font_size", 11)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	if remove.is_valid():
		var x := Button.new()
		x.name = "Remove"
		x.text = "×"
		x.flat = true
		x.tooltip_text = remove_tip
		x.focus_mode = Control.FOCUS_NONE
		x.add_theme_color_override("font_color", c.darkened(0.3))
		x.pressed.connect(remove)
		row.add_child(x)
		# the × sits on the card: it gets the click, the rest of the card opens the form
	for ch in row.get_children():
		if ch is Label:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.relabel()
	if fill.is_valid():
		var form := VBoxContainer.new()
		form.name = "Form"
		form.add_theme_constant_override("separation", 4)
		var holder := PanelContainer.new()
		holder.name = "FormBox"
		var fs := StyleBoxFlat.new()
		fs.bg_color = UISkin.CREAM
		fs.border_color = c
		fs.set_border_width_all(1)
		fs.set_corner_radius_all(8)
		fs.set_content_margin_all(8)
		holder.add_theme_stylebox_override("panel", fs)
		holder.add_child(form)
		holder.visible = false
		box.add_child(holder)
		var open := func() -> void:
			if form.get_child_count() == 0:
				fill.call(form)
			holder.visible = true
		card.pressed.connect(func() -> void:
			if holder.visible:
				holder.visible = false
				_open = ""
			else:
				open.call()
				_open = id)
		if _open == id:
			open.call()
		box.form = form
		form.set_meta("node", box)
	return box


func _line(h := 12) -> Control:
	var c := CenterContainer.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = UISkin.TAN
	r.custom_minimum_size = Vector2(2, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	return c


func _gap(h: int) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _plus(add: Callable) -> Control:
	var b := MenuButton.new()
	b.name = "Plus"
	b.text = "+"
	b.tooltip_text = "Add: a roll, damage, healing, a condition or a modifier"
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	for i in ADD.size():
		b.get_popup().add_item(str(ADD[i]), i)
	b.get_popup().id_pressed.connect(func(i: int) -> void: add.call(str(ADD[i])))
	return b


## A node: its card and its form; `relabel` redraws the card's line from the data.
class FlowNode extends VBoxContainer:
	var kind := ""
	var line: Callable
	var label: Label
	var form: VBoxContainer
	var card: Button
	var row: HBoxContainer

	func _ready() -> void:
		relabel.call_deferred()  # sizes are known once the theme reaches it

	func relabel() -> void:
		if label != null and line.is_valid():
			label.text = str(line.call())
		if card != null and row != null:  # the card grows with its line (the row is only laid on it)
			card.custom_minimum_size.x = maxf(200.0, row.get_combined_minimum_size().x + 18.0)
