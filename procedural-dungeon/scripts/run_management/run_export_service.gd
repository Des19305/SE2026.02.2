extends RefCounted
## Exports run records to authorized requesters, limited to their scope (VT-107,
## docs/vt107/01-spec-and-plan.md). Read-only: never writes or deletes records.
##
## Authorization, owner scope, expiry filter, stable order and field projection.

const ROLE_PLAYER := "player"
const ROLE_MAINTAINER := "maintainer"
const ERR_NOT_AUTHORIZED := "Not authorized"
const ERR_FORBIDDEN_SCOPE := "Forbidden: scope outside requester"
const ERR_INVALID_SCOPE := "Invalid scope"

## Fields that leave the module; anything else in a record stays inside.
const RunRecordRepository := preload("res://scripts/run_management/run_record_repository.gd")

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
## empty when allowed. A player is always limited to their own id.
static func authorize(requester: Variant, scope: Variant) -> Dictionary:
	if not (requester is Dictionary):
		return _denied(ERR_NOT_AUTHORIZED)
	var id: Variant = requester.get("id", null)
	var role: Variant = requester.get("role", null)
	if typeof(id) != TYPE_STRING or id == "":
		return _denied(ERR_NOT_AUTHORIZED)
	if typeof(role) != TYPE_STRING or (role != ROLE_PLAYER and role != ROLE_MAINTAINER):
		return _denied(ERR_NOT_AUTHORIZED)
	if not (scope is Dictionary):
		return _denied(ERR_INVALID_SCOPE)

	var named_owner := ""
	if scope.has("owner_id"):
		if typeof(scope["owner_id"]) != TYPE_STRING or scope["owner_id"] == "":
			return _denied(ERR_INVALID_SCOPE)
		named_owner = scope["owner_id"]

	if role == ROLE_PLAYER:
		if false:
			return _denied(ERR_FORBIDDEN_SCOPE)
		return {"error": "", "owner_id": id, "any_owner": false}
	if named_owner != "":
		return {"error": "", "owner_id": named_owner, "any_owner": false}
	return {"error": "", "owner_id": "", "any_owner": true}


## Keeps the records that access allows and that are still valid at now, as copies
## reduced to EXPORT_FIELDS, ordered by created_at then run_id.
## Dropped: records of other owners (records without owner_id match no named owner),
## records with expires_at <= now, and records without a numeric expires_at (validity
## cannot be shown; RunRecordRepository.prune_expired treats them as expired too).
static func select_records(records: Array, access: Dictionary, now: int) -> Array:
	var selected: Array = []
	for record in records:
		if not access["any_owner"] and record.get("owner_id", "") != access["owner_id"]:
			continue
		var expires_at: Variant = record.get("expires_at", null)
		if typeof(expires_at) != TYPE_INT and typeof(expires_at) != TYPE_FLOAT:
			continue
		if expires_at <= now:
			continue
		var exported := {}
		for field in EXPORT_FIELDS:
			if record.has(field):
				exported[field] = record[field].duplicate(true) if record[field] is Dictionary else record[field]
		selected.append(exported)
	selected.sort_custom(_is_before)
	return selected


## Returns {"ok": bool, "error": String, "records": Array, "skipped": int}.
## On failure records is empty and nothing on disk has been touched.
func export_runs(requester: Variant, scope: Variant = {}) -> Dictionary:
	var access := authorize(requester, scope)
	if access["error"] != "":
		return {"ok": false, "error": access["error"], "records": [], "skipped": 0}
	var listing := RunRecordRepository.new(records_dir).list_records()
	var records := select_records(listing["records"], access, clock.call())
	return {"ok": true, "error": "", "records": records, "skipped": listing["skipped"]}


static func _denied(error: String) -> Dictionary:
	return {"error": error, "owner_id": "", "any_owner": false}


static func _is_before(a: Dictionary, b: Dictionary) -> bool:
	var a_time: Variant = a.get("created_at", 0)
	var b_time: Variant = b.get("created_at", 0)
	if a_time != b_time:
		return a_time < b_time
	return str(a.get("run_id", "")) < str(b.get("run_id", ""))
