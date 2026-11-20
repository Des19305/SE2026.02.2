extends "res://tests/test_case.gd"

const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")

class TrackingItemDatabase extends ItemDatabase:
	var unavailable_ids: Dictionary = {}

	func get_item_definition(item_id: String) -> Dictionary:
		if unavailable_ids.has(item_id):
			return {
				"ok": false,
				"error": "Item definition not found: %s" % item_id,
				"definition": null,
			}
		return super.get_item_definition(item_id)

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}

var item_database
var run_manager: Node
var inventory_manager
var records_dir: String
var inventory_events: Array = []


func before_each() -> void:
	item_database = TrackingItemDatabase.new()
	run_manager = RunManagerScript.new()
	records_dir = "user://test_inventory_runs/%d" % Time.get_ticks_usec()
	run_manager.records_dir = records_dir

	_register_definition("apple", "Consumable", "consumable", true, 2)
	_register_definition("potion", "Consumable", "consumable", true, 3)
	_register_definition("zinc", "Consumable", "material", true, 4)
	_register_definition("sword", "Equipment", "equipment", false, 1)

	inventory_manager = InventoryManagerScript.new(item_database, run_manager)
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void: inventory_events.append(items)
	)


func after_each() -> void:
	inventory_manager = null
	run_manager.free()
	_remove_dir("user://test_inventory_runs")


func test_initial_state_and_queries() -> void:
	check_eq(inventory_manager.get_items(), [], "initial items")
	check_eq(inventory_manager.get_item_count("potion"), 0, "initial potion count")
	check_eq(inventory_manager.get_max_slots(), 12, "initial capacity")
	check_eq(inventory_manager.get_used_slots(), 0, "initial used slots")
	check_eq(inventory_events.size(), 0, "initial signal count")


func test_adds_registered_item_and_emits_updated_snapshot() -> void:
	check(inventory_manager.add_item("potion", 2), "registered item should be added")
	check_eq(inventory_manager.get_item_count("potion"), 2, "potion count")
	check_eq(inventory_manager.get_items(), [{"item_id": "potion", "amount": 2}], "snapshot")
	check_eq(inventory_events, [[{"item_id": "potion", "amount": 2}]], "signal payload")


func test_rejects_unknown_item_and_nonpositive_amounts_without_changes() -> void:
	check(not inventory_manager.add_item("unknown", 1), "unknown item should be rejected")
	check(not inventory_manager.add_item("potion", 0), "zero amount should be rejected")
	check(not inventory_manager.add_item("potion", -1), "negative amount should be rejected")
	check(not inventory_manager.remove_item("potion", 0), "zero removal should be rejected")
	check(not inventory_manager.remove_item("potion", -1), "negative removal should be rejected")

	check_eq(inventory_manager.get_items(), [], "failed operations must not change items")
	check_eq(inventory_manager.get_used_slots(), 0, "failed operations must not use slots")
	check_eq(inventory_events.size(), 0, "failed operations must not emit")


func test_groups_splits_and_sorts_stacks_by_item_id() -> void:
	check(inventory_manager.add_item("zinc", 1), "zinc add")
	check(inventory_manager.add_item("potion", 5), "potion add")
	check(inventory_manager.add_item("apple", 3), "apple add")

	check_eq(inventory_manager.get_items(), [
		{"item_id": "apple", "amount": 2},
		{"item_id": "apple", "amount": 1},
		{"item_id": "potion", "amount": 3},
		{"item_id": "potion", "amount": 2},
		{"item_id": "zinc", "amount": 1},
	], "sorted grouped stacks")
	check_eq(inventory_manager.get_item_count("potion"), 5, "total across potion stacks")
	check_eq(inventory_manager.get_used_slots(), 5, "used stack slots")


func test_non_stackable_items_use_one_slot_each() -> void:
	check(inventory_manager.add_item("sword", 3), "non-stackable items should fit")
	check_eq(inventory_manager.get_items(), [
		{"item_id": "sword", "amount": 1},
		{"item_id": "sword", "amount": 1},
		{"item_id": "sword", "amount": 1},
	], "non-stackable snapshot")
	check_eq(inventory_manager.get_item_count("sword"), 3, "sword count")
	check_eq(inventory_manager.get_used_slots(), 3, "sword slots")


func test_partial_stacks_fit_at_capacity_and_overflow_is_atomic() -> void:
	check(inventory_manager.add_item("potion", 1), "partial potion stack")
	check(inventory_manager.add_item("sword", 11), "fill remaining capacity")
	check_eq(inventory_manager.get_used_slots(), 12, "inventory full")

	check(inventory_manager.add_item("potion", 2), "existing partial stack should accept items")
	check_eq(inventory_manager.get_item_count("potion"), 3, "potion count at capacity")
	check_eq(inventory_manager.get_used_slots(), 12, "partial-stack addition uses no new slot")

	var before_overflow: Array = inventory_manager.get_items()
	var event_count := inventory_events.size()
	check(not inventory_manager.add_item("potion", 1), "overflow should fail")
	check_eq(inventory_manager.get_items(), before_overflow, "overflow must not partially mutate")
	check_eq(inventory_events.size(), event_count, "overflow must not emit")


func test_remove_updates_quantities_and_releases_slots() -> void:
	check(inventory_manager.add_item("potion", 5), "initial potion add")
	check(inventory_manager.remove_item("potion", 2), "partial removal")
	check_eq(inventory_manager.get_item_count("potion"), 3, "count after partial removal")
	check_eq(inventory_manager.get_items(), [{"item_id": "potion", "amount": 3}], "re-grouped stack")

	check(inventory_manager.remove_item("potion", 3), "complete removal")
	check_eq(inventory_manager.get_item_count("potion"), 0, "count after complete removal")
	check_eq(inventory_manager.get_items(), [], "empty after complete removal")
	check_eq(inventory_manager.get_used_slots(), 0, "slot released")
	check_eq(inventory_events.size(), 3, "successful add and removals must emit")
	check_eq(inventory_events.back(), [], "final removal signal snapshot")


func test_failed_removals_do_not_partially_mutate_or_emit() -> void:
	check(inventory_manager.add_item("potion", 2), "initial potion add")
	var before_removal: Array = inventory_manager.get_items()
	var event_count := inventory_events.size()

	check(not inventory_manager.remove_item("potion", 3), "insufficient quantity should fail")
	check(not inventory_manager.remove_item("unknown", 1), "missing item should fail")
	check_eq(inventory_manager.get_items(), before_removal, "failed removals must not mutate")
	check_eq(inventory_events.size(), event_count, "failed removals must not emit")

	item_database.unavailable_ids["potion"] = true
	check(not inventory_manager.remove_item("potion", 1), "unregistered item ID should fail")
	check_eq(inventory_manager.get_item_count("potion"), 2, "unregistered removal must preserve quantity")
	check_eq(inventory_events.size(), event_count, "unregistered removal must not emit")


func test_snapshot_and_signal_payload_are_defensive_copies() -> void:
	var second_subscriber_events: Array = []
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void: second_subscriber_events.append(items)
	)
	check(inventory_manager.add_item("potion", 2), "initial potion add")

	var snapshot: Array = inventory_manager.get_items()
	snapshot[0]["amount"] = 99
	snapshot.append({"item_id": "sword", "amount": 1})
	check_eq(inventory_manager.get_item_count("potion"), 2, "mutating snapshot must not affect state")
	check_eq(inventory_manager.get_items(), [{"item_id": "potion", "amount": 2}], "fresh snapshot")

	var first_payload: Array = inventory_events[0]
	var second_payload: Array = second_subscriber_events[0]
	check(first_payload.is_read_only(), "signal array must be read-only")
	check(first_payload[0].is_read_only(), "signal entry must be read-only")
	check(second_payload.is_read_only(), "every subscriber must receive a read-only array")
	check(second_payload[0].is_read_only(), "every subscriber must receive read-only entries")
	check_eq(second_payload[0]["amount"], 2, "second subscriber payload")
	check_eq(inventory_manager.get_item_count("potion"), 2, "signal payload must not affect state")


func test_successful_run_start_resets_nonempty_inventory() -> void:
	check(inventory_manager.add_item("potion", 2), "initial potion add")
	var event_count := inventory_events.size()

	var result: Dictionary = run_manager.start_new_run(42, CONFIG)

	check(result["ok"], "run should start: %s" % result["error"])
	check_eq(inventory_manager.get_items(), [], "successful run reset")
	check_eq(inventory_manager.get_max_slots(), 12, "capacity after run reset")
	check_eq(inventory_events.size(), event_count + 1, "reset signal count")
	check_eq(inventory_events.back(), [], "reset signal snapshot")


func test_noop_run_reset_does_not_emit_inventory_changed() -> void:
	var result: Dictionary = run_manager.start_new_run(42, CONFIG)

	check(result["ok"], "run should start: %s" % result["error"])
	check_eq(inventory_manager.get_items(), [], "inventory remains empty")
	check_eq(inventory_events.size(), 0, "no-op reset must not emit")


func test_failed_run_start_does_not_reset_inventory() -> void:
	check(inventory_manager.add_item("potion", 2), "initial potion add")
	var before_start: Array = inventory_manager.get_items()
	var event_count := inventory_events.size()
	var invalid_config := CONFIG.duplicate()
	invalid_config["width"] = 201

	var result: Dictionary = run_manager.start_new_run(42, invalid_config)

	check(not result["ok"], "invalid run should fail")
	check_eq(inventory_manager.get_items(), before_start, "failed start must preserve inventory")
	check_eq(inventory_events.size(), event_count, "failed start must not emit")


func _register_definition(
	item_id: String,
	item_category: String,
	item_type_value: String,
	is_stackable: bool,
	item_max_stack: int
) -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = "Test %s" % item_id
	definition.description = "Test definition"
	definition.icon = null
	definition.category = item_category
	definition.item_type = item_type_value
	definition.tags = []
	definition.allowed_slot_types = []
	definition.slots_required = 0
	definition.effects = []
	definition.stackable = is_stackable
	definition.max_stack = item_max_stack

	var result: Dictionary = item_database.register_definition(definition)
	check(result["ok"], "definition registration failed: %s" % result["error"])


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
