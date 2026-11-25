class_name InventoryUI
extends Control

signal selection_changed(item_id: String)

var inventory_manager: InventoryManager
var item_database: ItemDatabase
var player: Player
var _selected_item_id: String = ""
var _wired := false
var _inventory_open := false
var _paused_before_open := false
var _hotbar_ui


func setup(
	inventory_manager_instance: InventoryManager,
	item_database_instance: ItemDatabase,
	player_instance: Player = null
) -> void:
	if (
		inventory_manager_instance == null
		or item_database_instance == null
	):
		push_error("InventoryUI requires InventoryManager and ItemDatabase")
		return

	inventory_manager = inventory_manager_instance
	item_database = item_database_instance
	player = player_instance

	if not _wired:
		inventory_manager.inventory_changed.connect(_refresh_inventory)
		inventory_manager.item_used.connect(_refresh_after_item_use)
		_wired = true

	_refresh_inventory(inventory_manager.get_items())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	if is_instance_valid(inventory_manager) and is_instance_valid(item_database):
		_refresh_inventory(inventory_manager.get_items())

	var use_button := get_node_or_null(
		"MarginContainer/VBoxContainer/Actions/UseButton"
	)
	if use_button != null:
		use_button.pressed.connect(_on_use_pressed)

	var remove_button := get_node_or_null(
		"MarginContainer/VBoxContainer/Actions/RemoveButton"
	)
	if remove_button != null:
		remove_button.pressed.connect(_on_remove_pressed)

	var assign_button := get_node_or_null(
		"MarginContainer/VBoxContainer/Actions/AssignHotbarButton"
	)
	if assign_button != null:
		assign_button.pressed.connect(_on_assign_hotbar_pressed)

	if is_instance_valid(_hotbar_ui):
		_hotbar_ui.set_inventory_pause_active(_inventory_open)

	if not _inventory_open:
		visible = false


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_E:
		return

	get_viewport().set_input_as_handled()
	toggle_inventory()


func is_inventory_open() -> bool:
	return _inventory_open


func open_inventory() -> bool:
	if _inventory_open:
		return false

	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_paused_before_open = get_tree().paused
	_inventory_open = true
	visible = true
	if is_instance_valid(_hotbar_ui):
		_hotbar_ui.set_inventory_pause_active(true)
	get_tree().paused = true
	return true


func close_inventory() -> bool:
	if not _inventory_open:
		return false

	var should_flush := not _paused_before_open
	_inventory_open = false
	visible = false
	if is_instance_valid(_hotbar_ui):
		_hotbar_ui.set_inventory_pause_active(false)
	get_tree().paused = _paused_before_open
	if should_flush and is_instance_valid(inventory_manager):
		inventory_manager.flush_deferred_effects(player)
	return true


func toggle_inventory() -> bool:
	if _inventory_open:
		close_inventory()
		return false

	open_inventory()
	return true


func _exit_tree() -> void:
	if _inventory_open:
		_inventory_open = false
		if is_instance_valid(_hotbar_ui):
			_hotbar_ui.set_inventory_pause_active(false)
		if is_instance_valid(get_tree()):
			get_tree().paused = _paused_before_open

	if not _wired:
		return

	if is_instance_valid(inventory_manager):
		if inventory_manager.inventory_changed.is_connected(_refresh_inventory):
			inventory_manager.inventory_changed.disconnect(_refresh_inventory)
		if inventory_manager.item_used.is_connected(_refresh_after_item_use):
			inventory_manager.item_used.disconnect(_refresh_after_item_use)

	_wired = false


func select_item(item_id: String) -> bool:
	if inventory_manager == null:
		return false

	if inventory_manager.get_item_count(item_id) <= 0:
		return false

	_selected_item_id = item_id
	_refresh_details()
	selection_changed.emit(item_id)
	return true


func get_selected_item_id() -> String:
	return _selected_item_id


func use_selected_item(player: Node) -> Dictionary:
	if inventory_manager == null:
		return {
			"ok": false,
			"error": "inventory_unavailable",
			"item_id": _selected_item_id,
			"consumed": false,
		}

	if _selected_item_id == "":
		return {
			"ok": false,
			"error": "no_item_selected",
			"item_id": "",
			"consumed": false,
		}

	if _inventory_open:
		return inventory_manager.queue_consumable_use(_selected_item_id, player)

	return inventory_manager.use_item(_selected_item_id, player)


func remove_selected_item(amount: int = 1) -> Dictionary:
	if inventory_manager == null:
		return {
			"ok": false,
			"error": "inventory_unavailable",
			"item_id": _selected_item_id,
			"removed": false,
		}

	if _selected_item_id == "":
		return {
			"ok": false,
			"error": "no_item_selected",
			"item_id": "",
			"removed": false,
		}

	var success := inventory_manager.remove_item(_selected_item_id, amount)
	return {
		"ok": success,
		"error": "" if success else "remove_failed",
		"item_id": _selected_item_id,
		"removed": success,
	}


func assign_selected_item_to_hotbar(slot_index: int) -> Dictionary:
	if not is_instance_valid(_hotbar_ui):
		return {
			"ok": false,
			"error": "hotbar_unavailable",
			"item_id": _selected_item_id,
			"slot_index": slot_index,
			"assigned": false,
		}

	if _selected_item_id == "":
		return {
			"ok": false,
			"error": "no_item_selected",
			"item_id": "",
			"slot_index": slot_index,
			"assigned": false,
		}

	return _hotbar_ui.assign_item(slot_index, _selected_item_id)


func _on_use_pressed() -> void:
	if is_instance_valid(player):
		use_selected_item(player)


func _on_remove_pressed() -> void:
	remove_selected_item(1)


func _on_assign_hotbar_pressed() -> void:
	if is_instance_valid(_hotbar_ui):
		_hotbar_ui.assign_selected_item(_selected_item_id)


func set_hotbar_ui(hotbar_ui) -> void:
	_hotbar_ui = hotbar_ui
	if is_instance_valid(_hotbar_ui):
		_hotbar_ui.set_inventory_pause_active(_inventory_open)


func get_display_state() -> Dictionary:
	var items: Array = []
	if is_instance_valid(inventory_manager):
		items = inventory_manager.get_items()

	var used_slots := 0
	var max_slots := 0
	var selected_name := ""
	var selected_description := ""
	var selected_quantity := 0

	if is_instance_valid(inventory_manager):
		used_slots = inventory_manager.get_used_slots()
		max_slots = inventory_manager.get_max_slots()

	if is_instance_valid(item_database) and _selected_item_id != "":
		var lookup: Dictionary = item_database.get_item_definition(_selected_item_id)
		if lookup["ok"]:
			var definition: ItemData = lookup["definition"]
			selected_name = definition.name if definition.name != "" else _selected_item_id
			selected_description = definition.description
			selected_quantity = inventory_manager.get_item_count(_selected_item_id)

	return {
		"items": items,
		"used_slots": used_slots,
		"max_slots": max_slots,
		"selected_item_id": _selected_item_id,
		"selected_name": selected_name,
		"selected_description": selected_description,
		"selected_quantity": selected_quantity,
		"empty": items.is_empty(),
	}


func _refresh_after_item_use(_item_id: String, _result: Dictionary) -> void:
	_refresh_details()


func _refresh_inventory(items: Array) -> void:
	if not is_instance_valid(inventory_manager):
		return

	var capacity_label := get_node_or_null("MarginContainer/VBoxContainer/CapacityLabel")
	if capacity_label != null:
		capacity_label.text = "Capacity: %d / %d" % [
			inventory_manager.get_used_slots(),
			inventory_manager.get_max_slots(),
		]

	var empty_label := get_node_or_null(
		"MarginContainer/VBoxContainer/EmptyLabel"
	)
	if empty_label != null:
		empty_label.visible = items.is_empty()

	var item_grid := get_node_or_null(
		"MarginContainer/VBoxContainer/ScrollContainer/ItemGrid"
	)
	if item_grid != null:
		for child in item_grid.get_children():
			child.free()

		for entry in items:
			var item_id: String = entry["item_id"]
			var amount: int = entry["amount"]
			var display_name := item_id
			if is_instance_valid(item_database):
				var lookup: Dictionary = item_database.get_item_definition(item_id)
				if lookup["ok"]:
					var definition: ItemData = lookup["definition"]
					if definition.name != "":
						display_name = definition.name

			var button := Button.new()
			button.text = "%s x%d" % [display_name, amount]
			button.custom_minimum_size = Vector2(120, 48)
			button.pressed.connect(func() -> void: select_item(item_id))
			item_grid.add_child(button)

	if _selected_item_id != "" and inventory_manager.get_item_count(_selected_item_id) <= 0:
		_selected_item_id = ""

	_refresh_details()


func _refresh_details() -> void:
	var name_label := get_node_or_null(
		"MarginContainer/VBoxContainer/DetailsNameLabel"
	)
	var description_label := get_node_or_null(
		"MarginContainer/VBoxContainer/DetailsDescriptionLabel"
	)
	var quantity_label := get_node_or_null(
		"MarginContainer/VBoxContainer/DetailsQuantityLabel"
	)

	if _selected_item_id == "":
		if name_label != null:
			name_label.text = "No item selected"
		if description_label != null:
			description_label.text = ""
		if quantity_label != null:
			quantity_label.text = ""
		return

	if not is_instance_valid(item_database):
		return

	var lookup: Dictionary = item_database.get_item_definition(_selected_item_id)
	if not lookup["ok"]:
		if name_label != null:
			name_label.text = _selected_item_id
		if description_label != null:
			description_label.text = ""
		if quantity_label != null:
			quantity_label.text = ""
		return

	var definition: ItemData = lookup["definition"]
	if name_label != null:
		name_label.text = definition.name if definition.name != "" else _selected_item_id
	if description_label != null:
		description_label.text = definition.description
	if quantity_label != null:
		quantity_label.text = "Quantity: %d" % inventory_manager.get_item_count(
			_selected_item_id
		)
