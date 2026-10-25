extends RefCounted
# Tests for DungeonGrid, DungeonRenderer and Player (issue #5).
# Convention used by tests/run_tests.gd: every method named test_* returns ""
# on success or a failure message.

const GridScript := preload("res://scenes/dungeon/dungeon_grid.gd")
const RendererScript := preload("res://scenes/dungeon/dungeon_renderer.gd")
const PlayerScript := preload("res://scenes/player/player.gd")


func _fixture() -> Dictionary:
    return {
        "ok": true, "error": "", "seed": 1, "width": 5, "height": 5,
        "tiles": [
            [0, 0, 0, 0, 0],
            [0, 1, 1, 1, 0],
            [0, 1, 0, 1, 0],
            [0, 1, 1, 1, 0],
            [0, 0, 0, 0, 0],
        ],
        "rooms": [], "start_cell": Vector2i(1, 1), "boss_cell": Vector2i(3, 3),
    }


func _grid() -> DungeonGrid:
    return GridScript.from_dungeon(_fixture())["grid"]


func _expect(condition: bool, message: String) -> String:
    return "" if condition else message


func test_grid_accepts_valid_dungeon() -> String:
    var result: Dictionary = GridScript.from_dungeon(_fixture())
    if result["ok"] != true:
        return "valid dungeon rejected: %s" % result["error"]
    var grid: DungeonGrid = result["grid"]
    return _expect(grid.width == 5 and grid.height == 5 and grid.start_cell == Vector2i(1, 1),
        "size or start_cell not copied")


func test_grid_rejects_failed_generation() -> String:
    var d := _fixture()
    d["ok"] = false
    d["error"] = "retry limit"
    return _expect(GridScript.from_dungeon(d)["ok"] == false, "ok=false dungeon accepted")


func test_grid_rejects_missing_key() -> String:
    var d := _fixture()
    d.erase("tiles")
    return _expect(GridScript.from_dungeon(d)["ok"] == false, "missing tiles accepted")


func test_grid_rejects_wrong_shape() -> String:
    var short_row := _fixture()
    short_row["tiles"][2] = [0, 1, 0]
    if GridScript.from_dungeon(short_row)["ok"] != false:
        return "short row accepted"
    var few_rows := _fixture()
    few_rows["tiles"].pop_back()
    return _expect(GridScript.from_dungeon(few_rows)["ok"] == false, "wrong row count accepted")


func test_grid_rejects_bad_tile_value() -> String:
    var d := _fixture()
    d["tiles"][1][1] = 2
    return _expect(GridScript.from_dungeon(d)["ok"] == false, "tile value 2 accepted")


func test_grid_rejects_bad_start_cell() -> String:
    var on_wall := _fixture()
    on_wall["start_cell"] = Vector2i(0, 0)
    if GridScript.from_dungeon(on_wall)["ok"] != false:
        return "start on wall accepted"
    var outside := _fixture()
    outside["start_cell"] = Vector2i(9, 9)
    return _expect(GridScript.from_dungeon(outside)["ok"] == false, "start out of bounds accepted")


func test_grid_is_a_private_copy() -> String:
    var d := _fixture()
    var grid: DungeonGrid = GridScript.from_dungeon(d)["grid"]
    d["tiles"][1][2] = 0  # someone edits the generator's dictionary afterwards
    return _expect(grid.is_walkable(Vector2i(2, 1)), "grid changed after the source dictionary was edited")


func test_walkable_and_bounds() -> String:
    var grid := _grid()
    if not grid.is_walkable(Vector2i(1, 1)):
        return "floor should be walkable"
    if grid.is_walkable(Vector2i(0, 0)) or grid.is_walkable(Vector2i(2, 2)):
        return "wall should be blocked"
    if grid.is_walkable(Vector2i(-1, 1)) or grid.is_walkable(Vector2i(5, 1)) or grid.is_walkable(Vector2i(1, 5)):
        return "out-of-bounds cell should be blocked"
    return ""


func test_player_spawns_on_start_cell() -> String:
    var grid := _grid()
    var player: Player = PlayerScript.new()
    var result := player.setup(grid)
    var message := ""
    if result["ok"] != true:
        message = "setup failed: %s" % result["error"]
    elif player.cell != Vector2i(1, 1) or player.position != grid.cell_center(Vector2i(1, 1)):
        message = "player not on start_cell"
    player.free()
    return message


func test_player_blocked_by_walls() -> String:
    var player: Player = PlayerScript.new()
    player.setup(_grid())
    var message := ""
    if player.try_move(Vector2i.UP)["ok"] != false or player.cell != Vector2i(1, 1):
        message = "wall above did not block"
    elif player.try_move(Vector2i.LEFT)["ok"] != false or player.cell != Vector2i(1, 1):
        message = "wall on the left did not block"
    elif player.try_move(Vector2i.RIGHT)["ok"] != true or player.cell != Vector2i(2, 1):
        message = "could not walk onto floor"
    elif player.try_move(Vector2i.DOWN)["ok"] != false or player.cell != Vector2i(2, 1):
        message = "inner wall did not block"
    player.free()
    return message


func test_player_rejects_invalid_steps() -> String:
    var player: Player = PlayerScript.new()
    var message := ""
    if player.try_move(Vector2i.RIGHT)["ok"] != false:
        message = "move before setup should fail safely"
    else:
        player.setup(_grid())
        if player.try_move(Vector2i(1, 1))["ok"] != false:
            message = "diagonal step accepted"
        elif player.try_move(Vector2i(2, 0))["ok"] != false:
            message = "two-cell step accepted"
        elif player.try_move(Vector2i.ZERO)["ok"] != false:
            message = "zero step accepted"
        elif player.cell != Vector2i(1, 1):
            message = "invalid steps changed the position"
        elif player.setup(null)["ok"] != false:
            message = "setup(null) should fail"
    player.free()
    return message


func test_walk_ring_and_random_walk_stay_on_floor() -> String:
    var grid := _grid()
    var player: Player = PlayerScript.new()
    player.setup(grid)
    for step in [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.DOWN,
            Vector2i.LEFT, Vector2i.LEFT, Vector2i.UP]:
        player.try_move(step)
    var message := ""
    if player.cell != Vector2i(1, 2):
        message = "ring walk ended on %s, expected (1, 2)" % str(player.cell)
    else:
        var rng := RandomNumberGenerator.new()
        rng.seed = 12345
        var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
        for i in range(2000):
            player.try_move(directions[rng.randi_range(0, 3)])
            if not grid.is_walkable(player.cell):
                message = "player entered a wall at step %d: %s" % [i, str(player.cell)]
                break
    player.free()
    return message


func test_render_and_collision_share_one_grid() -> String:
    var grid := _grid()
    var renderer: DungeonRenderer = RendererScript.new()
    var player: Player = PlayerScript.new()
    renderer.setup(grid)
    renderer.add_child(player)
    player.setup(grid)
    player.try_move(Vector2i.RIGHT)
    var message := ""
    if renderer.grid != player.grid:
        message = "renderer and player use different grid instances"
    elif player.position != grid.cell_center(player.cell):
        message = "player position does not follow its cell"
    renderer.free()
    return message
