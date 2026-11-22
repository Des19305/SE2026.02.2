extends "res://tests/test_case.gd"

const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const EquipmentManagerScript := preload("res://scripts/inventory/equipment_manager.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")
const PlayerRunResetScript := preload("res://scripts/run_management/player_run_reset.gd")
const PlayerScript := preload("res://scenes/player/player.gd")

var item_database
var run_manager: Node
var player: Player
var inventory_manager
var equipment_manager
var inventory_events: Array = []
var inventory_equipment_snapshots: Array[Dictionary] = []
var equipment_events: Array[Dictionary] = []
var equipment_inventory_counts: Array[int] = []
var slot_events: int = 0


func before_each() -> void:
	item_database = ItemDatabaseScript.new()
	run_manager = RunManagerScript.new()
	player = PlayerScript.new()
	inventory_manager = InventoryManagerScript.new(item_database, run_manager)
	equipment_manager = EquipmentManagerScript.new(
		item_database,
		inventory_manager,
		run_manager,
		player
	)
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void:
			inventory_events.append(items)
			inventory_equipment_snapshots.append(equipment_manager.get_equipment())
	)
	equipment_manager.equipment_changed.connect(
		func() -> void:
			equipment_events.append(equipment_manager.get_equipment())
			equipment_inventory_counts.append(inventory_manager.get_item_count("sword"))
	)
	equipment_manager.equipment_slots_changed.connect(
		func() -> void: slot_events += 1
	)

	_register_definition("apple", true, 2)
	_register_definition("potion", true, 3)
	_register_equipment_definition("sword", ["weapon"], 1)
	_register_equipment_definition("shield", ["weapon"], 1)
	_register_equipment_definition(
		"bow", ["weapon"], 2, false, 1,
		[_max_hp_effect(20, "increase_max_and_current")]
	)
	_register_equipment_definition("helmet_piece", ["helmet"], 1)
	_register_equipment_definition("old_ring", ["accessory"], 1)
	_register_equipment_definition("stack_ring", ["accessory"], 1, true, 3)
	_register_equipment_definition("heavy_non_bow", ["weapon"], 2)
	_register_equipment_definition(
		"vital_armor", ["armor"], 1, false, 1,
		[_max_hp_effect(20, "increase_max_and_current")]
	)
	_register_equipment_definition(
		"vital_armor_replacement", ["armor"], 1, false, 1,
		[_max_hp_effect(20, "increase_max_and_current")]
	)
	_register_equipment_definition(
		"vital_helmet", ["helmet"], 1, false, 1,
		[_max_hp_effect(10, "increase_max_only")]
	)
	_register_equipment_definition(
		"invalid_effect_armor", ["armor"], 1, false, 1,
		[{"type": "stat", "stat": "max_hp", "operation": "add", "value": 0, "hp_behavior": "increase_max_only"}]
	)


func after_each() -> void:
	equipment_manager = null
	inventory_manager = null
	run_manager.free()
	player.free()


func test_initial_slots_and_equipment_snapshot() -> void:
	var expected := {
		"weapon_1": "",
		"weapon_2": "",
		"helmet": "",
		"armor": "",
		"boots": "",
		"accessory_1": "",
		"accessory_2": "",
	}
	check_eq(equipment_manager.get_equipment(), expected, "initial equipment")
	check(equipment_manager.get_equipment().is_read_only(), "snapshot should be read-only")

	var detached_snapshot: Dictionary = equipment_manager.get_equipment().duplicate()
	detached_snapshot["helmet"] = "changed"
	check_eq(equipment_manager.get_equipment(), expected, "snapshot must not expose state")


func test_dynamic_slots_validate_and_emit_only_when_added() -> void:
	var result: Dictionary = equipment_manager.add_slot("trinket_1", "trinket")

	check_eq(result, {"ok": true, "error": ""}, "add slot result")
	check(equipment_manager.has_slot("trinket_1"), "added slot should exist")
	check_eq(equipment_manager.get_slot_type("trinket_1"), "trinket", "dynamic slot type")
	check_eq(equipment_manager.get_equipment()["trinket_1"], "", "new slot starts empty")
	check_eq(slot_events, 1, "successful add emits slots signal")

	check_eq(equipment_manager.add_slot("", "trinket"), {"ok": false, "error": "invalid_slot"}, "empty ID")
	check_eq(equipment_manager.add_slot("trinket_2", ""), {"ok": false, "error": "invalid_slot"}, "empty type")
	check_eq(
		equipment_manager.add_slot("trinket_1", "trinket"),
		{"ok": false, "error": "invalid_slot"},
		"duplicate ID"
	)
	check(not equipment_manager.has_slot("missing"), "unknown slot query")
	check_eq(equipment_manager.get_slot_type("missing"), "", "unknown slot type")
	check_eq(slot_events, 1, "failed additions do not emit")


func test_dynamic_slot_equipment_change_keeps_effect_sources_consistent() -> void:
	check(inventory_manager.add_item("vital_helmet"), "add Max HP equipment")
	check(equipment_manager.add_slot("extra_helmet", "helmet")["ok"], "add dynamic helmet slot")

	var equip_result: Dictionary = equipment_manager.equip_item(
		"vital_helmet",
		"extra_helmet"
	)

	check_eq(equip_result, {"ok": true, "error": ""}, "dynamic-slot equip")
	check_eq(equipment_manager.get_equipment()["extra_helmet"], "vital_helmet", "dynamic slot occupied")
	check_eq(player.get_max_hp(), 110, "dynamic equipment effect applied once")
	check_eq(player.get_current_hp(), 100, "max-only effect preserves Current HP")
	check_eq(inventory_manager.get_item_count("vital_helmet"), 0, "equipped item removed from Inventory")

	var unequip_result: Dictionary = equipment_manager.unequip_item("extra_helmet")

	check_eq(unequip_result, {"ok": true, "error": ""}, "dynamic-slot unequip")
	check_eq(equipment_manager.get_equipment()["extra_helmet"], "", "dynamic slot released")
	check_eq(player.get_max_hp(), 100, "dynamic equipment effect removed")
	check_eq(player.get_current_hp(), 100, "effect removal preserves Current HP")
	check_eq(inventory_manager.get_item_count("vital_helmet"), 1, "unequipped item returned")


func test_equip_publishes_only_after_inventory_and_equipment_commit() -> void:
	check(inventory_manager.add_item("sword"), "add sword")
	inventory_events.clear()
	inventory_equipment_snapshots.clear()

	var result: Dictionary = equipment_manager.equip_item("sword", "weapon_1")

	check_eq(result, {"ok": true, "error": ""}, "equip result")
	check_eq(inventory_manager.get_item_count("sword"), 0, "equipped item removed from Inventory")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "sword", "sword equipped")
	check_eq(inventory_events.size(), 1, "Inventory publishes once")
	check_eq(inventory_equipment_snapshots[0]["weapon_1"], "sword", "Inventory observer sees final Equipment")
	check_eq(equipment_events.size(), 1, "Equipment publishes once")
	check_eq(equipment_inventory_counts[0], 0, "Equipment observer sees final Inventory")


func test_equip_validation_failures_do_not_mutate_or_emit() -> void:
	check(inventory_manager.add_item("potion"), "add non-equipment item")

	check_eq(equipment_manager.equip_item("missing", "weapon_1"), _error("invalid_item"), "unknown item")
	check_eq(equipment_manager.equip_item("potion", "weapon_1"), _error("not_equipment"), "wrong item type")
	check_eq(equipment_manager.equip_item("sword", "weapon_1"), _error("item_not_owned"), "not owned")
	check_eq(equipment_manager.equip_item("potion", "missing"), _error("invalid_slot"), "unknown slot")
	check_eq(equipment_manager.equip_item("potion", "helmet"), _error("not_equipment"), "not equipment")
	check_eq(inventory_manager.get_item_count("potion"), 1, "failed equip preserves inventory")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "", "failed equip preserves equipment")
	check_eq(inventory_events.size(), 1, "failed equip emits no inventory signal")
	check_eq(equipment_events.size(), 0, "failed equip emits no equipment signal")


func test_incompatible_and_unsupported_multislot_equipment_fail() -> void:
	check(inventory_manager.add_item("sword"), "add sword")
	check(inventory_manager.add_item("heavy_non_bow"), "add non-Bow multi-slot item")

	check_eq(equipment_manager.equip_item("sword", "helmet"), _error("incompatible_slot"), "slot mismatch")
	check_eq(
		equipment_manager.equip_item("heavy_non_bow", "weapon_1"),
		_error("incompatible_slot"),
		"non-Bow multi-slot item"
	)
	check_eq(inventory_manager.get_item_count("sword"), 1, "incompatible equip preserves item")
	check_eq(inventory_manager.get_item_count("heavy_non_bow"), 1, "unsupported item remains owned")
	check_eq(equipment_events.size(), 0, "incompatible equip emits no equipment signal")


func test_replacement_returns_displaced_item_atomically() -> void:
	check(inventory_manager.add_item("sword"), "add initial sword")
	check(inventory_manager.add_item("shield"), "add replacement shield")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip initial sword")
	inventory_events.clear()
	inventory_equipment_snapshots.clear()
	equipment_events.clear()
	equipment_inventory_counts.clear()

	var result: Dictionary = equipment_manager.equip_item("shield", "weapon_1")

	check_eq(result, {"ok": true, "error": ""}, "replacement result")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "shield", "replacement equipped")
	check_eq(inventory_manager.get_item_count("sword"), 1, "displaced item returned once")
	check_eq(inventory_manager.get_item_count("shield"), 0, "incoming item removed")
	check_eq(inventory_events.size(), 1, "replacement Inventory signal count")
	check_eq(inventory_equipment_snapshots[0]["weapon_1"], "shield", "Inventory sees final replacement")
	check_eq(equipment_events.size(), 1, "replacement Equipment signal count")
	check_eq(equipment_inventory_counts[0], 1, "Equipment sees final Inventory")


func test_inventory_capacity_failure_preserves_equipment_and_inventory() -> void:
	check(inventory_manager.add_item("old_ring"), "add old ring")
	check(equipment_manager.equip_item("old_ring", "accessory_1")["ok"], "equip old ring")
	check(inventory_manager.add_item("stack_ring", 3), "add full stack of incoming rings")
	check(inventory_manager.add_item("sword", 11), "fill remaining Inventory slots")
	inventory_events.clear()
	equipment_events.clear()

	var result: Dictionary = equipment_manager.equip_item("stack_ring", "accessory_1")

	check_eq(result, _error("inventory_full"), "capacity failure result")
	check_eq(equipment_manager.get_equipment()["accessory_1"], "old_ring", "equipment unchanged")
	check_eq(inventory_manager.get_item_count("old_ring"), 0, "displaced item not partially returned")
	check_eq(inventory_manager.get_item_count("stack_ring"), 3, "incoming stack unchanged")
	check_eq(inventory_manager.get_item_count("sword"), 11, "other inventory unchanged")
	check_eq(inventory_events.size(), 0, "failed transfer emits no inventory signal")
	check_eq(equipment_events.size(), 0, "failed transfer emits no equipment signal")


func test_equipping_bow_replaces_both_weapon_slots_once() -> void:
	check(inventory_manager.add_item("sword"), "add sword")
	check(inventory_manager.add_item("shield"), "add shield")
	check(inventory_manager.add_item("bow"), "add bow")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip sword")
	check(equipment_manager.equip_item("shield", "weapon_2")["ok"], "equip shield")
	inventory_events.clear()
	equipment_events.clear()

	var result: Dictionary = equipment_manager.equip_item("bow", "weapon_2")

	check_eq(result, {"ok": true, "error": ""}, "Bow equip result")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "bow", "Bow reserves weapon 1")
	check_eq(equipment_manager.get_equipment()["weapon_2"], "bow", "Bow reserves weapon 2")
	check_eq(inventory_manager.get_item_count("sword"), 1, "first displaced item returned")
	check_eq(inventory_manager.get_item_count("shield"), 1, "second displaced item returned")
	check_eq(inventory_manager.get_item_count("bow"), 0, "Bow removed from Inventory")
	check_eq(inventory_events.size(), 1, "multi-item transfer publishes once")
	check_eq(equipment_events.size(), 1, "multi-slot equip publishes once")


func test_replacing_bow_with_single_weapon_clears_and_returns_bow_once() -> void:
	check(inventory_manager.add_item("bow"), "add bow")
	check(inventory_manager.add_item("shield"), "add shield")
	check(equipment_manager.equip_item("bow", "weapon_1")["ok"], "equip bow")
	inventory_events.clear()
	equipment_events.clear()

	var result: Dictionary = equipment_manager.equip_item("shield", "weapon_2")

	check_eq(result, {"ok": true, "error": ""}, "replace Bow result")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "", "Bow's first slot released")
	check_eq(equipment_manager.get_equipment()["weapon_2"], "shield", "incoming weapon equipped")
	check_eq(inventory_manager.get_item_count("bow"), 1, "Bow returned exactly once")
	check_eq(inventory_manager.get_item_count("shield"), 0, "incoming shield removed")
	check_eq(inventory_events.size(), 1, "replacement publishes one Inventory signal")
	check_eq(equipment_events.size(), 1, "replacement publishes one Equipment signal")


func test_unequip_bow_from_either_slot_returns_it_once() -> void:
	check(inventory_manager.add_item("bow"), "add bow")
	check(equipment_manager.equip_item("bow", "weapon_2")["ok"], "equip bow")
	inventory_events.clear()
	equipment_events.clear()

	var result: Dictionary = equipment_manager.unequip_item("weapon_1")

	check_eq(result, {"ok": true, "error": ""}, "Bow unequip result")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "", "first Bow slot released")
	check_eq(equipment_manager.get_equipment()["weapon_2"], "", "second Bow slot released")
	check_eq(inventory_manager.get_item_count("bow"), 1, "Bow returned once")
	check_eq(inventory_events.size(), 1, "unequip Inventory signal count")
	check_eq(equipment_events.size(), 1, "unequip Equipment signal count")


func test_unequip_failures_and_same_item_noop_do_not_emit() -> void:
	check_eq(equipment_manager.unequip_item("missing"), _error("invalid_slot"), "unknown slot")
	check_eq(equipment_manager.unequip_item("weapon_1"), _error("slot_empty"), "empty slot")
	check(inventory_manager.add_item("sword", 2), "add duplicate swords")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip first sword")
	inventory_events.clear()
	equipment_events.clear()

	var result: Dictionary = equipment_manager.equip_item("sword", "weapon_1")

	check_eq(result, {"ok": true, "error": ""}, "same item replacement is a successful no-op")
	check_eq(inventory_manager.get_item_count("sword"), 1, "net no-op preserves inventory count")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "sword", "net no-op preserves equipment")
	check_eq(inventory_events.size(), 0, "no-op does not publish Inventory")
	check_eq(equipment_events.size(), 0, "no-op does not publish Equipment")


func test_run_start_resets_dynamic_slots_and_equipment_before_later_observers() -> void:
	check(inventory_manager.add_item("sword"), "add sword")
	check(equipment_manager.add_slot("extra_weapon", "weapon")["ok"], "add dynamic slot")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip sword")
	inventory_events.clear()
	equipment_events.clear()
	slot_events = 0
	var observed_equipment: Array[Dictionary] = []
	var reset_signal_counts_during_dispatch: Array[int] = []
	run_manager.run_started.connect(
		func(_seed: int, _dungeon: Dictionary) -> void:
			observed_equipment.append(equipment_manager.get_equipment())
			reset_signal_counts_during_dispatch.append(
				equipment_events.size() + slot_events
			)
	)

	run_manager.run_started.emit(123, {})

	var expected := {
		"weapon_1": "",
		"weapon_2": "",
		"helmet": "",
		"armor": "",
		"boots": "",
		"accessory_1": "",
		"accessory_2": "",
	}
	check_eq(equipment_manager.get_equipment(), expected, "run reset restores default slots")
	check(not equipment_manager.has_slot("extra_weapon"), "run reset removes dynamic slot")
	check_eq(observed_equipment, [expected], "later run observer sees reset state")
	check_eq(reset_signal_counts_during_dispatch, [0], "reset signals wait until dispatch completes")


func test_failed_run_start_does_not_reset_equipment() -> void:
	check(inventory_manager.add_item("sword"), "add sword")
	check(equipment_manager.add_slot("extra_weapon", "weapon")["ok"], "add dynamic slot")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip sword")

	var result: Dictionary = run_manager.start_new_run(0, {})

	check(not result["ok"], "invalid run start should fail")
	check(equipment_manager.has_slot("extra_weapon"), "failed start preserves dynamic slot")
	check_eq(equipment_manager.get_equipment()["weapon_1"], "sword", "failed start preserves equipment")


func test_composed_run_reset_publishes_only_after_all_state_is_reset() -> void:
	check(inventory_manager.add_item("potion"), "add retained Inventory item")
	check(inventory_manager.add_item("vital_armor"), "add Max HP equipment")
	check(equipment_manager.add_slot("extra_accessory", "accessory")["ok"], "add dynamic slot")
	check(equipment_manager.equip_item("vital_armor", "armor")["ok"], "equip Max HP equipment")
	check_eq(player.get_current_hp(), 120, "precondition Current HP")
	check_eq(player.get_max_hp(), 120, "precondition Max HP")
	var player_run_reset = PlayerRunResetScript.new(player, run_manager)

	inventory_events.clear()
	equipment_events.clear()
	equipment_inventory_counts.clear()
	slot_events = 0
	var health_events: Array = []
	var max_hp_events: Array = []
	var notification_names: Array[String] = []
	var notification_snapshots: Array[Dictionary] = []
	var run_started_snapshots: Array[Dictionary] = []

	inventory_manager.inventory_changed.connect(
		func(_items: Array) -> void:
			notification_names.append("inventory")
			notification_snapshots.append(_capture_reset_snapshot())
	)
	equipment_manager.equipment_changed.connect(
		func() -> void:
			notification_names.append("equipment")
			notification_snapshots.append(_capture_reset_snapshot())
	)
	equipment_manager.equipment_slots_changed.connect(
		func() -> void:
			notification_names.append("slots")
			notification_snapshots.append(_capture_reset_snapshot())
	)
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void:
			health_events.append([current_hp, max_hp])
			notification_names.append("health")
			notification_snapshots.append(_capture_reset_snapshot())
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void:
			max_hp_events.append(max_hp)
			notification_names.append("max_hp")
			notification_snapshots.append(_capture_reset_snapshot())
	)
	run_manager.run_started.connect(
		func(_seed: int, _dungeon: Dictionary) -> void:
			run_started_snapshots.append(_capture_reset_snapshot())
			check_eq(notification_names, [], "reset notifications must wait for run_started dispatch")
	)

	run_manager.run_started.emit(123, {})

	check_eq(notification_names, [], "no reset notifications are synchronous")
	check_eq(run_started_snapshots.size(), 1, "later run_started observer executes")
	if not run_started_snapshots.is_empty():
		_assert_run_reset_snapshot(run_started_snapshots[0], "run_started observer")

	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame

	check_eq(notification_names.size(), 5, "all changed-owner notifications publish")
	check_eq(notification_names.count("inventory"), 1, "Inventory publishes once")
	check_eq(notification_names.count("equipment"), 1, "Equipment publishes once")
	check_eq(notification_names.count("slots"), 1, "dynamic slots publish once")
	check_eq(notification_names.count("max_hp"), 1, "Max HP publishes once")
	check_eq(notification_names.count("health"), 1, "Current HP publishes once")
	check_eq(inventory_events.size(), 1, "one inventory reset notification")
	check_eq(equipment_events.size(), 1, "one equipment reset notification")
	check_eq(slot_events, 1, "one dynamic-slot reset notification")
	check_eq(max_hp_events, [100], "Max HP reset notification")
	check_eq(health_events, [[100, 100]], "Current HP reset notification")
	for snapshot in notification_snapshots:
		_assert_run_reset_snapshot(snapshot, "reset signal observer")

	notification_names.clear()
	run_manager.run_started.emit(124, {})
	check_eq(notification_names, [], "no-op reset emits nothing synchronously")
	await tree.process_frame
	check_eq(notification_names, [], "no-op reset emits no deferred notifications")

	check(inventory_manager.add_item("sword"), "add item before failed start")
	check(equipment_manager.add_slot("another_slot", "weapon")["ok"], "add slot before failed start")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip item before failed start")
	var before_failed_start := _capture_reset_snapshot()
	notification_names.clear()
	var invalid_config := {
		"width": 201,
		"height": 50,
		"min_rooms": 8,
		"max_rooms": 12,
		"min_room_size": 5,
		"max_room_size": 10,
	}

	var failed_start: Dictionary = run_manager.start_new_run(42, invalid_config)

	check(not failed_start["ok"], "invalid run start should fail")
	check_eq(_capture_reset_snapshot(), before_failed_start, "failed start preserves all reset state")
	check_eq(notification_names, [], "failed start publishes no reset notification")
	await tree.process_frame
	check_eq(notification_names, [], "failed start queues no reset notification")
	player_run_reset = null


func _capture_reset_snapshot() -> Dictionary:
	return {
		"items": inventory_manager.get_items(),
		"max_slots": inventory_manager.get_max_slots(),
		"equipment": equipment_manager.get_equipment(),
		"has_extra_accessory": equipment_manager.has_slot("extra_accessory"),
		"has_another_slot": equipment_manager.has_slot("another_slot"),
		"current_hp": player.get_current_hp(),
		"max_hp": player.get_max_hp(),
	}


func _assert_run_reset_snapshot(snapshot: Dictionary, context: String) -> void:
	check_eq(snapshot["items"], [], "%s sees empty Inventory" % context)
	check_eq(snapshot["max_slots"], 12, "%s sees initial Inventory capacity" % context)
	check_eq(snapshot["equipment"], {
		"weapon_1": "",
		"weapon_2": "",
		"helmet": "",
		"armor": "",
		"boots": "",
		"accessory_1": "",
		"accessory_2": "",
	}, "%s sees default Equipment" % context)
	check(not snapshot["has_extra_accessory"], "%s sees dynamic slot removed" % context)
	check(not snapshot["has_another_slot"], "%s sees failed-start slot absent" % context)
	check_eq(snapshot["current_hp"], 100, "%s sees reset Current HP" % context)
	check_eq(snapshot["max_hp"], 100, "%s sees reset Max HP" % context)


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


func test_equipping_and_unequipping_max_hp_equipment_syncs_player() -> void:
	check(inventory_manager.add_item("vital_armor"), "add Max HP equipment")

	check(equipment_manager.equip_item("vital_armor", "armor")["ok"], "equip Max HP equipment")
	check_eq(player.get_current_hp(), 120, "equip applies Current HP contribution")
	check_eq(player.get_max_hp(), 120, "equip applies Max HP contribution")

	check(equipment_manager.unequip_item("armor")["ok"], "unequip Max HP equipment")
	check_eq(player.get_current_hp(), 100, "unequip clamps Current HP to new Max HP")
	check_eq(player.get_max_hp(), 100, "unequip removes Max HP contribution")


func test_replacing_identical_effect_uses_new_equipment_source() -> void:
	player._current_hp = 50
	check(inventory_manager.add_item("vital_armor"), "add original equipment")
	check(inventory_manager.add_item("vital_armor_replacement"), "add replacement equipment")
	check(equipment_manager.equip_item("vital_armor", "armor")["ok"], "equip original equipment")

	check(
		equipment_manager.equip_item("vital_armor_replacement", "armor")["ok"],
		"replace equipment"
	)
	check_eq(player.get_current_hp(), 90, "new instance adds identical Current HP effect")
	check_eq(player.get_max_hp(), 120, "replacement keeps final Max HP")


func test_multislot_bow_applies_effect_once_and_noop_does_not_repeat_it() -> void:
	player._current_hp = 50
	check(inventory_manager.add_item("bow", 2), "add Bow instances")
	check(equipment_manager.equip_item("bow", "weapon_1")["ok"], "equip Bow")
	check_eq(player.get_current_hp(), 70, "Bow applies Current HP effect once")
	check_eq(player.get_max_hp(), 120, "Bow applies Max HP effect once")

	check(equipment_manager.equip_item("bow", "weapon_2")["ok"], "same Bow is a no-op")
	check_eq(player.get_current_hp(), 70, "no-op does not duplicate Current HP effect")
	check_eq(player.get_max_hp(), 120, "no-op preserves Max HP")


func test_multiple_equipped_effects_aggregate() -> void:
	player._current_hp = 70
	check(inventory_manager.add_item("vital_armor"), "add armor")
	check(inventory_manager.add_item("vital_helmet"), "add helmet")
	check(equipment_manager.equip_item("vital_armor", "armor")["ok"], "equip armor")
	check(equipment_manager.equip_item("vital_helmet", "helmet")["ok"], "equip helmet")

	check_eq(player.get_current_hp(), 90, "only armor changes Current HP")
	check_eq(player.get_max_hp(), 130, "equipment effects aggregate Max HP")


func test_failed_operations_and_effectless_equipment_preserve_player_effects() -> void:
	check(inventory_manager.add_item("vital_armor"), "add armor")
	check(inventory_manager.add_item("helmet_piece"), "add effectless helmet")
	check(equipment_manager.equip_item("vital_armor", "armor")["ok"], "equip armor")
	var health_after_equip := player.get_current_hp()
	var max_hp_after_equip := player.get_max_hp()

	check_eq(equipment_manager.equip_item("helmet_piece", "missing"), _error("invalid_slot"), "invalid equip")
	check_eq(equipment_manager.unequip_item("helmet"), _error("slot_empty"), "invalid unequip")
	check_eq(player.get_current_hp(), health_after_equip, "failed operations preserve Current HP")
	check_eq(player.get_max_hp(), max_hp_after_equip, "failed operations preserve Max HP")

	check(equipment_manager.equip_item("helmet_piece", "helmet")["ok"], "equip effectless item")
	check_eq(player.get_current_hp(), health_after_equip, "effectless item preserves Current HP")
	check_eq(player.get_max_hp(), max_hp_after_equip, "effectless item preserves Max HP")


func test_invalid_equipment_effect_fails_before_inventory_or_equipment_commit() -> void:
	check(inventory_manager.add_item("invalid_effect_armor"), "add invalid-effect equipment")
	inventory_events.clear()
	equipment_events.clear()

	var result: Dictionary = equipment_manager.equip_item("invalid_effect_armor", "armor")

	check_eq(result, _error("invalid_effect"), "invalid effect result")
	check_eq(inventory_manager.get_item_count("invalid_effect_armor"), 1, "Inventory must remain unchanged")
	check_eq(equipment_manager.get_equipment()["armor"], "", "Equipment must remain unchanged")
	check_eq(player.get_current_hp(), 100, "Player Current HP must remain unchanged")
	check_eq(player.get_max_hp(), 100, "Player Max HP must remain unchanged")
	check_eq(inventory_events.size(), 0, "invalid effect must not emit inventory_changed")
	check_eq(equipment_events.size(), 0, "invalid effect must not emit equipment_changed")


func test_effect_sync_emits_player_signals_only_for_effect_changes() -> void:
	var health_events: Array = []
	var max_hp_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: max_hp_events.append(max_hp)
	)
	check(inventory_manager.add_item("helmet_piece"), "add effectless helmet")
	check(inventory_manager.add_item("vital_armor"), "add armor")

	check(equipment_manager.equip_item("helmet_piece", "helmet")["ok"], "equip effectless item")
	check_eq(health_events, [], "effectless equipment emits no health signal")
	check_eq(max_hp_events, [], "effectless equipment emits no Max HP signal")

	check(equipment_manager.equip_item("vital_armor", "armor")["ok"], "equip armor")
	check_eq(health_events, [[120, 120]], "effect equip emits final health signal")
	check_eq(max_hp_events, [120], "effect equip emits final Max HP signal")


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


func _register_equipment_definition(
	item_id: String,
	allowed_slot_types: Array[String],
	slots_required: int,
	stackable: bool = false,
	max_stack: int = 1,
	effects: Array = []
) -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = "Test %s" % item_id
	definition.description = "Test equipment definition"
	definition.icon = null
	definition.category = "Equipment"
	definition.item_type = "equipment"
	definition.tags = []
	definition.allowed_slot_types = allowed_slot_types
	definition.slots_required = slots_required
	definition.effects = effects
	definition.stackable = stackable
	definition.max_stack = max_stack

	var result: Dictionary = item_database.register_definition(definition)
	check(result["ok"], "equipment definition registration failed: %s" % result["error"])


func _error(error_code: String) -> Dictionary:
	return {"ok": false, "error": error_code}


func _max_hp_effect(value: int, hp_behavior: String) -> Dictionary:
	return {
		"type": "stat",
		"stat": "max_hp",
		"operation": "add",
		"value": value,
		"hp_behavior": hp_behavior,
	}
