extends SceneTree

const RunManager := preload("res://scripts/run_management/run_manager.gd")
const TASK_COUNT := 120
const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}


func _init() -> void:
	var run_manager := RunManager.new()
	var records_dir := "user://vt110_loadtest_a8b09ef_%d" % Time.get_ticks_usec()
	run_manager.records_dir = records_dir
	run_manager.clock = func() -> int: return 1800000000
	var started_events: Array = []
	run_manager.run_started.connect(func(_seed: int, _dungeon: Dictionary) -> void: started_events.append(true))

	var service_samples_usec: Array[int] = []
	var queue_completion_samples_usec: Array[int] = []
	var errors: Array[String] = []
	var succeeded := 0
	var batch_started_usec := Time.get_ticks_usec()
	for task_index in range(TASK_COUNT):
		var task_started_usec := Time.get_ticks_usec()
		var result: Dictionary = run_manager.start_new_run(
			"vt110-load-%03d" % task_index,
			340,
			CONFIG
		)
		var task_elapsed_usec := Time.get_ticks_usec() - task_started_usec
		service_samples_usec.append(task_elapsed_usec)
		queue_completion_samples_usec.append(Time.get_ticks_usec() - batch_started_usec)
		if result.get("ok", false):
			succeeded += 1
			run_manager.end_run(false, "load-test-queue")
		else:
			errors.append("task %d: %s" % [task_index, result.get("error", "unknown error")])

	var total_elapsed_usec := Time.get_ticks_usec() - batch_started_usec
	var record_count := _record_count(records_dir)
	print("MODE=single_process_serial_queue; all logical tasks submitted at batch start; RunManager calls are sequential")
	print("TASKS=%d SUCCEEDED=%d FAILED=%d RUN_STARTED=%d RECORDS=%d" % [TASK_COUNT, succeeded, TASK_COUNT - succeeded, started_events.size(), record_count])
	print("START_SERVICE_US p50=%d p95=%d p99=%d" % [
		_percentile(service_samples_usec, 0.50),
		_percentile(service_samples_usec, 0.95),
		_percentile(service_samples_usec, 0.99),
	])
	print("QUEUED_RESPONSE_US p50=%d p95=%d p99=%d" % [
		_percentile(queue_completion_samples_usec, 0.50),
		_percentile(queue_completion_samples_usec, 0.95),
		_percentile(queue_completion_samples_usec, 0.99),
	])
	print("TOTAL_BATCH_US=%d" % total_elapsed_usec)
	for task_index in range(TASK_COUNT):
		print("TASK %03d start_us=%d queued_response_us=%d" % [
			task_index,
			service_samples_usec[task_index],
			queue_completion_samples_usec[task_index],
		])
	for error_message in errors:
		printerr("ERROR " + error_message)

	var measurement_valid := succeeded == TASK_COUNT and started_events.size() == TASK_COUNT and record_count == TASK_COUNT
	run_manager.free()
	_remove_dir(records_dir)
	quit(0 if measurement_valid else 1)


func _percentile(samples: Array[int], percentile_value: float) -> int:
	if samples.is_empty():
		return 0
	var sorted_samples: Array[int] = samples.duplicate()
	sorted_samples.sort()
	var rank := int(ceil(percentile_value * sorted_samples.size()))
	return sorted_samples[clampi(rank - 1, 0, sorted_samples.size() - 1)]


func _record_count(records_dir: String) -> int:
	var dir := DirAccess.open(records_dir)
	if dir == null:
		return 0
	var count := 0
	for file_name in dir.get_files():
		if file_name.ends_with(".json") and file_name != "last_run.json":
			count += 1
	return count


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for subdirectory in dir.get_directories():
		_remove_dir(path.path_join(subdirectory))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))