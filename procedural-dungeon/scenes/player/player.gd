class_name Player
extends Node2D
## Grid-based player movement with wall collision.
## Add the player as a child of the DungeonRenderer so both share the same local space.

signal moved(cell: Vector2i)

const MOVE_INTERVAL: float = 0.12  # seconds between steps while a key is held
const BODY_COLOR := Color("#ebcb8b")

var grid: DungeonGrid = null
var cell: Vector2i = Vector2i.ZERO
var _cooldown: float = 0.0


## Places the player on grid.start_cell. Returns {"ok": bool, "error": String}.
func setup(new_grid: DungeonGrid) -> Dictionary:
	if new_grid == null:
		return {"ok": false, "error": "grid is null"}
	if not new_grid.is_walkable(new_grid.start_cell):
		return {"ok": false, "error": "start cell is not walkable"}
	grid = new_grid
	cell = grid.start_cell
	position = grid.cell_center(cell)
	queue_redraw()
	return {"ok": true, "error": ""}


## Tries to move one orthogonal step. The grid decides whether the target is free.
## Returns {"ok": bool, "cell": Vector2i, "error": String}; on failure nothing changes.
func try_move(direction: Vector2i) -> Dictionary:
	if grid == null:
		return {"ok": false, "cell": cell, "error": "player is not set up"}
	if absi(direction.x) + absi(direction.y) != 1:
		return {"ok": false, "cell": cell, "error": "direction must be one orthogonal step"}
	var target := cell + direction
	if not grid.is_walkable(target):
		return {"ok": false, "cell": cell, "error": "blocked"}
	cell = target
	position = grid.cell_center(cell)
	moved.emit(cell)
	return {"ok": true, "cell": cell, "error": ""}


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0:
		return
	var direction := _read_direction()
	if direction != Vector2i.ZERO:
		try_move(direction)
		_cooldown = MOVE_INTERVAL


func _read_direction() -> Vector2i:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		return Vector2i.UP
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		return Vector2i.DOWN
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		return Vector2i.LEFT
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _draw() -> void:
	var side := DungeonGrid.CELL_SIZE * 0.6
	draw_rect(Rect2(Vector2.ONE * (-side * 0.5), Vector2.ONE * side), BODY_COLOR)
