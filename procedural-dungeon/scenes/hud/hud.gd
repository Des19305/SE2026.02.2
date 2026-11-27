class_name HUD
extends CanvasLayer

var _player: Player
var _equipment_manager: EquipmentManager
var _inventory_manager: InventoryManager
var _run_manager: Node
var _current_hp: int = 100
var _max_hp: int = 100
var _seed: String = "—"
var _inventory_used: int = 0
var _inventory_capacity: int = 12
var _equipment: Dictionary = {}
var _wired := false


func _init(
	player: Player = null,
	equipment_manager: EquipmentManager = null,
	inventory_manager: InventoryManager = null,
	run_manager: Node = null
) -> void:
	if (
		player != null
		and equipment_manager != null
		and inventory_manager != null
		and run_manager != null
	):
		setup(player, equipment_manager, inventory_manager, run_manager)


func _ready() -> void:
	_refresh_ui()


func setup(
	player: Player,
	equipment_manager: EquipmentManager,
	inventory_manager: InventoryManager,
	run_manager: Node
) -> void:
	if _wired:
		return

	_player = player
	_equipment_manager = equipment_manager
	_inventory_manager = inventory_manager
	_run_manager = run_manager
	_wired = true

	_player.health_changed.connect(_refresh_hp)
	_player.max_hp_changed.connect(_refresh_max_hp)
	_equipment_manager.equipment_changed.connect(_refresh_equipment)
	_equipment_manager.equipment_slots_changed.connect(_refresh_equipment)
	_inventory_manager.inventory_changed.connect(_refresh_inventory)
	_run_manager.run_started.connect(_on_run_started)

	_refresh_initial_state()


func get_display_state() -> Dictionary:
	var snapshot := _equipment.duplicate()
	snapshot.make_read_only()
	return {
		"current_hp": _current_hp,
		"max_hp": _max_hp,
		"seed": _seed,
		"inventory_used": _inventory_used,
		"inventory_capacity": _inventory_capacity,
		"equipment": snapshot,
	}


func _refresh_initial_state() -> void:
	_refresh_hp(_player.get_current_hp(), _player.get_max_hp())
	_refresh_inventory([])
	_refresh_equipment()
	_refresh_ui()


func _refresh_hp(current_hp: int, max_hp: int) -> void:
	_current_hp = current_hp
	_max_hp = max_hp
	_refresh_ui()


func _refresh_max_hp(max_hp: int) -> void:
	_max_hp = max_hp
	_refresh_ui()


func _refresh_equipment() -> void:
	var snapshot: Dictionary = _equipment_manager.get_equipment()
	_equipment = snapshot.duplicate()
	_refresh_ui()


func _refresh_inventory(_items: Array) -> void:
	_inventory_used = _inventory_manager.get_used_slots()
	_inventory_capacity = _inventory_manager.get_max_slots()
	_refresh_ui()


func _on_run_started(run_seed: int, _dungeon: Dictionary) -> void:
	_seed = str(run_seed)
	_refresh_initial_state()


func _refresh_ui() -> void:
	var hp_label := get_node_or_null("MarginContainer/VBoxContainer/HPLabel")
	if hp_label != null:
		hp_label.text = "HP: %d / %d" % [_current_hp, _max_hp]

	var seed_label := get_node_or_null("MarginContainer/VBoxContainer/SeedLabel")
	if seed_label != null:
		seed_label.text = "Seed: %s" % _seed

	var inventory_label := get_node_or_null(
		"MarginContainer/VBoxContainer/InventoryLabel"
	)
	if inventory_label != null:
		inventory_label.text = "Inventory: %d / %d" % [
			_inventory_used,
			_inventory_capacity,
		]

	var equipment_label := get_node_or_null(
		"MarginContainer/VBoxContainer/EquipmentLabel"
	)
	if equipment_label != null:
		var lines: Array[String] = []
		var slot_ids: Array = _equipment.keys()
		slot_ids.sort()
		for slot_id in slot_ids:
			var item_id: String = _equipment[slot_id]
			lines.append("%s: %s" % [slot_id, item_id if item_id != "" else "—"])
		equipment_label.text = "Equipment:\n" + "\n".join(lines)
