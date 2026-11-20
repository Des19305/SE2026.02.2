extends "res://tests/test_case.gd"

const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")

class FailingPlayer extends Player:
	func heal(_amount: int) -> Dictionary:
		return {"ok": false, "error": "Test healing failure"}

var item_database
var run_manager: Node
var inventory_manager
var player: Player
var inventory_events: Array = []
var item_use_events: Array = []


func before_each() -> void:
	item_database = ItemDatabaseScript.new()
	run_manager = RunManagerScript.new()
	inventory_manager = InventoryManagerScript.new(item_database, run_manager)
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void: inventory_events.append(items)
	)
	inventory_manager.item_used.connect(
		func(item_id: String, result: Dictionary) -> void:
			item_use_events.append({"item_id": item_id, "result": result})
	)

	_register_definition("potion", "consumable", [{"type": "heal", "value": 25}])
	_register_definition("material", "material", [{"type": "heal", "value": 25}])
	_register_definition("unsupported", "consumable", [{"type": "damage", "value": 25}])
	_register_definition(
		"multiple_effects",
		"consumable",
		[{"type": "heal", "value": 25}, {"type": "heal", "value": 5}]
	)
	_register_definition("malformed_effect", "consumable", ["heal"])
	_register_definition("missing_value", "consumable", [{"type": "heal"}])
	_register_definition("unexpected_key", "consumable", [{"type": "heal", "bonus": 25}])


func after_each() -> void:
	if is_instance_valid(player):
		player.free()
	run_manager.free()


func test_successful_healing_consumes_exactly_one_item_and_emits_signals() -> void:
	player = _player_at(70)
	check(inventory_manager.add_item("potion", 2), "initial potion add")
	inventory_events.clear()

	var result: Dictionary = inventory_manager.use_item("potion", player)

	check_eq(result, {
		"ok": true,
		"error": "",
		"item_id": "potion",
		"consumed": true,
	}, "successful use result")
	check_eq(player.get_current_hp(), 95, "healed HP")
	check_eq(inventory_manager.get_item_count("potion"), 1, "exactly one potion consumed")
	check_eq(inventory_events.size(), 1, "successful removal signal count")
	check_eq(inventory_events[0], [{"item_id": "potion", "amount": 1}], "updated inventory payload")
	_assert_item_used("potion", result)


func test_healing_clamps_at_max_hp_and_consumes_one_item() -> void:
	player = _player_at(90)
	check(inventory_manager.add_item("potion", 2), "initial potion add")
	inventory_events.clear()

	var result: Dictionary = inventory_manager.use_item("potion", player)

	check(result["ok"], "clamped healing should succeed")
	check_eq(player.get_current_hp(), 100, "healing must clamp to Max HP")
	check_eq(inventory_manager.get_item_count("potion"), 1, "one potion consumed")
	check_eq(inventory_events.size(), 1, "successful removal emits once")
	_assert_item_used("potion", result)


func test_unknown_item_fails_without_state_changes() -> void:
	player = _player_at(70)
	var health_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)

	var result: Dictionary = inventory_manager.use_item("missing", player)

	_assert_failure(result, "invalid_item", "missing")
	check_eq(player.get_current_hp(), 70, "unknown item must not heal")
	check_eq(health_events, [], "unknown item must not emit health_changed")
	check_eq(inventory_manager.get_item_count("missing"), 0, "unknown item count")
	check_eq(inventory_events.size(), 0, "unknown item must not emit inventory_changed")
	_assert_item_used("missing", result)


func test_invalid_user_fails_without_state_changes() -> void:
	player = _player_at(70)
	check(inventory_manager.add_item("potion", 1), "initial potion add")
	inventory_events.clear()
	var invalid_user := Node.new()

	var result: Dictionary = inventory_manager.use_item("potion", invalid_user)

	invalid_user.free()
	_assert_failure(result, "invalid_user", "potion")
	check_eq(player.get_current_hp(), 70, "invalid user must not heal")
	check_eq(inventory_manager.get_item_count("potion"), 1, "invalid user must not consume")
	check_eq(inventory_events.size(), 0, "invalid user must not emit inventory_changed")
	_assert_item_used("potion", result)


func test_item_not_owned_fails_without_state_changes() -> void:
	player = _player_at(70)

	var result: Dictionary = inventory_manager.use_item("potion", player)

	_assert_failure(result, "item_not_owned", "potion")
	check_eq(player.get_current_hp(), 70, "unowned item must not heal")
	check_eq(inventory_events.size(), 0, "unowned item must not emit inventory_changed")
	_assert_item_used("potion", result)


func test_wrong_item_type_fails_without_state_changes() -> void:
	player = _player_at(70)
	check(inventory_manager.add_item("material", 1), "initial material add")
	inventory_events.clear()

	var result: Dictionary = inventory_manager.use_item("material", player)

	_assert_failure(result, "item_not_usable", "material")
	check_eq(player.get_current_hp(), 70, "wrong item type must not heal")
	check_eq(inventory_manager.get_item_count("material"), 1, "wrong item type must not consume")
	check_eq(inventory_events.size(), 0, "wrong item type must not emit inventory_changed")
	_assert_item_used("material", result)


func test_unsupported_effect_shapes_fail_without_state_changes() -> void:
	player = _player_at(70)
	for item_id in ["unsupported", "multiple_effects", "malformed_effect"]:
		check(inventory_manager.add_item(item_id, 1), "initial %s add" % item_id)
	inventory_events.clear()

	for item_id in ["unsupported", "multiple_effects", "malformed_effect"]:
		var result: Dictionary = inventory_manager.use_item(item_id, player)
		_assert_failure(result, "item_not_usable", item_id)
		check_eq(inventory_manager.get_item_count(item_id), 1, "%s must remain owned" % item_id)

	check_eq(player.get_current_hp(), 70, "unsupported effects must not heal")
	check_eq(inventory_events.size(), 0, "unsupported effects must not emit inventory_changed")
	check_eq(item_use_events.size(), 3, "each unsupported attempt emits item_used")


func test_unexpected_healing_effect_key_is_not_usable() -> void:
	player = _player_at(70)
	check(inventory_manager.add_item("unexpected_key", 1), "initial item add")
	inventory_events.clear()

	var result: Dictionary = inventory_manager.use_item("unexpected_key", player)

	_assert_failure(result, "item_not_usable", "unexpected_key")
	check_eq(player.get_current_hp(), 70, "unsupported key must not heal")
	check_eq(inventory_manager.get_item_count("unexpected_key"), 1, "unsupported key must not consume")
	check_eq(inventory_events.size(), 0, "unsupported key must not emit inventory_changed")
	_assert_item_used("unexpected_key", result)


func test_malformed_and_nonpositive_healing_values_fail() -> void:
	player = _player_at(70)
	var invalid_values: Array = [0, -1, 25.0, "25", true]
	var item_ids: Array[String] = []
	for index in range(invalid_values.size()):
		var item_id := "invalid_value_%d" % index
		item_ids.append(item_id)
		_register_definition(
			item_id,
			"consumable",
			[{"type": "heal", "value": invalid_values[index]}]
		)
		check(inventory_manager.add_item(item_id, 1), "initial %s add" % item_id)
	check(inventory_manager.add_item("missing_value", 1), "initial missing value add")
	inventory_events.clear()

	for item_id in item_ids + ["missing_value"]:
		var result: Dictionary = inventory_manager.use_item(item_id, player)
		_assert_failure(result, "effect_failed", item_id)
		check_eq(inventory_manager.get_item_count(item_id), 1, "%s must remain owned" % item_id)

	check_eq(player.get_current_hp(), 70, "invalid effects must not heal")
	check_eq(inventory_events.size(), 0, "invalid effects must not emit inventory_changed")
	check_eq(item_use_events.size(), item_ids.size() + 1, "each invalid attempt emits item_used")


func test_full_hp_failure_maps_to_hp_full_without_consumption() -> void:
	player = _player_at(100)
	var health_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	check(inventory_manager.add_item("potion", 1), "initial potion add")
	inventory_events.clear()

	var result: Dictionary = inventory_manager.use_item("potion", player)

	_assert_failure(result, "hp_full", "potion")
	check_eq(player.get_current_hp(), 100, "full HP must remain unchanged")
	check_eq(health_events, [], "full HP failure must not emit health_changed")
	check_eq(inventory_manager.get_item_count("potion"), 1, "full HP failure must preserve item")
	check_eq(inventory_events.size(), 0, "full HP failure must not emit inventory_changed")
	_assert_item_used("potion", result)


func test_other_player_heal_failure_maps_to_effect_failed() -> void:
	player = FailingPlayer.new()
	player._current_hp = 70
	check(inventory_manager.add_item("potion", 1), "initial potion add")
	inventory_events.clear()

	var result: Dictionary = inventory_manager.use_item("potion", player)

	_assert_failure(result, "effect_failed", "potion")
	check_eq(player.get_current_hp(), 70, "failed healing must not change HP")
	check_eq(inventory_manager.get_item_count("potion"), 1, "failed healing must preserve item")
	check_eq(inventory_events.size(), 0, "failed healing must not emit inventory_changed")
	_assert_item_used("potion", result)


func test_reentrant_inventory_removal_is_reported_without_claiming_consumption() -> void:
	player = _player_at(70)
	check(inventory_manager.add_item("potion", 1), "initial potion add")
	inventory_events.clear()
	player.health_changed.connect(
		func(_current_hp: int, _max_hp: int) -> void:
			check(inventory_manager.remove_item("potion", 1), "reentrant removal should succeed")
	)

	var result: Dictionary = inventory_manager.use_item("potion", player)

	_assert_failure(result, "item_not_owned", "potion")
	check_eq(player.get_current_hp(), 95, "healing has already succeeded before reentrant removal")
	check_eq(inventory_manager.get_item_count("potion"), 0, "reentrant callback removed the item")
	check_eq(inventory_events.size(), 1, "only the successful reentrant removal emits")
	check_eq(inventory_events[0], [], "reentrant removal snapshot")
	_assert_item_used("potion", result)


func _player_at(current_hp: int) -> Player:
	var new_player: Player = PlayerScript.new()
	new_player._current_hp = current_hp
	return new_player


func _register_definition(item_id: String, item_type_value: String, effects: Array) -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = "Test %s" % item_id
	definition.description = "Test definition"
	definition.icon = null
	definition.category = "Consumable"
	definition.item_type = item_type_value
	definition.tags = []
	definition.allowed_slot_types = []
	definition.slots_required = 0
	definition.effects = effects
	definition.stackable = true
	definition.max_stack = 10

	var result: Dictionary = item_database.register_definition(definition)
	check(result["ok"], "definition registration failed: %s" % result["error"])


func _assert_failure(result: Dictionary, error: String, item_id: String) -> void:
	check_eq(result, {
		"ok": false,
		"error": error,
		"item_id": item_id,
		"consumed": false,
	}, "failed use result")


func _assert_item_used(item_id: String, result: Dictionary) -> void:
	check_eq(item_use_events.size(), 1, "item_used signal count")
	if item_use_events.is_empty():
		return

	check_eq(item_use_events[0]["item_id"], item_id, "item_used item ID")
	check_eq(item_use_events[0]["result"], result, "item_used result payload")
	check(item_use_events[0]["result"].is_read_only(), "item_used payload must be read-only")
