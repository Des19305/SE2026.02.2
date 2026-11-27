class_name ItemDatabase
extends RefCounted

const _VALID_CATEGORIES: Array[String] = ["Consumable", "Key / Quest", "Equipment"]

var _definitions: Dictionary = {}


func register_definition(definition: ItemData) -> Dictionary:
	if definition == null:
		return {"ok": false, "error": "Item definition cannot be null"}

	if definition.id.is_empty():
		return {"ok": false, "error": "Item ID cannot be empty"}

	if _definitions.has(definition.id):
		return {"ok": false, "error": "Item definition already registered: %s" % definition.id}

	if definition.max_stack < 1:
		return {"ok": false, "error": "max_stack must be at least 1"}

	if not definition.stackable and definition.max_stack != 1:
		return {"ok": false, "error": "Non-stackable items must have max_stack = 1"}

	if not _VALID_CATEGORIES.has(definition.category):
		return {"ok": false, "error": "Invalid item category: %s" % definition.category}

	_definitions[definition.id] = definition
	return {"ok": true, "error": ""}


func get_item_definition(item_id: String) -> Dictionary:
	if not _definitions.has(item_id):
		return {
			"ok": false,
			"error": "Item definition not found: %s" % item_id,
			"definition": null,
		}

	return {
		"ok": true,
		"error": "",
		"definition": _definitions[item_id],
	}
