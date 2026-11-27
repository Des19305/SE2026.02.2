extends "res://tests/test_case.gd"

const FixtureScene := preload("res://tests/inventory_ui_fixture.tscn")

var fixture


func before_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	fixture = FixtureScene.instantiate()
	tree.root.add_child(fixture)
	await tree.process_frame
	await tree.process_frame


func after_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if is_instance_valid(fixture):
		if fixture.inventory_ui.is_inventory_open():
			fixture.inventory_ui.close_inventory()
		fixture.queue_free()
		await tree.process_frame
	fixture = null
	tree.paused = false


func test_e_key_opens_inventory_and_pauses_gameplay() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var event := _key_event(KEY_E)

	fixture.inventory_ui._input(event)

	check(fixture.inventory_ui.is_inventory_open(), "E opens Inventory")
	check(fixture.inventory_ui.visible, "Inventory becomes visible")
	check(tree.paused, "opening Inventory pauses the SceneTree")
	check_eq(
		fixture.inventory_ui.process_mode,
		Node.PROCESS_MODE_WHEN_PAUSED,
		"Inventory remains interactive while paused"
	)


func test_e_key_again_closes_inventory_and_resumes_gameplay() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var event := _key_event(KEY_E)

	fixture.inventory_ui._input(event)
	check(tree.paused, "opening pauses gameplay")

	fixture.inventory_ui._input(event)
	check(not fixture.inventory_ui.is_inventory_open(), "second E closes Inventory")
	check(not fixture.inventory_ui.visible, "closed Inventory is hidden")
	check(not tree.paused, "closing resumes gameplay")


func test_single_echo_or_repeat_event_does_not_toggle_twice() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var event := _key_event(KEY_E)

	fixture.inventory_ui._input(event)
	check(fixture.inventory_ui.is_inventory_open(), "one press opens Inventory")
	check(tree.paused, "one press pauses gameplay")

	var echo_event := _key_event(KEY_E)
	echo_event.echo = true
	fixture.inventory_ui._input(echo_event)
	check(fixture.inventory_ui.is_inventory_open(), "echo event does not close Inventory")
	check(tree.paused, "echo event does not resume gameplay")


func test_ui_actions_remain_functional_while_paused() -> void:
	fixture.inventory_ui.open_inventory()
	check(fixture.inventory_ui.is_inventory_open(), "Inventory is open")

	fixture.player._current_hp = 70
	var player_hp: int = fixture.player.get_current_hp()
	check(inventory_fixture_add(fixture, "potion", 1), "add potion while paused")
	check(fixture.inventory_ui.select_item("potion"), "select potion while paused")
	var use_result: Dictionary = fixture.inventory_ui.use_selected_item(fixture.player)
	check_eq(use_result["ok"], true, "Use remains functional while paused")
	check_eq(use_result["queued"], true, "paused Use queues instead of applying immediately")
	check_eq(
		fixture.inventory_manager.get_item_count("potion"),
		0,
		"paused Use consumes exactly one potion"
	)
	check_eq(
		fixture.player.get_current_hp(),
		player_hp,
		"paused Use does not apply healing before Resume"
	)
	check_eq(
		fixture.inventory_manager.get_deferred_effect_count(),
		1,
		"paused Use enqueues exactly one effect"
	)

	check(inventory_fixture_add(fixture, "sword", 1), "add sword while paused")
	check(fixture.inventory_ui.select_item("sword"), "select sword while paused")
	var remove_result: Dictionary = fixture.inventory_ui.remove_selected_item(1)
	check_eq(remove_result["ok"], true, "Remove remains functional while paused")
	check_eq(
		fixture.inventory_manager.get_item_count("sword"),
		0,
		"paused Remove removes the sword"
	)

	check(fixture.inventory_ui.close_inventory(), "close Inventory to resume")
	check_eq(
		fixture.player.get_current_hp(),
		95,
		"Resume applies the queued healing effect"
	)


func test_hotbar_assignment_remains_available_while_paused() -> void:
	fixture.inventory_ui.open_inventory()
	check(inventory_fixture_add(fixture, "potion", 1), "add potion while paused")
	check(fixture.inventory_ui.select_item("potion"), "select potion while paused")

	var hotbar_ui = fixture.hotbar_ui
	check(hotbar_ui.select_slot(1), "select Hotbar slot 2")
	var result: Dictionary = fixture.inventory_ui.assign_selected_item_to_hotbar(1)

	check_eq(result["ok"], true, "paused assignment succeeds")
	check_eq(hotbar_ui.get_slot_item_id(1), "potion", "paused assignment stores item ID")
	check_eq(
		fixture.inventory_manager.get_item_count("potion"),
		1,
		"paused assignment does not consume potion"
	)

	fixture.player._current_hp = 70
	var use_result: Dictionary = hotbar_ui.use_slot(1)
	check_eq(use_result["ok"], true, "paused Hotbar use is accepted")
	check_eq(use_result["queued"], true, "paused Hotbar use queues an effect")
	check_eq(fixture.inventory_manager.get_item_count("potion"), 0, "paused Hotbar use consumes one potion")
	check_eq(fixture.player.get_current_hp(), 70, "paused Hotbar use does not heal immediately")
	check(fixture.inventory_ui.close_inventory(), "close Inventory to resume Hotbar queue")
	check_eq(fixture.player.get_current_hp(), 95, "Resume applies Hotbar queued healing")


func test_repeated_toggle_keeps_single_pause_owner_and_connections() -> void:
	var tree := Engine.get_main_loop() as SceneTree

	check(fixture.inventory_ui.open_inventory(), "first open succeeds")
	check(fixture.inventory_ui.close_inventory(), "first close succeeds")
	check(not tree.paused, "first close restores normal state")

	check(fixture.inventory_ui.open_inventory(), "second open succeeds")
	check(fixture.inventory_ui.open_inventory() == false, "second open is rejected while already open")
	check(fixture.inventory_ui.close_inventory(), "second close succeeds")
	check(not tree.paused, "second close restores normal state")

	check(fixture.inventory_ui._wired, "existing Inventory signal connections remain enabled")


func test_close_restores_a_preexisting_pause_state() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = true

	fixture.inventory_ui.open_inventory()
	check(tree.paused, "Inventory opens from a preexisting paused state")

	fixture.player._current_hp = 70
	check(inventory_fixture_add(fixture, "potion", 1), "add potion during preexisting pause")
	check(fixture.inventory_ui.select_item("potion"), "select potion")
	var use_result: Dictionary = fixture.inventory_ui.use_selected_item(fixture.player)
	check_eq(use_result["queued"], true, "preexisting pause queues use")
	check_eq(fixture.player.get_current_hp(), 70, "preexisting pause applies no healing")

	fixture.inventory_ui.close_inventory()
	check(tree.paused, "closing restores the preexisting paused state")
	check_eq(fixture.player.get_current_hp(), 70, "closing preexisting pause does not flush")
	check_eq(
		fixture.inventory_manager.get_deferred_effect_count(),
		1,
		"closing preexisting pause retains queued effect"
	)


func inventory_fixture_add(fixture_instance, item_id: String, amount: int) -> bool:
	return fixture_instance.inventory_manager.add_item(item_id, amount)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = false
	event.keycode = keycode
	return event
