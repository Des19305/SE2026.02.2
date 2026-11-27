extends Node2D
class_name Main

const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const EquipmentManagerScript := preload("res://scripts/inventory/equipment_manager.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const PlayerRunResetScript := preload(
	"res://scripts/run_management/player_run_reset.gd"
)
const HUDScene := preload("res://scenes/hud/hud.tscn")
const DungeonGridScript := preload("res://scenes/dungeon/dungeon_grid.gd")
const DungeonRendererScript := preload(
	"res://scenes/dungeon/dungeon_renderer.gd"
)
const InventoryUIScene := preload("res://scenes/ui/inventory_ui.tscn")
const HotbarUIScene := preload("res://scenes/ui/hotbar_ui.tscn")

var run_manager
var item_database: ItemDatabase
var player: Player
var inventory_manager: InventoryManager
var equipment_manager: EquipmentManager
var player_run_reset: PlayerRunReset
var hud
var dungeon_grid: DungeonGrid
var dungeon_renderer: DungeonRenderer
var dungeon_camera: Camera2D
var inventory_ui
var hotbar_ui
var ui_layer: CanvasLayer
## Folder for run records. Set it before the node enters the tree (tests use a
## temporary folder); _ready() passes it to RunManager before the first run.
var records_dir := "user://runs"

## Screen height kept free for the hotbar at the bottom (see hotbar_ui.tscn).
const HOTBAR_RESERVED_HEIGHT := 115.0

const STARTUP_RUN_CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}


func _ready() -> void:
	run_manager = RunManagerScript.new()
	run_manager.records_dir = records_dir
	add_child(run_manager)

	item_database = ItemDatabaseScript.new()

	dungeon_renderer = DungeonRendererScript.new()
	add_child(dungeon_renderer)

	dungeon_camera = Camera2D.new()
	add_child(dungeon_camera)
	dungeon_camera.make_current()

	player = PlayerScript.new()
	dungeon_renderer.add_child(player)

	inventory_manager = InventoryManagerScript.new(item_database, run_manager)
	equipment_manager = EquipmentManagerScript.new(
		item_database,
		inventory_manager,
		run_manager,
		player
	)
	player_run_reset = PlayerRunResetScript.new(player, run_manager)
	hud = HUDScene.instantiate()
	add_child(hud)
	if hud is HUD:
		hud.setup(player, equipment_manager, inventory_manager, run_manager)

	run_manager.run_started.connect(_on_run_started)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "InventoryAndHotbarUI"
	add_child(ui_layer)

	inventory_ui = InventoryUIScene.instantiate()
	ui_layer.add_child(inventory_ui)
	inventory_ui.setup(inventory_manager, item_database, player)

	hotbar_ui = HotbarUIScene.instantiate()
	ui_layer.add_child(hotbar_ui)
	hotbar_ui.setup(inventory_manager, item_database, player)
	inventory_ui.set_hotbar_ui(hotbar_ui)

	start_run(42, STARTUP_RUN_CONFIG)


## Opens the Inventory with E while the game runs. InventoryUI only processes
## input while the tree is paused (PROCESS_MODE_WHEN_PAUSED), so it handles the
## closing E itself and this handler handles the opening one.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_E:
		return
	if inventory_ui == null:
		return

	get_viewport().set_input_as_handled()
	inventory_ui.toggle_inventory()


func _on_run_started(_seed: int, dungeon: Dictionary) -> void:
	var conversion: Dictionary = DungeonGridScript.from_dungeon(dungeon)
	if not conversion["ok"]:
		return

	var new_grid: DungeonGrid = conversion["grid"]
	var player_setup: Dictionary = player.setup(new_grid)
	if not player_setup["ok"]:
		return

	dungeon_grid = new_grid
	dungeon_renderer.setup(new_grid)
	_frame_camera(new_grid)


func _frame_camera(grid: DungeonGrid) -> void:
	if dungeon_camera == null:
		return

	var dungeon_width: float = grid.width * DungeonGrid.CELL_SIZE
	var dungeon_height: float = grid.height * DungeonGrid.CELL_SIZE
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var padding := 1.10
	# The hotbar covers the bottom of the screen. The camera stays centred on the
	# dungeon, so the same band is kept free at the top and the bottom.
	var usable_height := maxf(viewport_size.y - 2.0 * HOTBAR_RESERVED_HEIGHT, 1.0)
	var scale_x := viewport_size.x / (dungeon_width * padding)
	var scale_y := usable_height / (dungeon_height * padding)
	var zoom_scale := minf(scale_x, scale_y)
	zoom_scale = maxf(zoom_scale, 0.01)

	dungeon_camera.position = Vector2(
		dungeon_width * 0.5,
		dungeon_height * 0.5
	)
	dungeon_camera.zoom = Vector2(zoom_scale, zoom_scale)


func start_run(run_seed: int, config: Dictionary) -> Dictionary:
	if run_manager == null:
		return {"ok": false, "error": "Production composition is not ready"}
	return run_manager.start_new_run(run_seed, config)


func replay_last_run() -> Dictionary:
	if run_manager == null:
		return {"ok": false, "error": "Production composition is not ready"}
	return run_manager.replay_last_run()


func register_item_definition(definition: ItemData) -> Dictionary:
	if item_database == null:
		return {"ok": false, "error": "Production composition is not ready"}
	return item_database.register_definition(definition)
