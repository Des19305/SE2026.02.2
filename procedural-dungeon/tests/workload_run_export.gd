extends RefCounted
## Shared workload for the VT-107 concurrency tests (TC-15..TC-18) and the load
## harness (tests/load_run_export.gd). Not a test suite itself.
##
## Runs N tasks against a real records directory, one Thread per task, all released
## together by a start gate. (WorkerThreadPool is not used: it starts as many workers
## as there are CPUs, so on a 1-CPU machine the tasks ran one after another;
## max_concurrent = 1 was measured, see docs/vt107/03-concurrency-notes.md.)
##   even task index  -> writer: saves a new run record through RunRecordRepository
##   odd task index   -> exporter: calls RunExportService.export_runs
## (with_writers = false makes every task an exporter).
## Every task's role and data come from its index only: no random numbers, no wall
## time, so a failure message names the task and can be reproduced.

const RunExportService := preload("res://scripts/run_management/run_export_service.gd")
const RunRecordRepository := preload("res://scripts/run_management/run_record_repository.gd")

const OWNERS := ["alice", "bob", "carol"]
const SEED_RECORDS_PER_OWNER := 10
const EXPIRED_OWNER := "alice"
const BASE_TIME := 1_000_000
const FAR_FUTURE := 9_000_000_000
## "now" of every exporter; later than the expiry of the expired seed records.
const NOW := BASE_TIME + 2000
## Exporter kinds, by index modulo 5: three players, one maintainer, one invalid requester.
const EXPORTER_KINDS := 5
const KIND_MAINTAINER := 3
const KIND_INVALID := 4

var root_dir: String
var with_writers := true
## When set, every exporter task shares this one service instance (TC-16).
var shared_service: RefCounted = null
var expired_seed_count := 0
var outcomes: Array = []
var durations_us: Array = []
## Highest number of tasks that were inside _task at the same moment.
var max_concurrent := 0
var _active := 0
var _mutex := Mutex.new()


## Writes the records that exist before any task starts: SEED_RECORDS_PER_OWNER per
## owner that never expire, plus expired_seed_count expired ones of EXPIRED_OWNER.
func seed_records(expired_count: int = 0) -> void:
	expired_seed_count = expired_count
	var repository := RunRecordRepository.new(root_dir)
	for i in expired_count:
		var expired := _record("exp_%d" % i, EXPIRED_OWNER, i, BASE_TIME + 500 + i)
		assert(repository.save_new_run(expired) == "")
	var offset := 100
	for owner in OWNERS:
		for i in SEED_RECORDS_PER_OWNER:
			assert(repository.save_new_run(_record(seed_id(owner, i), owner, offset, FAR_FUTURE)) == "")
			offset += 1


## Runs task_count tasks at once and blocks until all have finished.
func run(task_count: int) -> void:
	outcomes.clear()
	outcomes.resize(task_count)
	durations_us.clear()
	durations_us.resize(task_count)
	max_concurrent = 0
	_active = 0
	var gate := Semaphore.new()
	var threads: Array[Thread] = []
	for i in task_count:
		var thread := Thread.new()
		thread.start(_run_after_gate.bind(i, gate))
		threads.append(thread)
	for i in task_count:
		gate.post()
	for thread in threads:
		thread.wait_to_finish()


func new_service() -> RefCounted:
	var service := RunExportService.new(root_dir)
	service.clock = func() -> int: return NOW
	return service


static func seed_id(owner: String, index: int) -> String:
	return "seed_%s_%d" % [owner, index]


static func requester_for(kind: int) -> Variant:
	if kind < OWNERS.size():
		return {"id": OWNERS[kind], "role": RunExportService.ROLE_PLAYER}
	if kind == KIND_MAINTAINER:
		return {"id": "qa", "role": RunExportService.ROLE_MAINTAINER}
	return {"id": "intruder", "role": "guest"}


## Nearest-rank percentile of values (microseconds).
static func percentile_us(values: Array, percent: float) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	var rank := int(ceil(percent / 100.0 * sorted.size())) - 1
	return int(sorted[clampi(rank, 0, sorted.size() - 1)])


static func remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	for sub in dir.get_directories():
		remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)


## Everything that must hold for every interleaving, checked per finished task.
## Returns one message per violation; empty means the invariants held.
func violations() -> Array[String]:
	var found: Array[String] = []
	for i in outcomes.size():
		var outcome: Variant = outcomes[i]
		if typeof(outcome) != TYPE_DICTIONARY:
			found.append("task %d did not finish" % i)
			continue
		if outcome["role"] == "writer":
			if outcome["error"] != "":
				found.append("task %d: writer failed: %s" % [i, outcome["error"]])
			continue
		var ids: Array = outcome["records"].map(func(r): return r["run_id"])
		var unique := {}
		for id in ids:
			unique[id] = true
		if unique.size() != ids.size():
			found.append("task %d: a run_id was exported twice" % i)
		var kind: int = outcome["kind"]
		if kind == KIND_INVALID:
			if outcome["ok"] or outcome["error"] != RunExportService.ERR_NOT_AUTHORIZED or not ids.is_empty():
				found.append("task %d: invalid requester got ok=%s error=%s records=%d" % [i, outcome["ok"], outcome["error"], ids.size()])
			continue
		if not outcome["ok"]:
			found.append("task %d: export failed: %s" % [i, outcome["error"]])
			continue
		for record in outcome["records"]:
			if kind != KIND_MAINTAINER and record["owner_id"] != OWNERS[kind]:
				found.append("task %d: %s received record %s of owner %s" % [i, OWNERS[kind], record["run_id"], record["owner_id"]])
			if str(record["run_id"]).begins_with("exp_"):
				found.append("task %d: expired record %s was exported" % [i, record["run_id"]])
		for owner in _owners_visible_to(kind):
			for index in SEED_RECORDS_PER_OWNER:
				if not ids.has(seed_id(owner, index)):
					found.append("task %d: seed record %s is missing" % [i, seed_id(owner, index)])
					break
	return found


## After every task has finished: the final state must be exactly the seeds plus
## every record a writer saved, and nothing may have been left unreadable.
func final_violations() -> Array[String]:
	var found: Array[String] = []
	var expected: Array = []
	for owner in OWNERS:
		for index in SEED_RECORDS_PER_OWNER:
			expected.append(seed_id(owner, index))
	for outcome in outcomes:
		if typeof(outcome) == TYPE_DICTIONARY and outcome["role"] == "writer":
			expected.append(outcome["run_id"])
	expected.sort()
	var result: Dictionary = new_service().export_runs(requester_for(KIND_MAINTAINER), {})
	if not result["ok"]:
		found.append("final export failed: %s" % result["error"])
		return found
	var actual: Array = result["records"].map(func(r): return r["run_id"])
	actual.sort()
	if actual != expected:
		found.append("final export has %d records, expected %d (seeds + writers)" % [actual.size(), expected.size()])
	if result["skipped"] != 0:
		found.append("final export skipped %d unreadable files" % result["skipped"])
	return found


func _run_after_gate(i: int, gate: Semaphore) -> void:
	gate.wait()
	_task(i)


func _task(i: int) -> void:
	_mutex.lock()
	_active += 1
	max_concurrent = maxi(max_concurrent, _active)
	_mutex.unlock()
	var started := Time.get_ticks_usec()
	var outcome: Dictionary = _write_task(i) if _is_writer(i) else _export_task(i)
	var elapsed := Time.get_ticks_usec() - started
	_mutex.lock()
	outcomes[i] = outcome
	durations_us[i] = elapsed
	_active -= 1
	_mutex.unlock()


func _is_writer(i: int) -> bool:
	return with_writers and i % 2 == 0


func _write_task(i: int) -> Dictionary:
	var owner: String = OWNERS[(i >> 1) % OWNERS.size()]
	var run_id := "t%d_%s" % [i, owner]
	var repository := RunRecordRepository.new(root_dir)
	var error := repository.save_new_run(_record(run_id, owner, 1000 + i, FAR_FUTURE))
	return {"role": "writer", "run_id": run_id, "owner": owner, "error": error}


func _export_task(i: int) -> Dictionary:
	var kind := ((i >> 1) if with_writers else i) % EXPORTER_KINDS
	var service: RefCounted = shared_service if shared_service != null else new_service()
	var result: Dictionary = service.export_runs(requester_for(kind), {})
	var slim: Array = result["records"].map(func(r): return {"run_id": r["run_id"], "owner_id": r.get("owner_id", "")})
	return {"role": "export", "kind": kind, "ok": result["ok"], "error": result["error"], "skipped": result["skipped"], "records": slim}


func _owners_visible_to(kind: int) -> Array:
	return OWNERS if kind == KIND_MAINTAINER else [OWNERS[kind]]


func _record(run_id: String, owner_id: String, offset: int, expires_at: int) -> Dictionary:
	return {
		"run_id": run_id,
		"seed": offset,
		"config": {"width": 50, "height": 50},
		"generation_version": 1,
		"created_at": BASE_TIME + offset,
		"expires_at": expires_at,
		"status": "completed",
		"won": true,
		"reason": "boss",
		"owner_id": owner_id,
	}
