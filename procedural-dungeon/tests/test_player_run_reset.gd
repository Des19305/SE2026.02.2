extends "res://tests/test_case.gd"

const PlayerScript := preload("res://scenes/player/player.gd")
const PlayerRunResetScript := preload("res://scripts/run_management/player_run_reset.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}

var player: Player
var run_manager: Node
var player_run_reset
var records_dir: String


func before_each() -> void:
	player = PlayerScript.new()
	run_manager = RunManagerScript.new()
	records_dir = "user://test_player_run_reset/%d" % Time.get_ticks_usec()
	run_manager.records_dir = records_dir
	player_run_reset = PlayerRunResetScript.new(player, run_manager)


func after_each() -> void:
	player_run_reset = null
	run_manager.free()
	player.free()
	_remove_dir("user://test_player_run_reset")


func test_successful_run_start_resets_player_hp_and_effects() -> void:
	var effect := _max_hp_effect(20, "increase_max_and_current")
	check(player.set_max_hp_effects({"armor_instance_1": effect})["ok"], "add effect")
	check_eq(player.get_current_hp(), 120, "effect increases Current HP")
	check_eq(player.get_max_hp(), 120, "effect increases Max HP")

	var result: Dictionary = run_manager.start_new_run(42, CONFIG)

	check(result["ok"], "run should start: %s" % result["error"])
	check_eq(player.get_current_hp(), 100, "successful run resets Current HP")
	check_eq(player.get_max_hp(), 100, "successful run clears Max HP effects")


func test_failed_run_start_preserves_player_hp_and_effects() -> void:
	var effect := _max_hp_effect(20, "increase_max_and_current")
	check(player.set_max_hp_effects({"armor_instance_1": effect})["ok"], "add effect")
	var invalid_config := CONFIG.duplicate()
	invalid_config["width"] = 201

	var result: Dictionary = run_manager.start_new_run(42, invalid_config)

	check(not result["ok"], "invalid run should fail")
	check_eq(player.get_current_hp(), 120, "failed run preserves Current HP")
	check_eq(player.get_max_hp(), 120, "failed run preserves Max HP effects")


func test_successful_run_start_ends_combat() -> void:
	var combat_events: Array[bool] = []
	player.combat_state_changed.connect(
		func(is_in_combat: bool) -> void:
			combat_events.append(is_in_combat)
	)
	player.start_combat()
	check(player.is_in_combat(), "Player starts Combat")

	var result: Dictionary = run_manager.start_new_run(42, CONFIG)

	check(result["ok"], "run should start: %s" % result["error"])
	check(not player.is_in_combat(), "successful run reset ends Combat")
	check_eq(combat_events, [true, false], "run reset emits one Combat exit transition")


func test_failed_run_start_preserves_combat_state() -> void:
	player.start_combat()
	var invalid_config := CONFIG.duplicate()
	invalid_config["width"] = 201

	var result: Dictionary = run_manager.start_new_run(42, invalid_config)

	check(not result["ok"], "invalid run should fail")
	check(player.is_in_combat(), "failed run preserves Combat state")


func _max_hp_effect(value: int, hp_behavior: String) -> Dictionary:
	return {
		"type": "stat",
		"stat": "max_hp",
		"operation": "add",
		"value": value,
		"hp_behavior": hp_behavior,
	}


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
