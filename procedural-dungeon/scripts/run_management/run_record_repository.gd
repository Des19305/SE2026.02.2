extends RefCounted
## Stores run records as JSON files and removes records past their expires_at.
## Knows nothing about seeds, configs or run rules beyond the record fields it
## reads (run_id, created_at, expires_at).

const LAST_RUN_FILE := "last_run.json"
## Errors that may go away on their own (file locked by another process, device
## busy). Writes failing with these are retried; any other error is permanent.
const TRANSIENT_ERRORS := [ERR_BUSY, ERR_FILE_ALREADY_IN_USE, ERR_FILE_CANT_OPEN, ERR_FILE_CANT_WRITE, ERR_LOCKED, ERR_TIMEOUT]
## Wait before each retry. Its size is the number of retries (4 attempts in total).
const RETRY_DELAYS_MS := [50, 100, 200]
const TEMP_SUFFIX := ".tmp"

var records_dir: String
## (path: String, text: String) -> int (Error). Replaceable in tests to simulate storage faults.
var write_file: Callable
## (msec: int) -> void. Replaceable in tests so they never wait.
var sleep: Callable = func(msec: int) -> void: OS.delay_msec(msec)


func _init(dir: String) -> void:
	records_dir = dir
	write_file = _write_to_disk


## Prunes expired records, then writes the new record and last_run.json.
## All or nothing: if either write still fails after retries, the record file
## is removed again and last_run.json keeps its previous content.
## Returns an empty string on success, otherwise an error message.
func save_new_run(record: Dictionary) -> String:
	var err := DirAccess.make_dir_recursive_absolute(records_dir)
	if err != OK:
		return "Cannot save run record: %s" % error_string(err)
	prune_expired(record["created_at"])
	var record_file: String = record["run_id"] + ".json"
	var write_error := _write(record_file, record)
	if write_error == "":
		write_error = _write(LAST_RUN_FILE, record)
	if write_error != "":
		_remove(record_file)
	return write_error


## Overwrites an existing run record. Returns an empty string on success.
func update(record: Dictionary) -> String:
	return _write(record["run_id"] + ".json", record)


func prune_expired(now: int) -> void:
	var dir := DirAccess.open(records_dir)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json") or file_name == LAST_RUN_FILE:
			continue
		# A file another writer is replacing right now may read as empty: skip it.
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(records_dir.path_join(file_name))) != OK:
			continue
		var old: Variant = json.data
		if old is Dictionary and int(old.get("expires_at", 0)) <= now:
			dir.remove(file_name)


static func is_transient(err: int) -> bool:
	return TRANSIENT_ERRORS.has(err)


## Writes the whole file, retrying transient errors. Overwriting a file with the
## same text is idempotent, so a retry cannot duplicate anything.
func _write(file_name: String, record: Dictionary) -> String:
	var path := records_dir.path_join(file_name)
	var text := JSON.stringify(record, "\t")
	var err := _write_replace(path, text)
	var retries := 0
	while err != OK and is_transient(err) and retries < RETRY_DELAYS_MS.size():
		sleep.call(RETRY_DELAYS_MS[retries])
		retries += 1
		err = _write_replace(path, text)
	if err != OK:
		_remove_path(_temp_path(path))
		return "Cannot save run record: %s" % error_string(err)
	return ""


## One attempt: write a temporary file, then rename it over the real one, so a
## half-written attempt never replaces a complete record.
func _write_replace(path: String, text: String) -> int:
	var temp_path := _temp_path(path)
	var err: int = write_file.call(temp_path, text)
	if err != OK:
		return err
	# On Windows, rename reports a generic FAILED when another writer is
	# replacing the same file at that moment. Treat it as busy so it is retried
	# (bounded by RETRY_DELAYS_MS) instead of failing the run at once.
	if DirAccess.rename_absolute(temp_path, path) != OK:
		return ERR_BUSY
	return OK


## The temporary name is unique per repository object, so two writers of the
## same file (last_run.json) never share a temporary file.
func _temp_path(path: String) -> String:
	return "%s.%d%s" % [path, get_instance_id(), TEMP_SUFFIX]


func _remove(file_name: String) -> void:
	_remove_path(records_dir.path_join(file_name))


func _remove_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _write_to_disk(path: String, text: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	var err := file.get_error()
	file.close()
	return err
