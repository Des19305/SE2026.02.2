extends "res://tests/test_case.gd"
## VT-108: retry transient storage errors without repeating side effects.
## State transition tests (docs/vt108-retry.md §3). States: S0 idle, S1 run in
## progress, S2 completed. Storage faults are scripted, waits are recorded, so
## nothing here depends on timing or randomness.

const RunManager := preload("res://scripts/run_management/run_manager.gd")
const RunRecordRepository := preload("res://scripts/run_management/run_record_repository.gd")

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}
const NOW := 1_800_000_000
const PARTIAL := -1  # scripted outcome: write half of the text, then fail


## Fake storage. outcomes["record"] / outcomes["last_run"] hold the results of
## the next writes to a run record file / to last_run.json. When a queue is
## empty, the write goes to disk normally.
class ScriptedStorage:
	var outcomes := {"record": [], "last_run": []}
	var calls: Array[String] = []

	func write(path: String, text: String) -> int:
		var key := "last_run" if path.get_file().trim_suffix(".tmp") == "last_run.json" else "record"
		calls.append(key)
		var queue: Array = outcomes[key]
		var outcome: int = queue.pop_front() if not queue.is_empty() else OK
		if outcome == PARTIAL:
			_store(path, text.substr(0, text.length() / 2))
			return ERR_FILE_CANT_WRITE
		if outcome != OK:
			return outcome
		_store(path, text)
		return OK

	func _store(path: String, text: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()


var manager: Node
var storage: ScriptedStorage
var records_dir: String
var waits: Array = []
var started_events: Array = []
var ended_events: Array = []


func before_each() -> void:
	records_dir = "user://test_retry/%d" % Time.get_ticks_usec()
	storage = ScriptedStorage.new()
	manager = RunManager.new()
	manager.records_dir = records_dir
	manager.clock = func() -> int: return NOW
	manager.storage_writer = storage.write
	manager.retry_sleep = func(msec: int) -> void: waits.append(msec)
	manager.run_started.connect(func(seed_value, _dungeon): started_events.append(seed_value))
	manager.run_ended.connect(func(won, reason): ended_events.append([won, reason]))


func after_each() -> void:
	manager.free()
	_remove_dir("user://test_retry")


# --- S0 --start--> S1 -------------------------------------------------------

## TC-01 S0 --start / storage ok--> S1. Baseline: no retry, no wait.
func test_start_without_faults_writes_once() -> void:
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(result["ok"], "start failed: %s" % result["error"])
	check_eq(storage.calls, ["record", "last_run"], "write calls")
	check_eq(waits, [], "waits")
	check_eq(_record_files(), ["%d_42.json" % NOW], "record files")


## TC-02 S0 --start / transient x2 on the record--> S1. AC-1, AC-2.
func test_start_retries_transient_record_error_without_duplicates() -> void:
	storage.outcomes["record"] = [ERR_BUSY, ERR_FILE_CANT_OPEN]
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(result["ok"], "start should succeed after retries: %s" % result["error"])
	check_eq(storage.calls, ["record", "record", "record", "last_run"], "write calls")
	check_eq(waits, [50, 100], "backoff")
	check_eq(_record_files(), ["%d_42.json" % NOW], "exactly one record file")
	check_eq(started_events, [42], "run_started emitted once")
	check_eq(manager.current_run.get("status", ""), "in_progress", "state S1")


## TC-03 S0 --start / transient x3 on last_run.json--> S1. Boundary: last retry.
func test_start_succeeds_on_last_allowed_retry() -> void:
	storage.outcomes["last_run"] = [ERR_LOCKED, ERR_TIMEOUT, ERR_FILE_ALREADY_IN_USE]
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(result["ok"], "start should succeed on the 4th attempt: %s" % result["error"])
	check_eq(waits, [50, 100, 200], "backoff")
	check_eq(_read(records_dir.path_join("last_run.json")).get("run_id", ""), "%d_42" % NOW, "last_run.json")
	check_eq(started_events, [42], "run_started emitted once")


## TC-04 S0 --start / transient x4--> S0. Negative: retries exhausted. AC-4.
func test_start_fails_cleanly_when_retries_are_exhausted() -> void:
	storage.outcomes["record"] = [ERR_BUSY, ERR_BUSY, ERR_BUSY, ERR_BUSY]
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(not result["ok"], "start must fail after 4 attempts")
	check(result["error"].begins_with("Cannot save run record: "), "error was: %s" % result["error"])
	check_eq(storage.calls.size(), 4, "attempts")
	check_eq(waits, [50, 100, 200], "backoff")
	_check_idle_after_failed_start()


## TC-05 S0 --start / permanent error--> S0. Negative: no retry. AC-3.
func test_start_does_not_retry_permanent_error() -> void:
	storage.outcomes["record"] = [ERR_FILE_NO_PERMISSION]
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(not result["ok"], "start must fail")
	check_eq(storage.calls, ["record"], "write calls")
	check_eq(waits, [], "waits")
	_check_idle_after_failed_start()


## TC-06 S0 --start / record ok, last_run.json fails--> S0. Failure path of
## the VT-108 risk (partial failure). AC-4: the record is rolled back and the
## previous last_run.json is kept.
func test_partial_start_failure_rolls_back_record() -> void:
	_write(records_dir.path_join("last_run.json"), {"run_id": "previous"})
	storage.outcomes["last_run"] = [ERR_FILE_NO_PERMISSION]
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(not result["ok"], "start must fail")
	check_eq(storage.calls, ["record", "last_run"], "write calls")
	check_eq(_record_files(), [], "orphan run record left on disk")
	check_eq(_read(records_dir.path_join("last_run.json")).get("run_id", ""), "previous", "last_run.json changed")
	check(manager.current_run.is_empty(), "current_run must stay empty")
	check_eq(started_events, [], "run_started")


## TC-07 S0 --start / partial write, then ok--> S1. The retry overwrites the
## half-written file, so the stored record is complete JSON.
func test_retry_replaces_partially_written_record() -> void:
	storage.outcomes["record"] = [PARTIAL]
	var result: Dictionary = manager.start_new_run(42, CONFIG)
	check(result["ok"], "start should succeed after retry: %s" % result["error"])
	var saved := _read(records_dir.path_join("%d_42.json" % NOW))
	check_eq(saved.get("status", ""), "in_progress", "stored record")
	check_eq(int(saved.get("seed", -1)), 42, "stored seed")


## TC-08 S1 --start--> S1. Rejected without touching the storage.
func test_start_while_in_progress_writes_nothing() -> void:
	manager.start_new_run(42, CONFIG)
	storage.calls.clear()
	var result: Dictionary = manager.start_new_run(43, CONFIG)
	check(not result["ok"], "second start must be rejected")
	check_eq(storage.calls, [], "write calls")
	check_eq(started_events, [42], "run_started")


# --- S1 --end--> S2 / S1 ----------------------------------------------------

## TC-09 S1 --end / transient x1--> S2 -> S0. AC-1, AC-2.
func test_end_retries_transient_error_and_emits_once() -> void:
	manager.start_new_run(42, CONFIG)
	storage.outcomes["record"] = [ERR_FILE_CANT_WRITE]
	var result := _end(true, "boss defeated")
	check(result.get("ok", false), "end should succeed after retry: %s" % result.get("error", ""))
	check_eq(_read(records_dir.path_join("%d_42.json" % NOW)).get("status", ""), "completed", "stored status")
	check(manager.current_run.is_empty(), "state must return to S0")
	check_eq(ended_events, [[true, "boss defeated"]], "run_ended")


## TC-10 S1 --end / transient x4--> S1. Negative + failure path. AC-5: memory
## and disk both still say in_progress, run_ended is not emitted.
func test_failed_end_keeps_run_in_progress() -> void:
	manager.start_new_run(42, CONFIG)
	storage.outcomes["record"] = [ERR_BUSY, ERR_BUSY, ERR_BUSY, ERR_BUSY]
	var result := _end(false, "player died")
	check(not result.get("ok", true), "end must report the storage failure")
	check_eq(manager.current_run.get("status", ""), "in_progress", "state must stay S1")
	check_eq(_read(records_dir.path_join("%d_42.json" % NOW)).get("status", ""), "in_progress", "stored status")
	check_eq(ended_events, [], "run_ended")


## TC-11 S1 (after failed end) --end / ok--> S2 -> S0. AC-5: one run_ended in total.
func test_end_can_be_repeated_after_storage_recovers() -> void:
	manager.start_new_run(42, CONFIG)
	storage.outcomes["record"] = [ERR_BUSY, ERR_BUSY, ERR_BUSY, ERR_BUSY]
	_end(false, "player died")
	var result := _end(false, "player died")
	check(result.get("ok", false), "second end should succeed: %s" % result.get("error", ""))
	check_eq(_read(records_dir.path_join("%d_42.json" % NOW)).get("status", ""), "completed", "stored status")
	check_eq(ended_events, [[false, "player died"]], "run_ended emitted once")


## TC-15 S1 --end / partial writes until retries run out--> S1. Found in
## review: each failed attempt may leave a half-written file, so the stored
## record must still be the complete in_progress record afterwards.
func test_failed_end_does_not_corrupt_stored_record() -> void:
	manager.start_new_run(42, CONFIG)
	storage.outcomes["record"] = [PARTIAL, PARTIAL, PARTIAL, PARTIAL]
	var result := _end(false, "player died")
	check(not result.get("ok", true), "end must report the storage failure")
	var saved := _read(records_dir.path_join("%d_42.json" % NOW))
	check_eq(saved.get("status", ""), "in_progress", "stored record after failed end")
	check_eq(int(saved.get("seed", -1)), 42, "stored seed after failed end")


## TC-12 S0 --end--> S0. Invalid transition: no write, no signal.
func test_end_without_run_is_rejected() -> void:
	var result := _end(true, "nothing")
	check(not result.get("ok", true), "end without a run must fail")
	check_eq(result.get("error", ""), "No run in progress", "error")
	check_eq(storage.calls, [], "write calls")
	check_eq(ended_events, [], "run_ended")


## TC-13 S0 (after a failed start) --replay--> S1 with the previous good run.
func test_replay_after_failed_start_uses_previous_run() -> void:
	manager.start_new_run(7, CONFIG)
	manager.end_run(true, "boss defeated")
	storage.outcomes["record"] = [ERR_FILE_NO_PERMISSION]
	manager.start_new_run(8, CONFIG)
	var replay: Dictionary = manager.replay_last_run()
	check(replay["ok"], "replay failed: %s" % replay["error"])
	check_eq(replay["seed"], 7, "replayed seed")


# --- retry policy -----------------------------------------------------------

## TC-14 Error classification table (AC-1 / AC-3).
func test_error_classification() -> void:
	var repository := RunRecordRepository.new(records_dir)
	if not repository.has_method("is_transient"):
		check(false, "RunRecordRepository has no is_transient() classification")
		return
	for code in [ERR_BUSY, ERR_FILE_ALREADY_IN_USE, ERR_FILE_CANT_OPEN, ERR_FILE_CANT_WRITE, ERR_LOCKED, ERR_TIMEOUT]:
		check(repository.is_transient(code), "%s should be transient" % error_string(code))
	for code in [OK, FAILED, ERR_FILE_NO_PERMISSION, ERR_FILE_NOT_FOUND, ERR_FILE_BAD_PATH, ERR_CANT_CREATE, ERR_INVALID_PARAMETER]:
		check(not repository.is_transient(code), "%s should be permanent" % error_string(code))


# --- helpers ----------------------------------------------------------------

## end_run must return {ok, error} (AC-5); before VT-108 it returned nothing.
func _end(won: bool, reason: String) -> Dictionary:
	var result: Variant = manager.end_run(won, reason)
	if not result is Dictionary:
		check(false, "end_run must return a result Dictionary, got <%s>" % result)
		return {}
	return result

func _check_idle_after_failed_start() -> void:
	check_eq(_record_files(), [], "record files")
	check(not FileAccess.file_exists(records_dir.path_join("last_run.json")), "last_run.json written")
	check(manager.current_run.is_empty(), "current_run must stay empty")
	check(manager.last_run.is_empty(), "last_run must stay empty")
	check_eq(started_events, [], "run_started")


func _record_files() -> Array:
	var names: Array = []
	var dir := DirAccess.open(records_dir)
	if dir == null:
		return names
	for file_name in dir.get_files():
		if file_name != "last_run.json":
			names.append(file_name)
	return names


## Missing or half-written files read as {} (JSON.parse does not log errors).
func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
