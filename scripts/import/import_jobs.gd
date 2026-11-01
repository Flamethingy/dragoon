class_name ImportJobs
extends RefCounted
## The VTT side of the import agent (TASK-28, import-agent.md "VTT <-> tool"): starts
## tools/import_agent.py as its own process for a PDF, image or link, follows its job folder
## (data/imports/<job>/: job.json, progress.log, a draft package) and merges reviewed drafts
## into a package. Nothing reaches a package unless accepted here.
## Settings (API key, python, agent script) live in user:// only, never in data/ or git.

static var settings_file := "user://import_settings.cfg"  ## tests point this elsewhere
const FILE_KINDS := {"pdf": "pdf", "png": "image", "jpg": "image", "jpeg": "image", "webp": "image"}
## Duplicate handling when a draft's name is already in the target kind.
const ASK := "ask"
const REPLACE := "replace"
const KEEP_BOTH := "keep"
const SKIP := "skip"

var packages_root := ""
var imports_root := ""  ## data/imports next to the packages
var pids := {}  ## job id -> process id (this run)


func _init(root := "") -> void:
	packages_root = root if root != "" else PackageDB.default_root()
	imports_root = packages_root.get_base_dir().path_join("imports")


# --- Settings -------------------------------------------------------------------------------

static func setting(key: String, default := "") -> String:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	return str(cfg.get_value("import", key, default))


static func set_setting(key: String, value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_file)
	cfg.set_value("import", key, value)
	cfg.save(settings_file)


static func python() -> String:
	return setting("python", "python")


## The agent script: the setting, else tools/import_agent.py of the project (or next to the exe).
static func agent_script() -> String:
	var s := setting("agent", "")
	if s != "":
		return s
	var dev := ProjectSettings.globalize_path("res://tools/import_agent.py")
	return dev if FileAccess.file_exists(dev) else OS.get_executable_path().get_base_dir().path_join("tools/import_agent.py")


## "pdf", "image" or "url" for an input ("" = not importable).
static func input_kind(input: String) -> String:
	if input.begins_with("http://") or input.begins_with("https://"):
		return "url"
	return FILE_KINDS.get(input.get_extension().to_lower(), "")


# --- Jobs ------------------------------------------------------------------------------------------

## Starts an import: creates data/imports/<job>/ with job.json and launches the agent
## (the API key goes in as the ANTHROPIC_API_KEY environment variable, never as an argument
## or into a file). `target` is a package id or "new:<name>". Returns the job ({} + error).
func start(input: String, target: String) -> Dictionary:
	var kind := input_kind(input)
	if kind == "":
		return {"error": "Can't import %s (PDF, PNG, JPG, WebP or a link)" % input.get_file()}
	if kind != "url" and not FileAccess.file_exists(input):
		return {"error": "No file %s" % input}
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var base := "%s-%s" % [stamp, EntryStore.slug(input.get_file().get_basename() if kind != "url" else input.get_slice("//", 1).get_slice("/", 0))]
	var job_id := base
	var n := 2
	while DirAccess.dir_exists_absolute(imports_root.path_join(job_id)):
		job_id = "%s-%d" % [base, n]
		n += 1
	var dir := imports_root.path_join(job_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var job := {"id": job_id, "input": input, "kind": kind, "target": target, "status": "starting",
		"started": Time.get_datetime_string_from_system()}
	EntryStore._write(dir.path_join("job.json"), job)
	var script := agent_script()
	if not FileAccess.file_exists(script):
		job.status = "failed"
		job["error"] = "The import tool is missing (%s)" % script
		EntryStore._write(dir.path_join("job.json"), job)
		return job
	var key := setting("api_key", "")
	if key != "":
		OS.set_environment("ANTHROPIC_API_KEY", key)
	var pid := OS.create_process(python(), [script, "--input", input, "--kind", kind, "--target", target,
		"--job", dir, "--packages", packages_root])
	if key != "":
		OS.unset_environment("ANTHROPIC_API_KEY")
	if pid <= 0:
		job.status = "failed"
		job["error"] = "Can't start %s (is Python installed? see Import settings)" % python()
		EntryStore._write(dir.path_join("job.json"), job)
		return job
	pids[job_id] = pid
	return job


func job_dir(job_id: String) -> String:
	return imports_root.path_join(job_id)


## A job as it is now: job.json, `log` (progress.log) and `running` (the process lives).
## A job whose process ended without saying done/failed counts as failed.
func status(job_id: String) -> Dictionary:
	var dir := job_dir(job_id)
	var job: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("job.json"))) \
		if FileAccess.file_exists(dir.path_join("job.json")) else null
	if not job is Dictionary:
		return {}
	job["log"] = FileAccess.get_file_as_string(dir.path_join("progress.log")) if FileAccess.file_exists(dir.path_join("progress.log")) else ""
	var pid: int = pids.get(job_id, 0)
	job["running"] = pid > 0 and OS.is_process_running(pid)
	if str(job.status) in ["starting", "running"] and pid > 0 and not job.running:
		job.status = "failed"
		job["error"] = str(job.get("error", "The import tool stopped without finishing"))
	return job


## Every job, newest first.
func jobs() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(imports_root):
		return out
	var ids := Array(DirAccess.get_directories_at(imports_root))
	ids.sort()
	ids.reverse()
	for id: String in ids:
		var s := status(id)
		if not s.is_empty():
			out.append(s)
	return out


func cancel(job_id: String) -> void:
	var pid: int = pids.get(job_id, 0)
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var s := status(job_id)
	if not s.is_empty() and str(s.status) in ["starting", "running"]:
		s.status = "cancelled"
		s.erase("log")
		s.erase("running")
		EntryStore._write(job_dir(job_id).path_join("job.json"), s)


# --- Drafts ----------------------------------------------------------------------------------------

## The job's draft package (null until the tool wrote package.json).
func drafts(job_id: String) -> EntryStore:
	return EntryStore.open(job_dir(job_id))


## [{kind, entry}] of the drafts still waiting for review (features come with their monsters).
func draft_entries(job_id: String) -> Array:
	var store := drafts(job_id)
	var out := []
	if store == null:
		return out
	for file in DirAccess.get_files_at(store.folder):
		var kind := file.get_basename()
		if not file.ends_with(".json") or kind in ["package", "job", "features"]:
			continue
		for e: Variant in store.list(kind):
			if e is Dictionary and e.has("id"):
				out.append({"kind": kind, "entry": e})
	return out


## Crops the draft's picture from its source page (`source_page`, page pixels) into
## art/<id>.jpg and points `image` at it.
func crop(job_id: String, kind: String, entry_id: String, rect: Rect2i) -> Dictionary:
	var store := drafts(job_id)
	var e := store.find(kind, entry_id) if store else {}
	if e.is_empty() or str(e.get("source_page", "")) == "":
		return {}
	var page := ImageCache.decode(FileAccess.get_file_as_bytes(store.folder.path_join(str(e.source_page))))
	if page == null:
		return {}
	var r := rect.intersection(Rect2i(Vector2i.ZERO, page.get_size()))
	if r.size.x < 2 or r.size.y < 2:
		return {}
	DirAccess.make_dir_recursive_absolute(store.folder.path_join("art"))
	var rel := "art/%s.jpg" % entry_id
	page.get_region(r).save_jpg(store.folder.path_join(rel), 0.9)
	var copy := e.duplicate(true)
	copy["image"] = rel
	copy["crop"] = [r.position.x, r.position.y, r.size.x, r.size.y]
	store.save(kind, copy)
	return copy


## The target entry with the same name as a draft ({} if none).
static func duplicate_of(target: EntryStore, kind: String, draft: Dictionary) -> Dictionary:
	var name := str(draft.get("name", "")).strip_edges().to_lower()
	for e: Variant in target.list(kind):
		if e is Dictionary and str(e.get("name", "")).strip_edges().to_lower() == name:
			return e
	return {}


## Merges one draft into the target package (with its features and picture, keeping its
## import `origin`) and removes it from the drafts. A name already in the target: `on_duplicate`
## decides (ASK returns {duplicate: entry} and does nothing). A read-only source package is
## unlocked: picking it as the import target is the explicit choice.
## Returns {merged: entry} / {skipped: true} / {duplicate: entry} / {error}.
func accept(job_id: String, kind: String, entry_id: String, target: EntryStore, on_duplicate := ASK) -> Dictionary:
	var store := drafts(job_id)
	var draft := store.find(kind, entry_id) if store else {}
	if draft.is_empty() or target == null:
		return {"error": "Nothing to merge"}
	var dup := duplicate_of(target, kind, draft)
	if not dup.is_empty():
		match on_duplicate:
			ASK:
				return {"duplicate": dup}
			SKIP:
				store.delete(kind, entry_id)
				return {"skipped": true}
	if target.is_read_only():
		target.unlock()
	if not dup.is_empty() and on_duplicate == REPLACE:
		target.delete(kind, str(dup.id))
	var copy := target.copy_entry(store, kind, entry_id)
	if copy.is_empty():
		return {"error": "Can't write into %s" % target.name}
	if draft.has("origin"):
		copy["origin"] = draft.origin  # where it was imported from, not the draft folder
	for key in ["crop", "source_page"]:
		copy.erase(key)
	var old_id := str(copy.id)
	if not dup.is_empty() and on_duplicate == REPLACE:
		copy["id"] = str(dup.id)
	target.save(kind, copy, old_id)
	store.delete(kind, entry_id)
	return {"merged": copy}


func discard(job_id: String, kind: String, entry_id: String) -> void:
	var store := drafts(job_id)
	if store:
		store.delete(kind, entry_id)


## The target package for a job: an existing package or a new world package ("new:<name>").
func target_store(target: String) -> EntryStore:
	if target.begins_with("new:"):
		return EntryStore.create_world(packages_root, target.substr(4).strip_edges())
	return EntryStore.open(packages_root.path_join(target))
