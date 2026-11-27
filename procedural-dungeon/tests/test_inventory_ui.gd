extends "res://tests/test_case.gd"

const FixtureScene := preload("res://tests/inventory_ui_fixture.tscn")

var fixture


func before_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	fixture = FixtureScene.instantiate()
	tree.root.add_child(fixture)
	await tree.process_frame
	await tree.process_frame


func after_each() -> void:
	if is_instance_valid(fixture):
		var tree := Engine.get_main_loop() as SceneTree
		fixture.queue_free()
		await tree.process_frame
	fixture = null


func test_empty_inventory_presentation() -> void:
	check(
		fixture.inventory_ui.get_script() != null,
		"independent fixture should attach the Inventory UI script"
	)
	check(
		fixture.inventory_ui.has_method("get_display_state"),
		"Inventory UI scene exposes get_display_state"
	)
	if fixture.inventory_ui.get_script() != null:
		check_eq(
			fixture.inventory_ui.get_script().resource_path,
			"res://scenes/ui/inventory_ui.gd",
			"Inventory UI scene attaches the expected script"
		)

	check_eq(
		fixture.inventory_ui.get_node("MarginContainer/VBoxContainer/CapacityLabel").text,
		"Capacity: 0 / 12",
		"rendered capacity label shows empty Inventory"
	)
	check(
		fixture.inventory_ui.get_node("MarginContainer/VBoxContainer/EmptyLabel").visible,
		"rendered empty-state label is visible"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/EmptyLabel"
		).text,
		"Inventory is empty",
		"rendered empty-state label text"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/ScrollContainer/ItemGrid"
		).get_child_count(),
		0,
		"rendered item grid has no item slots"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsNameLabel"
		).text,
		"No item selected",
		"rendered details name shows no selection"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsDescriptionLabel"
		).text,
		"",
		"rendered details description is empty"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsQuantityLabel"
		).text,
		"",
		"rendered details quantity is empty"
	)

	var state: Dictionary = fixture.inventory_ui.get_display_state()

	check_eq(state["empty"], true, "empty Inventory is reported")
	check_eq(state["items"], [], "empty Inventory snapshot")
	check_eq(state["used_slots"], 0, "empty Inventory uses zero slots")
	check_eq(state["max_slots"], 12, "empty Inventory uses base capacity")
	check_eq(state["selected_item_id"], "", "empty Inventory has no selected item")
	check_eq(state["selected_name"], "", "empty Inventory has no selected name")
	check_eq(state["selected_description"], "", "empty Inventory has no selected description")


func test_real_inventory_snapshot_details_and_selection() -> void:
	check(fixture.inventory_manager.add_item("potion", 5), "add potion stacks")
	check(fixture.inventory_manager.add_item("sword", 3), "add swords")

	var state: Dictionary = fixture.inventory_ui.get_display_state()
	check_eq(state["empty"], false, "mixed Inventory is not empty")
	check_eq(state["used_slots"], 5, "potion stacks and swords use five slots")
	check_eq(state["max_slots"], 12, "Inventory capacity remains 12")
	check_eq(state["items"], [
		{"item_id": "potion", "amount": 3},
		{"item_id": "potion", "amount": 2},
		{"item_id": "sword", "amount": 1},
		{"item_id": "sword", "amount": 1},
		{"item_id": "sword", "amount": 1},
	], "UI receives the real stable Inventory snapshot")

	var item_grid: GridContainer = fixture.inventory_ui.get_node(
		"MarginContainer/VBoxContainer/ScrollContainer/ItemGrid"
	) as GridContainer
	check_eq(item_grid.get_child_count(), 5, "rendered item grid contains one slot per stack")
	var potion_button_1: Button = item_grid.get_child(0) as Button
	var potion_button_2: Button = item_grid.get_child(1) as Button
	var sword_button_1: Button = item_grid.get_child(2) as Button
	var sword_button_2: Button = item_grid.get_child(3) as Button
	var sword_button_3: Button = item_grid.get_child(4) as Button
	check_eq(potion_button_1.text, "Healing Potion x3", "first rendered potion stack")
	check_eq(potion_button_2.text, "Healing Potion x2", "second rendered potion stack")
	check_eq(sword_button_1.text, "Iron Sword x1", "first rendered sword slot")
	check_eq(sword_button_2.text, "Iron Sword x1", "second rendered sword slot")
	check_eq(sword_button_3.text, "Iron Sword x1", "third rendered sword slot")

	check(fixture.inventory_ui.select_item("potion"), "select potion")
	state = fixture.inventory_ui.get_display_state()
	check_eq(state["selected_item_id"], "potion", "potion remains selected")
	check_eq(state["selected_name"], "Healing Potion", "potion name comes from Item Database")
	check_eq(state["selected_description"], "Restores health.", "potion description comes from Item Database")
	check_eq(state["selected_quantity"], 5, "potion detail shows total quantity")

	check(fixture.inventory_ui.select_item("sword"), "select sword")
	state = fixture.inventory_ui.get_display_state()
	check_eq(state["selected_item_id"], "sword", "sword remains selected")
	check_eq(state["selected_name"], "Iron Sword", "sword name comes from Item Database")
	check_eq(state["selected_description"], "A basic sword.", "sword description comes from Item Database")
	check_eq(state["selected_quantity"], 3, "sword detail shows total quantity")

	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsNameLabel"
		).text,
		"Iron Sword",
		"rendered details name updates on selection"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsDescriptionLabel"
		).text,
		"A basic sword.",
		"rendered details description updates on selection"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsQuantityLabel"
		).text,
		"Quantity: 3",
		"rendered details quantity updates on selection"
	)


func test_inventory_signals_refresh_ui_and_ui_snapshot_is_not_authoritative() -> void:
	check(fixture.inventory_manager.add_item("potion", 2), "add potion")

	var state: Dictionary = fixture.inventory_ui.get_display_state()
	check_eq(state["used_slots"], 1, "inventory_changed refreshes used slots")
	check_eq(state["selected_item_id"], "", "adding an item does not introduce an approved auto-selection rule")
	check_eq(state["selected_quantity"], 0, "no item details are shown without selection")

	check(fixture.inventory_ui.select_item("potion"), "select potion before removal")
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/DetailsQuantityLabel"
		).text,
		"Quantity: 2",
		"rendered selected quantity refreshes after add"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/CapacityLabel"
		).text,
		"Capacity: 1 / 12",
		"rendered capacity label refreshes after add"
	)

	var displayed_items: Array = state["items"]
	displayed_items[0]["amount"] = 99
	check_eq(
		fixture.inventory_manager.get_item_count("potion"),
		2,
		"mutating UI snapshot does not mutate Inventory"
	)

	check(fixture.inventory_manager.remove_item("potion", 2), "remove potion")
	state = fixture.inventory_ui.get_display_state()
	check_eq(state["empty"], true, "inventory_changed refreshes empty state")
	check_eq(state["used_slots"], 0, "inventory_changed refreshes capacity usage")
	check_eq(state["selected_item_id"], "", "empty Inventory clears selection")
	check(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/EmptyLabel"
		).visible,
		"rendered empty label becomes visible after remove"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/CapacityLabel"
		).text,
		"Capacity: 0 / 12",
		"rendered capacity label refreshes after remove"
	)
	check_eq(
		fixture.inventory_ui.get_node(
			"MarginContainer/VBoxContainer/ScrollContainer/ItemGrid"
		).get_child_count(),
		0,
		"rendered item grid removes stale item buttons"
	)


func test_no_selected_item_actions_are_safe() -> void:
	var use_result: Dictionary = fixture.inventory_ui.use_selected_item(fixture.player)
	check_eq(use_result["ok"], false, "Use with no selection fails")
	check_eq(use_result["error"], "no_item_selected", "Use with no selection reports a safe error")
	check_eq(use_result["consumed"], false, "Use with no selection consumes nothing")

	var remove_result: Dictionary = fixture.inventory_ui.remove_selected_item(1)
	check_eq(remove_result["ok"], false, "Remove with no selection fails")
	check_eq(remove_result["error"], "no_item_selected", "Remove with no selection reports a safe error")
	check_eq(remove_result["removed"], false, "Remove with no selection removes nothing")
	check_eq(fixture.inventory_manager.get_items(), [], "no-selection actions leave Inventory unchanged")


func test_use_selected_healing_item_updates_inventory_player_and_ui() -> void:
	fixture.player._current_hp = 70
	check(fixture.inventory_manager.add_item("potion", 1), "add one potion")
	check(fixture.inventory_ui.select_item("potion"), "select potion")

	var use_result: Dictionary = fixture.inventory_ui.use_selected_item(fixture.player)

	check_eq(use_result["ok"], true, "selected potion use succeeds")
	check_eq(use_result["consumed"], true, "selected potion is consumed")
	check_eq(fixture.player.get_current_hp(), 95, "healing updates Player HP")
	check_eq(fixture.player.get_max_hp(), 100, "healing preserves Max HP")
	check_eq(fixture.inventory_manager.get_item_count("potion"), 0, "potion is consumed once")
	check_eq(fixture.inventory_manager.get_used_slots(), 0, "potion slot is released")
	check_eq(fixture.inventory_manager.get_items(), [], "Inventory snapshot is empty after use")

	var state: Dictionary = fixture.inventory_ui.get_display_state()
	check_eq(state["empty"], true, "UI refreshes empty Inventory")
	check_eq(state["used_slots"], 0, "UI refreshes used slots after use")
	check_eq(state["max_slots"], 12, "UI preserves capacity after use")
	check_eq(state["selected_item_id"], "", "exhausted selected item is cleared")


func test_remove_selected_item_updates_inventory_and_ui() -> void:
	check(fixture.inventory_manager.add_item("sword"), "add one sword")
	check(fixture.inventory_ui.select_item("sword"), "select sword")

	var remove_result: Dictionary = fixture.inventory_ui.remove_selected_item(1)

	check_eq(remove_result["ok"], true, "remove selected item succeeds")
	check_eq(remove_result["removed"], true, "remove reports item removed")
	check_eq(fixture.inventory_manager.get_item_count("sword"), 0, "sword is removed once")
	check_eq(fixture.inventory_manager.get_used_slots(), 0, "sword slot is released")
	check_eq(fixture.inventory_manager.get_items(), [], "Inventory snapshot is empty after remove")

	var state: Dictionary = fixture.inventory_ui.get_display_state()
	check_eq(state["empty"], true, "UI refreshes empty Inventory after remove")
	check_eq(state["used_slots"], 0, "UI refreshes used slots after remove")
	check_eq(state["selected_item_id"], "", "removed selected item is cleared")
