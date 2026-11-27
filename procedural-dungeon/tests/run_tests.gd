
extends SceneTree
## Headless test runner.
## Supports both TestCase-based tests and RefCounted tests returning String.
##
## Usage:
##   godot --headless --path . --script res://tests/run_tests.gd

const TEST_DIR := "res://tests/"


## Records engine/script errors so a test that crashes is not reported as passing.
class ErrorCollector extends Logger:
        var errors: Array[String] = []

        func _log_error(function: String, file: String, line: int, code: String, rationale: String,
                        _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
                errors.append("%s (%s:%d in %s)" % [
                        rationale if rationale != "" else code,
                        file,
                        line,
                        function
                ])

        func _log_message(_message: String, _error: bool) -> void:
                pass


func _has_property(object: Object, property_name: String) -> bool:
        for property in object.get_property_list():
                if property["name"] == property_name:
                        return true
        return false


func _init() -> void:
        call_deferred("_run_tests")


func _run_tests() -> void:
        var collector := ErrorCollector.new()
        OS.add_logger(collector)

        var total := 0
        var failed := 0
        var dir := DirAccess.open(TEST_DIR)

        if dir == null:
                print("FAIL: Cannot open %s" % TEST_DIR)
                OS.remove_logger(collector)
                quit(1)
                return

        # Automatically discover test scripts.
        var files: Array[String] = []
        for file_name in dir.get_files():
                if file_name.begins_with("test_") and file_name.ends_with(".gd"):
                        files.append(TEST_DIR + file_name)
        files.sort()

        for path in files:
                var script: GDScript = load(path)

                if script == null or not script.can_instantiate():
                        total += 1
                        failed += 1
                        print("FAIL %s (cannot load script)" % path.get_file())
                        continue

                for method in script.get_script_method_list():
                        var test_name: String = method["name"]

                        if not test_name.begins_with("test_"):
                                continue

                        total += 1
                        collector.errors.clear()

                        var suite = script.new()
                        var test_result: Variant = null

                        # TestCase-based suites use setup and teardown hooks.
                        if suite.has_method("before_each"):
                                suite.call("before_each")

                        test_result = await suite.call(test_name)

                        if suite.has_method("after_each"):
                                suite.call("after_each")

                        var problems: Array[String] = []

                        # RefCounted tests report failure through a non-empty String.
                        if test_result is String and not test_result.is_empty():
                                problems.append(test_result)

                        # TestCase-based suites report failures through this property.
                        if _has_property(suite, "failures"):
                                var suite_failures: Variant = suite.get("failures")
                                if suite_failures is Array:
                                        for problem in suite_failures:
                                                problems.append(str(problem))

                        # Ignore only errors explicitly expected by the current test.
                        var expected_errors: Array = []
                        if _has_property(suite, "expected_errors"):
                                var value: Variant = suite.get("expected_errors")
                                if value is Array:
                                        expected_errors = value

                        for error in collector.errors:
                                var expected := false

                                for expected_error in expected_errors:
                                        if error.contains(str(expected_error)):
                                                expected = true
                                                break

                                if not expected:
                                        problems.append("script error: %s" % error)

                        if problems.is_empty():
                                print("PASS %s::%s" % [path.get_file(), test_name])
                        else:
                                failed += 1
                                print("FAIL %s::%s" % [path.get_file(), test_name])

                                for problem in problems:
                                        print("    - %s" % problem)

        OS.remove_logger(collector)

        print("\n%d tests, %d passed, %d failed" % [
                total,
                total - failed,
                failed
        ])

        quit(1 if failed > 0 else 0)
