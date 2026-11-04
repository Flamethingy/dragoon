class_name BunnyDesk
extends Window
## The Table Bunny's desktop (TASK-102), Tamago's ScreenWorld for Dragoon: a transparent,
## borderless, always-on-top window over the usable area of the screen Dragoon is on
## (everything above the taskbar). The bunny walks along the taskbar there, and can stand on the
## top of Dragoon's window. Clicks go through it except on the bunny and its bubbles
## (update_passthrough). It follows Dragoon's window to another screen, unless the bunny was
## carried to another screen (TASK-105): then it stays there (per client, TableBunny "screen").
## Ported from Tamago's scripts/pet/screen_world.gd; see backlog doc "Bunny shared with Tamago".
## Where windows can't be see-through (headless, the setting off), the bunny stays inside
## Dragoon's window instead (TableBunny without a desk).

## Extra pixels around each clickable thing that still catch the mouse while it moves.
const PASSTHROUGH_PADDING := 8.0
## A window with no clickable things gets this tiny region (an empty polygon would make the
## whole window catch the mouse).
const NOTHING := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
const SCREEN_CHECK := 1.0  ## seconds between looks at Dragoon's window

var stage: Control  ## the bunny's parent: the whole window
var bunny: TableBunny
var screen := -1
var _last_polygon := PackedVector2Array()
var _check := 0.0
var _puffs := 0


## Can this computer show a see-through desktop window at all?
static func available() -> bool:
	# embedded in the editor's Game view a see-through window breaks the embedding (the game
	# was drawn scaled next to its frame, Nico 2026-11-04): the bunny stays inside Dragoon there
	return DisplayServer.get_name() != "headless" and not OS.has_feature("embedded_in_editor") and DisplayServer.is_window_transparency_available() \
		and bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false))


func _init() -> void:
	name = "BunnyDesk"
	title = "Table Bunny"
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	visible = false  # (force_native can't change on a shown window)
	force_native = true  # a real OS window, also while Dragoon embeds its dialogs
	mouse_passthrough_polygon = PackedVector2Array(NOTHING)
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.theme = UISkin.theme()  # its bubbles look like the table's pages
	add_child(stage)
	stage.child_entered_tree.connect(func(n: Node) -> void:
		if n is BunnyPuff:
			_puffs += 1
			update_passthrough()
			n.tree_exited.connect(func() -> void: _puffs -= 1))


func _ready() -> void:
	follow_main_window()
	show()


## Takes the bunny in (from wherever it was).
func hold(b: TableBunny) -> void:
	bunny = b
	if b.get_parent() != null:
		b.reparent(stage, false)
	else:
		stage.add_child(b)
	b.floor_gap = 0.0
	b.apply_settings()


## Covers the usable area of the screen the bunny was carried to, else the one Dragoon is on.
func follow_main_window() -> void:
	var main := get_tree().root if is_inside_tree() else null
	var at := DisplayServer.window_get_current_screen() if main == null else main.current_screen
	var chosen := int(TableBunny.setting("screen", -1))
	if chosen >= 0 and chosen < DisplayServer.get_screen_count():
		at = chosen
	if at != screen and (bunny == null or bunny.state != "dragged"):
		set_screen(at)


## Carried over another screen: the window moves there, the bunny stays under the cursor.
func carry(mouse: Vector2i) -> void:
	var over := DisplayServer.get_screen_from_rect(Rect2(Vector2(mouse), Vector2.ONE))
	if over >= 0 and over != screen:
		set_screen(over, true)
		TableBunny.set_setting("screen", over)
	bunny.drag_to(Vector2(mouse - position))


## Back to the screen Dragoon is on (its menu).
func back_to_dragoon() -> void:
	TableBunny.set_setting("screen", -1)
	follow_main_window()


func set_screen(index: int, carrying := false) -> void:
	screen = index
	var area := DisplayServer.screen_get_usable_rect(screen)  # without the taskbar
	# 1 px shorter than the usable area so Windows never treats it as fullscreen (Tamago)
	size = Vector2i(area.size.x, area.size.y - 1)
	position = Vector2i(area.position.x, area.position.y + 1)
	stage.size = Vector2(size)
	_last_polygon = PackedVector2Array()
	if bunny != null and not carrying:
		bunny.position.x = clampf(bunny.position.x, 0.0, maxf(0.0, stage.size.x - bunny.size.x))
		bunny.drop()


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = SCREEN_CHECK
		follow_main_window()
	if bunny != null:
		if bunny.state == "dragged" and bunny.carried_by_mouse():
			carry(DisplayServer.mouse_get_position())  # the real cursor, also over other screens (Tamago)
		bunny.platforms = platforms()
	update_passthrough()


## Dragoon's window top as a platform (in this window's coordinates), if it is a normal window
## below the top of the screen: [{id, left, y, segments: [Vector2(x1, x2)]}] like Tamago's.
func platforms() -> Array:
	var main := get_tree().root
	if main == null or main.mode != Window.MODE_WINDOWED or not main.visible:
		return []
	var top_left := Vector2(main.get_position_with_decorations() - position)
	var width := float(main.get_size_with_decorations().x)
	var bunny_h := bunny.size.y if bunny != null else 210.0
	if top_left.y < bunny_h + 10.0 or top_left.y > stage.size.y - 20.0:
		return []  # too close to the top of the screen or to the taskbar
	var a := maxf(top_left.x, 0.0)
	var b := minf(top_left.x + width, stage.size.x)
	if b - a < 40.0:
		return []
	return [{"id": 1, "left": top_left.x, "y": top_left.y, "segments": [Vector2(a, b)]}]


# --- Passthrough (Tamago: ScreenWorld) --------------------------------------------------------

func update_passthrough() -> void:
	# On Windows the passthrough region also clips drawing and lags a frame behind: while the
	# bunny is carried or falls, or a puff plays, the whole window (empty polygon = no
	# passthrough); otherwise padded boxes around the bunny and its bubbles.
	var poly := PackedVector2Array()
	var fast := _puffs > 0 or (bunny != null and bunny.is_moving_fast())
	if not fast:
		var rects: Array[Rect2] = []
		if bunny != null and bunny.visible:
			for r: Rect2 in bunny.clickable_rects():
				rects.append(r.grow(PASSTHROUGH_PADDING))
		if rects.is_empty():
			poly = PackedVector2Array(NOTHING)
		else:
			poly = region_polygon(merge_overlapping(rects))
	if poly != _last_polygon:
		_last_polygon = poly
		mouse_passthrough_polygon = poly


## Overlapping boxes become one (the region's fill is even-odd, so overlaps would be holes).
static func merge_overlapping(rects: Array[Rect2]) -> Array[Rect2]:
	var merged := true
	while merged:
		merged = false
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j], true):
					rects[i] = rects[i].merge(rects[j])
					rects.remove_at(j)
					merged = true
					break
			if merged:
				break
	return rects


## One polygon covering separate boxes: from each box's corner a zero-width bridge leads to the
## next box and is walked back at the end, so the bridges add no area.
static func region_polygon(rects: Array[Rect2]) -> PackedVector2Array:
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var poly := PackedVector2Array()
	if rects.size() == 1:
		var r := rects[0]
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for r in rects:
		poly.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	for i in range(rects.size() - 2, 0, -1):
		poly.append(rects[i].position)
	return poly
