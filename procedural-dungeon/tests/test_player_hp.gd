extends RefCounted

const PlayerScript := preload("res://scenes/player/player.gd")


func test_combat_state_contract() -> String:
	var player: Player = PlayerScript.new()
	var events: Array[bool] = []
	player.combat_state_changed.connect(
		func(is_in_combat: bool) -> void:
			events.append(is_in_combat)
	)

	var message := ""
	if player.is_in_combat():
		message = "Player should start outside Combat"
	else:
		player.start_combat()
		if not player.is_in_combat():
			message = "start_combat should activate Combat"
		elif events != [true]:
			message = "start_combat should emit one true transition"
		else:
			player.start_combat()
			if events != [true]:
				message = "repeated start_combat must not emit"
			else:
				player.end_combat()
				if player.is_in_combat():
					message = "end_combat should deactivate Combat"
				elif events != [true, false]:
					message = "end_combat should emit one false transition"
				else:
					player.end_combat()
					if events != [true, false]:
						message = "repeated end_combat must not emit"

	player.free()
	return message


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


func test_max_hp_only_effect_changes_only_max_hp() -> String:
	var player := _player_at(80, 100)
	var events := _connect_hp_events(player)

	var result: Dictionary = player.set_max_hp_effects({
		"helmet_instance_1": _max_hp_effect(20, "increase_max_only"),
	})
	var message := ""
	if not result["ok"] or result["error"] != "":
		message = "valid Max HP effect should succeed"
	elif player.get_current_hp() != 80 or player.get_max_hp() != 120:
		message = "max-only effect should leave Current HP unchanged"
	elif events["health"] != [] or events["max"] != [120]:
		message = "max-only effect should emit only max_hp_changed"

	player.free()
	return message


func test_max_hp_and_current_effect_changes_both_values() -> String:
	var player := _player_at(80, 100)
	var events := _connect_hp_events(player)

	var result: Dictionary = player.set_max_hp_effects({
		"armor_instance_1": _max_hp_effect(20, "increase_max_and_current"),
	})
	var message := ""
	if not result["ok"]:
		message = "valid Max HP and Current HP effect should succeed"
	elif player.get_current_hp() != 100 or player.get_max_hp() != 120:
		message = "effect should increase both HP values"
	elif events["max"] != [120] or events["health"] != [[100, 120]]:
		message = "effect should emit updated signal payloads"

	player.free()
	return message


func test_removing_max_hp_effect_does_not_heal_and_clamps_only_when_needed() -> String:
	var player := _player_at(60, 100)
	var events := _connect_hp_events(player)
	var effect := _max_hp_effect(20, "increase_max_and_current")
	player.set_max_hp_effects({"armor_instance_1": effect})
	events["health"].clear()
	events["max"].clear()

	var result: Dictionary = player.set_max_hp_effects({})
	var message := ""
	if not result["ok"]:
		message = "effect removal should succeed"
	elif player.get_current_hp() != 80 or player.get_max_hp() != 100:
		message = "effect removal should preserve Current HP when no clamp is needed"
	elif events["health"] != [] or events["max"] != [100]:
		message = "non-clamping removal should emit only max_hp_changed"

	player.free()
	return message


func test_removing_max_hp_effect_clamps_current_hp() -> String:
	var player := _player_at(100, 100)
	var events := _connect_hp_events(player)
	var effect := _max_hp_effect(20, "increase_max_and_current")
	player.set_max_hp_effects({"armor_instance_1": effect})
	events["health"].clear()
	events["max"].clear()

	var result: Dictionary = player.set_max_hp_effects({})
	var message := ""
	if not result["ok"]:
		message = "effect removal should succeed"
	elif player.get_current_hp() != 100 or player.get_max_hp() != 100:
		message = "effect removal should clamp Current HP to the new Max HP"
	elif events["max"] != [100] or events["health"] != [[100, 100]]:
		message = "clamping removal should emit both updated signal payloads"

	player.free()
	return message


func test_replacing_identical_effect_from_new_source_adds_current_hp() -> String:
	var player := _player_at(50, 100)
	var events := _connect_hp_events(player)
	var effect := _max_hp_effect(20, "increase_max_and_current")
	player.set_max_hp_effects({"armor_instance_1": effect})
	events["health"].clear()
	events["max"].clear()

	var result: Dictionary = player.set_max_hp_effects({
		"armor_instance_2": effect,
	})
	var message := ""
	if not result["ok"]:
		message = "effect replacement should succeed"
	elif player.get_current_hp() != 90 or player.get_max_hp() != 120:
		message = "a new source must add an identical effect's Current HP contribution"
	elif events["max"] != [] or events["health"] != [[90, 120]]:
		message = "replacement should publish final HP values once"

	player.free()
	return message


func test_reapplying_same_effect_source_does_not_add_current_hp_twice() -> String:
	var player := _player_at(50, 100)
	var events := _connect_hp_events(player)
	var effects_by_source := {
		"armor_instance_1": _max_hp_effect(20, "increase_max_and_current"),
	}
	player.set_max_hp_effects(effects_by_source)
	events["health"].clear()
	events["max"].clear()

	var result: Dictionary = player.set_max_hp_effects(effects_by_source)
	var message := ""
	if not result["ok"]:
		message = "reapplying an active effect source should succeed"
	elif player.get_current_hp() != 70 or player.get_max_hp() != 120:
		message = "same-source reapplication must preserve HP values"
	elif events["health"] != [] or events["max"] != []:
		message = "same-source reapplication must not emit HP signals"

	player.free()
	return message


func test_invalid_effect_preserves_state_and_emits_nothing() -> String:
	var player := _player_at(80, 100)
	var events := _connect_hp_events(player)
	var valid_effect := _max_hp_effect(20, "increase_max_only")
	player.set_max_hp_effects({"helmet_instance_1": valid_effect})
	events["health"].clear()
	events["max"].clear()

	var invalid_effects: Array = [
		{},
		_max_hp_effect(0, "increase_max_only"),
		{"type": "stat", "stat": "attack", "operation": "add", "value": 1, "hp_behavior": "increase_max_only"},
		_max_hp_effect(1, "unsupported"),
	]
	var message := ""
	for effects in invalid_effects:
		var result: Dictionary = player.set_max_hp_effects({"invalid_source": effects})
		if result != {"ok": false, "error": "invalid_effect"}:
			message = "invalid effects must return invalid_effect"
			break
		if player.get_current_hp() != 80 or player.get_max_hp() != 120:
			message = "invalid effects must preserve HP state"
			break

	if message.is_empty() and (events["health"] != [] or events["max"] != []):
		message = "invalid effects must not emit HP signals"

	player.free()
	return message


func test_reset_hp_clears_effects_and_emits_only_changed_values() -> String:
	var player := _player_at(70, 100)
	var events := _connect_hp_events(player)
	player.set_max_hp_effects({
		"armor_instance_1": _max_hp_effect(20, "increase_max_and_current"),
	})
	events["health"].clear()
	events["max"].clear()

	var result: Dictionary = player.reset_hp()
	var message := ""
	if not result["ok"]:
		message = "reset should succeed"
	elif player.get_current_hp() != 100 or player.get_max_hp() != 100:
		message = "reset should restore initial HP values"
	elif events["max"] != [100] or events["health"] != [[100, 100]]:
		message = "reset should emit both changed HP signals"
	else:
		events["health"].clear()
		events["max"].clear()
		player.reset_hp()
		if events["health"] != [] or events["max"] != []:
			message = "no-op reset must not emit HP signals"

	player.free()
	return message


func _player_at(current_hp: int, max_hp: int) -> Player:
	var player: Player = PlayerScript.new()
	player._current_hp = current_hp
	player._max_hp = max_hp
	return player


func _max_hp_effect(value: int, hp_behavior: String) -> Dictionary:
	return {
		"type": "stat",
		"stat": "max_hp",
		"operation": "add",
		"value": value,
		"hp_behavior": hp_behavior,
	}


func _connect_hp_events(player: Player) -> Dictionary:
	var events := {"health": [], "max": []}
	player.health_changed.connect(
		func(current_hp: int, max_hp: int) -> void:
			events["health"].append([current_hp, max_hp])
	)
	player.max_hp_changed.connect(
		func(max_hp: int) -> void: events["max"].append(max_hp)
	)
	return events
