extends SceneTree
## Headless check of value tokens in the editor (TASK-29): which fields become tokens, the known
## values of a field (most used first, spellings merged), base lists, one value vs. lists,
## the "+" / search with autocomplete against known values, long lists, ref fields (stored as
## refs or names, Ctrl+click opens the entry) and saving through the editor in the book.
## godot --headless --path . -s tools/test_tokens.gd

const DIR := "user://test_tokens"

var _failed := 0


func _init() -> void:
	PackageManager._delete_tree(ProjectSettings.globalize_path(DIR))
	var root := ProjectSettings.globalize_path(DIR + "/packages")
	_package(root.path_join("mini"))
	var manager := PackageManager.new(root)
	manager.set_enabled("mini", true)

	# --- Schema ------------------------------------------------------------------------------------
	var f := _fields("monsters")
	_check(f.tags.type == "tokens" and f.size.type == "token" and f.type.type == "token", "monster tags / size / type are tokens")
	_check(f.condition_immunities.type == "tokens" and "poisoned" in f.condition_immunities.base, "condition immunities with the conditions")
	_check(f.resistances.base == Schema.DAMAGE_TYPES and f.senses.type == "list", "damage types; senses stay text")
	_check(_fields("items").rarity.type == "token" and _fields("items").type.type == "tokens", "items: rarity one, type a list")
	_check(_fields("spells").school.base == Schema.SCHOOLS and _fields("spells").classes.type == "tokens", "spells: school, classes")
	var pcs := _fields("pcs")
	_check(pcs.race.type == "token" and pcs.race.ref_kind == "races" and pcs.race.ref_store == "ref", "pc race is a ref token")
	_check(pcs.factions.type == "tokens" and pcs.factions.ref_kind == "factions", "factions are ref tokens")
	_check(_fields("npcs").race.ref_store == "name", "npc race keeps names")
	var cls := Schema.fields("classes", {"spellcast_ability": "", "saving_throws": ["Strength"], "hit_dice": "12"})
	var by_key := {}
	for x: Dictionary in cls:
		by_key[x.key] = x
	_check(by_key.saving_throws.type == "tokens" and by_key.spellcast_ability.base == Schema.ABILITY_NAMES and by_key.hit_dice.type == "line", "guessed class fields become tokens")
	_check(Schema.fields("subclasses", {"class": "Fighter"}).any(func(x: Dictionary) -> bool: return x.key == "class" and x.type == "token" and x.ref_kind == "classes"), "subclass class: ref token")
	_check(_fields("monsters").description.type == "markdown", "text fields stay text")

	# --- Known values --------------------------------------------------------------------------------
	var db := PackageDB.new()
	db.load_now(root)
	var rarity := db.field_values("items", "rarity")
	_check(rarity[0].value == "rare" and rarity[0].count == 3, "most used first (%s)" % [rarity])
	_check(rarity.filter(func(v: Dictionary) -> bool: return str(v.value).to_lower() == "very rare").size() == 1
		and rarity.any(func(v: Dictionary) -> bool: return v.value == "very rare" and v.count == 3), "spellings merged into the most used one")
	_check(db.field_values("monsters", "tags").size() == 2, "list values count one by one")
	var opts := TokenField.build_options(_fields("items").rarity, "items", db)
	_check(opts[0].value == "rare" and opts.any(func(o: Dictionary) -> bool: return o.value == "artifact" and o.count == 0), "data first, then the base list")
	_check(TokenField.build_options(_fields("items").rarity, "items", null).size() == Schema.RARITIES.size(), "base list without any data")
	var race_opts := TokenField.build_options(pcs.race, "pcs", db)
	_check(race_opts.size() == 2 and race_opts[0].value == "races/elf" and race_opts[0].label == "Elf", "ref options: entries of the kind, most used first (%s)" % [race_opts.map(func(o: Dictionary) -> String: return o.value)])
	_check(TokenField.build_options(_fields("npcs").race, "npcs", db)[0].value == "Elf", "name refs store the name")

	# --- One value -------------------------------------------------------------------------------------
	var host := Control.new()
	get_root().add_child(host)
	var one := _token_field(host, _fields("items").rarity, opts, "Very Rare")
	_check(one.value() == "very rare", "a stored spelling picks the known value")
	one.toggle("rare")
	_check(one.value() == "rare", "click another: switch")
	one.toggle("rare")
	_check(one.value() == "", "click the selected one: cleared")
	one.add_value("LEGENDARY")
	_check(one.value() == "legendary" and one.options.size() == opts.size(), "typed in another spelling: the known value, no new token")
	one.add_value("mythic")
	_check(one.value() == "mythic" and one.option_for("mythic").count == 0, "a new value becomes a token")

	# --- Lists ---------------------------------------------------------------------------------------
	var res_field: Dictionary = f.resistances
	var many := _token_field(host, res_field, TokenField.build_options(res_field, "monsters", db), ["fire"])
	many.toggle("cold")
	many.toggle("fire")
	many.toggle("acid")
	_check(many.value() == ["cold", "acid"], "toggle any number (%s)" % [many.value()])
	_check(many.search.visible and many.flow.get_child_count() == 2 + 11 + 1, "13 damage types: all shown, the chosen first (%d)" % many.flow.get_child_count())
	var cond: Dictionary = f.condition_immunities
	var long := _token_field(host, cond, TokenField.build_options(cond, "monsters", db), [])
	_check(long.flow.get_child_count() == TokenField.SHOWN + 2, "15 conditions: top 12, 'more' and '+' (%d)" % long.flow.get_child_count())
	_check(long.flow.get_node_or_null("More") != null and long.flow.get_node_or_null("Add") != null, "a 'more' and a '+' token")
	long.search.text = "unc"
	long._render()
	_check(long.flow.get_node_or_null("Token_unconscious") != null and long.flow.get_node_or_null("Token_blinded") == null, "search filters the tokens")
	long.search.text = ""
	long._render()
	(long.flow.get_node("More") as Button).pressed.emit()
	_check(long.flow.get_node_or_null("Token_unconscious") != null and long.flow.get_node_or_null("More") == null, "show all")
	var plain := _token_field(host, f.tags, TokenField.build_options(f.tags, "monsters", db), [])
	_check(not plain.search.visible, "short lists have no search")
	(plain.flow.get_node("Add") as Button).pressed.emit()
	_check(plain.search.visible, "'+' opens the field")
	plain.search.text = "Swamp"
	(plain.flow.get_node("Add") as Button).pressed.emit()
	_check(plain.value() == ["swamp"] or plain.value() == ["Swamp"], "'+' adds what was typed (%s)" % [plain.value()])

	# --- Refs ----------------------------------------------------------------------------------------
	var race := _token_field(host, pcs.race, race_opts, "Elf")
	_check(race.value() == "races/elf", "a name in a ref field is stored as the ref")
	race.add_value("dwa")
	_check(race.value() == "races/dwarf", "refs: the only match is picked")
	var opened := []
	race.open_requested.connect(func(o: Dictionary) -> void: opened.append(o))
	_press_ctrl(true)
	(race.flow.get_node("Token_Elf") as Button).pressed.emit()
	_press_ctrl(false)
	_check(opened.size() == 1 and opened[0].entry.id == "elf" and race.value() == "races/dwarf", "Ctrl+click opens the entry, keeps the value")

	# --- In the book ---------------------------------------------------------------------------------
	var screen := SubViewport.new()
	screen.size = Vector2i(1600, 950)
	get_root().add_child(screen)
	var book := Compendium.new()
	book.tabs_file = ""
	book.packages_root = root
	screen.add_child(book)
	await book.db.loaded
	await process_frame
	var store := EntryStore.open(root.path_join("mini"))
	store.unlock()
	var form := book.edit_entry(store, "items", "ring")
	_check(form != null and form.find_child("Field_rarity", true, false) is TokenField, "the editor shows tokens")
	var tf := form.find_child("Field_rarity", true, false) as TokenField
	tf.toggle("very rare")
	_check(not form.save().is_empty() and str(store.find("items", "ring").rarity) == "very rare", "saved through the editor")
	_check(book.db.field_values("items", "rarity").any(func(v: Dictionary) -> bool: return v.value == "very rare" and v.count == 4), "the counts follow the save")
	var pc_form := book.edit_entry(store, "pcs", "ash")
	var race_tf := pc_form.find_child("Field_race", true, false) as TokenField
	var before := book.current_tab_key()
	race_tf.open_requested.emit(race_tf.option_for("races/elf"))
	await process_frame
	_check(book.current_tab_key().ends_with("races/elf") and before != book.current_tab_key(), "Ctrl+click in the book opens the race (%s)" % book.current_tab_key())

	print("tokens: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _fields(kind: String) -> Dictionary:
	var out := {}
	for x: Dictionary in Schema.fields(kind):
		out[x.key] = x
	return out


func _token_field(host: Control, field: Dictionary, opts: Array, value: Variant) -> TokenField:
	var t := TokenField.new()
	host.add_child(t)
	t.setup(field, opts, value)
	return t


func _press_ctrl(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_CTRL
	e.physical_keycode = KEY_CTRL
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _package(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	EntryStore._write(folder.path_join("package.json"), {"format": "dragoon-package", "format_version": 1, "id": "mini",
		"name": "Mini", "kind": "source", "version": "1.0.0"})
	EntryStore._write(folder.path_join("items.json"), [
		{"id": "ring", "name": "Ring", "rarity": "rare", "type": ["Ring"]},
		{"id": "rod", "name": "Rod", "rarity": "rare", "type": ["Rod"]},
		{"id": "orb", "name": "Orb", "rarity": "Rare", "type": ["Wondrous Item"]},
		{"id": "crown", "name": "Crown", "rarity": "very rare", "type": ["Wondrous Item"]},
		{"id": "staff", "name": "Staff", "rarity": "very rare", "type": ["Staff"]},
		{"id": "cup", "name": "Cup", "rarity": "Very Rare", "type": ["Wondrous Item"]}])
	EntryStore._write(folder.path_join("monsters.json"), [
		{"id": "imp", "name": "Imp", "type": "Fiend", "tags": ["devil", "small"], "resistances": ["cold"]},
		{"id": "rat", "name": "Rat", "type": "Beast", "tags": ["small"]}])
	EntryStore._write(folder.path_join("races.json"), [
		{"id": "dwarf", "name": "Dwarf"}, {"id": "elf", "name": "Elf"}])
	EntryStore._write(folder.path_join("pcs.json"), [
		{"id": "ash", "name": "Ash", "race": "races/elf", "factions": []}])
	EntryStore._write(folder.path_join("npcs.json"), [
		{"id": "mira", "name": "Mira", "race": "Elf"}])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
