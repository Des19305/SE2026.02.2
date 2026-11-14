extends "res://tests/test_case.gd"
## VT-107: RunExportService (docs/vt107/02-test-strategy.md).
## Slice 1: TC-01, TC-02, TC-03, TC-06. Slice 2: TC-13, TC-14, TC-19.
## Slice 3: TC-04, TC-05, TC-07, TC-08, TC-09, TC-10, TC-11, TC-12.
## Integration tests use the real RunRecordRepository / RunManager on a real
## temporary directory; no fake storage anywhere.

const RunExportService := preload("res://scripts/run_management/run_export_service.gd")
const RunRecordRepository := preload("res://scripts/run_management/run_record_repository.gd")
const RunConfigValidator := preload("res://scripts/run_management/run_config_validator.gd")
const RunManager := preload("res://scripts/run_management/run_manager.gd")

const BASE_TIME := 1_000_000
const FAR_FUTURE := 9_000_000_000
const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}
## Keys the exporter reads from a stored record (see TC-13).
const KEYS_READ_BY_EXPORTER := ["run_id", "created_at", "expires_at", "owner_id"]

var root_dir: String


func before_each() -> void:
	root_dir = "user://test_run_export/%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_dir(root_dir)


# --- TC-01: invalid requesters are rejected (negative) ----------------------

func test_invalid_requesters_are_not_authorized() -> void:
	var invalid_requesters: Array = [
		{},
		{"role": "player"},
		{"id": "", "role": "player"},
		{"id": 42, "role": "player"},
		{"id": "alice", "role": "guest"},
		{"id": "alice"},
		null,
		"alice",
	]
	for i in invalid_requesters.size():
		var access := RunExportService.authorize(invalid_requesters[i], {})
		check_eq(access["error"], RunExportService.ERR_NOT_AUTHORIZED, "invalid requester #%d" % i)


# --- TC-02: a player cannot name another owner (negative) -------------------

func test_player_cannot_export_another_owners_scope() -> void:
	var access := RunExportService.authorize(_player("alice"), {"owner_id": "bob"})
	check_eq(access["error"], RunExportService.ERR_FORBIDDEN_SCOPE, "player scope bob")


# --- TC-03: how the scope is resolved ---------------------------------------

func test_scope_resolution_for_player_and_maintainer() -> void:
	var own := RunExportService.authorize(_player("alice"), {})
	check_eq(own["error"], "", "player own: error")
	check_eq(own["owner_id"], "alice", "player without scope is limited to own id")
	check_eq(own["any_owner"], false, "player is never any_owner")

	var named_self := RunExportService.authorize(_player("alice"), {"owner_id": "alice"})
	check_eq(named_self["error"], "", "player naming self: error")
	check_eq(named_self["owner_id"], "alice", "player naming self")

	var everything := RunExportService.authorize(_maintainer(), {})
	check_eq(everything["error"], "", "maintainer all: error")
	check_eq(everything["any_owner"], true, "maintainer without owner sees all owners")

	var one_owner := RunExportService.authorize(_maintainer(), {"owner_id": "bob"})
	check_eq(one_owner["error"], "", "maintainer one owner: error")
	check_eq(one_owner["owner_id"], "bob", "maintainer scoped owner")
	check_eq(one_owner["any_owner"], false, "maintainer scoped is not any_owner")


# --- TC-06: a player exports only own records from the real repository ------

func test_player_exports_only_own_records_from_real_repository() -> void:
	var repository := RunRecordRepository.new(root_dir)
	# Saved alternately; bob's record is saved last, so last_run.json is bob's copy.
	for i in 3:
		check_eq(repository.save_new_run(_record("alice_%d" % i, "alice", i * 2)), "", "save alice %d" % i)
		check_eq(repository.save_new_run(_record("bob_%d" % i, "bob", i * 2 + 1)), "", "save bob %d" % i)

	var service := RunExportService.new(root_dir)
	service.clock = func() -> int: return BASE_TIME + 100
	var result: Dictionary = service.export_runs(_player("alice"), {})

	check(result["ok"], "export failed: %s" % result["error"])
	check_eq(result["error"], "", "error")
	var ids: Array = result["records"].map(func(r): return r["run_id"])
	ids.sort()
	check_eq(ids, ["alice_0", "alice_1", "alice_2"], "exported run ids")
	for record in result["records"]:
		check_eq(record.get("owner_id", ""), "alice", "owner of %s" % record.get("run_id", "?"))
		for key in record.keys():
			check(RunExportService.EXPORT_FIELDS.has(key), "field %s must not leave the module" % key)


# --- TC-13: what RunManager really writes has every key the exporter reads ---

func test_run_manager_record_has_every_key_the_exporter_reads() -> void:
	var manager := RunManager.new()
	manager.records_dir = root_dir
	manager.owner_id = "alice"
	var started: Dictionary = manager.start_new_run(42, CONFIG)
	check(started["ok"], "start failed: %s" % started["error"])
	var path := root_dir.path_join(manager.current_run["run_id"] + ".json")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved is Dictionary, "record file is not a JSON object")
	if saved is Dictionary:
		for key in KEYS_READ_BY_EXPORTER:
			check(saved.has(key), "stored record lacks key %s" % key)
		for key in RunExportService.EXPORT_FIELDS:
			check(saved.has(key), "stored record lacks exported field %s" % key)
		check_eq(saved.get("owner_id", null), "alice", "stored owner_id")
	manager.free()


# --- TC-14: runs of two owners through RunManager, export shows only own ------

func test_owner_exports_only_own_runs_started_through_run_manager() -> void:
	var manager := RunManager.new()
	manager.records_dir = root_dir
	manager.clock = func() -> int: return BASE_TIME + 5
	manager.owner_id = "alice"
	check(manager.start_new_run(42, CONFIG)["ok"], "alice start")
	manager.end_run(true, "boss")
	manager.owner_id = "bob"
	check(manager.start_new_run(43, CONFIG)["ok"], "bob start")
	manager.end_run(false, "died")
	manager.free()

	var service := RunExportService.new(root_dir)
	service.clock = func() -> int: return BASE_TIME + 100
	var result: Dictionary = service.export_runs(_player("alice"), {})

	check(result["ok"], "export failed: %s" % result["error"])
	check_eq(result["records"].size(), 1, "alice record count")
	if result["records"].size() == 1:
		var record: Dictionary = result["records"][0]
		check_eq(record["owner_id"], "alice", "owner")
		check_eq(record["status"], "completed", "status")
		check_eq(record["won"], true, "won")
		check_eq(record["reason"], "boss", "reason")
		check_eq(int(record["seed"]), 42, "seed")


# --- TC-19: numbers from the real repository are ints, config is valid -------

func test_exported_numbers_are_ints_and_config_passes_run_config_validator() -> void:
	var record := _record("alice_0", "alice", 5)
	record["config"] = CONFIG.duplicate()
	var repository := RunRecordRepository.new(root_dir)
	check_eq(repository.save_new_run(record), "", "save")

	var service := RunExportService.new(root_dir)
	service.clock = func() -> int: return BASE_TIME + 100
	var result: Dictionary = service.export_runs(_player("alice"), {})

	check_eq(result["records"].size(), 1, "record count")
	if result["records"].size() != 1:
		return
	var exported: Dictionary = result["records"][0]
	for key in ["seed", "created_at", "generation_version"]:
		check_eq(typeof(exported[key]), TYPE_INT, "type of %s" % key)
	for key in CONFIG.keys():
		check_eq(typeof(exported["config"][key]), TYPE_INT, "type of config.%s" % key)
	check_eq(RunConfigValidator.validate(int(exported["seed"]), exported["config"]), "", "validator on exported config")


# --- TC-04: expiry boundary and a fixed order (unit) -------------------------

func test_select_records_drops_expired_and_orders_by_created_at_then_run_id() -> void:
	var now := BASE_TIME + 100
	var records: Array = [
		_stamped("late", BASE_TIME + 30, now + 10),
		_stamped("b", BASE_TIME + 10, now + 10),
		_stamped("a", BASE_TIME + 10, now + 10),
		_stamped("gone_before", BASE_TIME + 5, now - 1),
		_stamped("gone_exactly", BASE_TIME + 6, now),
		_stamped("last_valid", BASE_TIME + 40, now + 1),
	]
	var no_expiry := _stamped("no_expiry", BASE_TIME + 7, now + 10)
	no_expiry.erase("expires_at")
	records.append(no_expiry)
	var access := {"error": "", "owner_id": "", "any_owner": true}

	var ids: Array = RunExportService.select_records(records, access, now).map(func(r): return r["run_id"])

	check_eq(ids, ["a", "b", "late", "last_valid"], "ids kept, in order (no_expiry is dropped: cannot prove it is valid)")


# --- TC-05: invalid scope, and the requester is judged first (negative) -------

func test_invalid_scope_is_rejected_and_requester_is_checked_first() -> void:
	var bad_scopes: Array = [{"owner_id": 7}, {"owner_id": ""}, "alice", null, [], 5]
	for i in bad_scopes.size():
		var access := RunExportService.authorize(_player("alice"), bad_scopes[i])
		check_eq(access["error"], RunExportService.ERR_INVALID_SCOPE, "bad scope #%d for player" % i)
		var maintainer_access := RunExportService.authorize(_maintainer(), bad_scopes[i])
		check_eq(maintainer_access["error"], RunExportService.ERR_INVALID_SCOPE, "bad scope #%d for maintainer" % i)
	var both_bad := RunExportService.authorize({"id": "alice", "role": "guest"}, {"owner_id": 7})
	check_eq(both_bad["error"], RunExportService.ERR_NOT_AUTHORIZED, "invalid requester wins over invalid scope")


# --- TC-07: last_run.json is a copy, not a second record (contract) -----------

func test_last_run_copy_is_not_exported_as_a_record() -> void:
	var repository := RunRecordRepository.new(root_dir)
	for i in 4:
		check_eq(repository.save_new_run(_record("alice_%d" % i, "alice", i)), "", "save %d" % i)
	check(FileAccess.file_exists(root_dir.path_join("last_run.json")), "precondition: last_run.json exists on disk")

	var result: Dictionary = _export(_player("alice"), root_dir)

	var ids: Array = result["records"].map(func(r): return r["run_id"])
	check_eq(ids, ["alice_0", "alice_1", "alice_2", "alice_3"], "each run exactly once")


# --- TC-08: an expired file that is still on disk is not exported -------------

func test_expired_record_still_on_disk_is_not_exported() -> void:
	var repository := RunRecordRepository.new(root_dir)
	check_eq(repository.save_new_run(_record("valid", "alice", 0)), "", "save valid")
	# Saved last: save_new_run prunes before writing, so this expired record stays on disk.
	var expired := _record("expired", "alice", 10)
	expired["expires_at"] = BASE_TIME + 20
	check_eq(repository.save_new_run(expired), "", "save expired")
	check(FileAccess.file_exists(root_dir.path_join("expired.json")), "precondition: expired file still on disk")

	var result: Dictionary = _export(_player("alice"), root_dir)

	var ids: Array = result["records"].map(func(r): return r["run_id"])
	check_eq(ids, ["valid"], "only the unexpired record")


# --- TC-09: corrupt files are skipped and counted (failure path) --------------

func test_corrupt_files_are_skipped_and_counted() -> void:
	expect_error("Parse JSON failed")
	var repository := RunRecordRepository.new(root_dir)
	check_eq(repository.save_new_run(_record("alice_0", "alice", 0)), "", "save 0")
	check_eq(repository.save_new_run(_record("alice_1", "alice", 1)), "", "save 1")
	_write_raw("truncated.json", "{\"run_id\": \"x\", \"se")
	_write_raw("array.json", "[]")
	_write_raw("empty.json", "")

	var result: Dictionary = _export(_player("alice"), root_dir)

	check(result["ok"], "export must not fail because of corrupt files: %s" % result["error"])
	var ids: Array = result["records"].map(func(r): return r["run_id"])
	check_eq(ids, ["alice_0", "alice_1"], "valid records survive")
	check_eq(result["skipped"], 3, "corrupt files counted")


# --- TC-10: records without an owner belong to nobody ------------------------

func test_records_without_owner_are_only_visible_to_a_maintainer() -> void:
	var repository := RunRecordRepository.new(root_dir)
	var legacy := _record("legacy", "", 0)
	legacy.erase("owner_id")
	check_eq(repository.save_new_run(legacy), "", "save legacy")
	check_eq(repository.save_new_run(_record("unowned", "", 1)), "", "save empty owner")
	check_eq(repository.save_new_run(_record("mine", "alice", 2)), "", "save alice")

	var as_player: Array = _export(_player("alice"), root_dir)["records"].map(func(r): return r["run_id"])
	var as_maintainer: Array = _export(_maintainer(), root_dir)["records"].map(func(r): return r["run_id"])

	check_eq(as_player, ["mine"], "player sees only own")
	check_eq(as_maintainer, ["legacy", "unowned", "mine"], "maintainer sees everything")


# --- TC-11: export never changes what is stored (read-only invariant) --------

func test_export_does_not_change_stored_files() -> void:
	expect_error("Parse JSON failed")
	var repository := RunRecordRepository.new(root_dir)
	check_eq(repository.save_new_run(_record("valid", "alice", 0)), "", "save valid")
	var expired := _record("expired", "alice", 10)
	expired["expires_at"] = BASE_TIME + 20
	check_eq(repository.save_new_run(expired), "", "save expired")
	_write_raw("corrupt.json", "{\"broken\"")
	var before := _snapshot(root_dir)
	check_eq(before.size(), 4, "precondition: valid, expired, corrupt and last_run.json exist")

	_export(_player("alice"), root_dir)
	_export(_maintainer(), root_dir)
	var denied: Dictionary = _export({}, root_dir)

	check_eq(denied["ok"], false, "denied export fails")
	check_eq(_snapshot(root_dir), before, "files and contents unchanged after successful and denied exports")


# --- TC-12: no records directory yet (edge / failure path) -------------------

func test_missing_records_directory_exports_nothing_and_creates_nothing() -> void:
	var missing := root_dir.path_join("never_created")

	var result: Dictionary = _export(_player("alice"), missing)

	check(result["ok"], "a missing directory means no runs yet, not an error: %s" % result["error"])
	check_eq(result["records"], [], "records")
	check_eq(result["skipped"], 0, "skipped")
	check(DirAccess.open(missing) == null, "export must not create the directory")
	check(DirAccess.open(root_dir) == null, "export must not create the parent directory")


# --- helpers ----------------------------------------------------------------

func _player(id: String) -> Dictionary:
	return {"id": id, "role": RunExportService.ROLE_PLAYER}


func _maintainer() -> Dictionary:
	return {"id": "qa", "role": RunExportService.ROLE_MAINTAINER}


func _record(run_id: String, owner_id: String, offset: int) -> Dictionary:
	return {
		"run_id": run_id,
		"seed": offset,
		"config": {"width": 50, "height": 50},
		"generation_version": 1,
		"created_at": BASE_TIME + offset,
		"expires_at": FAR_FUTURE,
		"status": "completed",
		"won": true,
		"reason": "boss",
		"owner_id": owner_id,
	}


func _stamped(run_id: String, created_at: int, expires_at: int) -> Dictionary:
	var record := _record(run_id, "alice", 0)
	record["created_at"] = created_at
	record["expires_at"] = expires_at
	return record


func _export(requester: Variant, dir: String) -> Dictionary:
	var service := RunExportService.new(dir)
	service.clock = func() -> int: return BASE_TIME + 100
	return service.export_runs(requester, {})


func _write_raw(file_name: String, text: String) -> void:
	var file := FileAccess.open(root_dir.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


## File name -> MD5 of its content, for every file in dir.
func _snapshot(dir_path: String) -> Dictionary:
	var snapshot := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return snapshot
	for file_name in dir.get_files():
		snapshot[file_name] = FileAccess.get_md5(dir_path.path_join(file_name))
	return snapshot


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
