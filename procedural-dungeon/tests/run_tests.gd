extends SceneTree
## Headless test runner. Runs every test_* method in TEST_SCRIPTS and exits
## with code 1 if any test fails or raises a script error.
##
## Usage (from the procedural-dungeon/ folder):
##   godot --headless --path . -s res://tests/run_tests.gd
## Set TEST_SHUFFLE_SEED=<int> to run the tests of each file in a shuffled
## order (used to look for order-dependent tests).

const TEST_SCRIPTS := [
	"res://tests/test_dungeon_generator.gd",
	"res://tests/test_run_manager.gd",
	"res://tests/test_run_retry.gd",
]


## Records engine/script errors so a test that crashes mid-way is not reported as passing.
class ErrorCollector extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var collector := ErrorCollector.new()
	OS.add_logger(collector)
	var total := 0
	var failed := 0
	var shuffle_seed := OS.get_environment("TEST_SHUFFLE_SEED")
	if shuffle_seed != "":
		print("Shuffled test order, TEST_SHUFFLE_SEED=%s" % shuffle_seed)
	for path in TEST_SCRIPTS:
		collector.errors.clear()
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			print("FAIL %s (cannot load script)" % path.get_file())
			continue
		var test_names: Array[String] = []
		for method in script.get_script_method_list():
			if method["name"].begins_with("test_"):
				test_names.append(method["name"])
		if shuffle_seed != "":
			var rng := RandomNumberGenerator.new()
			rng.seed = int(shuffle_seed)
			for i in range(test_names.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var swap := test_names[i]
				test_names[i] = test_names[j]
				test_names[j] = swap
		for test_name in test_names:
			total += 1
			collector.errors.clear()
			var suite = script.new()
			suite.before_each()
			suite.call(test_name)
			suite.after_each()
			var problems: Array[String] = []
			problems.append_array(suite.failures)
			for error in collector.errors:
				if not suite.expected_errors.any(func(expected): return error.contains(expected)):
					problems.append("script error: %s" % error)
			if problems.is_empty():
				print("PASS %s::%s" % [path.get_file(), test_name])
			else:
				failed += 1
				print("FAIL %s::%s" % [path.get_file(), test_name])
				for problem in problems:
					print("    - %s" % problem)
	OS.remove_logger(collector)
	print("\n%d tests, %d passed, %d failed" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
