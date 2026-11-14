extends "res://tests/test_case.gd"
## VT-107 concurrency testing (docs/vt107/02-test-strategy.md, section 4):
## TC-15, TC-16, TC-17, TC-18. Safety properties that must hold for every
## interleaving; the real RunRecordRepository and real files are used throughout.
## Assertions run on the main thread after wait_for_group_task_completion.

const Workload := preload("res://tests/workload_run_export.gd")
const RunExportService := preload("res://scripts/run_management/run_export_service.gd")

var root_dir: String


func before_each() -> void:
	root_dir = "user://test_run_export/conc_%d" % Time.get_ticks_usec()


func after_each() -> void:
	Workload.remove_dir(root_dir)


# --- TC-15: 100 writers and 100 exporters at once ---------------------------

func test_mixed_writers_and_exporters_never_leak_or_duplicate() -> void:
	expect_error("Parse JSON failed")  # a file caught mid-write is skipped, by design
	var workload := _workload()
	workload.seed_records()

	workload.run(200)

	_check_overlap(workload)
	_report(workload.violations())
	_report(workload.final_violations())


# --- TC-16: one shared service instance, 200 exporters ----------------------

func test_shared_service_instance_keeps_requesters_apart() -> void:
	var workload := _workload()
	workload.with_writers = false
	workload.seed_records()
	workload.shared_service = workload.new_service()

	workload.run(200)

	_check_overlap(workload)
	_report(workload.violations())
	# No writers, so the result of every exporter is exactly known.
	for i in workload.outcomes.size():
		var outcome: Dictionary = workload.outcomes[i]
		var expected: Array = []
		if outcome["kind"] == Workload.KIND_MAINTAINER:
			for owner in Workload.OWNERS:
				for index in Workload.SEED_RECORDS_PER_OWNER:
					expected.append(Workload.seed_id(owner, index))
		elif outcome["kind"] != Workload.KIND_INVALID:
			for index in Workload.SEED_RECORDS_PER_OWNER:
				expected.append(Workload.seed_id(Workload.OWNERS[outcome["kind"]], index))
		var actual: Array = outcome["records"].map(func(r): return r["run_id"])
		actual.sort()
		expected.sort()
		check_eq(actual, expected, "task %d (kind %d) exported ids" % [i, outcome["kind"]])
		check_eq(outcome["skipped"], 0, "task %d skipped" % i)


# --- TC-17: exporters read while writers prune expired files ------------------

func test_export_while_expired_files_are_pruned() -> void:
	# A file can vanish between listing and reading, or be caught mid-write.
	expect_error("Parse JSON failed")
	expect_error("Cannot open file")
	var workload := _workload()
	workload.seed_records(20)
	check(FileAccess.file_exists(root_dir.path_join("exp_0.json")), "precondition: expired files are on disk")

	workload.run(200)

	_check_overlap(workload)
	_report(workload.violations())
	_report(workload.final_violations())
	check(not FileAccess.file_exists(root_dir.path_join("exp_0.json")), "writers pruned the expired files")


# --- TC-18: p95 at 200 concurrent tasks against the 5.0 s target -------------

func test_200_concurrent_tasks_p95_is_within_5_seconds() -> void:
	expect_error("Parse JSON failed")
	var workload := _workload()
	workload.seed_records()

	workload.run(200)

	var p95_s := Workload.percentile_us(workload.durations_us, 95.0) / 1_000_000.0
	print("    TC-18: 200 tasks, max overlap %d, p95 = %.3f s (target <= 5.0 s)" % [workload.max_concurrent, p95_s])
	_check_overlap(workload)
	check(p95_s <= 5.0, "p95 %.3f s exceeds 5.0 s" % p95_s)
	_report(workload.violations())


func _workload() -> RefCounted:
	var workload := Workload.new()
	workload.root_dir = root_dir
	return workload


## A concurrency test that never overlapped proves nothing (WorkerThreadPool on a
## 1-CPU machine ran tasks one after another), so the overlap itself is asserted.
func _check_overlap(workload: RefCounted) -> void:
	check(workload.max_concurrent >= 2, "tasks never overlapped (max_concurrent = %d)" % workload.max_concurrent)


func _report(problems: Array[String]) -> void:
	for problem in problems.slice(0, 10):
		check(false, problem)
	if problems.size() > 10:
		check(false, "... and %d more violations" % (problems.size() - 10))
