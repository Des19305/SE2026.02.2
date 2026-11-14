extends RefCounted
## Exports run records to authorized requesters, limited to their scope (VT-107,
## docs/vt107/01-spec-and-plan.md). Read-only: never writes or deletes records.
##
## SKELETON: public names and return shapes only. The behavior is deliberately
## not implemented yet, so the first tests fail on their assertions.

const ROLE_PLAYER := "player"
const ROLE_MAINTAINER := "maintainer"
const ERR_NOT_AUTHORIZED := "Not authorized"
const ERR_FORBIDDEN_SCOPE := "Forbidden: scope outside requester"
const ERR_INVALID_SCOPE := "Invalid scope"

## Fields that leave the module; anything else in a record stays inside.
const EXPORT_FIELDS := [
	"run_id", "seed", "config", "generation_version",
	"created_at", "status", "won", "reason", "owner_id",
]

var records_dir: String
## Returns the current Unix time in seconds; replaceable in tests.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())


func _init(dir: String) -> void:
	records_dir = dir


## Decides whether requester may export and which owner(s) the export covers.
## Returns {"error": String, "owner_id": String, "any_owner": bool}; error is
## empty when allowed.
static func authorize(_requester: Variant, _scope: Variant) -> Dictionary:
	return {"error": "", "owner_id": "", "any_owner": true}


## Keeps the records that access allows, as exported copies.
static func select_records(records: Array, _access: Dictionary, _now: int) -> Array:
	return records


## Returns {"ok": bool, "error": String, "records": Array, "skipped": int}.
func export_runs(_requester: Variant, _scope: Variant = {}) -> Dictionary:
	return {"ok": false, "error": "Not implemented", "records": [], "skipped": 0}
