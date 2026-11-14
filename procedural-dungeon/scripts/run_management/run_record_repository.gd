extends RefCounted
## Stores run records as JSON files and removes records past their expires_at.
## Knows nothing about seeds, configs or run rules beyond the record fields it
## reads (run_id, created_at, expires_at).

const LAST_RUN_FILE := "last_run.json"

var records_dir: String


func _init(dir: String) -> void:
	records_dir = dir


## Prunes expired records, then writes the new record and last_run.json.
## Returns an empty string on success, otherwise an error message.
func save_new_run(record: Dictionary) -> String:
	var err := DirAccess.make_dir_recursive_absolute(records_dir)
	if err != OK:
		return "Cannot save run record: %s" % error_string(err)
	prune_expired(record["created_at"])
	var write_error := _write(record["run_id"] + ".json", record)
	if write_error != "":
		return write_error
	return _write(LAST_RUN_FILE, record)


## Overwrites an existing run record. Best-effort: a failed write is ignored.
func update(record: Dictionary) -> void:
	_write(record["run_id"] + ".json", record)


## Read-only. Returns {"records": Array, "skipped": int}: every run record file
## except last_run.json (a copy of the latest record), plus how many files could
## not be read as a record. Does not filter by owner or expiry.
func list_records() -> Dictionary:
	var records: Array = []
	var skipped := 0
	var dir := DirAccess.open(records_dir)
	if dir == null:
		return {"records": records, "skipped": skipped}
	for file_name in dir.get_files():
		if not file_name.ends_with(".json") or file_name == LAST_RUN_FILE:
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(records_dir.path_join(file_name)))
		if parsed is Dictionary:
			records.append(_restore_ints(parsed))
		else:
			skipped += 1
	return {"records": records, "skipped": skipped}


func prune_expired(now: int) -> void:
	var dir := DirAccess.open(records_dir)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json") or file_name == LAST_RUN_FILE:
			continue
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(records_dir.path_join(file_name)))
		if old is Dictionary and int(old.get("expires_at", 0)) <= now:
			dir.remove(file_name)


## JSON has a single number type, so JSON.parse_string returns every number as a
## float. Records are written with int fields (seed, timestamps, config values), so
## whole-number floats are turned back into ints; a real fraction is left alone.
static func _restore_ints(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if value == floorf(value) and absf(value) < 9007199254740992.0:
				return int(value)
			return value
		TYPE_DICTIONARY:
			var restored := {}
			for key in value:
				restored[key] = _restore_ints(value[key])
			return restored
		TYPE_ARRAY:
			var items: Array = []
			for item in value:
				items.append(_restore_ints(item))
			return items
	return value


func _write(file_name: String, record: Dictionary) -> String:
	var file := FileAccess.open(records_dir.path_join(file_name), FileAccess.WRITE)
	if file == null:
		return "Cannot save run record: %s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return ""
