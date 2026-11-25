class_name HotbarUI
extends Control

signal slot_selected(slot_index: int)

const SLOT_COUNT := 4

var inventory_manager: InventoryManager
var item_database: ItemDatabase
var player: Player

var _slot_item_ids: Array[String] = ["", "", "", ""]
var _selected_slot_index := 0
var _wired := false
var _inventory_pause_active := false


func setup(
	inventory_manager_instance: InventoryManager,
	item_database_instance: ItemDatabase,
	player_instance: Player = null
) -> void:
	if inventory_manager_instance == null or item_database_instance == null:
		push_error("HotbarUI requires InventoryManager and ItemDatabase")
		return

	inventory_manager = inventory_manager_instance
	item_database = item_database_instance
	player = player_instance

	if not _wired:
		inventory_manager.inventory_changed.connect(_on_inventory_changed)
		_wired = true

	_refresh_slots()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	for slot_index in range(SLOT_COUNT):
		var button := get_node_or_null("MarginContainer/VBoxContainer/Slots/Slot%dButton" % [slot_index + 1])
		if button != null:
			button.pressed.connect(
				func() -> void: select_slot(slot_index)
			)

	_inventory_pause_active = false
	_refresh_slots()


func _exit_tree() -> void:
	if not _wired:
		return

	if is_instance_valid(inventory_manager):
		if inventory_manager.inventory_changed.is_connected(_on_inventory_changed):
			inventory_manager.inventory_changed.disconnect(_on_inventory_changed)

	_wired = false


func select_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false

	_selected_slot_index = slot_index
	_refresh_slots()
	slot_selected.emit(slot_index)
	return true


func get_selected_slot_index() -> int:
	return _selected_slot_index


func assign_item(slot_index: int, item_id: String) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {
			"ok": false,
			"error": "invalid_slot",
			"item_id": item_id,
			"slot_index": slot_index,
			"assigned": false,
		}

	if item_id == "" or inventory_manager == null or item_database == null:
		return {
			"ok": false,
			"error": "invalid_item",
			"item_id": item_id,
			"slot_index": slot_index,
			"assigned": false,
		}

	var lookup: Dictionary = item_database.get_item_definition(item_id)
	if not lookup["ok"]:
		return {
			"ok": false,
			"error": "invalid_item",
			"item_id": item_id,
			"slot_index": slot_index,
			"assigned": false,
		}

	if inventory_manager.get_item_count(item_id) <= 0:
		return {
			"ok": false,
			"error": "item_unavailable",
			"item_id": item_id,
			"slot_index": slot_index,
			"assigned": false,
		}

	if not _is_eligible_definition(lookup["definition"]):
		return {
			"ok": false,
			"error": "item_not_usable",
			"item_id": item_id,
			"slot_index": slot_index,
			"assigned": false,
		}

	_slot_item_ids[slot_index] = item_id
	_selected_slot_index = slot_index
	_refresh_slots()
	return {
		"ok": true,
		"error": "",
		"item_id": item_id,
		"slot_index": slot_index,
		"assigned": true,
	}


func assign_selected_item(item_id: String) -> Dictionary:
	return assign_item(_selected_slot_index, item_id)


func use_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {
			"ok": false,
			"error": "invalid_slot",
			"item_id": "",
			"consumed": false,
		}

	var item_id: String = _slot_item_ids[slot_index]
	if item_id == "":
		return {
			"ok": false,
			"error": "slot_empty",
			"item_id": "",
			"consumed": false,
		}

	if not is_item_available(slot_index):
		return {
			"ok": false,
			"error": "item_unavailable",
			"item_id": item_id,
			"consumed": false,
		}

	if inventory_manager == null:
		return {
			"ok": false,
			"error": "inventory_unavailable",
			"item_id": item_id,
			"consumed": false,
		}

	var result: Dictionary
	if _inventory_pause_active:
		result = inventory_manager.queue_consumable_use(item_id, player)
	else:
		result = inventory_manager.use_item(item_id, player)
	_refresh_slots()
	return result


func use_selected_slot() -> Dictionary:
	return use_slot(_selected_slot_index)


func set_inventory_pause_active(active: bool) -> void:
	_inventory_pause_active = active


func handle_shortcut(slot_index: int) -> Dictionary:
	return use_slot(slot_index)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var slot_index := -1
	match key_event.keycode:
		KEY_1:
			slot_index = 0
		KEY_2:
			slot_index = 1
		KEY_3:
			slot_index = 2
		KEY_4:
			slot_index = 3
		_:
			return

	get_viewport().set_input_as_handled()
	handle_shortcut(slot_index)


func get_slot_item_id(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return ""
	return _slot_item_ids[slot_index]


func is_item_available(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false

	var item_id: String = _slot_item_ids[slot_index]
	if item_id == "" or inventory_manager == null or item_database == null:
		return false
	if inventory_manager.get_item_count(item_id) <= 0:
		return false

	var lookup: Dictionary = item_database.get_item_definition(item_id)
	if not lookup["ok"]:
		return false

	return _is_eligible_definition(lookup["definition"])


func get_slot_state(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {"ok": false, "error": "invalid_slot"}

	var item_id: String = _slot_item_ids[slot_index]
	if item_id == "":
		return {
			"slot_index": slot_index,
			"item_id": "",
			"name": "",
			"status": "empty",
			"available": false,
		}

	var display_name := item_id
	var lookup: Dictionary = {}
	if is_instance_valid(item_database):
		lookup = item_database.get_item_definition(item_id)
		if lookup["ok"]:
			var definition: ItemData = lookup["definition"]
			if definition.name != "":
				display_name = definition.name

	return {
		"slot_index": slot_index,
		"item_id": item_id,
		"name": display_name,
		"status": "available" if is_item_available(slot_index) else "unavailable",
		"available": is_item_available(slot_index),
	}


func get_hotbar_state() -> Array:
	var state: Array = []
	for slot_index in range(SLOT_COUNT):
		state.append(get_slot_state(slot_index))
	return state


func get_slot_count() -> int:
	return SLOT_COUNT


func _on_inventory_changed(_items: Array) -> void:
	_refresh_slots()


func _is_eligible_definition(definition: ItemData) -> bool:
	if definition == null:
		return false
	if definition.item_type != "consumable":
		return false
	if definition.effects.size() != 1:
		return false

	var effect: Variant = definition.effects[0]
	if not (effect is Dictionary):
		return false

	var healing_effect: Dictionary = effect
	if not healing_effect.has("type") or healing_effect["type"] != "heal":
		return false
	if healing_effect.keys().size() != 2:
		return false
	if not healing_effect.has("value"):
		return false
	if typeof(healing_effect["value"]) != TYPE_INT:
		return false
	return healing_effect["value"] > 0


func _refresh_slots() -> void:
	var selected_label := get_node_or_null(
		"MarginContainer/VBoxContainer/SelectedSlotLabel"
	)
	if selected_label != null:
		selected_label.text = "Selected Slot: %d" % [_selected_slot_index + 1]

	for slot_index in range(SLOT_COUNT):
		var button := get_node_or_null(
			"MarginContainer/VBoxContainer/Slots/Slot%dButton" % [slot_index + 1]
		)
		if button == null:
			continue

		var state: Dictionary = get_slot_state(slot_index)
		var status: String = state["status"]
		var slot_text := "%d: " % [slot_index + 1]

		match status:
			"empty":
				slot_text += "Empty"
				button.modulate = Color(0.75, 0.75, 0.75)
			"available":
				slot_text += state["name"]
				button.modulate = Color(1.0, 1.0, 1.0)
			"unavailable":
				slot_text += "%s (Unavailable)" % state["name"]
				button.modulate = Color(0.55, 0.55, 0.55)

		if slot_index == _selected_slot_index:
			slot_text += " [Selected]"

		button.text = slot_text
