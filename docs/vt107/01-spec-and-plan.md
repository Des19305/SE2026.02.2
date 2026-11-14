# VT-107 — Export run records: specification, plan and plan review

- Student: Trần Văn Duy (23001856), team SE2026-T27, topic GAME-2D-02 (Procedural Dungeon)
- Baseline: `7ae04c55fc1900ddb3e583e6fb58aa04b2f0a964` (head of `feature/run-record`, 2026-11-14)
- Submission branch: `test/vt107-run-export` (not merged; waits for team review)
- Status: DRAFT for review. No production code has been changed yet.

## 1. Problem statement

The project stores one JSON run record per run (`RunRecordRepository`, `user://runs`),
but nothing can read those records back out as a set. Teammates and testers need an
export (for example to attach seed and config to a bug, AC-SEED-03). A careless export
can leak other people's records or return stale or duplicate data.

Add a public export API to Run Management so that:

1. only a requester who is allowed to export gets data, and
2. the data returned is exactly the records inside the requester's allowed scope.

"Endpoint/API" means a public function of the Run Management module (architecture §7.1:
modules talk through function calls and `Dictionary` results). The repository has no
network layer, accounts or database, see option B in section 5.

## 2. Terms

- **requester**: `{"id": String, "role": "player" | "maintainer"}`.
- **scope**: `{"owner_id": String}` (optional key).
- **record owner**: new optional field `owner_id` in the run record (see AC-EXP-03).
- **Result**: `{"ok": bool, "error": String, "records": Array, "skipped": int}`
  (`ok/error` convention of architecture §7.1; `skipped` counts unreadable files).

## 3. Acceptance criteria

| ID | Given / When / Then |
|---|---|
| AC-EXP-01 | **Given** a valid requester and a valid scope, **when** it calls `export_runs`, **then** `ok` is true and `records` holds the matching records, sorted by `created_at` then `run_id`, each reduced to the allowed fields. |
| AC-EXP-02 | **Given** a missing, malformed or unknown-role requester, **when** it calls `export_runs`, **then** `ok` is false, `error` is `Not authorized`, `records` is empty and no file is read, changed or deleted. |
| AC-EXP-03 | **Given** records of several owners, **when** a `player` exports, **then** only records with `owner_id == requester.id` are returned, and a scope naming another owner is rejected (`Forbidden: scope outside requester`). A `maintainer` gets the owner named in scope, or all records if no owner is named. Records without `owner_id` (legacy) are visible only to a `maintainer`. |
| AC-EXP-04 | **Given** a records directory written by the real `RunRecordRepository`, **when** exporting, **then** `last_run.json` (a copy of the latest record) is not counted, records with `expires_at <= now` are excluded, and an unreadable or corrupt file is skipped, counted in `skipped`, and never crashes the export. |
| AC-EXP-05 | **Given** 200 concurrent tasks (exports by different requesters mixed with new runs being saved), **when** they all finish, **then** every export satisfies AC-EXP-02..04, no record is returned twice or to a wrong requester, and the p95 task duration is at most 5.0 s. |

## 4. Non-functional constraints

- **NFR-1 Performance**: p95 per task at most 5.0 s with 200 concurrent tasks (VT-107 load level).
- **NFR-2 Read-only, no side effects**: export never writes, renames or deletes records, including on failure (architecture §7.7: failures must not change state).
- **NFR-3 Contract compatibility**: the change to the run record is additive only. `start_new_run`, `replay_last_run`, `end_run` signatures and the existing record keys stay as they are (§7.3, §7.7). Legacy records without `owner_id` stay readable.
- **NFR-4 Determinism**: output order is fixed and "now" comes from an injectable clock, so tests do not depend on wall time or directory order.

## 5. Invariant and contract to protect

**Invariant (most important):** for every record `r` in `result.records`,
`r` belongs to the requester's allowed scope, `r` is not expired, and `r` is a real run
record (not `last_run.json`, not a half-written file). Corollary: a failed authorization
returns zero records.

**Contract to protect:** the file format that `RunRecordRepository` writes (`run_id`,
`seed`, `config`, `created_at`, `expires_at`, `status`, ..., `owner_id`) is exactly what the
exporter reads. This is the risk of VT-107 ("a mock hides a wrong contract"): a fake
repository would not contain `last_run.json`, expired files or corrupt files, so the
integration tests must use the real repository on a real temporary directory, and one
contract test compares what the real repository writes with what the exporter expects.

## 6. Two options proposed by the AI, and the decision

**Option A — `RunExportService` inside `scripts/run_management/`.** A `RefCounted` class
taking `records_dir` and a clock, reading through a new read-only
`RunRecordRepository.list_records()`. Authorization and scoping live in the service,
file access stays in the repository (architecture §7.1: a module owns its state, others
use the public API).

**Option B — local HTTP endpoint.** A `TCPServer`/`HTTPServer` listener with a token
and `GET /export`.

**Decision: A.** Evidence from the repository at `7ae04c5`:

1. `grep -rnE "HTTPServer|TCPServer|HTTPRequest|HTTPClient|WebSocket|ENet"` over all `.gd`,
   `.tscn`, `project.godot` and CI finds nothing: B would add a networking layer nobody owns.
2. There are no accounts, sessions or tokens anywhere (`grep owner|requester|role` finds
   nothing), so B would need a whole auth system before the actual change request.
3. `architecture.md` §7.1 defines inter-module access as function calls returning
   `Dictionary`; CI (`ci.yml`) only imports the project and has no way to host a server.
4. A listener with 200 real sockets in a headless CI job is a flaky-test risk that
   would hide the risk we actually care about (contract with storage).

**Rejected: B** (HTTP endpoint). It stays out of scope; limits are written in the report.

## 7. Plan produced by the coding agent (v1)

Prompt actually used: the student pasted the VT-107 assignment text with the repository and wrote
(Vietnamese, shortened): "analyze the assignment ... what am I still missing ... do not do the
assignment yet, analyze it carefully first, then prepare code", then approved the plan with "co" (yes).
The paragraph that follows is how the AI formulated the task for itself (read docs/architecture.md
section 7 and scripts/run_management/; plan without code a small export API using the real
repository; give two options, the files to change, the assumptions and the first failing test).
It is not a sentence the student typed.

Files the agent intends to change:

| File | Change |
|---|---|
| `scripts/run_management/run_export_service.gd` | new: `export_runs(requester, scope) -> Dictionary` |
| `scripts/run_management/run_record_repository.gd` | add read-only `list_records()`; no change to writes |
| `scripts/run_management/run_manager.gd` | add `var owner_id := ""`, written to the record as `owner_id` |
| `tests/test_run_export.gd` | new: unit, integration and contract tests |
| `tests/test_run_export_concurrency.gd` | new: concurrency tests |
| `tests/load_run_export.gd` | new: 200-task load harness (run by hand, not in the default suite) |
| `tests/run_tests.gd` | register the new test scripts |
| `docs/vt107/`, `README.md` | evidence and how to run |

First vertical slice (test-first): AC-EXP-02 and AC-EXP-03 on the real repository, then
AC-EXP-04, then AC-EXP-05.

## 8. Review of the plan against the repository

R1, R2 and R4 are assumptions the agent made in its first analysis of the repository;
R3, R5 and R6 are shortcuts it considered. Each one was checked with the command shown;
the results are real, from the baseline checkout.

| # | Draft assumption or shortcut | Check | Result |
|---|---|---|---|
| R1 | "A new test file must be listed in `TEST_SCRIPTS`." | `tests/run_tests.gd` lines 9-13 list three scripts; `test_seed_utils.gd` ran in the baseline (51 tests) because it is listed. | **Confirmed.** Shared file: also edited on other branches, so keep the edit to one line per script to limit conflicts. |
| R2 | "Scanning the directory for `*.json` gives all run records." | `run_record_repository.gd`: `save_new_run` also writes `last_run.json`; `prune_expired` skips it by name; expired files are only deleted when the next run is saved. | **Corrected.** The exporter must skip `last_run.json` and filter `expires_at` at read time (AC-EXP-04). |
| R3 | Shortcut: "put the owner in `config`, so no new field and no signature change." | `RunManager._new_record` has no owner field; no `owner`, `requester` or `role` in `scripts/` or `tests/`. | **Corrected.** Add optional `owner_id`; legacy records are maintainer-only. Put it in a `RunManager` property, **not** in `config`: `replay_last_run` reuses `last_run["config"]` and `seed_report` prints config keys, so an owner in config would leak into replay and bug reports. |
| R4 | "Concurrent reads will hit torn (half-written) JSON; the test should provoke it." | Spike (`/tmp/spike/spike.gd`, not in the repo): 3 runs of 200 `WorkerThreadPool` tasks, 100 saves and 10,100 reads each, **0 null parses**. `JSON.parse_string` on a truncated string returns `null` and logs an engine error. | **Weakened, then reversed in slice 4.** The torn-read hazard was not observed at this scale (and this sandbox has 1 CPU), so no test may claim it happens. The failure-path test writes a truncated file deterministically; the concurrency test asserts invariants (no leak, no duplicate), not that tearing occurs. **Correction (slice 4):** the spike used `WorkerThreadPool` on a 1-CPU machine, where the 200 tasks ran one after another (measured `max_concurrent = 1`), so "0 null parses" was an empty result. With real threads, torn reads do occur (hundreds of unreadable files over 20 runs, all skipped without a leak); see `03-concurrency-notes.md`. |
| R5 | Shortcut: "concurrency tests can `await` tasks." | `run_tests.gd` calls `suite.call(test_name)` with no `await`. | **Corrected.** Tests block until every thread has finished (`Thread.wait_to_finish`; slice 4 uses one `Thread` per task, see `03-concurrency-notes.md`). Because the runner's `ErrorCollector` also receives engine errors, error-producing tests must declare `expect_error`, and worker tasks write shared counters under a `Mutex`. |
| R6 | Shortcut: "option B (HTTP) can be tested like option A." | grep for networking classes: no hits; CI only runs `godot --headless --editor --path . --quit`. | **Rejected** (section 6). |

Corrected or rejected: R2, R3, R4, R5, R6 (five points; two were required).

## 9. Assumptions still unproven

- `FileAccess`/`DirAccess` on `user://` are safe from several worker threads on Windows;
  the spike ran on Linux only. Re-run on the student's Windows machine before submitting.
- The load result measures in-process file access, not network latency.

## 10. Needs team agreement before code (workflow §2.1, architecture §7.7)

- `owner_id` added to the run record and `list_records()` added to the repository belong to
  Run Management (owner: Đặng Chí Kiên). The change is additive, but the owner must be told
  in the PR. The VT-108 branch also edits `run_record_repository.gd`; expect a textual
  conflict in that file if both are merged.
