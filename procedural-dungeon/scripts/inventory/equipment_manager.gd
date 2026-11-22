class_name EquipmentManager
extends RefCounted

signal equipment_changed
signal equipment_slots_changed

const _BOW_ITEM_ID := "bow"
const _DEFAULT_SLOT_TYPES := {
	"weapon_1": "weapon",
	"weapon_2": "weapon",
	"helmet": "helmet",
	"armor": "armor",
	"boots": "boots",
	"accessory_1": "accessory",
	"accessory_2": "accessory",
}

var _item_database: ItemDatabase
var _inventory_manager: InventoryManager
var _run_manager: Node
var _player: Player
var _slot_types: Dictionary = {}
var _equipped_item_ids_by_slot: Dictionary = {}
var _equipped_effect_source_ids_by_slot: Dictionary = {}
var _next_effect_source_id := 1


func _init(
	item_database: ItemDatabase,
	inventory_manager: InventoryManager,
	run_manager: Node,
	player: Player
) -> void:
	assert(item_database != null, "EquipmentManager requires an ItemDatabase")
	assert(inventory_manager != null, "EquipmentManager requires an InventoryManager")
	assert(run_manager != null, "EquipmentManager requires a RunManager")
	assert(player != null, "EquipmentManager requires a Player")

	_item_database = item_database
	_inventory_manager = inventory_manager
	_run_manager = run_manager
	_player = player
	_reset_to_default_slots()
	_run_manager.connect(&"run_started", _on_run_started)


func add_slot(slot_id: String, slot_type: String) -> Dictionary:
	if slot_id.is_empty() or slot_type.is_empty() or _slot_types.has(slot_id):
		return _failure("invalid_slot")

	_slot_types[slot_id] = slot_type
	_equipped_item_ids_by_slot[slot_id] = ""
	_equipped_effect_source_ids_by_slot[slot_id] = ""
	equipment_slots_changed.emit()
	return _success()


func has_slot(slot_id: String) -> bool:
	return _slot_types.has(slot_id)


func get_slot_type(slot_id: String) -> String:
	var slot_type: String = _slot_types.get(slot_id, "")
	return slot_type


func equip_item(item_id: String, slot: String) -> Dictionary:
	var lookup: Dictionary = _item_database.get_item_definition(item_id)
	if not lookup["ok"]:
		return _failure("invalid_item")
	if not _slot_types.has(slot):
		return _failure("invalid_slot")

	var definition: ItemData = lookup["definition"]
	if definition.item_type != "equipment":
		return _failure("not_equipment")
	if _inventory_manager.get_item_count(item_id) < 1:
		return _failure("item_not_owned")

	var target_slots: Array[String] = []
	if item_id == _BOW_ITEM_ID:
		if (
			(slot != "weapon_1" and slot != "weapon_2")
			or definition.slots_required != 2
			or not definition.allowed_slot_types.has("weapon")
		):
			return _failure("incompatible_slot")
		target_slots = ["weapon_1", "weapon_2"]
	else:
		if (
			definition.slots_required != 1
			or not definition.allowed_slot_types.has(_slot_types[slot])
		):
			return _failure("incompatible_slot")
		target_slots = [slot]

	var resulting_equipment: Dictionary = _equipped_item_ids_by_slot.duplicate()
	var displaced_counts: Dictionary = {}
	var bow_displaced := false
	for affected_slot in target_slots:
		var displaced_item_id: String = _equipped_item_ids_by_slot[affected_slot]
		if displaced_item_id.is_empty():
			continue

		if displaced_item_id == _BOW_ITEM_ID:
			if not bow_displaced:
				displaced_counts[displaced_item_id] = (
					displaced_counts.get(displaced_item_id, 0) + 1
				)
				bow_displaced = true
			resulting_equipment["weapon_1"] = ""
			resulting_equipment["weapon_2"] = ""
		else:
			displaced_counts[displaced_item_id] = (
				displaced_counts.get(displaced_item_id, 0) + 1
			)
			resulting_equipment[affected_slot] = ""

	for affected_slot in target_slots:
		resulting_equipment[affected_slot] = item_id

	return _commit_equipment_change(
		{item_id: 1},
		displaced_counts,
		resulting_equipment
	)


func unequip_item(slot: String) -> Dictionary:
	if not _slot_types.has(slot):
		return _failure("invalid_slot")

	var item_id: String = _equipped_item_ids_by_slot[slot]
	if item_id.is_empty():
		return _failure("slot_empty")

	var resulting_equipment: Dictionary = _equipped_item_ids_by_slot.duplicate()
	if item_id == _BOW_ITEM_ID:
		resulting_equipment["weapon_1"] = ""
		resulting_equipment["weapon_2"] = ""
	else:
		resulting_equipment[slot] = ""

	return _commit_equipment_change(
		{},
		{item_id: 1},
		resulting_equipment
	)


func get_equipment() -> Dictionary:
	var snapshot: Dictionary = _equipped_item_ids_by_slot.duplicate()
	snapshot.make_read_only()
	return snapshot


func _commit_equipment_change(
	removals: Dictionary,
	additions: Dictionary,
	resulting_equipment: Dictionary
) -> Dictionary:
	var preflight: Dictionary = _inventory_manager.preflight_transfer_batch(
		removals,
		additions
	)
	if not preflight["ok"]:
		var inventory_error: String = preflight["error"]
		if inventory_error.contains("capacity"):
			return _failure("inventory_full")
		if inventory_error.contains("Insufficient"):
			return _failure("item_not_owned")
		return _failure("invalid_item")

	var effect_preflight: Dictionary = _validate_resulting_effects(resulting_equipment)
	if not effect_preflight["ok"]:
		return _failure(effect_preflight["error"])

	var inventory_changed: bool = _inventory_manager.commit_transfer_batch(
		removals,
		additions
	)
	var equipment_state_changed := _equipped_item_ids_by_slot != resulting_equipment
	var resulting_effect_sources: Dictionary = {}
	if equipment_state_changed:
		resulting_effect_sources = _build_effect_source_ids(resulting_equipment)
	_equipped_item_ids_by_slot = resulting_equipment
	if equipment_state_changed:
		_equipped_effect_source_ids_by_slot = resulting_effect_sources
		_sync_player_effects()

	_inventory_manager.publish_transfer_batch(inventory_changed)
	if equipment_state_changed:
		equipment_changed.emit()
	return _success()


func _reset_to_default_slots() -> void:
	_slot_types = _DEFAULT_SLOT_TYPES.duplicate()
	_equipped_item_ids_by_slot = {}
	_equipped_effect_source_ids_by_slot = {}
	_next_effect_source_id = 1
	for slot_id in _slot_types:
		_equipped_item_ids_by_slot[slot_id] = ""
		_equipped_effect_source_ids_by_slot[slot_id] = ""


func _build_effect_source_ids(resulting_equipment: Dictionary) -> Dictionary:
	var resulting_sources: Dictionary = {}
	var bow_source_id := _get_existing_bow_source_id(resulting_equipment)
	if resulting_equipment.get("weapon_1", "") == _BOW_ITEM_ID and bow_source_id.is_empty():
		bow_source_id = _new_effect_source_id(_BOW_ITEM_ID)

	for slot_id in resulting_equipment:
		var item_id: String = resulting_equipment[slot_id]
		if item_id.is_empty():
			resulting_sources[slot_id] = ""
		elif item_id == _BOW_ITEM_ID:
			resulting_sources[slot_id] = bow_source_id
		elif (
			_equipped_item_ids_by_slot.get(slot_id, "") == item_id
			and not _equipped_effect_source_ids_by_slot.get(slot_id, "").is_empty()
		):
			resulting_sources[slot_id] = _equipped_effect_source_ids_by_slot[slot_id]
		else:
			resulting_sources[slot_id] = _new_effect_source_id(item_id)
	return resulting_sources


func _get_existing_bow_source_id(resulting_equipment: Dictionary) -> String:
	if resulting_equipment.get("weapon_1", "") != _BOW_ITEM_ID:
		return ""
	for slot_id in ["weapon_1", "weapon_2"]:
		if _equipped_item_ids_by_slot.get(slot_id, "") == _BOW_ITEM_ID:
			return _equipped_effect_source_ids_by_slot.get(slot_id, "")
	return ""


func _new_effect_source_id(item_id: String) -> String:
	var source_id := "%s_instance_%d" % [item_id, _next_effect_source_id]
	_next_effect_source_id += 1
	return source_id


func _sync_player_effects() -> void:
	var effects_by_source: Dictionary = {}
	var processed_sources: Dictionary = {}
	for slot_id in _equipped_item_ids_by_slot:
		var item_id: String = _equipped_item_ids_by_slot[slot_id]
		var item_source_id: String = _equipped_effect_source_ids_by_slot[slot_id]
		if item_id.is_empty() or processed_sources.has(item_source_id):
			continue
		processed_sources[item_source_id] = true

		var lookup: Dictionary = _item_database.get_item_definition(item_id)
		assert(lookup["ok"], "Equipped item must have a definition")
		var definition: ItemData = lookup["definition"]
		for effect_index in range(definition.effects.size()):
			effects_by_source["%s_effect_%d" % [item_source_id, effect_index]] = (
				definition.effects[effect_index]
			)

	var result: Dictionary = _player.set_max_hp_effects(effects_by_source)
	assert(result["ok"], "Equipment effects must use the approved Max HP effect schema")


func _validate_resulting_effects(resulting_equipment: Dictionary) -> Dictionary:
	var effects_by_source: Dictionary = {}
	var bow_processed := false
	for slot_id in resulting_equipment:
		var item_id: String = resulting_equipment[slot_id]
		if item_id.is_empty() or (item_id == _BOW_ITEM_ID and bow_processed):
			continue
		if item_id == _BOW_ITEM_ID:
			bow_processed = true

		var lookup: Dictionary = _item_database.get_item_definition(item_id)
		assert(lookup["ok"], "Equipped item must have a definition")
		var definition: ItemData = lookup["definition"]
		for effect_index in range(definition.effects.size()):
			effects_by_source["preflight_%s_%d" % [slot_id, effect_index]] = (
				definition.effects[effect_index]
			)
	return _player.validate_max_hp_effects(effects_by_source)


func _on_run_started(_seed: int, _dungeon: Dictionary) -> void:
	var equipment_state_changed := false
	for item_id in _equipped_item_ids_by_slot.values():
		if not item_id.is_empty():
			equipment_state_changed = true
			break
	var slots_changed := _slot_types != _DEFAULT_SLOT_TYPES
	if not equipment_state_changed and not slots_changed:
		return

	_reset_to_default_slots()
	call_deferred(
		"_publish_run_reset_signals",
		equipment_state_changed,
		slots_changed
	)


func _publish_run_reset_signals(
	equipment_state_changed: bool,
	slots_changed: bool
) -> void:
	if equipment_state_changed:
		equipment_changed.emit()
	if slots_changed:
		equipment_slots_changed.emit()


func _success() -> Dictionary:
	return {"ok": true, "error": ""}


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
