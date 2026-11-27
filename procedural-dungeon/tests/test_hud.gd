extends "res://tests/test_case.gd"

const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const EquipmentManagerScript := preload("res://scripts/inventory/equipment_manager.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const PlayerRunResetScript := preload("res://scripts/run_management/player_run_reset.gd")

const HUD_PATH := "res://scenes/hud/hud.gd"
const MainScene := preload("res://main.tscn")

var item_database
var run_manager: Node
var player: Player
var inventory_manager
var equipment_manager
var player_run_reset
var hud


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
	player_run_reset = PlayerRunResetScript.new(player, run_manager)

	_register_equipment_definition("sword", ["weapon"], 1)
	_register_equipment_definition(
		"vital_helmet",
		["helmet"],
		1,
		[_max_hp_effect(10, "increase_max_only")]
	)
	_register_definition(
		"potion",
		"Consumable",
		"consumable",
		true,
		3,
		[{"type": "heal", "value": 25}]
	)

	hud = _create_hud()


func after_each() -> void:
	if is_instance_valid(hud):
		hud.free()
	hud = null
	player_run_reset = null
	equipment_manager = null
	inventory_manager = null
	player.free()
	run_manager.free()


func test_initial_hud_state_uses_real_owner_getters() -> void:
	if hud == null:
		return

	check_eq(hud.get_display_state(), {
		"current_hp": 100,
		"max_hp": 100,
		"seed": "—",
		"inventory_used": 0,
		"inventory_capacity": 12,
		"equipment": {
			"weapon_1": "",
			"weapon_2": "",
			"helmet": "",
			"armor": "",
			"boots": "",
			"accessory_1": "",
			"accessory_2": "",
		},
	}, "initial HUD state")


func test_main_initializes_scripted_hud_instance() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame

	print("HUD_DIAGNOSTIC main_valid=%s main_in_tree=%s main_hud_null=%s hud_valid=%s hud_in_tree=%s" % [
		is_instance_valid(main),
		main.is_inside_tree(),
		main.hud == null,
		is_instance_valid(main.hud),
		is_instance_valid(main.hud) and main.hud.is_inside_tree(),
	])

	var hud_instance: Node = main.find_child("HUD", true, false)
	check(hud_instance != null, "Main should instantiate a HUD scene")
	if hud_instance != null:
		check(hud_instance is HUD, "HUD scene should resolve as the HUD script instance")
		check(hud_instance.has_method("setup"), "HUD instance should expose setup")
		check(hud_instance.has_method("get_display_state"), "HUD instance should expose get_display_state")
		if hud_instance is HUD:
			var hud_typed: HUD = hud_instance as HUD
			var state: Dictionary = hud_typed.get_display_state()
			check_eq(state["current_hp"], 100, "Main HUD starts with Current HP")
			check_eq(state["max_hp"], 100, "Main HUD starts with Max HP")
			check_eq(state["inventory_capacity"], 12, "Main HUD starts with base Inventory capacity")
			check_eq(state["seed"], "42", "Main HUD starts with successful startup seed")

	main.queue_free()
	await tree.process_frame


func test_hp_and_max_hp_signals_update_observable_state() -> void:
	if hud == null:
		return

	var current_result: Dictionary = player.set_max_hp_effects({
		"helmet_instance_1": _max_hp_effect(10, "increase_max_only"),
	})
	check(current_result["ok"], "valid Max HP update")
	check_eq(hud.get_display_state()["current_hp"], 100, "max-only preserves displayed Current HP")
	check_eq(hud.get_display_state()["max_hp"], 110, "displayed Max HP updates")

	var health_result: Dictionary = player.heal(5)
	check(health_result["ok"], "healing at Current HP 100/110 is valid and should succeed")
	check_eq(hud.get_display_state()["current_hp"], 105, "health_changed updates displayed Current HP")
	check_eq(hud.get_display_state()["max_hp"], 110, "health update preserves displayed Max HP")


func test_equipment_and_dynamic_slots_refresh_from_real_signals() -> void:
	if hud == null:
		return

	check(inventory_manager.add_item("sword"), "add sword")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip sword")
	check_eq(
		hud.get_display_state()["equipment"]["weapon_1"],
		"sword",
		"equipment_changed refreshes real snapshot"
	)

	check(equipment_manager.add_slot("extra_helmet", "helmet")["ok"], "add dynamic helmet slot")
	check_eq(
		hud.get_display_state()["equipment"].has("extra_helmet"),
		true,
		"equipment_slots_changed refresh includes dynamic slot"
	)

	check(inventory_manager.add_item("vital_helmet"), "add dynamic-slot helmet")
	check(
		equipment_manager.equip_item("vital_helmet", "extra_helmet")["ok"],
		"equip item in dynamic slot"
	)
	check_eq(
		hud.get_display_state()["equipment"]["extra_helmet"],
		"vital_helmet",
		"dynamic slot equipment snapshot updates"
	)

	check(equipment_manager.unequip_item("extra_helmet")["ok"], "unequip dynamic-slot item")
	check_eq(
		hud.get_display_state()["equipment"]["extra_helmet"],
		"",
		"unequip refreshes dynamic slot"
	)


func test_inventory_summary_and_capacity_refresh_from_real_signals() -> void:
	if hud == null:
		return

	check(inventory_manager.add_item("potion", 3), "add potion")
	check_eq(hud.get_display_state()["inventory_used"], 1, "Inventory add updates used slots")
	check_eq(hud.get_display_state()["inventory_capacity"], 12, "initial capacity remains 12")

	check(inventory_manager.upgrade_capacity()["ok"], "upgrade capacity")
	check_eq(hud.get_display_state()["inventory_used"], 1, "upgrade preserves inventory summary")
	check_eq(hud.get_display_state()["inventory_capacity"], 14, "capacity upgrade updates summary")


func test_capacity_upgrade_inventory_hud_flow() -> void:
	if hud == null:
		return

	check(inventory_manager.add_item("potion", 5), "add five potions")
	check(inventory_manager.add_item("sword", 3), "add three swords")

	var initial_snapshot: Array = inventory_manager.get_items()
	var initial_used_slots: int = inventory_manager.get_used_slots()
	var upgrade_payloads: Array = []
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void: upgrade_payloads.append(items)
	)

	check_eq(inventory_manager.get_max_slots(), 12, "initial capacity is 12")
	check_eq(initial_used_slots, 5, "mixed inventory uses five slots")
	check_eq(initial_snapshot, [
		{"item_id": "potion", "amount": 3},
		{"item_id": "potion", "amount": 2},
		{"item_id": "sword", "amount": 1},
		{"item_id": "sword", "amount": 1},
		{"item_id": "sword", "amount": 1},
	], "initial inventory snapshot")
	check_eq(
		hud.get_display_state()["inventory_used"],
		5,
		"HUD reflects initial inventory usage"
	)
	check_eq(
		hud.get_display_state()["inventory_capacity"],
		12,
		"HUD reflects initial inventory capacity"
	)

	var first_result: Dictionary = inventory_manager.upgrade_capacity()
	check(first_result["ok"], "first capacity upgrade succeeds")
	check_eq(inventory_manager.get_max_slots(), 14, "first upgrade increases capacity to 14")
	check_eq(inventory_manager.get_used_slots(), initial_used_slots, "first upgrade preserves used slots")
	check_eq(inventory_manager.get_items(), initial_snapshot, "first upgrade preserves inventory snapshot")
	check_eq(upgrade_payloads.size(), 1, "first upgrade emits one inventory_changed signal")
	check_eq(upgrade_payloads.back(), initial_snapshot, "first upgrade payload preserves inventory snapshot")
	check_eq(
		hud.get_display_state()["inventory_used"],
		5,
		"HUD preserves inventory usage after first upgrade"
	)
	check_eq(
		hud.get_display_state()["inventory_capacity"],
		14,
		"HUD reflects capacity after first upgrade"
	)

	var second_result: Dictionary = inventory_manager.upgrade_capacity()
	check(second_result["ok"], "second capacity upgrade succeeds")
	check_eq(inventory_manager.get_max_slots(), 16, "second upgrade increases capacity to 16")
	check_eq(inventory_manager.get_used_slots(), initial_used_slots, "second upgrade preserves used slots")
	check_eq(inventory_manager.get_items(), initial_snapshot, "second upgrade preserves inventory snapshot")
	check_eq(upgrade_payloads.size(), 2, "two successful upgrades emit two inventory_changed signals")
	check_eq(upgrade_payloads.back(), initial_snapshot, "second upgrade payload preserves inventory snapshot")
	check_eq(
		hud.get_display_state()["inventory_used"],
		5,
		"HUD preserves inventory usage after second upgrade"
	)
	check_eq(
		hud.get_display_state()["inventory_capacity"],
		16,
		"HUD reflects capacity after second upgrade"
	)

	var before_failed_capacity: int = inventory_manager.get_max_slots()
	var before_failed_used_slots: int = inventory_manager.get_used_slots()
	var before_failed_snapshot: Array = inventory_manager.get_items()
	var before_failed_payload_count: int = upgrade_payloads.size()
	var third_result: Dictionary = inventory_manager.upgrade_capacity()

	check(not third_result["ok"], "third capacity upgrade fails at the limit")
	check(third_result["error"].contains("limit"), "third upgrade reports the upgrade limit")
	check_eq(inventory_manager.get_max_slots(), before_failed_capacity, "failed upgrade preserves capacity")
	check_eq(inventory_manager.get_used_slots(), before_failed_used_slots, "failed upgrade preserves used slots")
	check_eq(inventory_manager.get_items(), before_failed_snapshot, "failed upgrade preserves inventory snapshot")
	check_eq(
		upgrade_payloads.size(),
		before_failed_payload_count,
		"failed upgrade emits no inventory_changed signal"
	)
	check_eq(
		hud.get_display_state()["inventory_used"],
		5,
		"HUD preserves inventory usage after failed upgrade"
	)
	check_eq(
		hud.get_display_state()["inventory_capacity"],
		16,
		"HUD remains consistent after failed upgrade"
	)


func test_healing_item_updates_inventory_player_and_hud() -> void:
	if hud == null:
		return

	var max_hp_result: Dictionary = player.set_max_hp_effects({
		"healing_test_source": _max_hp_effect(20, "increase_max_only"),
	})
	check(max_hp_result["ok"], "valid Max HP setup succeeds")
	check_eq(player.get_current_hp(), 100, "Player starts at 100 Current HP")
	check_eq(player.get_max_hp(), 120, "Player starts at 120 Max HP")
	check_eq(hud.get_display_state()["current_hp"], 100, "HUD starts at 100 Current HP")
	check_eq(hud.get_display_state()["max_hp"], 120, "HUD starts at 120 Max HP")

	check(inventory_manager.add_item("potion"), "add exactly one potion")
	check_eq(inventory_manager.get_item_count("potion"), 1, "potion count is one")
	check_eq(inventory_manager.get_used_slots(), 1, "potion uses one slot")
	check_eq(hud.get_display_state()["inventory_used"], 1, "HUD shows one used inventory slot")
	check_eq(hud.get_display_state()["inventory_capacity"], 12, "HUD shows base inventory capacity")

	var health_events: Array = []
	var inventory_events: Array = []
	var item_use_events: Array = []

	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void:
			health_events.append([current_hp, max_hp])
	)
	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void:
			inventory_events.append(items)
	)
	inventory_manager.item_used.connect(
		func(item_id: String, result: Dictionary) -> void:
			item_use_events.append({
				"item_id": item_id,
				"result": result,
			})
	)

	var successful_result: Dictionary = inventory_manager.use_item("potion", player)

	check_eq(successful_result, {
		"ok": true,
		"error": "",
		"item_id": "potion",
		"consumed": true,
	}, "healing use succeeds and consumes the potion")
	check_eq(item_use_events.size(), 1, "successful use emits item_used once")
	check_eq(health_events, [[120, 120]], "successful use emits one clamped health_changed")
	check_eq(inventory_events.size(), 1, "successful use emits one inventory_changed")
	check_eq(inventory_events.back(), [], "successful use publishes empty inventory snapshot")
	check_eq(player.get_current_hp(), 120, "successful use clamps Player HP at Max HP")
	check_eq(player.get_max_hp(), 120, "successful use preserves Max HP")
	check_eq(inventory_manager.get_item_count("potion"), 0, "successful use consumes potion")
	check_eq(inventory_manager.get_used_slots(), 0, "successful use releases inventory slot")
	check_eq(inventory_manager.get_items(), [], "successful use leaves empty inventory snapshot")

	var state_after_success: Dictionary = hud.get_display_state()
	check_eq(state_after_success["current_hp"], 120, "HUD reflects clamped Current HP")
	check_eq(state_after_success["max_hp"], 120, "HUD reflects Max HP")
	check_eq(state_after_success["inventory_used"], 0, "HUD reflects released inventory slot")
	check_eq(state_after_success["inventory_capacity"], 12, "HUD reflects inventory capacity")

	var failed_result: Dictionary = inventory_manager.use_item("potion", player)

	check_eq(failed_result, {
		"ok": false,
		"error": "item_not_owned",
		"item_id": "potion",
		"consumed": false,
	}, "second use fails because potion is no longer owned")
	check_eq(item_use_events.size(), 2, "failed use emits item_used once more")
	check_eq(health_events, [[120, 120]], "failed use emits no additional health_changed")
	check_eq(inventory_events.size(), 1, "failed use emits no additional inventory_changed")
	check_eq(player.get_current_hp(), 120, "failed use leaves Current HP unchanged")
	check_eq(player.get_max_hp(), 120, "failed use leaves Max HP unchanged")
	check_eq(inventory_manager.get_item_count("potion"), 0, "failed use leaves potion count unchanged")
	check_eq(inventory_manager.get_used_slots(), 0, "failed use leaves used slots unchanged")
	check_eq(inventory_manager.get_items(), [], "failed use leaves inventory snapshot unchanged")

	var state_after_failure: Dictionary = hud.get_display_state()
	check_eq(state_after_failure, state_after_success, "failed use leaves HUD state unchanged")


func test_run_seed_updates_from_run_started_and_failed_starts_preserve_seed() -> void:
	if hud == null:
		return

	check_eq(hud.get_display_state()["seed"], "—", "seed starts as placeholder")

	var result: Dictionary = run_manager.start_new_run(42, _run_config())
	check(result["ok"], "run should start: %s" % result["error"])
	check_eq(hud.get_display_state()["seed"], "42", "run_started updates seed")

	var before_failed_seed: String = hud.get_display_state()["seed"]
	var invalid_config := _run_config()
	invalid_config["width"] = 201
	check(not run_manager.start_new_run(43, invalid_config)["ok"], "failed run should fail")
	check_eq(hud.get_display_state()["seed"], before_failed_seed, "failed run preserves seed")


func test_run_reset_integration_refreshes_all_owned_state() -> void:
	if hud == null:
		return

	check(inventory_manager.add_item("potion", 2), "add inventory item")
	check(inventory_manager.upgrade_capacity()["ok"], "upgrade inventory")
	check(inventory_manager.add_item("sword"), "add sword")
	check(equipment_manager.add_slot("extra_helmet", "helmet")["ok"], "add dynamic slot")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip sword")
	check(inventory_manager.add_item("vital_helmet"), "add vital helmet")
	check(equipment_manager.equip_item("vital_helmet", "helmet")["ok"], "equip Max HP equipment")

	var result: Dictionary = run_manager.start_new_run(73, _run_config())
	check(result["ok"], "run should start: %s" % result["error"])

	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame

	var state: Dictionary = hud.get_display_state()
	check_eq(state["seed"], "73", "successful run updates seed")
	check_eq(state["current_hp"], 100, "run reset restores Current HP")
	check_eq(state["max_hp"], 100, "run reset restores Max HP")
	check_eq(state["inventory_used"], 0, "run reset clears Inventory summary")
	check_eq(state["inventory_capacity"], 12, "run reset restores base capacity")
	check_eq(state["equipment"]["weapon_1"], "", "run reset clears equipped snapshot")
	check_eq(state["equipment"].has("extra_helmet"), false, "run reset removes dynamic slot")


func test_same_seed_replay_resets_composed_owner_state() -> void:
	if hud == null:
		return

	var initial_result: Dictionary = run_manager.start_new_run(73, _run_config())
	check(initial_result["ok"], "initial run should start: %s" % initial_result["error"])
	run_manager.end_run(false, "prepare replay")

	check(inventory_manager.add_item("potion", 2), "add two potions")
	check(inventory_manager.add_item("sword"), "add sword")
	check(inventory_manager.add_item("vital_helmet"), "add vital helmet")
	check(inventory_manager.upgrade_capacity()["ok"], "first capacity upgrade succeeds")
	check(inventory_manager.upgrade_capacity()["ok"], "second capacity upgrade succeeds")
	check(equipment_manager.equip_item("sword", "weapon_1")["ok"], "equip sword")
	check(equipment_manager.equip_item("vital_helmet", "helmet")["ok"], "equip vital helmet")

	check_eq(inventory_manager.get_max_slots(), 16, "pre-replay capacity is 16")
	check_eq(inventory_manager.get_used_slots(), 1, "pre-replay inventory uses one slot")
	check_eq(inventory_manager.get_items(), [
		{"item_id": "potion", "amount": 2},
	], "pre-replay inventory contains exactly two potions")
	check_eq(
		equipment_manager.get_equipment()["weapon_1"],
		"sword",
		"pre-replay sword is equipped"
	)
	check_eq(
		equipment_manager.get_equipment()["helmet"],
		"vital_helmet",
		"pre-replay vital helmet is equipped"
	)
	check_eq(player.get_current_hp(), 100, "pre-replay Current HP remains 100")
	check_eq(player.get_max_hp(), 110, "pre-replay Max HP is 110")

	check(
		equipment_manager.add_slot("extra_helmet", "helmet")["ok"],
		"add dynamic helmet slot"
	)
	check(equipment_manager.has_slot("extra_helmet"), "dynamic slot exists")
	check_eq(
		equipment_manager.get_slot_type("extra_helmet"),
		"helmet",
		"dynamic slot type"
	)
	check(
		equipment_manager.get_equipment().has("extra_helmet"),
		"dynamic slot appears in equipment snapshot"
	)

	var replay_events: Array[Dictionary] = []
	run_manager.run_started.connect(
		func(run_seed: int, _dungeon: Dictionary) -> void:
			replay_events.append({"seed": run_seed})
	)

	var replay_result: Dictionary = run_manager.replay_last_run()

	check(replay_result["ok"], "same-seed replay should start: %s" % replay_result["error"])
	check_eq(replay_result["seed"], 73, "replay retains the exact seed")
	check_eq(replay_events.size(), 1, "replay emits one run_started event")
	if replay_events.size() == 1:
		check_eq(replay_events[0]["seed"], 73, "run_started replay seed is 73")

	check_eq(inventory_manager.get_items(), [], "replay clears inventory")
	check_eq(inventory_manager.get_used_slots(), 0, "replay restores used slots to zero")
	check_eq(inventory_manager.get_max_slots(), 12, "replay restores base capacity")
	check_eq(
		equipment_manager.get_equipment(),
		{
			"weapon_1": "",
			"weapon_2": "",
			"helmet": "",
			"armor": "",
			"boots": "",
			"accessory_1": "",
			"accessory_2": "",
		},
		"replay clears equipment to default slots"
	)
	check(not equipment_manager.has_slot("extra_helmet"), "replay removes dynamic slot")
	check_eq(
		equipment_manager.get_slot_type("extra_helmet"),
		"",
		"replay removes dynamic slot type"
	)
	check(
		not equipment_manager.get_equipment().has("extra_helmet"),
		"replay removes dynamic slot snapshot"
	)
	check_eq(player.get_current_hp(), 100, "replay restores Current HP")
	check_eq(player.get_max_hp(), 100, "replay restores Max HP")

	var state: Dictionary = hud.get_display_state()
	check_eq(state["inventory_used"], 0, "HUD reflects replay inventory usage")
	check_eq(state["inventory_capacity"], 12, "HUD reflects replay base capacity")
	check_eq(state["equipment"], equipment_manager.get_equipment(), "HUD reflects cleared equipment")
	check_eq(state["current_hp"], 100, "HUD reflects replay Current HP")
	check_eq(state["max_hp"], 100, "HUD reflects replay Max HP")
	check_eq(state["seed"], "73", "HUD reflects replay seed")


func _create_hud() -> Variant:
	var hud_script: Variant = load(HUD_PATH)
	check(hud_script != null, "planned HUD script should exist at %s" % HUD_PATH)
	if hud_script == null:
		return null
	return hud_script.new(
		player,
		equipment_manager,
		inventory_manager,
		run_manager
	)


func _register_definition(
	item_id: String,
	item_category: String,
	item_type_value: String,
	is_stackable: bool,
	item_max_stack: int,
	effects: Array = []
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
	definition.effects = effects
	definition.stackable = is_stackable
	definition.max_stack = item_max_stack

	var result: Dictionary = item_database.register_definition(definition)
	check(result["ok"], "definition registration failed: %s" % result["error"])


func _register_equipment_definition(
	item_id: String,
	allowed_slot_types: Array[String],
	slots_required: int,
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
	definition.stackable = false
	definition.max_stack = 1

	var result: Dictionary = item_database.register_definition(definition)
	check(result["ok"], "equipment definition failed: %s" % result["error"])


func _max_hp_effect(value: int, hp_behavior: String) -> Dictionary:
	return {
		"type": "stat",
		"stat": "max_hp",
		"operation": "add",
		"value": value,
		"hp_behavior": hp_behavior,
	}


func _run_config() -> Dictionary:
	return {
		"width": 50,
		"height": 50,
		"min_rooms": 8,
		"max_rooms": 12,
		"min_room_size": 5,
		"max_room_size": 10,
	}



