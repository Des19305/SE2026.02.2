class_name DungeonGrid
extends RefCounted
## Read-only tile grid built from a generator result (docs/architecture.md, section 7.2).
##
## This is the single source of truth for BOTH rendering and collision, so the
## picture and the walkable area cannot drift apart. It keeps its own copy of the
## tiles, so nobody can change the layout by editing the generator's dictionary.

const WALL: int = 0
const FLOOR: int = 1
const CELL_SIZE: int = 32

var width: int = 0
var height: int = 0
var start_cell: Vector2i = Vector2i.ZERO
var _cells: PackedByteArray = PackedByteArray()


## Builds a grid from a dungeon dictionary returned by generate_dungeon().
## Returns {"ok": bool, "error": String, "grid": DungeonGrid or null}.
## Convention used here: tiles[y][x] (row-major) -- confirm with the Generation owner.
static func from_dungeon(dungeon: Dictionary) -> Dictionary:
	for key in ["ok", "width", "height", "tiles", "start_cell"]:
		if not dungeon.has(key):
			return _fail("missing key: %s" % key)
	if dungeon["ok"] != true:
		return _fail("dungeon is not valid: %s" % str(dungeon.get("error", "")))
	if typeof(dungeon["width"]) != TYPE_INT or typeof(dungeon["height"]) != TYPE_INT:
		return _fail("width and height must be int")
	if typeof(dungeon["start_cell"]) != TYPE_VECTOR2I:
		return _fail("start_cell must be Vector2i")
	if not (dungeon["tiles"] is Array):
		return _fail("tiles must be an Array")

	var w: int = dungeon["width"]
	var h: int = dungeon["height"]
	var tiles: Array = dungeon["tiles"]
	if w <= 0 or h <= 0:
		return _fail("width and height must be positive")
	if tiles.size() != h:
		return _fail("tiles has %d rows, expected %d" % [tiles.size(), h])

	var grid := DungeonGrid.new()
	grid.width = w
	grid.height = h
	grid._cells.resize(w * h)
	for y in range(h):
		var row = tiles[y]
		if not (row is Array) or row.size() != w:
			return _fail("row %d must be an Array of %d tiles" % [y, w])
		for x in range(w):
			var value = row[x]
			if typeof(value) != TYPE_INT or (value != WALL and value != FLOOR):
				return _fail("invalid tile at (%d, %d): %s" % [x, y, str(value)])
			grid._cells[y * w + x] = value

	grid.start_cell = dungeon["start_cell"]
	if not grid.is_walkable(grid.start_cell):
		return _fail("start_cell %s is not a walkable tile" % str(grid.start_cell))
	return {"ok": true, "error": "", "grid": grid}


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Out-of-bounds cells are never walkable.
func is_walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and _cells[cell.y * width + cell.x] == FLOOR


## Centre of a cell in the local space of the node that draws the grid.
func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "grid": null}
