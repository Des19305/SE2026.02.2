class_name InventoryManager
extends RefCounted

signal inventory_changed(items: Array)
signal item_used(item_id: String, result: Dictionary)

const _INITIAL_CAPACITY := 12
const _UPGRADE_AMOUNT := 2
const _MAX_CAPACITY_UPGRADES := 2

var _item_database: ItemDatabase
var _run_manager: Node
var _item_counts: Dictionary = {}
var _max_slots: int = _INITIAL_CAPACITY
var _capacity_upgrade_count: int = 0


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
	var lookup: Dictionary = _item_database.get_item_definition(item_id)

	if not lookup["ok"]:
		result["error"] = "invalid_item"
		return _finish_item_use(item_id, result)

	if not is_instance_valid(user) or not (user is Player):
		result["error"] = "invalid_user"
		return _finish_item_use(item_id, result)

	if get_item_count(item_id) <= 0:
		result["error"] = "item_not_owned"
		return _finish_item_use(item_id, result)

	var definition: ItemData = lookup["definition"]
	if definition.item_type != "consumable" or definition.effects.size() != 1:
		result["error"] = "item_not_usable"
		return _finish_item_use(item_id, result)

	var effect: Variant = definition.effects[0]
	if not (effect is Dictionary):
		result["error"] = "item_not_usable"
		return _finish_item_use(item_id, result)

	var healing_effect: Dictionary = effect
	if not healing_effect.has("type") or healing_effect["type"] != "heal":
		result["error"] = "item_not_usable"
		return _finish_item_use(item_id, result)

	for key in healing_effect:
		if key != "type" and key != "value":
			result["error"] = "item_not_usable"
			return _finish_item_use(item_id, result)

	if not healing_effect.has("value"):
		result["error"] = "effect_failed"
		return _finish_item_use(item_id, result)

	var healing_value: Variant = healing_effect["value"]
	if typeof(healing_value) != TYPE_INT or healing_value <= 0:
		result["error"] = "effect_failed"
		return _finish_item_use(item_id, result)

	var player: Player = user
	var current_hp := player.get_current_hp()
	var max_hp := player.get_max_hp()
	var heal_result: Dictionary = player.heal(healing_value)
	if not heal_result.get("ok", false):
		result["error"] = "hp_full" if current_hp >= max_hp else "effect_failed"
		return _finish_item_use(item_id, result)

	# health_changed is synchronous; a callback can remove this item before consumption.
	if not remove_item(item_id, 1):
		result["error"] = "item_not_owned"
		return _finish_item_use(item_id, result)

	result["ok"] = true
	result["consumed"] = true
	return _finish_item_use(item_id, result)


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
	_emit_inventory_changed()
	return {"ok": true, "error": ""}


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
	var signal_result := result.duplicate()
	signal_result.make_read_only()
	item_used.emit(item_id, signal_result)
	return result


func _on_run_started(_seed: int, _dungeon: Dictionary) -> void:
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
