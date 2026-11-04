class_name BunnyButton
extends TextureButton
## The Table Bunny's icon in the lower left corner of the table (TASK-102): a click calls the
## bunny out (it appears in a puff), another click sends it away (it vanishes in one). The icon
## wears the host's colours for it (the rig's recolouring, like Tamago's tray icon).

const ICON := "res://assets/bunny/icon.png"
const SIDE := 44

var bunny: TableBunny


func _init() -> void:
	name = "BunnyButton"
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = custom_minimum_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(toggle)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(10, get_parent_area_size().y - SIDE - 10)
	if bunny != null:
		bunny.on_changed.connect(refresh)
		if bunny.table != null:
			bunny.table.bunny_look_changed.connect(refresh)
	refresh()


## Out or away.
func toggle() -> void:
	if bunny != null:
		bunny.set_on(not bunny.is_on())
		refresh()


func refresh() -> void:
	var image := (load(ICON) as Texture2D).get_image() if ResourceLoader.exists(ICON) else null
	if image != null and bunny != null and bunny.rig.is_inside_tree():
		image = bunny.rig.recolor(image)
	if image != null:
		texture_normal = ImageTexture.create_from_image(image)
	var on := bunny != null and bunny.is_on()
	self_modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
	var who := bunny.table.bunny_name if bunny != null and bunny.table != null else "the bunny"
	tooltip_text = ("Send %s away" if on else "Call %s") % who
