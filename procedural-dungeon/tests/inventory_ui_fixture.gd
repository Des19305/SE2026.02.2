class_name InventoryUITestFixture
extends Node

const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const InventoryUIScene := preload("res://scenes/ui/inventory_ui.tscn")
const HotbarUIScene := preload("res://scenes/ui/hotbar_ui.tscn")

var item_database: ItemDatabase
var run_manager: Node
var inventory_manager: InventoryManager
var player: Player
var inventory_ui
var hotbar_ui


func _ready() -> void:
	item_database = ItemDatabaseScript.new()
	run_manager = RunManagerScript.new()
	player = PlayerScript.new()
	inventory_manager = InventoryManagerScript.new(item_database, run_manager)

	_register_item(
		"potion",
		"Healing Potion",
		"Restores health.",
		"Consumable",
		"consumable",
		true,
		3,
		[{"type": "heal", "value": 25}]
	)
	_register_item(
		"sword",
		"Iron Sword",
		"A basic sword.",
		"Equipment",
		"equipment",
		false,
		1
	)

	inventory_ui = InventoryUIScene.instantiate()
	add_child(inventory_ui)
	inventory_ui.setup(inventory_manager, item_database, player)

	hotbar_ui = HotbarUIScene.instantiate()
	add_child(hotbar_ui)
	hotbar_ui.setup(inventory_manager, item_database, player)
	inventory_ui.set_hotbar_ui(hotbar_ui)


func _exit_tree() -> void:
	if is_instance_valid(run_manager):
		run_manager.free()
	if is_instance_valid(player):
		player.free()


func _register_item(
	item_id: String,
	item_name: String,
	description: String,
	category: String,
	item_type: String,
	is_stackable: bool,
	max_stack: int,
	effects: Array = []
) -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = item_name
	definition.description = description
	definition.icon = null
	definition.category = category
	definition.item_type = item_type
	definition.tags = []
	definition.allowed_slot_types = []
	definition.slots_required = 0
	definition.effects = effects
	definition.stackable = is_stackable
	definition.max_stack = max_stack

	var result: Dictionary = item_database.register_definition(definition)
	assert(result["ok"], "fixture item registration failed")
