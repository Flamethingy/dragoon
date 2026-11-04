class_name PinnedHud
extends CharacterHud
## A HUD that never shows itself (TASK-92): the pieces of a detached sheet page act through it,
## always for the character the page was opened for (`active` stays put), whatever token is
## selected. No keys, no selection, no building of its own.


func _init() -> void:
	super()
	name = "PinnedHud"
	visible = false
	set_process_input(false)


func _ready() -> void:
	pass  # not the table's HUD: doesn't follow the selection, the keys or the table


func _input(_event: InputEvent) -> void:
	pass


func _fill() -> void:
	pass


func set_active(_ref: String, _direction := 0) -> void:
	pass
