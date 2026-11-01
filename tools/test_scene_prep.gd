extends SceneTree
## Headless check of scene prep (TASK-34): a map picture is added to the world and its grid
## lined up by dragging over one square; monsters, NPCs and PCs from the compendium are
## dropped onto the map as `token.placed` events of the timeline; several of one monster are
## numbered copies with their own HP; two timelines of the world keep their own positions on
## the same map; the world's files are not touched by placing tokens.
## godot --headless --path . -s tools/test_scene_prep.gd

const DIR := "user://test_scene_prep"
const PORT := 47799

var _failed := 0


func _init() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	PackageManager._delete_tree(base)
	var worlds := base.path_join("worlds")
	var red := Worlds.install_example(worlds)
	var world := red.get_base_dir().get_base_dir()
	var packages := base.path_join("packages")
	_book(packages.path_join("bestiary"))
	var picture := base.path_join("cave.png")
	var img := Image.create(700, 490, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.25, 0.2))
	img.save_png(picture)
	await process_frame

	# --- Grid by dragging ------------------------------------------------------------------------
	var g := MapSetup.grid_from_drag(Vector2(160, 97), Vector2(110, 47))
	_check(is_equal_approx(float(g.size), 50.0) and g.offset == Vector2(10, 47), "a dragged square sets size and offset (%s)" % [g])
	var setup := MapSetup.new()
	root.add_child(setup)
	setup.new_map(world, picture)
	setup.canvas.cell_dragged.emit(Vector2(0, 0), Vector2(70, 70))
	_check(is_equal_approx(setup.size_spin.value, 70.0) and setup.offset_x.value == 0.0, "the dialog takes the dragged square")
	setup.name_edit.text = "Goblin Cave"
	setup.metres.value = 1.5
	var said := []
	setup.saved.connect(func(ref: String) -> void: said.append(ref))
	var cave := setup.save()
	_check(cave == "maps/goblin-cave" and said == [cave], "saved as a world map (%s)" % cave)
	var saved: Dictionary = EntryStore.open(world).find("maps", "goblin-cave")
	_check(FileAccess.file_exists(world.path_join("assets/maps/goblin-cave.png")) and str(saved.get("image", "")) == "assets/maps/goblin-cave.png", "picture copied into the world")
	_check(float(saved.grid.size) == 70.0 and float(saved.grid.cell_m) == 1.5, "grid and metres per cell in maps.json")
	setup.edit_map(world, saved)
	setup.set_grid({"size": 35.0, "offset": Vector2(5, 5)})
	_check(setup.save() == cave and float(EntryStore.open(world).find("maps", "goblin-cave").grid.size) == 35.0, "an existing map's grid can be lined up again")
	setup.queue_free()

	# --- Host and drop tokens ---------------------------------------------------------------------
	var holder := Node.new()
	holder.name = "DM"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/DM"))
	var table := NetTable.new()
	table.name = "Table"
	table.timeline_dir = red
	table.cache_dir = DIR.path_join("cache")
	holder.add_child(table)
	var ui := table.get_node("TableUI") as TableUI if table.has_node("TableUI") else null
	await process_frame
	_check(table.host(PORT) == OK, "DM hosts")
	table.maps_changed(cave)
	_check(table.map_id == cave and is_equal_approx(table.grid.cell, 35.0), "the new map is shown with its grid")
	var world_files := _snapshot(world)

	# The timeline's book: core, its world, the timeline (what the DM drags from, TASK-37).
	var db := PackageDB.new()
	db.timeline_dir = red
	db.world_filter = table.timeline.world_id()
	db.load_now(packages)
	var goblin: Dictionary = db.get_entry("bestiary", "monsters", "goblin")
	var mira: Dictionary = db.get_entry("westmarch", "npcs", "mira")
	_check(not goblin.is_empty() and not mira.is_empty(), "the book has the bestiary goblin and the world's Mira")
	_check(db.resolve("Elsewhere Elf").is_empty(), "not another world's entries")
	var g1 := table.drop_token(goblin, Vector2i(1, 1))
	var g2 := table.drop_token(goblin, Vector2i(2, 1))
	_check(g1 != g2 and table.timeline.name_of(g1) == "Goblin 1" and table.timeline.name_of(g2) == "Goblin 2", "numbered goblins (%s, %s)" % [g1, g2])
	_check(table.timeline.is_created(g1) and FileAccess.file_exists(red.path_join("assets/tokens/goblin.png")), "copies are timeline entries, picture copied")
	var placed := table.event_log.events.filter(func(e: Dictionary) -> bool: return e.type == "token.placed" and e.entity in [g1, g2])
	_check(placed.size() == 2 and placed[0].data.map == cave, "token.placed events on the map")
	_check(table.grid.tokens.has(g1) and table.grid.tokens.has(g2) and table.grid.token_cell(g2) == Vector2i(2, 1), "both on the grid")
	table.change_hp(g1, -5)
	var hp := {}
	for t: Dictionary in table.view_for("").tokens:
		hp[t.id] = t.get("hp")
	_check(int(hp[g1]) == 2 and int(hp[g2]) == 7, "own HP per goblin (%s)" % [hp])
	_check(table.drop_token(mira, Vector2i(4, 4)) == "npcs/mira" and table.drop_token(mira, Vector2i(5, 4)) == "npcs/mira", "a world NPC is placed itself, again = moved")
	_check(table.grid.token_cell("npcs/mira") == Vector2i(5, 4), "Mira moved")

	# Dropped through the UI drop zone at a screen point.
	var layer := CanvasLayer.new()  # like the table UI: screen coordinates, not the map's
	root.add_child(layer)
	var drop := MapDrop.new()
	drop.table = table
	layer.add_child(drop)
	var screen := table.grid.get_canvas_transform() * table.grid.cell_center(Vector2i(6, 2), 1.0)
	_check(drop._can_drop_data(screen, EntryDrag.data(goblin)) and not drop._can_drop_data(screen, {"x": 1}), "the drop zone takes compendium entries only")
	drop._drop_data(screen, EntryDrag.data(goblin))
	var g3 := "monsters/goblin-3"
	_check(table.grid.tokens.has(g3) and table.grid.token_cell(g3) == Vector2i(6, 2), "dropped at the cell under the mouse (%s)" % table.grid.token_cell(g3))
	var card := EntryCard.new()
	card.setup(goblin)
	_check(EntryDrag.is_entry(card._get_drag_data(Vector2.ZERO)) and EntryDrag.ref_of(card._get_drag_data(Vector2.ZERO)) == "monsters/goblin", "compendium cards can be dragged")
	card.free()
	_check(_snapshot(world) == world_files, "placing tokens leaves the world files alone")

	# --- Two timelines, one map -------------------------------------------------------------------
	var a := table.timeline
	var b := Timeline.new(a.fork("Other table", -1))
	b.events_log.move_token(g1, cave, Vector2i(1, 1), Vector2i(9, 9))
	a.events_log.move_token(g1, cave, Vector2i(1, 1), Vector2i(3, 3))
	_check(Replay.tokens_on(cave, a.events_log.effective())[g1] == Vector2i(3, 3) and Replay.tokens_on(cave, b.events_log.effective())[g1] == Vector2i(9, 9), "each timeline has its own positions on the map")
	var c := Timeline.new(Timeline.create(world, "Fresh", "prologue"))
	_check(not Replay.tokens_on(cave, c.events_log.effective()).has(g1) and not c.map_view(cave).is_empty(), "a timeline without those events sees the map without them")

	if ui != null:
		ui.queue_free()
	table.multiplayer.multiplayer_peer.close()
	print("scene prep: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


## A small core book with a goblin, and another world with an elf (should stay out).
func _book(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder.path_join("assets/tokens"))
	_write(folder.path_join("package.json"), {"id": "bestiary", "name": "Bestiary", "kind": "source", "version": "1"})
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.DARK_GREEN)
	img.save_png(folder.path_join("assets/tokens/goblin.png"))
	_write(folder.path_join("monsters.json"), [{"id": "goblin", "name": "Goblin", "type": "humanoid", "cr": 0.25, "ac": 15, "hp": 7,
		"size": "small", "description": "Small and mean.", "token": "assets/tokens/goblin.png"}])
	var other := Worlds.create("Elsewhere", "default", folder.get_base_dir().get_base_dir().path_join("worlds"))
	EntryStore.open(other).save("npcs", {"id": "elf", "name": "Elsewhere Elf", "description": "Not here."})


func _snapshot(folder: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(folder):
		out[f] = FileAccess.get_file_as_string(folder.path_join(f))
	return out


func _write(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, " "))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
