extends "res://tests/test_case.gd"
## Integration of Generation (issue #4) with DungeonGrid, DungeonRenderer and
## Player (issue #5), using real generate_dungeon() output instead of the 5x5
## fixture (review on PR #7, point 1). For many seeds and both configs:
## - the grid built from the dungeon matches tiles[y][x] cell by cell,
## - renderer and player share that grid and the player spawns on start_cell,
## - the player can walk from start_cell to boss_cell with try_move,
## - every step into a wall next to the path is refused.

const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")
const GridScript := preload("res://scenes/dungeon/dungeon_grid.gd")
const RendererScript := preload("res://scenes/dungeon/dungeon_renderer.gd")
const PlayerScript := preload("res://scenes/player/player.gd")

## Default config, architecture.md §5.2.
const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}
## Debug config also used in test_dungeon_generator.gd.
const DEBUG_CONFIG := {
	"width": 30,
	"height": 30,
	"min_rooms": 2,
	"max_rooms": 4,
	"min_room_size": 3,
	"max_room_size": 6,
}
const SEEDS := [0, 1, 7, 42, 99, 2024, 12345, 65535, 999999, 2147483647]
const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


func test_grid_matches_generated_tiles() -> void:
	for config in [CONFIG, DEBUG_CONFIG]:
		for seed_value in SEEDS:
			var dungeon := DungeonGenerator.generate_dungeon(seed_value, config)
			var label := _label(seed_value, config)
			if not _check_generated(dungeon, label):
				continue
			var built: Dictionary = GridScript.from_dungeon(dungeon)
			if not built["ok"]:
				check(false, "%s: from_dungeon failed: %s" % [label, built["error"]])
				continue
			var grid: DungeonGrid = built["grid"]
			check_eq(Vector2i(grid.width, grid.height), Vector2i(config["width"], config["height"]), "%s size" % label)
			check_eq(grid.start_cell, dungeon["start_cell"], "%s start_cell" % label)
			var mismatch := _first_mismatch(grid, dungeon["tiles"])
			check(mismatch == Vector2i(-1, -1), "%s: grid differs from tiles at %s" % [label, mismatch])


func test_player_spawns_on_start_cell_of_generated_dungeon() -> void:
	for seed_value in SEEDS:
		var dungeon := DungeonGenerator.generate_dungeon(seed_value, CONFIG)
		var label := _label(seed_value, CONFIG)
		if not _check_generated(dungeon, label):
			continue
		var grid: DungeonGrid = GridScript.from_dungeon(dungeon)["grid"]
		var renderer: DungeonRenderer = RendererScript.new()
		var player: Player = PlayerScript.new()
		renderer.setup(grid)
		renderer.add_child(player)
		var result := player.setup(grid)
		check(result["ok"], "%s: player setup failed: %s" % [label, result["error"]])
		check_eq(player.cell, dungeon["start_cell"], "%s player cell" % label)
		check_eq(player.position, grid.cell_center(dungeon["start_cell"]), "%s player position" % label)
		check(renderer.grid == player.grid, "%s: renderer and player use different grids" % label)
		renderer.free()


func test_player_walks_to_boss_and_walls_block() -> void:
	for config in [CONFIG, DEBUG_CONFIG]:
		for seed_value in SEEDS:
			var dungeon := DungeonGenerator.generate_dungeon(seed_value, config)
			var label := _label(seed_value, config)
			if not _check_generated(dungeon, label):
				continue
			var grid: DungeonGrid = GridScript.from_dungeon(dungeon)["grid"]
			var player: Player = PlayerScript.new()
			player.setup(grid)
			var path := _path(grid, dungeon["start_cell"], dungeon["boss_cell"])
			check(not path.is_empty(), "%s: no path from start to boss on the grid" % label)
			for target in path:
				_check_walls_block(player, grid, label)
				var result := player.try_move(target - player.cell)
				if not result["ok"]:
					check(false, "%s: move to %s refused: %s" % [label, target, result["error"]])
					break
				if not grid.is_walkable(player.cell):
					check(false, "%s: player stands on a wall at %s" % [label, player.cell])
					break
			check_eq(player.cell, dungeon["boss_cell"], "%s: player did not reach boss_cell" % label)
			player.free()


# --- helpers ----------------------------------------------------------------

func _label(seed_value: int, config: Dictionary) -> String:
	return "seed %d, %dx%d" % [seed_value, config["width"], config["height"]]


func _check_generated(dungeon: Dictionary, label: String) -> bool:
	check(dungeon["ok"], "%s: generation failed: %s" % [label, dungeon.get("error_message", "")])
	return dungeon["ok"]


## Returns (-1, -1) when every cell of grid matches tiles[y][x].
func _first_mismatch(grid: DungeonGrid, tiles: Array) -> Vector2i:
	for y in grid.height:
		for x in grid.width:
			if grid.is_walkable(Vector2i(x, y)) != (tiles[y][x] == DungeonGenerator.FLOOR):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Every neighbour of the player that is a wall must refuse the move and leave
## the player where it is.
func _check_walls_block(player: Player, grid: DungeonGrid, label: String) -> void:
	var here := player.cell
	for direction in DIRECTIONS:
		if grid.is_walkable(here + direction):
			continue
		var result := player.try_move(direction)
		if result["ok"] or player.cell != here:
			check(false, "%s: walked into wall at %s" % [label, here + direction])
			return


## Cells from start (exclusive) to goal (inclusive) along a shortest 4-way path
## on the grid; empty when goal is unreachable.
func _path(grid: DungeonGrid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var came_from := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == goal:
			break
		for direction in DIRECTIONS:
			var next: Vector2i = cell + direction
			if grid.is_walkable(next) and not came_from.has(next):
				came_from[next] = cell
				queue.append(next)
	var path: Array[Vector2i] = []
	if not came_from.has(goal):
		return path
	var step := goal
	while step != start:
		path.push_front(step)
		step = came_from[step]
	return path
