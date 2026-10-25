extends RefCounted
## Seeded BSP dungeon generator.
##
## Produces pure data (no scenes or nodes) so the layout can be validated and
## tested headlessly. Public API follows docs/architecture.md §7.2.

const WALL := 0
const FLOOR := 1
const DEFAULT_MAX_ATTEMPTS := 10
## Each retry derives its RNG seed from the run seed so retries stay reproducible.
const ATTEMPT_SEED_STRIDE := 1_000_003


## Generates a dungeon for [param dungeon_seed] and [param config].
## Returns [code]ok = false[/code] with an error message when no valid layout
## is produced within [code]config.max_attempts[/code] attempts.
static func generate_dungeon(dungeon_seed: int, config: Dictionary) -> Dictionary:
	var max_attempts: int = config.get("max_attempts", DEFAULT_MAX_ATTEMPTS)
	var attempt_errors: Array[String] = []
	for attempt in max_attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = dungeon_seed + attempt * ATTEMPT_SEED_STRIDE
		var dungeon := _generate_once(rng, dungeon_seed, config)
		if not dungeon["ok"]:
			attempt_errors.append("attempt %d: %s" % [attempt, dungeon["error"]])
			continue
		var check := validate_dungeon(dungeon)
		if check["valid"]:
			dungeon["attempts"] = attempt + 1
			return dungeon
		attempt_errors.append("attempt %d: %s" % [attempt, "; ".join(check["errors"])])
	return {
		"ok": false,
		"error": "No valid dungeon after %d attempts (%s)" % [max_attempts, " | ".join(attempt_errors)],
		"seed": dungeon_seed,
		"width": config.get("width", 0),
		"height": config.get("height", 0),
		"tiles": [],
		"rooms": [],
		"start_cell": Vector2i.ZERO,
		"boss_cell": Vector2i.ZERO,
	}


## Checks grid dimensions, room and cell bounds, walkable start/boss cells,
## boss reachability and that no walkable area is cut off from the start.
static func validate_dungeon(dungeon: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key in ["width", "height", "tiles", "rooms", "start_cell", "boss_cell"]:
		if not dungeon.has(key):
			errors.append("missing key: %s" % key)
	if not errors.is_empty():
		return {"valid": false, "errors": errors}

	var width: int = dungeon["width"]
	var height: int = dungeon["height"]
	var tiles: Array = dungeon["tiles"]
	if tiles.size() != height:
		errors.append("grid has %d rows, expected %d" % [tiles.size(), height])
	else:
		for y in height:
			if tiles[y].size() != width:
				errors.append("row %d has %d columns, expected %d" % [y, tiles[y].size(), width])
				break
	if not errors.is_empty():
		return {"valid": false, "errors": errors}

	var bounds := Rect2i(0, 0, width, height)
	var rooms: Array = dungeon["rooms"]
	for i in rooms.size():
		if not bounds.encloses(Rect2i(rooms[i]["position"], rooms[i]["size"])):
			errors.append("room %d is out of bounds" % i)

	var start: Vector2i = dungeon["start_cell"]
	var boss: Vector2i = dungeon["boss_cell"]
	for cell_name in ["start_cell", "boss_cell"]:
		var cell: Vector2i = dungeon[cell_name]
		if not bounds.has_point(cell):
			errors.append("%s %s is out of bounds" % [cell_name, cell])
		elif tiles[cell.y][cell.x] != FLOOR:
			errors.append("%s %s is not walkable" % [cell_name, cell])
	if start == boss:
		errors.append("start_cell and boss_cell are the same cell")

	if errors.is_empty():
		var reached := _flood_fill(tiles, start)
		if not reached.has(boss):
			errors.append("boss_cell is not reachable from start_cell")
		var walkable := 0
		for row in tiles:
			walkable += row.count(FLOOR)
		if reached.size() != walkable:
			errors.append("%d walkable tiles are disconnected from start_cell" % (walkable - reached.size()))

	return {"valid": errors.is_empty(), "errors": errors}


static func _generate_once(rng: RandomNumberGenerator, dungeon_seed: int, config: Dictionary) -> Dictionary:
	var width: int = config["width"]
	var height: int = config["height"]
	var min_rooms: int = config["min_rooms"]
	var max_rooms: int = config["max_rooms"]
	var min_size: int = config["min_room_size"]
	var max_size: int = config["max_room_size"]

	var tiles := []
	for y in height:
		var row := []
		row.resize(width)
		row.fill(WALL)
		tiles.append(row)

	# Leave a one-tile wall border; every leaf can hold a max-size room plus walls.
	var leaves: Array[Rect2i] = []
	_split(Rect2i(1, 1, width - 2, height - 2), max_size + 2, rng, leaves)

	var rooms := []
	for leaf in leaves:
		if rooms.size() >= max_rooms:
			break
		var size := Vector2i(
			rng.randi_range(min_size, mini(max_size, leaf.size.x - 2)),
			rng.randi_range(min_size, mini(max_size, leaf.size.y - 2)))
		var position := Vector2i(
			rng.randi_range(leaf.position.x + 1, leaf.end.x - 1 - size.x),
			rng.randi_range(leaf.position.y + 1, leaf.end.y - 1 - size.y))
		rooms.append({"position": position, "size": size})
		_carve_rect(tiles, position, size)

	if rooms.size() < min_rooms:
		return {"ok": false, "error": "only %d rooms fit, need at least %d" % [rooms.size(), min_rooms]}

	# BSP leaf order keeps consecutive rooms spatially close, so a chain of
	# L-shaped corridors connects every room.
	for i in range(1, rooms.size()):
		_carve_corridor(tiles, _center(rooms[i - 1]), _center(rooms[i]), rng.randi() % 2 == 0)

	var start_cell := _center(rooms[0])
	var boss_cell := start_cell
	var best_distance := -1
	for room in rooms:
		var center := _center(room)
		var distance := absi(center.x - start_cell.x) + absi(center.y - start_cell.y)
		if distance > best_distance:
			best_distance = distance
			boss_cell = center

	return {
		"ok": true,
		"error": "",
		"seed": dungeon_seed,
		"width": width,
		"height": height,
		"tiles": tiles,
		"rooms": rooms,
		"start_cell": start_cell,
		"boss_cell": boss_cell,
	}


static func _split(rect: Rect2i, min_leaf: int, rng: RandomNumberGenerator, leaves: Array[Rect2i]) -> void:
	var can_split_x := rect.size.x >= min_leaf * 2
	var can_split_y := rect.size.y >= min_leaf * 2
	if not can_split_x and not can_split_y:
		leaves.append(rect)
		return
	var split_x := can_split_x
	if can_split_x and can_split_y:
		split_x = rng.randf() < 0.5
	if split_x:
		var cut := rng.randi_range(min_leaf, rect.size.x - min_leaf)
		_split(Rect2i(rect.position, Vector2i(cut, rect.size.y)), min_leaf, rng, leaves)
		_split(Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y)), min_leaf, rng, leaves)
	else:
		var cut := rng.randi_range(min_leaf, rect.size.y - min_leaf)
		_split(Rect2i(rect.position, Vector2i(rect.size.x, cut)), min_leaf, rng, leaves)
		_split(Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut)), min_leaf, rng, leaves)


static func _carve_rect(tiles: Array, position: Vector2i, size: Vector2i) -> void:
	for y in range(position.y, position.y + size.y):
		for x in range(position.x, position.x + size.x):
			tiles[y][x] = FLOOR


static func _carve_corridor(tiles: Array, from: Vector2i, to: Vector2i, horizontal_first: bool) -> void:
	var corner := Vector2i(to.x, from.y) if horizontal_first else Vector2i(from.x, to.y)
	_carve_line(tiles, from, corner)
	_carve_line(tiles, corner, to)


static func _carve_line(tiles: Array, from: Vector2i, to: Vector2i) -> void:
	for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			tiles[y][x] = FLOOR


static func _center(room: Dictionary) -> Vector2i:
	return room["position"] + room["size"] / 2


static func _flood_fill(tiles: Array, start: Vector2i) -> Dictionary:
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if next.y < 0 or next.y >= tiles.size() or next.x < 0 or next.x >= tiles[next.y].size():
				continue
			if tiles[next.y][next.x] == FLOOR and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached
