class_name BunnyPuff
extends Sprite2D
## Ported from Tamago (scripts/fx/puff.gd, TASK-101; keep in step, see doc "Bunny shared with
## Tamago"). A smoke puff for teleports and for anything appearing or disappearing.
##
##     var puff := Puff.spawn(parent, center, width)
##     await puff.covered      # the cloud is at its biggest: show/hide/move things now
##
## Plays once and frees itself. The art is a 3x3 sprite sheet (grow, ring, scatter),
## read row by row; frames are cut out and scaled down once, then shared.

## The cloud is at its biggest; whatever it hides can change now.
signal covered

const SHEET := preload("res://assets/bunny/SmokePuff.png")
const COLUMNS := 3
const ROWS := 3
const FPS := 18.0
## Frames are scaled down once to this width (the sheet's cells are ~666 px).
const FRAME_WIDTH := 320
## The sheet has a faint stray line along its top edge; cut a few pixels off each cell.
const INSET := 4
## The biggest frame: fully hides what's behind it.
const COVER_FRAME := 2

static var _frames: Array[Texture2D] = []
## How far the visible smoke reaches below a frame's center (frame pixels, all frames).
static var _reach_down := 0.0

var _time := 0.0
var _covered := false
## Frames to stay hidden at first, so the window can stop clipping to its old shape
## (Tamago's desktop windows; Dragoon: one frame is enough).
var _wait := 1


## Puffs at `center` (parent's coordinates), about `width` pixels wide. The smoke never
## goes below `floor_y` (it's lifted instead), so it isn't cut off at a window edge.
static func spawn(parent: Node, center: Vector2, width: float, floor_y := INF) -> BunnyPuff:
	var puff := BunnyPuff.new()
	var frames := _get_frames()
	puff.texture = frames[0]
	puff.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # smooth art, unlike her pixels
	var s := width / frames[0].get_width()
	puff.scale = Vector2.ONE * s
	center.y = minf(center.y, floor_y - _reach_down * s)
	puff.position = center
	puff.visible = false
	parent.add_child(puff)
	return puff


static func _get_frames() -> Array[Texture2D]:
	if _frames.is_empty():
		var sheet := SHEET.get_image()
		if sheet.is_compressed():
			sheet.decompress()
		var cell := Vector2i(sheet.get_width() / COLUMNS, sheet.get_height() / ROWS)
		for row in ROWS:
			for col in COLUMNS:
				var frame := sheet.get_region(Rect2i(
						col * cell.x + INSET, row * cell.y + INSET, cell.x - 2 * INSET, cell.y - 2 * INSET))
				var height := roundi(FRAME_WIDTH * float(frame.get_height()) / frame.get_width())
				frame.resize(FRAME_WIDTH, height, Image.INTERPOLATE_LANCZOS)
				var used := frame.get_used_rect()
				if used.has_area():
					_reach_down = maxf(_reach_down, used.end.y - height * 0.5)
				_frames.append(ImageTexture.create_from_image(frame))
	return _frames


func _process(delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		visible = _wait == 0
		return
	_time += delta
	var index := int(_time * FPS)
	if index >= _frames.size():
		if not _covered:  # never leave a waiting teleport hanging
			_covered = true
			covered.emit()
		queue_free()
		return
	texture = _frames[index]
	if index >= COVER_FRAME and not _covered:
		_covered = true
		covered.emit()
