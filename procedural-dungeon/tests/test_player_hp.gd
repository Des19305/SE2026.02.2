extends RefCounted

const PlayerScript := preload("res://scenes/player/player.gd")


func test_initial_hp_values_and_no_initial_signals() -> String:
	var player: Player = PlayerScript.new()
	var health_events: Array = []
	var max_hp_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: max_hp_events.append(max_hp)
	)

	var message := ""
	if player.get_current_hp() != 100 or player.get_max_hp() != 100:
		message = "initial HP values should both be 100"
	elif not health_events.is_empty() or not max_hp_events.is_empty():
		message = "initialization must not emit HP signals"

	player.free()
	return message


func test_successful_healing_updates_hp_and_emits_updated_values() -> String:
	var player := _player_at(80, 100)
	var health_events: Array = []
	var max_hp_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: max_hp_events.append(max_hp)
	)

	var result: Dictionary = player.heal(10)
	var message := ""
	if not result["ok"] or result["error"] != "":
		message = "valid healing should succeed with an empty error"
	elif player.get_current_hp() != 90 or player.get_max_hp() != 100:
		message = "healing should update Current HP only"
	elif health_events != [[90, 100]]:
		message = "health_changed should report updated HP values"
	elif not max_hp_events.is_empty():
		message = "healing must not emit max_hp_changed"

	player.free()
	return message


func test_healing_above_max_hp_clamps_and_emits_clamped_values() -> String:
	var player := _player_at(95, 100)
	var health_events: Array = []
	var max_hp_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: max_hp_events.append(max_hp)
	)

	var result: Dictionary = player.heal(20)
	var message := ""
	if not result["ok"]:
		message = "healing that increases HP should succeed"
	elif player.get_current_hp() != 100:
		message = "Current HP should be clamped to Max HP"
	elif health_events != [[100, 100]]:
		message = "health_changed should report the clamped HP values"
	elif not max_hp_events.is_empty():
		message = "healing must not emit max_hp_changed"

	player.free()
	return message


func test_nonpositive_healing_fails_without_state_or_signal_changes() -> String:
	var player := _player_at(80, 100)
	var health_events: Array = []
	var max_hp_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: max_hp_events.append(max_hp)
	)

	var message := ""
	for amount in [0, -1]:
		var result: Dictionary = player.heal(amount)
		if result["ok"] or result["error"].is_empty():
			message = "nonpositive healing must fail with a descriptive error"
			break
		if player.get_current_hp() != 80 or player.get_max_hp() != 100:
			message = "failed healing must not change HP"
			break
		if not health_events.is_empty():
			message = "failed healing must not emit health_changed"
			break
		if not max_hp_events.is_empty():
			message = "failed healing must not emit max_hp_changed"
			break

	player.free()
	return message


func test_healing_at_full_hp_fails_without_state_or_signal_changes() -> String:
	var player := _player_at(100, 100)
	var health_events: Array = []
	var max_hp_events: Array = []
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void: health_events.append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: max_hp_events.append(max_hp)
	)

	var result: Dictionary = player.heal(1)
	var message := ""
	if result["ok"] or result["error"].is_empty():
		message = "healing at full HP must fail with a descriptive error"
	elif player.get_current_hp() != 100 or player.get_max_hp() != 100:
		message = "failed healing at full HP must not change HP"
	elif not health_events.is_empty():
		message = "failed healing at full HP must not emit health_changed"
	elif not max_hp_events.is_empty():
		message = "failed healing at full HP must not emit max_hp_changed"

	player.free()
	return message


func _player_at(current_hp: int, max_hp: int) -> Player:
	var player: Player = PlayerScript.new()
	player._current_hp = current_hp
	player._max_hp = max_hp
	return player
