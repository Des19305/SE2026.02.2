extends "res://tests/test_case.gd"

const HotbarScene := preload("res://scenes/ui/hotbar_ui.tscn")
const InventoryUIScene := preload("res://scenes/ui/inventory_ui.tscn")
const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")
const PlayerScript := preload("res://scenes/player/player.gd")

var item_database
var run_manager: Node
var inventory_manager
var player: Player
var hotbar


func before_each() -> void:
	item_database = ItemDatabaseScript.new()
	run_manager = RunManagerScript.new()
	player = PlayerScript.new()
	inventory_manager = InventoryManagerScript.new(item_database, run_manager)

	_register_item(
		"potion",
		"Healing Potion",
		"consumable",
		[{"type": "heal", "value": 25}]
	)
	_register_item(
		"elixir",
		"Small Elixir",
		"consumable",
		[{"type": "heal", "value": 20}]
	)
	_register_item("sword", "Iron Sword", "equipment", [])

	var tree := Engine.get_main_loop() as SceneTree
	hotbar = HotbarScene.instantiate()
	tree.root.add_child(hotbar)
	hotbar.setup(inventory_manager, item_database, player)


func after_each() -> void:
	if is_instance_valid(hotbar):
		hotbar.free()
	if is_instance_valid(player):
		player.free()
	if is_instance_valid(run_manager):
		run_manager.free()


func test_exactly_four_hotbar_slots_exist() -> void:
	check_eq(hotbar.get_slot_count(), 4, "Hotbar has exactly four slots")
	check_eq(hotbar.get_hotbar_state().size(), 4, "Hotbar exposes exactly four slot states")

	for slot_index in range(4):
		check_eq(hotbar.get_slot_state(slot_index)["status"], "empty", "initial slot is empty")


func test_assigning_eligible_item_stores_id_without_changing_quantity() -> void:
	check(inventory_manager.add_item("potion", 2), "add potion")

	var result: Dictionary = hotbar.assign_item(0, "potion")

	check_eq(result["ok"], true, "eligible item assignment succeeds")
	check_eq(hotbar.get_slot_item_id(0), "potion", "slot stores item ID")
	check_eq(hotbar.get_slot_state(0)["status"], "available", "assigned potion is available")
	check_eq(inventory_manager.get_item_count("potion"), 2, "assignment does not consume potion")


func test_reassigning_slot_replaces_previous_reference() -> void:
	check(inventory_manager.add_item("potion", 2), "add potion")
	check(inventory_manager.add_item("elixir", 1), "add elixir")
	check(hotbar.assign_item(1, "potion")["ok"], "initial assignment")

	var result: Dictionary = hotbar.assign_item(1, "elixir")

	check_eq(result["ok"], true, "reassignment succeeds")
	check_eq(hotbar.get_slot_item_id(1), "elixir", "reassignment replaces old reference")
	check_eq(inventory_manager.get_item_count("potion"), 2, "reassignment does not change quantity")
	check_eq(inventory_manager.get_item_count("elixir"), 1, "reassignment does not change elixir quantity")


func test_empty_slot_shortcut_is_safe() -> void:
	var result: Dictionary = hotbar.handle_shortcut(0)

	check_eq(result["ok"], false, "empty slot use fails")
	check_eq(result["error"], "slot_empty", "empty slot reports safe error")
	check_eq(result["consumed"], false, "empty slot consumes nothing")
	check_eq(inventory_manager.get_items(), [], "empty slot leaves Inventory unchanged")


func test_available_assigned_slot_uses_existing_api() -> void:
	player._current_hp = 70
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(hotbar.assign_item(2, "potion")["ok"], "assign potion")

	var result: Dictionary = hotbar.use_slot(2)

	check_eq(result["ok"], true, "available slot use succeeds")
	check_eq(result["consumed"], true, "available slot consumes one item")
	check_eq(inventory_manager.get_item_count("potion"), 0, "existing use API consumes potion")
	check_eq(player.get_current_hp(), 95, "existing use API applies healing")
	check_eq(hotbar.get_slot_state(2)["status"], "unavailable", "exhausted assignment becomes unavailable")


func test_unavailable_assigned_slot_does_not_use_item() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(hotbar.assign_item(3, "potion")["ok"], "assign potion")
	check(inventory_manager.remove_item("potion", 1), "remove potion")

	var result: Dictionary = hotbar.use_slot(3)

	check_eq(result["ok"], false, "unavailable slot use fails")
	check_eq(result["error"], "item_unavailable", "unavailable slot reports safe error")
	check_eq(result["consumed"], false, "unavailable slot consumes nothing")
	check_eq(hotbar.get_slot_item_id(3), "potion", "unavailable assignment remains retained")


func test_assignment_remains_when_item_disappears() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(hotbar.assign_item(0, "potion")["ok"], "assign potion")
	check(inventory_manager.remove_item("potion", 1), "remove potion")

	check_eq(hotbar.get_slot_item_id(0), "potion", "assignment is retained")
	check_eq(hotbar.get_slot_state(0)["status"], "unavailable", "missing item is unavailable")


func test_assignment_becomes_available_when_item_returns() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(hotbar.assign_item(0, "potion")["ok"], "assign potion")
	check(inventory_manager.remove_item("potion", 1), "remove potion")
	check_eq(hotbar.get_slot_state(0)["status"], "unavailable", "missing item starts unavailable")

	check(inventory_manager.add_item("potion", 1), "restore potion")
	check_eq(hotbar.get_slot_item_id(0), "potion", "restored item keeps assignment")
	check_eq(hotbar.get_slot_state(0)["status"], "available", "restored item becomes available")


func test_zero_quantity_and_invalid_assignments_are_rejected() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(inventory_manager.remove_item("potion", 1), "remove potion")

	var unavailable: Dictionary = hotbar.assign_item(0, "potion")
	check_eq(unavailable["error"], "item_unavailable", "zero quantity assignment is rejected")
	check_eq(hotbar.get_slot_item_id(0), "", "rejected zero quantity assignment stores no reference")

	check(inventory_manager.add_item("sword", 1), "add sword")
	var ineligible: Dictionary = hotbar.assign_item(0, "sword")
	check_eq(ineligible["error"], "item_not_usable", "non-consumable assignment is rejected")
	check_eq(hotbar.get_slot_item_id(0), "", "ineligible assignment stores no reference")

	var invalid: Dictionary = hotbar.assign_item(0, "missing")
	check_eq(invalid["error"], "invalid_item", "unknown item assignment is rejected")
	check_eq(hotbar.get_slot_item_id(0), "", "invalid assignment stores no reference")


func test_inventory_ui_can_assign_selected_item_to_selected_hotbar_slot() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var inventory_ui = InventoryUIScene.instantiate()
	tree.root.add_child(inventory_ui)
	inventory_ui.setup(inventory_manager, item_database, player)
	inventory_ui.set_hotbar_ui(hotbar)

	check(inventory_manager.add_item("potion", 2), "add potion")
	check(inventory_ui.select_item("potion"), "select potion")

	check(hotbar.select_slot(1), "select hotbar slot 2")
	var result: Dictionary = inventory_ui.assign_selected_item_to_hotbar(1)

	check_eq(result["ok"], true, "Inventory UI assigns selected item")
	check_eq(hotbar.get_slot_item_id(1), "potion", "Inventory UI assignment reaches Hotbar")
	check_eq(inventory_manager.get_item_count("potion"), 2, "Inventory UI assignment does not consume")

	inventory_ui.free()


func test_keyboard_shortcuts_1_through_4_use_each_slot_once() -> void:
	player._current_hp = 20
	check(inventory_manager.add_item("potion", 4), "add four potions")

	for slot_index in range(4):
		check(hotbar.assign_item(slot_index, "potion")["ok"], "assign potion to each slot")

	for keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
		var event := InputEventKey.new()
		event.pressed = true
		event.echo = false
		event.keycode = keycode
		hotbar._unhandled_key_input(event)

	check_eq(inventory_manager.get_item_count("potion"), 0, "four shortcut events consume one potion each")
	check_eq(player.get_current_hp(), 100, "shortcut healing uses the existing Player API")


func test_phase_one_and_two_inventory_ui_paths_remain_usable() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var inventory_ui = InventoryUIScene.instantiate()
	tree.root.add_child(inventory_ui)
	inventory_ui.setup(inventory_manager, item_database, player)

	player._current_hp = 70
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(inventory_ui.select_item("potion"), "select potion")
	var use_result: Dictionary = inventory_ui.use_selected_item(player)

	check_eq(use_result["ok"], true, "Phase 2 Use path remains usable")
	check_eq(inventory_manager.get_item_count("potion"), 0, "Phase 2 Use consumes quantity")
	check_eq(inventory_ui.get_selected_item_id(), "", "Phase 1 selection clears when item disappears")

	inventory_ui.free()


func _register_item(
	item_id: String,
	item_name: String,
	item_type: String,
	effects: Array
) -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = item_name
	definition.description = ""
	definition.icon = null
	definition.category = "Consumable" if item_type == "consumable" else "Equipment"
	definition.item_type = item_type
	definition.tags = []
	definition.allowed_slot_types = []
	definition.slots_required = 0
	definition.effects = effects
	definition.stackable = true
	definition.max_stack = 3 if item_type == "consumable" else 1

	var result: Dictionary = item_database.register_definition(definition)
	assert(result["ok"], "Hotbar test item registration failed")
