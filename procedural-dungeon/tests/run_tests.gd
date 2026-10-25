extends SceneTree

const TEST_DIR := "res://tests/"


func _initialize() -> void:
    var total := 0
    var failures := 0

    var dir := DirAccess.open(TEST_DIR)
    if dir == null:
        push_error("Cannot open %s" % TEST_DIR)
        quit(1)
        return

    var files: Array = []
    for f in dir.get_files():
        if f.begins_with("test_") and f.ends_with(".gd"):
            files.append(f)
    files.sort()

    for f in files:
        var script: GDScript = load(TEST_DIR + f)
        var suite = script.new()
        for m in suite.get_method_list():
            var method_name: String = m["name"]
            if not method_name.begins_with("test_"):
                continue
            total += 1
            var result = suite.call(method_name)
            if result is String and result != "":
                failures += 1
                print("FAIL  %s::%s -> %s" % [f, method_name, result])
            else:
                print("PASS  %s::%s" % [f, method_name])

    print("\n%d tests, %d failed" % [total, failures])
    quit(1 if failures > 0 else 0)