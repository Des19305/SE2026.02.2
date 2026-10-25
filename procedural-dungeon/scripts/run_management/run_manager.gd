extends Node
## Run Management: starts runs, retains seed + config for replay and stores the
## run record (AC-SEED-01). Public API follows docs/architecture.md §7.3.

signal run_started(seed: int, dungeon: Dictionary)
signal run_ended(won: bool, reason: String)

const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")

const RECORD_RETENTION_DAYS := 70
const SECONDS_PER_DAY := 86400
const GENERATION_VERSION := 1
const LAST_RUN_FILE := "last_run.json"

var records_dir := "user://runs"
var current_run := {}
var last_run := {}


func start_new_run(seed: int, config: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": "", "seed": seed, "dungeon": {}}

	if current_run.get("status", "") == "in_progress":
		result["error"] = "A run is already in progress"
		return result
	if seed < 0:
		result["error"] = "Seed must be non-negative"
		return result
	for key in ["width", "height", "min_rooms", "max_rooms", "min_room_size", "max_room_size"]:
		if not config.has(key):
			result["error"] = "Missing config key: %s" % key
			return result
		if typeof(config[key]) != TYPE_INT:
			result["error"] = "Config key %s must be an integer" % key
			return result
	if config["width"] < 20 or config["width"] > 200 or config["height"] < 20 or config["height"] > 200:
		result["error"] = "Dungeon size must be between 20 and 200 tiles"
		return result
	if config["min_rooms"] < 2 or config["min_rooms"] > config["max_rooms"]:
		result["error"] = "Room count range is invalid"
		return result
	if config["min_room_size"] < 3 or config["min_room_size"] > config["max_room_size"]:
		result["error"] = "Room size range is invalid"
		return result
	if config["max_room_size"] * 2 > mini(config["width"], config["height"]):
		result["error"] = "Rooms do not fit in the dungeon"
		return result

	var run_config := config.duplicate(true)
	if not run_config.has("max_attempts"):
		run_config["max_attempts"] = DungeonGenerator.DEFAULT_MAX_ATTEMPTS
	var dungeon := DungeonGenerator.generate_dungeon(seed, run_config)
	if not dungeon["ok"]:
		result["error"] = "Generation failed: %s" % dungeon["error"]
		return result
	var check := DungeonGenerator.validate_dungeon(dungeon)
	if not check["valid"]:
		result["error"] = "Generated dungeon is invalid: %s" % ", ".join(check["errors"])
		return result

	var now := int(Time.get_unix_time_from_system())
	var run_id := "%d_%d" % [now, seed]
	var record := {
		"run_id": run_id,
		"seed": seed,
		"config": run_config,
		"generation_version": GENERATION_VERSION,
		"created_at": now,
		"expires_at": now + RECORD_RETENTION_DAYS * SECONDS_PER_DAY,
		"status": "in_progress",
		"won": false,
		"reason": "",
	}

	var err := DirAccess.make_dir_recursive_absolute(records_dir)
	if err != OK:
		result["error"] = "Cannot save run record: %s" % error_string(err)
		return result
	var dir := DirAccess.open(records_dir)
	if dir != null:
		for file_name in dir.get_files():
			if not file_name.ends_with(".json") or file_name == LAST_RUN_FILE:
				continue
			var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(records_dir.path_join(file_name)))
			if old is Dictionary and int(old.get("expires_at", 0)) <= now:
				dir.remove(file_name)
	var file := FileAccess.open(records_dir.path_join(run_id + ".json"), FileAccess.WRITE)
	if file == null:
		result["error"] = "Cannot save run record: %s" % error_string(FileAccess.get_open_error())
		return result
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	var last_file := FileAccess.open(records_dir.path_join(LAST_RUN_FILE), FileAccess.WRITE)
	if last_file == null:
		result["error"] = "Cannot save run record: %s" % error_string(FileAccess.get_open_error())
		return result
	last_file.store_string(JSON.stringify(record, "\t"))
	last_file.close()

	current_run = record
	last_run = record
	result["ok"] = true
	result["dungeon"] = dungeon
	run_started.emit(seed, dungeon)
	return result


## Starts a fresh run with the previous run's seed and configuration.
## Does not restore health, inventory, enemies or combat progress.
func replay_last_run() -> Dictionary:
	if last_run.is_empty():
		return {"ok": false, "error": "No previous run to replay", "seed": 0, "dungeon": {}}
	return start_new_run(last_run["seed"], last_run["config"])


func end_run(won: bool, reason: String) -> void:
	if current_run.is_empty():
		return
	current_run["status"] = "completed"
	current_run["won"] = won
	current_run["reason"] = reason
	var file := FileAccess.open(records_dir.path_join(current_run["run_id"] + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(current_run, "\t"))
		file.close()
	current_run = {}
	run_ended.emit(won, reason)
