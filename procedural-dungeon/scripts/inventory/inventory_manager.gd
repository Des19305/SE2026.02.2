class_name InventoryManager
extends RefCounted

signal inventory_changed(items: Array)
signal item_used(item_id: String, result: Dictionary)
signal deferred_effect_applied(request_id: int, item_id: String, result: Dictionary)
signal deferred_effect_failed(request_id: int, item_id: String, result: Dictionary)

const _INITIAL_CAPACITY := 12
const _UPGRADE_AMOUNT := 2
const _MAX_CAPACITY_UPGRADES := 2

var _item_database: ItemDatabase
var _run_manager: Node
var _item_counts: Dictionary = {}
var _max_slots: int = _INITIAL_CAPACITY
var _capacity_upgrade_count: int = 0
var _deferred_effect_queue: Array[Dictionary] = []
var _deferred_request_sequence: int = 0
var _deferred_generation: int = 0
var _deferred_flush_active: bool = false
var _inventory_mutation_version: int = 0


func _init(item_database: ItemDatabase, run_manager: Node) -> void:
	assert(item_database != null, "InventoryManager requires an ItemDatabase")
	assert(run_manager != null, "InventoryManager requires a RunManager")

	_item_database = item_database
	_run_manager = run_manager
	_run_manager.connect(&"run_started", _on_run_started)


func add_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false

	var lookup: Dictionary = _item_database.get_item_definition(item_id)
	if not lookup["ok"]:
		return false

	var definition: ItemData = lookup["definition"]
	var current_amount: int = get_item_count(item_id)
	var current_slots := _slots_for_amount(current_amount, definition)
	var updated_slots := _slots_for_amount(current_amount + amount, definition)
	var resulting_used_slots := get_used_slots() - current_slots + updated_slots
	if resulting_used_slots > _max_slots:
		return false

	_item_counts[item_id] = current_amount + amount
	_inventory_mutation_version += 1
	_emit_inventory_changed()
	return true


func remove_item(item_id: String, amount: int = 1) -> bool:
	var lookup: Dictionary = _item_database.get_item_definition(item_id)
	if not lookup["ok"]:
		return false

	if amount <= 0:
		return false

	var current_amount: int = get_item_count(item_id)
	if current_amount < amount:
		return false

	var updated_amount := current_amount - amount
	if updated_amount == 0:
		_item_counts.erase(item_id)
	else:
		_item_counts[item_id] = updated_amount

	_inventory_mutation_version += 1
	_emit_inventory_changed()
	return true


func preflight_transfer_batch(removals: Dictionary, additions: Dictionary) -> Dictionary:
	var batch: Dictionary = _build_transfer_batch(removals, additions)
	return {"ok": batch["ok"], "error": batch["error"]}


func commit_transfer_batch(removals: Dictionary, additions: Dictionary) -> bool:
	var batch: Dictionary = _build_transfer_batch(removals, additions)
	assert(batch["ok"], "Batch transfer commit requires a successful, unchanged preflight")

	var final_counts: Dictionary = batch["item_counts"]
	var changed := _item_counts != final_counts
	if changed:
		_item_counts = final_counts
		_inventory_mutation_version += 1
	return changed


func publish_transfer_batch(changed: bool) -> void:
	if changed:
		_emit_inventory_changed()


func use_item(item_id: String, user: Node) -> Dictionary:
	var result := {
		"ok": false,
		"error": "",
		"item_id": item_id,
		"consumed": false,
	}
	var validation: Dictionary = _validate_consumable_request(item_id, user)
	if not validation["ok"]:
		result["error"] = validation["error"]
		return _finish_item_use(item_id, result)

	var player: Player = user
	if player.get_current_hp() >= player.get_max_hp():
		result["error"] = "hp_full"
		return _finish_item_use(item_id, result)

	var preflight: Dictionary = preflight_transfer_batch(
		{item_id: 1},
		{}
	)
	if not preflight["ok"]:
		result["error"] = "item_not_owned"
		return _finish_item_use(item_id, result)

	var use_generation := _deferred_generation
	commit_transfer_batch({item_id: 1}, {})
	var mutation_version_after_commit := _inventory_mutation_version

	var healing_effect: Dictionary = validation["effect"]
	var heal_result: Dictionary = player.heal(healing_effect["value"])

	if _deferred_generation != use_generation:
		result["ok"] = false
		result["error"] = "run_reset"
		result["consumed"] = true
		return result.duplicate(true)

	if heal_result.get("ok", false):
		result["ok"] = true
		result["consumed"] = true

		if _inventory_mutation_version == mutation_version_after_commit:
			publish_transfer_batch(true)
		else:
			# Public Inventory callbacks already published their own state changes.
			pass

		if _deferred_generation != use_generation:
			result["ok"] = false
			result["error"] = "run_reset"
			result["consumed"] = true
			return result.duplicate(true)

		return _finish_item_use(item_id, result)

	if _deferred_generation != use_generation:
		result["error"] = "run_reset"
		result["consumed"] = true
		return result.duplicate(true)

	var healing_error := str(heal_result.get("error", "effect_failed"))
	result["error"] = "hp_full" if healing_error == "hp_full" or player.get_current_hp() >= player.get_max_hp() else "effect_failed"

	if _inventory_mutation_version == mutation_version_after_commit:
		var restore_preflight: Dictionary = preflight_transfer_batch(
			{},
			{item_id: 1}
		)
		if restore_preflight["ok"]:
			commit_transfer_batch({}, {item_id: 1})
			result["consumed"] = false
		else:
			result["consumed"] = true
	else:
		result["consumed"] = true

	if _deferred_generation != use_generation:
		result["error"] = "run_reset"
		result["consumed"] = true
		return result.duplicate(true)

	return _finish_item_use(item_id, result)


func queue_consumable_use(item_id: String, user: Node) -> Dictionary:
	var validation: Dictionary = _validate_consumable_request(item_id, user)
	if not validation["ok"]:
		return _deferred_rejected_result(
			item_id,
			validation["error"]
		)

	var player: Player = user
	if player.get_current_hp() >= player.get_max_hp():
		return _deferred_rejected_result(item_id, "hp_full")

	var preflight: Dictionary = preflight_transfer_batch(
		{item_id: 1},
		{}
	)
	if not preflight["ok"]:
		return _deferred_rejected_result(item_id, "item_not_owned")

	var request_generation := _deferred_generation
	commit_transfer_batch({item_id: 1}, {})

	_deferred_request_sequence += 1
	var effect: Dictionary = validation["effect"].duplicate(true)
	var entry: Dictionary = {
		"run_generation": request_generation,
		"request_id": _deferred_request_sequence,
		"item_id": item_id,
		"effect": effect,
	}
	_deferred_effect_queue.append(entry)

	publish_transfer_batch(true)

	if _deferred_generation != request_generation:
		return _run_reset_deferred_result(item_id)

	var accepted: Dictionary = {
		"ok": true,
		"error": "",
		"item_id": item_id,
		"consumed": true,
		"queued": true,
		"applied": false,
		"request_id": _deferred_request_sequence,
	}
	var accepted_snapshot: Dictionary = accepted.duplicate(true)
	_finish_item_use(item_id, accepted_snapshot)

	if _deferred_generation != request_generation:
		return _run_reset_deferred_result(item_id)

	return accepted.duplicate(true)


func flush_deferred_effects(user: Node) -> Dictionary:
	if _deferred_flush_active:
		return {
			"ok": false,
			"error": "flush_already_in_progress",
			"applied": [],
			"failed": [],
			"remaining": _deferred_effect_queue.size(),
		}

	_deferred_flush_active = true
	var flush_generation := _deferred_generation
	var applied: Array = []
	var failed: Array = []

	while not _deferred_effect_queue.is_empty():
		if _deferred_generation != flush_generation:
			break

		var entry: Dictionary = _deferred_effect_queue.front()
		if entry["run_generation"] != flush_generation:
			break

		var result: Dictionary
		if not is_instance_valid(user) or not (user is Player):
			result = _failed_deferred_result(entry, "invalid_user")
		else:
			var player: Player = user
			if player.get_current_hp() >= player.get_max_hp():
				result = _failed_deferred_result(entry, "hp_full")
			else:
				var effect: Dictionary = entry["effect"]
				var heal_result: Dictionary = player.heal(effect["value"])

				if _deferred_generation != flush_generation:
					break

				if heal_result.get("ok", false):
					result = _applied_deferred_result(entry)
				else:
					var heal_error := str(heal_result.get("error", "effect_failed"))
					result = _failed_deferred_result(
						entry,
						"effect_failed" if heal_error != "hp_full" else "hp_full"
					)

		if not _remove_deferred_head(
			flush_generation,
			entry["request_id"]
		):
			break

		var independent_result: Dictionary = result.duplicate(true)
		if independent_result["ok"]:
			applied.append(independent_result.duplicate(true))
			var applied_payload: Dictionary = independent_result.duplicate(true)
			applied_payload.make_read_only()
			deferred_effect_applied.emit(
				entry["request_id"],
				entry["item_id"],
				applied_payload
			)
		else:
			failed.append(independent_result.duplicate(true))
			var failed_payload: Dictionary = independent_result.duplicate(true)
			failed_payload.make_read_only()
			deferred_effect_failed.emit(
				entry["request_id"],
				entry["item_id"],
				failed_payload
			)

		if _deferred_generation != flush_generation:
			break

	_deferred_flush_active = false

	var run_reset_during_flush := _deferred_generation != flush_generation
	return {
		"ok": false if run_reset_during_flush or not failed.is_empty() else true,
		"error": (
			"run_reset"
			if run_reset_during_flush
			else "deferred_effect_failures" if not failed.is_empty()
			else ""
		),
		"applied": applied,
		"failed": failed,
		"remaining": _deferred_effect_queue.size(),
	}


func get_deferred_effect_count() -> int:
	return _deferred_effect_queue.size()


func get_items() -> Array:
	var snapshot: Array = []
	var item_ids: Array = _item_counts.keys()
	item_ids.sort()

	for item_id in item_ids:
		var lookup: Dictionary = _item_database.get_item_definition(item_id)
		assert(lookup["ok"], "Registered Inventory item must have a definition")
		var definition: ItemData = lookup["definition"]
		var remaining_amount: int = _item_counts[item_id]

		while remaining_amount > 0:
			var stack_amount: int = min(remaining_amount, definition.max_stack)
			snapshot.append({
				"item_id": item_id,
				"amount": stack_amount,
			})
			remaining_amount -= stack_amount

	return snapshot


func get_item_count(item_id: String) -> int:
	return _item_counts.get(item_id, 0)


func get_max_slots() -> int:
	return _max_slots


func get_used_slots() -> int:
	var used_slots := 0
	for item_id in _item_counts:
		var lookup: Dictionary = _item_database.get_item_definition(item_id)
		assert(lookup["ok"], "Registered Inventory item must have a definition")
		var definition: ItemData = lookup["definition"]
		used_slots += _slots_for_amount(_item_counts[item_id], definition)
	return used_slots


func upgrade_capacity() -> Dictionary:
	if _capacity_upgrade_count >= _MAX_CAPACITY_UPGRADES:
		return {
			"ok": false,
			"error": "Inventory capacity upgrade limit reached",
		}

	_max_slots += _UPGRADE_AMOUNT
	_capacity_upgrade_count += 1
	_inventory_mutation_version += 1
	_emit_inventory_changed()
	return {"ok": true, "error": ""}


func _validate_consumable_request(item_id: String, user: Node) -> Dictionary:
	var lookup: Dictionary = _item_database.get_item_definition(item_id)
	if not lookup["ok"]:
		return {"ok": false, "error": "invalid_item", "effect": {}}

	if not is_instance_valid(user) or not (user is Player):
		return {"ok": false, "error": "invalid_user", "effect": {}}

	if get_item_count(item_id) <= 0:
		return {"ok": false, "error": "item_not_owned", "effect": {}}

	var definition: ItemData = lookup["definition"]
	if definition.item_type != "consumable" or definition.effects.size() != 1:
		return {"ok": false, "error": "item_not_usable", "effect": {}}

	var effect: Variant = definition.effects[0]
	if not (effect is Dictionary):
		return {"ok": false, "error": "item_not_usable", "effect": {}}

	var healing_effect: Dictionary = effect
	if not healing_effect.has("type") or healing_effect["type"] != "heal":
		return {"ok": false, "error": "item_not_usable", "effect": {}}

	for key in healing_effect:
		if key != "type" and key != "value":
			return {"ok": false, "error": "item_not_usable", "effect": {}}

	if not healing_effect.has("value"):
		return {"ok": false, "error": "effect_failed", "effect": {}}

	var healing_value: Variant = healing_effect["value"]
	if typeof(healing_value) != TYPE_INT or healing_value <= 0:
		return {"ok": false, "error": "effect_failed", "effect": {}}

	return {
		"ok": true,
		"error": "",
		"effect": {
			"type": "heal",
			"value": healing_value,
		},
	}


func _deferred_rejected_result(item_id: String, error: String) -> Dictionary:
	var result := {
		"ok": false,
		"error": error,
		"item_id": item_id,
		"consumed": false,
		"queued": false,
		"applied": false,
		"request_id": 0,
	}
	_finish_item_use(item_id, result)
	return result.duplicate(true)


func _run_reset_deferred_result(item_id: String) -> Dictionary:
	return {
		"ok": false,
		"error": "run_reset",
		"item_id": item_id,
		"consumed": false,
		"queued": false,
		"applied": false,
		"request_id": 0,
	}


func _remove_deferred_head(generation: int, request_id: int) -> bool:
	if _deferred_effect_queue.is_empty():
		return false

	var entry: Dictionary = _deferred_effect_queue.front()
	if entry["run_generation"] != generation:
		return false
	if entry["request_id"] != request_id:
		return false

	_deferred_effect_queue.remove_at(0)
	return true


func _applied_deferred_result(entry: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"error": "",
		"request_id": entry["request_id"],
		"item_id": entry["item_id"],
		"consumed": true,
		"applied": true,
	}


func _failed_deferred_result(entry: Dictionary, error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"request_id": entry["request_id"],
		"item_id": entry["item_id"],
		"consumed": true,
		"applied": false,
	}


func _slots_for_amount(amount: int, definition: ItemData) -> int:
	if amount <= 0:
		return 0

	var slots := ceili(float(amount) / float(definition.max_stack))
	return slots


func _build_transfer_batch(removals: Dictionary, additions: Dictionary) -> Dictionary:
	var definitions: Dictionary = {}
	for changes in [removals, additions]:
		for item_key in changes:
			if typeof(item_key) != TYPE_STRING or item_key.is_empty():
				return _transfer_batch_failure("Item IDs must be non-empty strings")

			var amount: Variant = changes[item_key]
			if typeof(amount) != TYPE_INT or amount <= 0:
				return _transfer_batch_failure("Transfer amounts must be positive integers")

			var item_id: String = item_key
			if definitions.has(item_id):
				continue

			var lookup: Dictionary = _item_database.get_item_definition(item_id)
			if not lookup["ok"]:
				return _transfer_batch_failure(lookup["error"])
			definitions[item_id] = lookup["definition"]

	var final_counts: Dictionary = _item_counts.duplicate()
	for item_key in removals:
		var item_id: String = item_key
		var current_amount: int = final_counts.get(item_id, 0)
		var removal_amount: int = removals[item_key]
		if current_amount < removal_amount:
			return _transfer_batch_failure("Insufficient inventory quantity for %s" % item_id)

		var remaining_amount := current_amount - removal_amount
		if remaining_amount == 0:
			final_counts.erase(item_id)
		else:
			final_counts[item_id] = remaining_amount

	for item_key in additions:
		var item_id: String = item_key
		final_counts[item_id] = final_counts.get(item_id, 0) + additions[item_key]

	var used_slots := 0
	for item_key in final_counts:
		var item_id: String = item_key
		var definition: ItemData
		if definitions.has(item_id):
			definition = definitions[item_id]
		else:
			var lookup: Dictionary = _item_database.get_item_definition(item_id)
			if not lookup["ok"]:
				return _transfer_batch_failure(lookup["error"])
			definition = lookup["definition"]
		used_slots += _slots_for_amount(final_counts[item_id], definition)

	if used_slots > _max_slots:
		return _transfer_batch_failure("Inventory capacity exceeded")

	return {
		"ok": true,
		"error": "",
		"item_counts": final_counts,
	}


func _transfer_batch_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "item_counts": {}}


func _emit_inventory_changed() -> void:
	var items := get_items()
	for item in items:
		item.make_read_only()
	items.make_read_only()
	inventory_changed.emit(items)


func _finish_item_use(item_id: String, result: Dictionary) -> Dictionary:
	var signal_result := result.duplicate(true)
	signal_result.make_read_only()
	item_used.emit(item_id, signal_result)
	return result


func _on_run_started(_seed: int, _dungeon: Dictionary) -> void:
	_deferred_effect_queue.clear()
	_deferred_generation += 1
	_inventory_mutation_version += 1

	var state_changed := (
		not _item_counts.is_empty()
		or _max_slots != _INITIAL_CAPACITY
		or _capacity_upgrade_count != 0
	)
	if not state_changed:
		return

	_item_counts.clear()
	_max_slots = _INITIAL_CAPACITY
	_capacity_upgrade_count = 0
	call_deferred("_emit_inventory_changed")
