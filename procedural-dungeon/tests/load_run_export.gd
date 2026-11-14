extends SceneTree
## VT-107 load harness (TC-18): N concurrent export/save tasks against real files,
## repeated several times, with per-task latency percentiles and the invariant checks
## of the concurrency tests. Exit code 1 if p95 exceeds the target or an invariant fails.
##
## Usage (from procedural-dungeon/):
##   godot --headless --path . -s res://tests/load_run_export.gd -- --tasks=200 --repeats=5
##
## What this measures: task latency inside one process, on the local disk, with one
## Thread per task. It is NOT network latency and NOT the game's own load.

const Workload := preload("res://tests/workload_run_export.gd")
const TARGET_P95_S := 5.0


func _init() -> void:
	var tasks := 200
	var repeats := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tasks="):
			tasks = int(arg.get_slice("=", 1))
		elif arg.begins_with("--repeats="):
			repeats = int(arg.get_slice("=", 1))
	print("VT-107 load harness: %d concurrent tasks x %d runs (half writers, half exporters)" % [tasks, repeats])
	print("environment: %s, %d logical CPU(s), Godot %s" % [OS.get_name(), OS.get_processor_count(), Engine.get_version_info()["string"]])

	var worst_p95_us := 0
	var all_ok := true
	for run_index in repeats:
		var workload := Workload.new()
		workload.root_dir = "user://test_run_export/load_%d" % Time.get_ticks_usec()
		workload.seed_records()
		var started := Time.get_ticks_usec()
		workload.run(tasks)
		var total_ms := (Time.get_ticks_usec() - started) / 1000.0
		var problems := workload.violations()
		problems.append_array(workload.final_violations())
		var skipped := 0
		for outcome in workload.outcomes:
			if outcome["role"] == "export":
				skipped += outcome["skipped"]
		var p50 := Workload.percentile_us(workload.durations_us, 50.0)
		var p95 := Workload.percentile_us(workload.durations_us, 95.0)
		var p99 := Workload.percentile_us(workload.durations_us, 99.0)
		var slowest := Workload.percentile_us(workload.durations_us, 100.0)
		worst_p95_us = maxi(worst_p95_us, p95)
		print("run %d: total %.0f ms | task ms p50 %.1f p95 %.1f p99 %.1f max %.1f | max overlap %d | unreadable files skipped %d | invariant violations %d" % [
			run_index + 1, total_ms, p50 / 1000.0, p95 / 1000.0, p99 / 1000.0, slowest / 1000.0,
			workload.max_concurrent, skipped, problems.size()])
		for problem in problems.slice(0, 5):
			print("    VIOLATION: %s" % problem)
		all_ok = all_ok and problems.is_empty()
		Workload.remove_dir(workload.root_dir)

	var worst_p95_s := worst_p95_us / 1_000_000.0
	var within := worst_p95_s <= TARGET_P95_S
	print("worst p95 over %d runs = %.3f s; target <= %.1f s: %s; invariants: %s" % [
		repeats, worst_p95_s, TARGET_P95_S, "PASS" if within else "FAIL", "held" if all_ok else "VIOLATED"])
	quit(0 if within and all_ok else 1)
