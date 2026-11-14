extends "res://tests/test_case.gd"
## VT-107 slice 1: authorization and scope of RunExportService
## (docs/vt107/02-test-strategy.md: TC-01, TC-02, TC-03, TC-06).
## TC-06 uses the real RunRecordRepository on a real temporary directory; no fake.

const RunExportService := preload("res://scripts/run_management/run_export_service.gd")
const RunRecordRepository := preload("res://scripts/run_management/run_record_repository.gd")

const BASE_TIME := 1_000_000
const FAR_FUTURE := 9_000_000_000

var root_dir: String


func before_each() -> void:
	root_dir = "user://test_run_export/%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_dir(root_dir)


# --- TC-01: invalid requesters are rejected (negative) ----------------------

func test_invalid_requesters_are_not_authorized() -> void:
	var invalid_requesters: Array = [
		{},
		{"role": "player"},
		{"id": "", "role": "player"},
		{"id": 42, "role": "player"},
		{"id": "alice", "role": "guest"},
		{"id": "alice"},
		null,
		"alice",
	]
	for i in invalid_requesters.size():
		var access := RunExportService.authorize(invalid_requesters[i], {})
		check_eq(access["error"], RunExportService.ERR_NOT_AUTHORIZED, "invalid requester #%d" % i)


# --- TC-02: a player cannot name another owner (negative) -------------------

func test_player_cannot_export_another_owners_scope() -> void:
	var access := RunExportService.authorize(_player("alice"), {"owner_id": "bob"})
	check_eq(access["error"], RunExportService.ERR_FORBIDDEN_SCOPE, "player scope bob")


# --- TC-03: how the scope is resolved ---------------------------------------

func test_scope_resolution_for_player_and_maintainer() -> void:
	var own := RunExportService.authorize(_player("alice"), {})
	check_eq(own["error"], "", "player own: error")
	check_eq(own["owner_id"], "alice", "player without scope is limited to own id")
	check_eq(own["any_owner"], false, "player is never any_owner")

	var named_self := RunExportService.authorize(_player("alice"), {"owner_id": "alice"})
	check_eq(named_self["error"], "", "player naming self: error")
	check_eq(named_self["owner_id"], "alice", "player naming self")

	var everything := RunExportService.authorize(_maintainer(), {})
	check_eq(everything["error"], "", "maintainer all: error")
	check_eq(everything["any_owner"], true, "maintainer without owner sees all owners")

	var one_owner := RunExportService.authorize(_maintainer(), {"owner_id": "bob"})
	check_eq(one_owner["error"], "", "maintainer one owner: error")
	check_eq(one_owner["owner_id"], "bob", "maintainer scoped owner")
	check_eq(one_owner["any_owner"], false, "maintainer scoped is not any_owner")


# --- TC-06: a player exports only own records from the real repository ------

func test_player_exports_only_own_records_from_real_repository() -> void:
	var repository := RunRecordRepository.new(root_dir)
	# Saved alternately; bob's record is saved last, so last_run.json is bob's copy.
	for i in 3:
		check_eq(repository.save_new_run(_record("alice_%d" % i, "alice", i * 2)), "", "save alice %d" % i)
		check_eq(repository.save_new_run(_record("bob_%d" % i, "bob", i * 2 + 1)), "", "save bob %d" % i)

	var service := RunExportService.new(root_dir)
	service.clock = func() -> int: return BASE_TIME + 100
	var result: Dictionary = service.export_runs(_player("alice"), {})

	check(result["ok"], "export failed: %s" % result["error"])
	check_eq(result["error"], "", "error")
	var ids: Array = result["records"].map(func(r): return r["run_id"])
	ids.sort()
	check_eq(ids, ["alice_0", "alice_1", "alice_2"], "exported run ids")
	for record in result["records"]:
		check_eq(record.get("owner_id", ""), "alice", "owner of %s" % record.get("run_id", "?"))
		for key in record.keys():
			check(RunExportService.EXPORT_FIELDS.has(key), "field %s must not leave the module" % key)


# --- helpers ----------------------------------------------------------------

func _player(id: String) -> Dictionary:
	return {"id": id, "role": RunExportService.ROLE_PLAYER}


func _maintainer() -> Dictionary:
	return {"id": "qa", "role": RunExportService.ROLE_MAINTAINER}


func _record(run_id: String, owner_id: String, offset: int) -> Dictionary:
	return {
		"run_id": run_id,
		"seed": offset,
		"config": {"width": 50, "height": 50},
		"generation_version": 1,
		"created_at": BASE_TIME + offset,
		"expires_at": FAR_FUTURE,
		"status": "completed",
		"won": true,
		"reason": "boss",
		"owner_id": owner_id,
	}


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
