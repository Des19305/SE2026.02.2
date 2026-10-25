extends "res://tests/test_case.gd"
## Unit, property and determinism tests for the generator (architecture.md §6.5, §8).

const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}


func test_same_seed_and_config_produce_identical_layout() -> void:
	var first := DungeonGenerator.generate_dungeon(12345, CONFIG)
	var second := DungeonGenerator.generate_dungeon(12345, CONFIG)
	check(first["ok"], "first generation failed: %s" % first["error"])
	check_eq(second["tiles"], first["tiles"], "tiles")
	check_eq(second["rooms"], first["rooms"], "rooms")
	check_eq(second["start_cell"], first["start_cell"], "start_cell")
	check_eq(second["boss_cell"], first["boss_cell"], "boss_cell")


func test_result_respects_config() -> void:
	var dungeon := DungeonGenerator.generate_dungeon(7, CONFIG)
	check(dungeon["ok"], "generation failed: %s" % dungeon["error"])
	check_eq(dungeon["seed"], 7, "seed")
	check_eq(dungeon["tiles"].size(), CONFIG["height"], "row count")
	check_eq(dungeon["tiles"][0].size(), CONFIG["width"], "column count")
	var room_count: int = dungeon["rooms"].size()
	check(room_count >= CONFIG["min_rooms"] and room_count <= CONFIG["max_rooms"], "room count %d out of range" % room_count)
	for room in dungeon["rooms"]:
		var size: Vector2i = room["size"]
		check(size.x >= CONFIG["min_room_size"] and size.x <= CONFIG["max_room_size"], "room width %d out of range" % size.x)
		check(size.y >= CONFIG["min_room_size"] and size.y <= CONFIG["max_room_size"], "room height %d out of range" % size.y)


func test_many_seeds_produce_valid_dungeons() -> void:
	for seed_value in range(0, 200):
		var dungeon := DungeonGenerator.generate_dungeon(seed_value, CONFIG)
		if not dungeon["ok"]:
			failures.append("seed %d config %s: %s" % [seed_value, CONFIG, dungeon["error"]])
			continue
		var check_result := DungeonGenerator.validate_dungeon(dungeon)
		check(check_result["valid"], "seed %d config %s: %s" % [seed_value, CONFIG, check_result["errors"]])


func test_impossible_config_returns_explicit_failure() -> void:
	var config := CONFIG.duplicate()
	config["width"] = 20
	config["height"] = 20
	config["min_rooms"] = 12
	config["max_room_size"] = 5
	var dungeon := DungeonGenerator.generate_dungeon(1, config)
	check(not dungeon["ok"], "expected failure")
	check(dungeon["error"].begins_with("No valid dungeon after 10 attempts"), "error was: %s" % dungeon["error"])
	check(dungeon["tiles"].is_empty(), "failed result must not carry a layout")


func test_validator_rejects_unreachable_boss() -> void:
	var dungeon := DungeonGenerator.generate_dungeon(3, CONFIG)
	var tiles: Array = dungeon["tiles"]
	var boss: Vector2i = dungeon["boss_cell"]
	# Wall off the boss cell completely.
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell: Vector2i = boss + step
		tiles[cell.y][cell.x] = DungeonGenerator.WALL
	var result := DungeonGenerator.validate_dungeon(dungeon)
	check(not result["valid"], "expected invalid dungeon")
	check(result["errors"].has("boss_cell is not reachable from start_cell"), "errors were: %s" % [result["errors"]])


func test_validator_rejects_wrong_grid_size() -> void:
	var dungeon := DungeonGenerator.generate_dungeon(3, CONFIG)
	dungeon["tiles"].pop_back()
	var result := DungeonGenerator.validate_dungeon(dungeon)
	check(not result["valid"], "expected invalid dungeon")
	check_eq(result["errors"], ["grid has 49 rows, expected 50"], "errors")
