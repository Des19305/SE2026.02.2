extends SceneTree
## VT-108 load check (NFR-1): 100 concurrent tasks, each starts a run and ends
## it, while the storage fails with transient errors at a given rate. Retries
## use the real waits (50/100/200 ms). Faults come from a seeded RNG per task,
## so a run can be repeated exactly.
##
## Usage (from the procedural-dungeon/ folder):
##   godot --headless --path . -s res://tests/load_test_vt108.gd
## Optional: TASKS=<n> (default 100), FAULT_RATES=0,0.3,0.5 (default),
## SHARED_DIR=1 to make all tasks write to one records folder. By default every
## task has its own folder, as every player has their own user:// folder; the
## shared folder (100 writers of one last_run.json) is a stress case.
## Not part of tests/run_tests.gd: it takes a few seconds and uses threads.

const RunManager := preload("res://scripts/run_management/run_manager.gd")
const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}
const NOW := 1_800_000_000
const P95_TARGET_MS := 3000.0
const RECORDS_DIR := "user://load_vt108"


## Storage that fails before writing with probability fault_rate.
class FlakyStorage:
	var rng := RandomNumberGenerator.new()
	var fault_rate: float
	var faults := 0
	var writes := 0

	func _init(task_seed: int, rate: float) -> void:
		rng.seed = task_seed
		fault_rate = rate

	func write(path: String, text: String) -> int:
		writes += 1
		if rng.randf() < fault_rate:
			faults += 1
			return ERR_BUSY
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(text)
		var err := file.get_error()
		file.close()
		return err


var t0_usec := 0
var shared_dir := true


func _init() -> void:
	var tasks := int(OS.get_environment("TASKS")) if OS.get_environment("TASKS") != "" else 100
	var rates_text := OS.get_environment("FAULT_RATES")
	var rates := Array(rates_text.split(",")) if rates_text != "" else ["0", "0.3", "0.5"]
	var all_ok := true
	shared_dir = OS.get_environment("SHARED_DIR") == "1"
	print("VT-108 load check: %d concurrent tasks per scenario, %s, Godot %s, %s, %d CPU threads" % [
		tasks, "one shared records folder" if shared_dir else "one records folder per task",
		Engine.get_version_info()["string"], OS.get_name(), OS.get_processor_count()])
	for rate_text in rates:
		all_ok = _scenario(tasks, float(rate_text)) and all_ok
	quit(0 if all_ok else 1)


func _scenario(tasks: int, fault_rate: float) -> bool:
	_clear_dir()
	var threads: Array[Thread] = []
	t0_usec = Time.get_ticks_usec()
	for i in tasks:
		var thread := Thread.new()
		thread.start(_task.bind(i, fault_rate))
		threads.append(thread)
	var results: Array = []
	for thread in threads:
		results.append(thread.wait_to_finish())

	var latencies: Array[float] = []
	var started_ok := 0
	var ended_ok := 0
	var faults := 0
	var writes := 0
	var problems: Array[String] = []
	var errors := {}
	for r in results:
		if r["error"] != "":
			errors[r["error"]] = errors.get(r["error"], 0) + 1
		latencies.append(r["ms"])
		faults += r["faults"]
		writes += r["writes"]
		if r["started"] != (1 if r["start_ok"] else 0):
			problems.append("task %d: run_started emitted %d times" % [r["task"], r["started"]])
		if r["ended"] != (1 if r["end_ok"] else 0):
			problems.append("task %d: run_ended emitted %d times" % [r["task"], r["ended"]])
		if r["start_ok"]:
			started_ok += 1
		if r["end_ok"]:
			ended_ok += 1
		if r["start_ok"] and not r["end_ok"] and r["memory_status"] != "in_progress":
			problems.append("task %d: end failed but run is not in progress in memory" % r["task"])

	# Disk must match memory: one record per started run, completed iff ended.
	var on_disk := _read_records()
	if on_disk["tmp"] > 0:
		problems.append("%d temporary files left" % on_disk["tmp"])
	for r in results:
		var expected := "" if not r["start_ok"] else ("completed" if r["end_ok"] else "in_progress")
		var actual: String = on_disk["status"].get("%d_%d" % [NOW, 1000 + r["task"]], "")
		if actual != expected:
			problems.append("task %d: record status <%s>, expected <%s>" % [r["task"], actual, expected])
	if on_disk["records"] != started_ok:
		problems.append("%d record files for %d started runs" % [on_disk["records"], started_ok])

	latencies.sort()
	var p50 := latencies[int(ceil(0.50 * latencies.size())) - 1]
	var p95 := latencies[int(ceil(0.95 * latencies.size())) - 1]
	var total := 0.0
	for ms in latencies:
		total += ms
	if fault_rate == 0.0 and ended_ok != results.size():
		problems.append("without injected faults every run must start and end (%d/%d)" % [ended_ok, results.size()])
	var passed := p95 <= P95_TARGET_MS and problems.is_empty()
	print("\nfault rate %.0f%%: %d writes, %d injected faults" % [fault_rate * 100, writes, faults])
	print("  runs started %d/%d, ended %d/%d" % [started_ok, results.size(), ended_ok, results.size()])
	print("  task time ms: avg %.0f, p50 %.0f, p95 %.0f, max %.0f (target p95 <= %.0f)" % [
		total / latencies.size(), p50, p95, latencies[-1], P95_TARGET_MS])
	for message in errors:
		print("  error x%d: %s" % [errors[message], message])
	print("  consistency problems: %d" % problems.size())
	for problem in problems.slice(0, 10):
		print("    - %s" % problem)
	print("  %s" % ("PASS" if passed else "FAIL"))
	_clear_dir()
	return passed


## One user: start a run, then end it. Time is measured from the moment all
## tasks were submitted, so waiting for a free CPU counts towards the latency.
func _task(i: int, fault_rate: float) -> Dictionary:
	var storage := FlakyStorage.new(i, fault_rate)
	var manager = RunManager.new()
	manager.records_dir = RECORDS_DIR if shared_dir else RECORDS_DIR.path_join("task_%d" % i)
	manager.clock = func() -> int: return NOW
	manager.storage_writer = storage.write
	var counts := {"started": 0, "ended": 0}
	manager.run_started.connect(func(_s, _d): counts["started"] += 1)
	manager.run_ended.connect(func(_w, _r): counts["ended"] += 1)
	var start: Dictionary = manager.start_new_run(1000 + i, CONFIG)
	var end := {"ok": false}
	if start["ok"]:
		end = manager.end_run(i % 2 == 0, "load test")
	var result := {
		"task": i,
		"ms": (Time.get_ticks_usec() - t0_usec) / 1000.0,
		"start_ok": start["ok"],
		"error": start["error"] if not start["ok"] else end.get("error", ""),
		"end_ok": end["ok"],
		"memory_status": manager.current_run.get("status", ""),
		"started": counts["started"],
		"ended": counts["ended"],
		"faults": storage.faults,
		"writes": storage.writes,
	}
	manager.free()
	return result


func _read_records(path := RECORDS_DIR, out := {"records": 0, "tmp": 0, "status": {}}) -> Dictionary:
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		_read_records(path.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.ends_with(".tmp"):
			out["tmp"] += 1
		elif file_name != "last_run.json":
			out["records"] += 1
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(file_name)))
			out["status"][file_name.get_basename()] = data.get("status", "") if data is Dictionary else "<unreadable>"
	return out


func _clear_dir(path := RECORDS_DIR) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_clear_dir(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
