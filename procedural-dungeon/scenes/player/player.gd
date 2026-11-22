class_name Player
extends Node2D
## Grid-based player movement with wall collision.
## Add the player as a child of the DungeonRenderer so both share the same local space.

signal moved(cell: Vector2i)
signal health_changed(current_hp: int, max_hp: int)
signal max_hp_changed(max_hp: int)

const MOVE_INTERVAL: float = 0.12  # seconds between steps while a key is held
const BODY_COLOR := Color("#ebcb8b")
const _INITIAL_MAX_HP := 100

var grid: DungeonGrid = null
var cell: Vector2i = Vector2i.ZERO
var _cooldown: float = 0.0
var _current_hp: int = _INITIAL_MAX_HP
var _max_hp: int = _INITIAL_MAX_HP
var _max_hp_effects: Dictionary = {}


func get_current_hp() -> int:
	return _current_hp


func get_max_hp() -> int:
	return _max_hp


func heal(amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "error": "Healing amount must be positive"}

	var healing_applied: int = min(amount, _max_hp - _current_hp)
	if healing_applied <= 0:
		return {"ok": false, "error": "Healing would not increase Current HP"}

	_current_hp += healing_applied
	health_changed.emit(_current_hp, _max_hp)
	return {"ok": true, "error": ""}


func set_max_hp_effects(effects_by_source: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_max_hp_effects(effects_by_source)
	if not validation["ok"]:
		return validation

	var validated_effects: Dictionary = {}
	for source_id in effects_by_source:
		var effect: Variant = effects_by_source[source_id]
		validated_effects[source_id] = effect.duplicate()

	var previous_effects := _max_hp_effects.duplicate(true)
	var previous_current_hp := _current_hp
	var previous_max_hp := _max_hp
	var newly_added_current_hp := _get_new_current_hp_contribution(
		previous_effects,
		validated_effects
	)

	_max_hp_effects = validated_effects
	_max_hp = _INITIAL_MAX_HP + _get_max_hp_modifier(_max_hp_effects)
	_current_hp = min(_current_hp + newly_added_current_hp, _max_hp)

	if _max_hp != previous_max_hp:
		max_hp_changed.emit(_max_hp)
	if _current_hp != previous_current_hp:
		health_changed.emit(_current_hp, _max_hp)
	return {"ok": true, "error": ""}


func validate_max_hp_effects(effects_by_source: Dictionary) -> Dictionary:
	for source_id in effects_by_source:
		if typeof(source_id) != TYPE_STRING or source_id.is_empty():
			return {"ok": false, "error": "invalid_effect"}
		if not _is_valid_max_hp_effect(effects_by_source[source_id]):
			return {"ok": false, "error": "invalid_effect"}
	return {"ok": true, "error": ""}


func reset_hp(defer_signals: bool = false) -> Dictionary:
	var previous_current_hp := _current_hp
	var previous_max_hp := _max_hp
	_max_hp_effects.clear()
	_max_hp = _INITIAL_MAX_HP
	_current_hp = _INITIAL_MAX_HP

	var current_hp_changed := _current_hp != previous_current_hp
	var max_value_changed := _max_hp != previous_max_hp
	if defer_signals and (current_hp_changed or max_value_changed):
		call_deferred(
			"_publish_reset_hp_signals",
			current_hp_changed,
			max_value_changed
		)
	else:
		_publish_reset_hp_signals(current_hp_changed, max_value_changed)
	return {"ok": true, "error": ""}


func _publish_reset_hp_signals(
	current_hp_changed: bool,
	max_value_changed: bool
) -> void:
	if max_value_changed:
		max_hp_changed.emit(_max_hp)
	if current_hp_changed:
		health_changed.emit(_current_hp, _max_hp)


func _is_valid_max_hp_effect(effect: Variant) -> bool:
	if not (effect is Dictionary):
		return false
	if effect.keys().size() != 5:
		return false
	if (
		effect.get("type") != "stat"
		or effect.get("stat") != "max_hp"
		or effect.get("operation") != "add"
	):
		return false

	var value: Variant = effect.get("value")
	if typeof(value) != TYPE_INT or value <= 0:
		return false

	var hp_behavior: Variant = effect.get("hp_behavior")
	return (
		hp_behavior == "increase_max_only"
		or hp_behavior == "increase_max_and_current"
	)


func _get_max_hp_modifier(effects_by_source: Dictionary) -> int:
	var modifier := 0
	for effect in effects_by_source.values():
		modifier += effect["value"]
	return modifier


func _get_new_current_hp_contribution(
	previous_effects_by_source: Dictionary,
	new_effects_by_source: Dictionary
) -> int:
	var contribution := 0
	for source_id in new_effects_by_source:
		if previous_effects_by_source.has(source_id):
			continue
		var effect: Dictionary = new_effects_by_source[source_id]
		if effect["hp_behavior"] == "increase_max_and_current":
			contribution += effect["value"]
	return contribution


## Places the player on grid.start_cell. Returns {"ok": bool, "error": String}.
func setup(new_grid: DungeonGrid) -> Dictionary:
	if new_grid == null:
		return {"ok": false, "error": "grid is null"}
	if not new_grid.is_walkable(new_grid.start_cell):
		return {"ok": false, "error": "start cell is not walkable"}
	grid = new_grid
	cell = grid.start_cell
	position = grid.cell_center(cell)
	queue_redraw()
	return {"ok": true, "error": ""}


## Tries to move one orthogonal step. The grid decides whether the target is free.
## Returns {"ok": bool, "cell": Vector2i, "error": String}; on failure nothing changes.
func try_move(direction: Vector2i) -> Dictionary:
	if grid == null:
		return {"ok": false, "cell": cell, "error": "player is not set up"}
	if absi(direction.x) + absi(direction.y) != 1:
		return {"ok": false, "cell": cell, "error": "direction must be one orthogonal step"}
	var target := cell + direction
	if not grid.is_walkable(target):
		return {"ok": false, "cell": cell, "error": "blocked"}
	cell = target
	position = grid.cell_center(cell)
	moved.emit(cell)
	return {"ok": true, "cell": cell, "error": ""}


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0:
		return
	var direction := _read_direction()
	if direction != Vector2i.ZERO:
		try_move(direction)
		_cooldown = MOVE_INTERVAL


func _read_direction() -> Vector2i:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		return Vector2i.UP
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		return Vector2i.DOWN
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		return Vector2i.LEFT
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _draw() -> void:
	var side := DungeonGrid.CELL_SIZE * 0.6
	draw_rect(Rect2(Vector2.ONE * (-side * 0.5), Vector2.ONE * side), BODY_COLOR)
