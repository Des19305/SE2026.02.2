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

var run_manager
var item_database: ItemDatabase
var player: Player
var inventory_manager: InventoryManager
var equipment_manager: EquipmentManager
var player_run_reset: PlayerRunReset


func _ready() -> void:
	run_manager = RunManagerScript.new()
	add_child(run_manager)

	item_database = ItemDatabaseScript.new()
	player = PlayerScript.new()
	add_child(player)

	inventory_manager = InventoryManagerScript.new(item_database, run_manager)
	equipment_manager = EquipmentManagerScript.new(
		item_database,
		inventory_manager,
		run_manager,
		player
	)
	player_run_reset = PlayerRunResetScript.new(player, run_manager)


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
