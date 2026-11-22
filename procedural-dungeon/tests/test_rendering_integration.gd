extends "res://tests/test_case.gd"

const MainScene := preload("res://main.tscn")
const GridScript := preload("res://scenes/dungeon/dungeon_grid.gd")
const RendererScript := preload("res://scenes/dungeon/dungeon_renderer.gd")

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}


func test_startup_rendering_sets_valid_grid_and_player_spawn() -> void:
	var fixture := await _create_fixture()
	var main: Main = fixture["main"]
	if main == null:
		await _remove_fixture(fixture)
		return
	await _process_frame()

	var renderer: DungeonRenderer = _find_renderer(main)
	check(renderer != null, "Main should own a DungeonRenderer")
	if renderer == null:
		await _remove_fixture(fixture)
		return

	check(renderer.grid != null, "renderer should have a valid DungeonGrid")
	check(main.player != null, "Main should own the Player")
	if main.player == null or renderer.grid == null:
		await _remove_fixture(fixture)
		return

	check(main.player.grid == renderer.grid, "Renderer and Player should share the same grid")
	check(
		main.player.cell == renderer.grid.start_cell,
		"Player should spawn on the dungeon start cell"
	)
	check(
		main.player.position == renderer.grid.cell_center(renderer.grid.start_cell),
		"Player position should match its start-cell center"
	)
	check(_find_camera(main) != null, "Main should own a Camera2D")

	await _remove_fixture(fixture)


func test_player_movement_keeps_grid_position_synchronized() -> void:
	var fixture := await _create_fixture()
	var main: Main = fixture["main"]
	if main == null:
		await _remove_fixture(fixture)
		return
	await _process_frame()

	var renderer: DungeonRenderer = _find_renderer(main)
	if renderer == null or main.player == null or renderer.grid == null:
		check(false, "rendering setup is required for movement test")
		await _remove_fixture(fixture)
		return

	var start_cell: Vector2i = main.player.cell
	var moved := false
	for direction in [
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.UP,
	]:
		var move_result: Dictionary = main.player.try_move(direction)
		if move_result["ok"]:
			moved = true
			break

	if moved:
		check(main.player.grid == renderer.grid, "movement should retain shared grid")
		check(
			main.player.position == renderer.grid.cell_center(main.player.cell),
			"movement should update Player position through the shared grid"
		)
	else:
		check(false, "Player should perform at least one successful movement")

	await _remove_fixture(fixture)


func test_failed_start_preserves_existing_rendering_state() -> void:
	var fixture := await _create_fixture()
	var main: Main = fixture["main"]
	if main == null:
		await _remove_fixture(fixture)
		return
	await _process_frame()

	var renderer: DungeonRenderer = _find_renderer(main)
	var camera: Camera2D = _find_camera(main)
	if renderer == null or main.player == null or camera == null:
		check(false, "existing rendering state is required before failed-start test")
		await _remove_fixture(fixture)
		return

	var old_grid: DungeonGrid = renderer.grid
	var old_player_grid: DungeonGrid = main.player.grid
	var old_player_cell: Vector2i = main.player.cell
	var old_player_position: Vector2 = main.player.position
	var old_camera_position: Vector2 = camera.position
	var old_camera_zoom: Vector2 = camera.zoom

	main.run_manager.end_run(true, "test failed start")
	var invalid_config := CONFIG.duplicate()
	invalid_config["width"] = 201
	var failed_result: Dictionary = main.start_run(
		45,
		invalid_config
	)

	check(not failed_result["ok"], "invalid startup should fail")
	await _process_frame()
	check(renderer.grid == old_grid, "failed start preserves renderer grid")
	check(main.player.grid == old_player_grid, "failed start preserves Player grid")
	check(main.player.cell == old_player_cell, "failed start preserves Player cell")
	check(main.player.position == old_player_position, "failed start preserves Player position")
	check(camera.position == old_camera_position, "failed start preserves camera position")
	check(camera.zoom == old_camera_zoom, "failed start preserves camera zoom")

	await _remove_fixture(fixture)


func test_replay_replaces_grid_and_resets_player_spawn() -> void:
	var fixture := await _create_fixture()
	var main: Main = fixture["main"]
	if main == null:
		await _remove_fixture(fixture)
		return
	await _process_frame()

	var renderer: DungeonRenderer = _find_renderer(main)
	if renderer == null or main.player == null:
		check(false, "existing rendering setup is required before replay")
		await _remove_fixture(fixture)
		return

	var old_grid: DungeonGrid = renderer.grid
	var move_succeeded := false
	for direction in [
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.UP,
	]:
		if main.player.try_move(direction)["ok"]:
			move_succeeded = true
			break
	check(move_succeeded, "Player should move away from spawn before replay")

	main.run_manager.end_run(true, "test replay")
	var replay_result: Dictionary = main.replay_last_run()

	check(replay_result["ok"], "replay should start: %s" % replay_result["error"])
	await _process_frame()
	check(renderer.grid != old_grid, "replay should replace the DungeonGrid")
	check(main.player.grid == renderer.grid, "replay Player should use replacement grid")
	check(
		main.player.cell == renderer.grid.start_cell,
		"replay should reset Player to replacement start cell"
	)
	check(
		main.player.position == renderer.grid.cell_center(renderer.grid.start_cell),
		"replay should reset Player position at start-cell center"
	)

	await _remove_fixture(fixture)


func test_camera_covers_dungeon_with_reasonable_padding() -> void:
	var fixture := await _create_fixture()
	var main: Main = fixture["main"]
	if main == null:
		await _remove_fixture(fixture)
		return
	await _process_frame()

	var renderer: DungeonRenderer = _find_renderer(main)
	var camera: Camera2D = _find_camera(main)
	if renderer == null or renderer.grid == null or camera == null:
		check(false, "renderer and camera are required for coverage test")
		await _remove_fixture(fixture)
		return

	var grid: DungeonGrid = renderer.grid
	var viewport_size: Vector2 = main.get_viewport().get_visible_rect().size
	var world_width: float = viewport_size.x / maxf(camera.zoom.x, 0.001)
	var world_height: float = viewport_size.y / maxf(camera.zoom.y, 0.001)
	var dungeon_width: float = grid.width * DungeonGrid.CELL_SIZE
	var dungeon_height: float = grid.height * DungeonGrid.CELL_SIZE

	check(
		world_width >= dungeon_width * 1.05,
		"camera viewport should cover dungeon width with padding"
	)
	check(
		world_height >= dungeon_height * 1.05,
		"camera viewport should cover dungeon height with padding"
	)

	var dungeon_center := Vector2(
		dungeon_width * 0.5,
		dungeon_height * 0.5
	)
	check(
		camera.position.distance_to(dungeon_center) <
			maxf(dungeon_width, dungeon_height) * 0.05,
		"camera should be centered on dungeon"
	)

	await _remove_fixture(fixture)


func test_hud_remains_compatible_after_rendering_start() -> void:
	var fixture := await _create_fixture()
	var main: Main = fixture["main"]
	if main == null:
		await _remove_fixture(fixture)
		return
	await _process_frame()

	check(main.hud != null, "Main should retain the existing HUD")
	if main.hud == null:
		await _remove_fixture(fixture)
		return

	check(main.hud.has_method("get_display_state"), "HUD should expose get_display_state")
	if main.hud.has_method("get_display_state"):
		var state: Dictionary = main.hud.get_display_state()
		check_eq(state["current_hp"], 100, "HUD should show initial Current HP")
		check_eq(state["max_hp"], 100, "HUD should show initial Max HP")
		check_eq(state["inventory_capacity"], 12, "HUD should show base Inventory capacity")
		check(state["seed"] != "—", "HUD should receive the successful startup seed")

	await _remove_fixture(fixture)


func _create_fixture() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var main_node: Node = MainScene.instantiate()
	check(main_node is Main, "main.tscn should attach the Main script")
	if not (main_node is Main):
		if is_instance_valid(main_node):
			main_node.queue_free()
			await _process_frame()
		return {
			"main": null,
			"records_dir": "",
		}
	var main: Main = main_node as Main
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var records_dir := "user://test_phase75_rendering/%d" % Time.get_ticks_usec()
	if main.run_manager != null:
		main.run_manager.records_dir = records_dir
	return {
		"main": main,
		"records_dir": records_dir,
	}


func _process_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame


func _find_renderer(main: Main) -> DungeonRenderer:
	var renderers: Array = main.find_children("*", "DungeonRenderer", true, false)
	if renderers.is_empty():
		return null
	return renderers[0]


func _find_camera(main: Main) -> Camera2D:
	var cameras: Array = main.find_children("*", "Camera2D", true, false)
	if cameras.is_empty():
		return null
	return cameras[0]


func _remove_fixture(fixture: Dictionary) -> void:
	var main: Main = fixture["main"]
	if is_instance_valid(main):
		main.queue_free()
		await _process_frame()
	if fixture["records_dir"] != "":
		_remove_dir(fixture["records_dir"])


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
