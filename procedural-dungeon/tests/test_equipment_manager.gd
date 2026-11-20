extends "res://tests/test_case.gd"

const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")

var item_database
var run_manager: Node
var inventory_manager
var inventory_events: Array = []


func before_each() -> void:
	item_database = ItemDatabaseScript.new()
	run_manager = RunManagerScript.new()
	inventory_manager = InventoryManagerScript.new(item_database, run_manager)
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void: inventory_events.append(items)
	)

	_register_definition("apple", true, 2)
	_register_definition("potion", true, 3)
	_register_definition("sword", false, 1)


func after_each() -> void:
	run_manager.free()


func test_valid_batch_preflights_without_mutation_and_publishes_once() -> void:
	check(inventory_manager.add_item("apple", 2), "initial apple add")
	check(inventory_manager.add_item("potion", 1), "initial potion add")
	inventory_events.clear()
	var removals := {"apple": 1}
	var additions := {"potion": 2}

	var preflight: Dictionary = inventory_manager.preflight_transfer_batch(removals, additions)

	check_eq(preflight, {"ok": true, "error": ""}, "valid batch preflight result")
	check_eq(inventory_manager.get_item_count("apple"), 2, "preflight preserves apples")
	check_eq(inventory_manager.get_item_count("potion"), 1, "preflight preserves potions")
	check_eq(inventory_events.size(), 0, "preflight must not emit")

	var changed: bool = inventory_manager.commit_transfer_batch(removals, additions)

	check(changed, "valid batch should change Inventory")
	check_eq(inventory_manager.get_item_count("apple"), 1, "apple count after commit")
	check_eq(inventory_manager.get_item_count("potion"), 3, "potion count after commit")
	check_eq(inventory_events.size(), 0, "silent commit must not emit")

	inventory_manager.publish_transfer_batch(changed)

	check_eq(inventory_events.size(), 1, "publish emits one inventory_changed")
	check_eq(inventory_events[0], [
		{"item_id": "apple", "amount": 1},
		{"item_id": "potion", "amount": 3},
	], "published final snapshot")


func test_unknown_item_definition_fails_preflight_without_mutation() -> void:
	check(inventory_manager.add_item("apple", 1), "initial apple add")
	inventory_events.clear()
	var before_items: Array = inventory_manager.get_items()

	var result: Dictionary = inventory_manager.preflight_transfer_batch({}, {"unknown": 1})

	check(not result["ok"], "unknown item definition must fail")
	check(not result["error"].is_empty(), "failure must explain the problem")
	check_eq(inventory_manager.get_items(), before_items, "failed preflight preserves Inventory")
	check_eq(inventory_events.size(), 0, "failed preflight must not emit")


func test_invalid_quantities_fail_preflight_without_mutation() -> void:
	check(inventory_manager.add_item("apple", 2), "initial apple add")
	inventory_events.clear()
	var before_items: Array = inventory_manager.get_items()
	var invalid_batches: Array = [
		[{}, {"potion": 0}],
		[{}, {"potion": -1}],
		[{"apple": 1.0}, {}],
		[{"apple": true}, {}],
		[{"": 1}, {}],
	]

	for batch in invalid_batches:
		var result: Dictionary = inventory_manager.preflight_transfer_batch(batch[0], batch[1])
		check(not result["ok"], "invalid batch must fail preflight")
		check(not result["error"].is_empty(), "invalid batch must report an error")

	check_eq(inventory_manager.get_items(), before_items, "invalid preflight preserves Inventory")
	check_eq(inventory_events.size(), 0, "invalid preflight must not emit")


func test_insufficient_removals_fail_preflight_without_mutation() -> void:
	check(inventory_manager.add_item("apple", 1), "initial apple add")
	inventory_events.clear()
	var before_items: Array = inventory_manager.get_items()

	var result: Dictionary = inventory_manager.preflight_transfer_batch({"apple": 2}, {"potion": 1})

	check(not result["ok"], "insufficient removal quantity must fail")
	check(result["error"].contains("Insufficient"), "failure should describe insufficient quantity")
	check_eq(inventory_manager.get_items(), before_items, "failed preflight preserves Inventory")
	check_eq(inventory_events.size(), 0, "failed preflight must not emit")


func test_capacity_is_validated_against_final_net_counts() -> void:
	check(inventory_manager.add_item("sword", 12), "fill all inventory slots")
	inventory_events.clear()

	var fitting_result: Dictionary = inventory_manager.preflight_transfer_batch(
		{"sword": 1},
		{"potion": 3}
	)
	check(fitting_result["ok"], "removing one slot before adding one stack should fit")

	var overflow_result: Dictionary = inventory_manager.preflight_transfer_batch(
		{"sword": 1},
		{"potion": 4}
	)
	check(not overflow_result["ok"], "two added potion stacks should exceed capacity")
	check(overflow_result["error"].contains("capacity"), "overflow should report capacity")
	check_eq(inventory_manager.get_item_count("sword"), 12, "capacity preflight must preserve swords")
	check_eq(inventory_manager.get_item_count("potion"), 0, "capacity preflight must preserve potions")
	check_eq(inventory_events.size(), 0, "capacity preflight must not emit")


func test_net_noop_batch_does_not_mutate_or_publish() -> void:
	check(inventory_manager.add_item("apple", 1), "initial apple add")
	inventory_events.clear()
	var removals := {"apple": 1}
	var additions := {"apple": 1}

	var preflight: Dictionary = inventory_manager.preflight_transfer_batch(removals, additions)
	check(preflight["ok"], "net no-op batch should preflight")
	var changed: bool = inventory_manager.commit_transfer_batch(removals, additions)

	check(not changed, "net no-op commit reports unchanged Inventory")
	check_eq(inventory_manager.get_item_count("apple"), 1, "net no-op preserves count")
	inventory_manager.publish_transfer_batch(changed)
	check_eq(inventory_events.size(), 0, "no-op publish must not emit")


func test_existing_add_and_remove_behavior_remains_compatible() -> void:
	check(inventory_manager.add_item("potion", 2), "existing add API")
	check_eq(inventory_manager.get_item_count("potion"), 2, "existing add count")
	check_eq(inventory_events.size(), 1, "existing add emits once")

	check(inventory_manager.remove_item("potion", 1), "existing remove API")
	check_eq(inventory_manager.get_item_count("potion"), 1, "existing remove count")
	check_eq(inventory_events.size(), 2, "existing remove emits once")
	check(not inventory_manager.remove_item("potion", 2), "insufficient remove still fails")
	check_eq(inventory_manager.get_item_count("potion"), 1, "failed existing remove preserves count")
	check_eq(inventory_events.size(), 2, "failed existing remove does not emit")


func _register_definition(item_id: String, stackable: bool, max_stack: int) -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = "Test %s" % item_id
	definition.description = "Test definition"
	definition.icon = null
	definition.category = "Consumable"
	definition.item_type = "consumable"
	definition.tags = []
	definition.allowed_slot_types = []
	definition.slots_required = 0
	definition.effects = []
	definition.stackable = stackable
	definition.max_stack = max_stack

	var result: Dictionary = item_database.register_definition(definition)
	check(result["ok"], "definition registration failed: %s" % result["error"])
