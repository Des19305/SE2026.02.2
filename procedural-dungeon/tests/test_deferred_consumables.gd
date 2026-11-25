extends "res://tests/test_case.gd"

const InventoryManagerScript := preload("res://scripts/inventory/inventory_manager.gd")
const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const RunManagerScript := preload("res://scripts/run_management/run_manager.gd")

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}

class CallbackFailingPlayer extends Player:
	var callback: Callable

	func heal(_amount: int) -> Dictionary:
		if callback.is_valid():
			callback.call()
		return {"ok": false, "error": "Test healing failure"}

var item_database
var run_manager: Node
var inventory_manager
var player: Player
var inventory_events: Array = []
var item_use_events: Array = []
var applied_events: Array = []
var failed_events: Array = []


func before_each() -> void:
	item_database = ItemDatabaseScript.new()
	run_manager = RunManagerScript.new()
	run_manager.records_dir = "user://test_deferred_consumables/%d" % Time.get_ticks_usec()
	player = PlayerScript.new()
	player._current_hp = 70
	inventory_manager = InventoryManagerScript.new(item_database, run_manager)

	inventory_manager.inventory_changed.connect(
		func(items: Array) -> void: inventory_events.append(items)
	)
	inventory_manager.item_used.connect(
		func(item_id: String, result: Dictionary) -> void:
			item_use_events.append({
				"item_id": item_id,
				"result": result,
			})
	)
	inventory_manager.deferred_effect_applied.connect(
		func(request_id: int, item_id: String, result: Dictionary) -> void:
			applied_events.append({
				"request_id": request_id,
				"item_id": item_id,
				"result": result,
			})
	)
	inventory_manager.deferred_effect_failed.connect(
		func(request_id: int, item_id: String, result: Dictionary) -> void:
			failed_events.append({
				"request_id": request_id,
				"item_id": item_id,
				"result": result,
			})
	)

	_register_potion()


func after_each() -> void:
	if is_instance_valid(player):
		player.free()
	if is_instance_valid(run_manager):
		run_manager.free()


func test_deferred_acceptance_consumes_once_without_applying_effect() -> void:
	check(inventory_manager.add_item("potion", 2), "add two potions")
	inventory_events.clear()
	item_use_events.clear()

	var accepted: Dictionary = inventory_manager.queue_consumable_use(
		"potion",
		player
	)

	check_eq(accepted["ok"], true, "deferred request is accepted")
	check_eq(accepted["consumed"], true, "deferred request consumes once")
	check_eq(accepted["queued"], true, "deferred request is queued")
	check_eq(accepted["applied"], false, "deferred request is not applied immediately")
	check_eq(inventory_manager.get_item_count("potion"), 1, "exactly one potion remains")
	check_eq(inventory_manager.get_deferred_effect_count(), 1, "one effect is queued")
	check_eq(player.get_current_hp(), 70, "healing is not applied while queued")
	check_eq(inventory_events.size(), 1, "consumption publishes inventory_changed")
	check_eq(item_use_events.size(), 1, "acceptance publishes item_used")

	accepted["queued"] = false
	check_eq(
		inventory_manager.get_deferred_effect_count(),
		1,
		"mutating an acceptance result cannot mutate queue state"
	)


func test_full_hp_rejects_deferred_request_without_signals() -> void:
	player._current_hp = 100
	check(inventory_manager.add_item("potion", 1), "add potion")
	inventory_events.clear()
	item_use_events.clear()

	var result: Dictionary = inventory_manager.queue_consumable_use(
		"potion",
		player
	)

	check_eq(result["ok"], false, "full HP rejects queue request")
	check_eq(result["error"], "hp_full", "full HP rejection is identified")
	check_eq(result["consumed"], false, "full HP rejection consumes nothing")
	check_eq(result["queued"], false, "full HP rejection does not queue")
	check_eq(inventory_manager.get_item_count("potion"), 1, "potion remains owned")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "queue remains empty")
	check_eq(inventory_events.size(), 0, "full HP rejection emits no inventory_changed")
	check_eq(item_use_events.size(), 1, "full HP rejection emits item_used failure")


func test_queue_uses_deep_copied_effect_snapshot() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	var accepted: Dictionary = inventory_manager.queue_consumable_use(
		"potion",
		player
	)
	check(accepted["ok"], "potion is queued")

	var lookup: Dictionary = item_database.get_item_definition("potion")
	var definition: ItemData = lookup["definition"]
	definition.effects[0]["value"] = 99

	var flush_result: Dictionary = inventory_manager.flush_deferred_effects(player)
	check_eq(flush_result["error"], "", "snapshot flush succeeds")
	check_eq(flush_result["applied"].size(), 1, "one snapshot effect applies")
	check_eq(player.get_current_hp(), 95, "queued effect uses copied value 25")


func test_fifo_failed_entry_is_removed_and_later_entry_continues() -> void:
	check(inventory_manager.add_item("potion", 2), "add two potions")
	check(inventory_manager.queue_consumable_use("potion", player)["ok"], "queue first")
	check(inventory_manager.queue_consumable_use("potion", player)["ok"], "queue second")

	player._current_hp = 100
	inventory_manager.deferred_effect_failed.connect(
		func(_request_id: int, _item_id: String, result: Dictionary) -> void:
			if result["error"] == "hp_full":
				player._current_hp = 70
	)

	var flush_result: Dictionary = inventory_manager.flush_deferred_effects(player)

	check_eq(flush_result["ok"], false, "flush reports one failure")
	check_eq(flush_result["error"], "deferred_effect_failures", "flush failure summary")
	check_eq(flush_result["failed"].size(), 1, "only one entry fails")
	check_eq(flush_result["applied"].size(), 1, "later entry succeeds")
	check_eq(flush_result["remaining"], 0, "both entries are removed")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "queue is empty")
	check_eq(player.get_current_hp(), 95, "later effect applies in FIFO order")


func test_reentrant_flush_is_rejected() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(inventory_manager.queue_consumable_use("potion", player)["ok"], "queue potion")

	var reentrant_results: Array = []
	inventory_manager.deferred_effect_applied.connect(
		func(_request_id: int, _item_id: String, _result: Dictionary) -> void:
			reentrant_results.append(
				inventory_manager.flush_deferred_effects(player)
			)
	)

	var flush_result: Dictionary = inventory_manager.flush_deferred_effects(player)

	check_eq(reentrant_results.size(), 1, "nested flush callback executes")
	check_eq(reentrant_results[0]["error"], "flush_already_in_progress", "reentrant flush is rejected")
	check_eq(flush_result["applied"].size(), 1, "outer flush applies once")
	check_eq(player.get_current_hp(), 95, "effect applies once")


func test_callback_appended_entry_is_processed_at_tail() -> void:
	check(inventory_manager.add_item("potion", 2), "add two potions")
	check(inventory_manager.queue_consumable_use("potion", player)["ok"], "queue first")

	var callback_added := false
	player.health_changed.connect(
		func(_current_hp: int, _max_hp: int) -> void:
			if not callback_added:
				callback_added = true
				inventory_manager.queue_consumable_use("potion", player)
	)

	var flush_result: Dictionary = inventory_manager.flush_deferred_effects(player)

	check_eq(flush_result["applied"].size(), 2, "original and callback-appended entries apply")
	check_eq(flush_result["remaining"], 0, "callback-appended entry is drained")
	check_eq(player.get_current_hp(), 100, "both effects apply once in FIFO order")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "tail entry leaves the queue")


func test_run_reset_during_heal_unwinds_active_flush() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(inventory_manager.queue_consumable_use("potion", player)["ok"], "queue potion")

	var reset_started := false
	player.health_changed.connect(
		func(_current_hp: int, _max_hp: int) -> void:
			if not reset_started:
				reset_started = true
				run_manager.start_new_run(42, CONFIG)
	)

	var flush_result: Dictionary = inventory_manager.flush_deferred_effects(player)

	check_eq(flush_result["error"], "run_reset", "active flush reports Run reset")
	check_eq(flush_result["applied"].size(), 0, "old flush does not report stale application")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "Run reset clears queue")
	check_eq(flush_result["remaining"], 0, "old flush retains no stale remaining entry")


func test_run_reset_during_applied_signal_unwinds_flush() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	check(inventory_manager.queue_consumable_use("potion", player)["ok"], "queue potion")

	var reset_started := false
	inventory_manager.deferred_effect_applied.connect(
		func(_request_id: int, _item_id: String, _result: Dictionary) -> void:
			if not reset_started:
				reset_started = true
				run_manager.start_new_run(42, CONFIG)
	)

	var flush_result: Dictionary = inventory_manager.flush_deferred_effects(player)

	check_eq(flush_result["error"], "run_reset", "signal-time Run reset unwinds flush")
	check_eq(flush_result["remaining"], 0, "new Run has no old queue entry")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "queue is cleared")


func test_run_reset_during_deferred_acceptance_leaves_no_stale_queue_or_signal() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	inventory_events.clear()
	item_use_events.clear()

	var reset_started := false
	inventory_manager.inventory_changed.connect(
		func(_items: Array) -> void:
			if not reset_started:
				reset_started = true
				run_manager.start_new_run(42, CONFIG)
	)

	var result: Dictionary = inventory_manager.queue_consumable_use(
		"potion",
		player
	)

	check_eq(result["error"], "run_reset", "acceptance reports Run reset")
	check_eq(result["consumed"], false, "reset acceptance is not reported as queued consumption")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "reset acceptance leaves no stale queue")
	check_eq(item_use_events.size(), 0, "reset acceptance emits no stale item_used")


func test_run_reset_during_immediate_heal_prevents_stale_signals() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	inventory_events.clear()
	item_use_events.clear()

	var reset_started := false
	player.health_changed.connect(
		func(_current_hp: int, _max_hp: int) -> void:
			if not reset_started:
				reset_started = true
				run_manager.start_new_run(42, CONFIG)
	)

	var result: Dictionary = inventory_manager.use_item("potion", player)

	check_eq(result["error"], "run_reset", "immediate use reports Run reset")
	check_eq(result["consumed"], true, "original committed consumption is not restored")
	check_eq(item_use_events.size(), 0, "Run reset emits no stale item_used")


func test_immediate_healing_failure_with_public_mutation_skips_compensation() -> void:
	var failing_player := CallbackFailingPlayer.new()
	failing_player._current_hp = 70
	check(inventory_manager.add_item("potion", 1), "add potion")
	failing_player.callback = func() -> void:
		inventory_manager.add_item("potion", 1)

	var result: Dictionary = inventory_manager.use_item("potion", failing_player)

	check_eq(result["ok"], false, "healing failure remains a failure")
	check_eq(result["error"], "effect_failed", "failing Player reports effect failure")
	check_eq(result["consumed"], true, "compensation is skipped after public mutation")
	check_eq(inventory_manager.get_item_count("potion"), 1, "callback mutation remains authoritative")

	failing_player.free()


func test_invalid_queue_request_does_not_consume_or_enqueue() -> void:
	check(inventory_manager.add_item("potion", 1), "add potion")
	inventory_events.clear()
	item_use_events.clear()

	var invalid_user: Node = Node.new()
	var result: Dictionary = inventory_manager.queue_consumable_use(
		"potion",
		invalid_user
	)
	invalid_user.free()

	check_eq(result["ok"], false, "invalid user rejects queue")
	check_eq(result["error"], "invalid_user", "invalid user is reported")
	check_eq(result["consumed"], false, "invalid user consumes nothing")
	check_eq(result["queued"], false, "invalid user queues nothing")
	check_eq(inventory_manager.get_item_count("potion"), 1, "item remains owned")
	check_eq(inventory_manager.get_deferred_effect_count(), 0, "invalid queue leaves no entry")


func _register_potion() -> void:
	var definition: ItemData = ItemDataScript.new()
	definition.id = "potion"
	definition.name = "Healing Potion"
	definition.description = "Restores health."
	definition.icon = null
	definition.category = "Consumable"
	definition.item_type = "consumable"
	definition.tags = []
	definition.allowed_slot_types = []
	definition.slots_required = 0
	definition.effects = [{"type": "heal", "value": 25}]
	definition.stackable = true
	definition.max_stack = 3

	var result: Dictionary = item_database.register_definition(definition)
	assert(result["ok"], "deferred test potion registration failed")
