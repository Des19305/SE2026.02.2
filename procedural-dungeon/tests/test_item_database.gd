extends "res://tests/test_case.gd"

const ItemDataScript := preload("res://scripts/inventory/item_data.gd")
const ItemDatabaseScript := preload("res://scripts/inventory/item_database.gd")

var database


func before_each() -> void:
	database = ItemDatabaseScript.new()


func test_register_and_lookup_valid_definition() -> void:
	var definition := _make_definition(
		"healing_potion",
		"Consumable",
		"consumable",
		["healing"],
		[],
		0,
		[],
		true,
		5
	)

	var registration: Dictionary = database.register_definition(definition)
	check_eq(registration, {"ok": true, "error": ""}, "registration result")

	var lookup: Dictionary = database.get_item_definition("healing_potion")
	check(lookup["ok"], "lookup should succeed")
	check_eq(lookup["error"], "", "lookup error")
	check_eq(lookup["definition"], definition, "lookup definition")


func test_metadata_is_preserved_without_mapping_or_interpretation() -> void:
	var effects: Array = ["opaque effect metadata"]
	var definition := _make_definition(
		"metadata_item",
		"Consumable",
		"equipment",
		["special"],
		["weapon"],
		2,
		effects,
		true,
		3
	)

	var registration: Dictionary = database.register_definition(definition)
	check(registration["ok"], "category and item_type must not be cross-validated")

	var lookup: Dictionary = database.get_item_definition("metadata_item")
	var retrieved: ItemData = lookup["definition"]
	check_eq(retrieved.category, "Consumable", "category")
	check_eq(retrieved.item_type, "equipment", "item_type")
	check_eq(retrieved.tags, ["special"], "tags")
	check_eq(retrieved.allowed_slot_types, ["weapon"], "allowed_slot_types")
	check_eq(retrieved.slots_required, 2, "slots_required")
	check_eq(retrieved.effects, effects, "effects")


func test_rejects_empty_id() -> void:
	var definition := _make_definition(
		"",
		"Consumable",
		"consumable",
		[],
		[],
		0,
		[],
		true,
		1
	)

	var result: Dictionary = database.register_definition(definition)
	check(not result["ok"], "empty ID should be rejected")
	check(not result["error"].is_empty(), "failure should have a descriptive error")
	check(not database.get_item_definition("")["ok"], "empty ID must not be registered")


func test_rejects_duplicate_id_without_overwriting_original() -> void:
	var original := _make_definition("shared_id", "Consumable", "consumable", [], [], 0, [], true, 1)
	var duplicate := _make_definition("shared_id", "Equipment", "equipment", [], ["weapon"], 1, [], false, 1)
	database.register_definition(original)

	var result: Dictionary = database.register_definition(duplicate)
	check(not result["ok"], "duplicate ID should be rejected")
	check(not result["error"].is_empty(), "failure should have a descriptive error")

	var lookup: Dictionary = database.get_item_definition("shared_id")
	check_eq(lookup["definition"], original, "original definition must remain registered")


func test_lookup_of_unknown_id_fails_with_null_definition() -> void:
	var result: Dictionary = database.get_item_definition("unknown_item")

	check(not result["ok"], "unknown ID should fail")
	check(not result["error"].is_empty(), "failure should have a descriptive error")
	check_eq(result["definition"], null, "failed lookup definition")


func test_rejects_max_stack_less_than_one() -> void:
	for invalid_max_stack in [0, -1]:
		var definition := _make_definition(
			"invalid_stack_%d" % invalid_max_stack,
			"Consumable",
			"consumable",
			[],
			[],
			0,
			[],
			true,
			invalid_max_stack
		)
		var result: Dictionary = database.register_definition(definition)
		check(not result["ok"], "max_stack %d should be rejected" % invalid_max_stack)
		check(not result["error"].is_empty(), "failure should have a descriptive error")


func test_rejects_non_stackable_definition_with_max_stack_other_than_one() -> void:
	var definition := _make_definition("non_stackable", "Equipment", "equipment", [], ["weapon"], 1, [], false, 2)

	var result: Dictionary = database.register_definition(definition)
	check(not result["ok"], "non-stackable max_stack other than one should be rejected")
	check(not result["error"].is_empty(), "failure should have a descriptive error")


func test_accepts_only_approved_categories() -> void:
	for category in ["Consumable", "Key / Quest", "Equipment"]:
		var definition := _make_definition(
			"valid_category_%s" % category,
			category,
			"independent_item_type",
			[],
			[],
			0,
			[],
			true,
			1
		)
		var result: Dictionary = database.register_definition(definition)
		check(result["ok"], "approved category %s should be accepted" % category)

	var invalid_definition := _make_definition(
		"invalid_category",
		"Upgrade",
		"upgrade",
		[],
		[],
		0,
		[],
		true,
		1
	)
	var invalid_result: Dictionary = database.register_definition(invalid_definition)
	check(not invalid_result["ok"], "unapproved category should be rejected")
	check(not invalid_result["error"].is_empty(), "failure should have a descriptive error")


func _make_definition(
	item_id: String,
	item_category: String,
	item_type_value: String,
	item_tags: Array[String],
	item_allowed_slot_types: Array[String],
	item_slots_required: int,
	item_effects: Array,
	is_stackable: bool,
	item_max_stack: int
) -> ItemData:
	var definition: ItemData = ItemDataScript.new()
	definition.id = item_id
	definition.name = "Test %s" % item_id
	definition.description = "Test definition"
	definition.icon = null
	definition.category = item_category
	definition.item_type = item_type_value
	definition.tags = item_tags
	definition.allowed_slot_types = item_allowed_slot_types
	definition.slots_required = item_slots_required
	definition.effects = item_effects
	definition.stackable = is_stackable
	definition.max_stack = item_max_stack
	return definition
