extends SceneTree
## Moves the old layout into worlds with timelines (TASK-32, timelines.md): world packages from
## data/packages to data/worlds, every data/campaigns/<id> into a timeline of its world (the old
## folder is kept in data/campaigns-migrated/). The app does the same on start.
## godot --headless --path . -s tools/migrate_data.gd [-- <data folder>]
## (examples/worlds/westmarch was made this way from the old example campaign red-fang.)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var data := args[0] if not args.is_empty() else PackageDB.default_root().get_base_dir()
	for line in Worlds.migrate_data(data):
		print(line)
	print("migration done: ", data)
	quit()
