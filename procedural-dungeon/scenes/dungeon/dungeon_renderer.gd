class_name DungeonRenderer
extends Node2D
## Draws a DungeonGrid. It only reads the grid: all walkable/wall decisions come from
## DungeonGrid.is_walkable(), the same call the player's collision uses.

const FLOOR_COLOR := Color("#3b4252")
const WALL_COLOR := Color("#11141a")
const START_COLOR := Color("#a3be8c")

var grid: DungeonGrid = null


func setup(new_grid: DungeonGrid) -> void:
	grid = new_grid
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	var size := Vector2.ONE * DungeonGrid.CELL_SIZE
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var color := FLOOR_COLOR if grid.is_walkable(cell) else WALL_COLOR
			draw_rect(Rect2(Vector2(cell * DungeonGrid.CELL_SIZE), size), color)
	# Mark the start cell so the spawn point is easy to verify by eye.
	draw_rect(Rect2(Vector2(grid.start_cell * DungeonGrid.CELL_SIZE) + size * 0.4, size * 0.2), START_COLOR)
