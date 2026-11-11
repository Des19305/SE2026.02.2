# VT-108 — Retry run record storage without repeating side effects

Owner: Nguyễn Thanh Hùng (23001882). Branch: `assignment/vt108-retry`, based on `e7bb126` (`feature/run-record`).
Individual assignment BT3 (Lecture 06–07). Not for merge until the team has reviewed it.

## 1. Specification

### 1.1 Problem statement

Run Management writes every run to the run record storage (`RunRecordRepository`, JSON files under `user://runs`). This storage is the only external dependency of the module. Today a single failed write ends the operation:

- `start_new_run` rejects the run on the first storage error, even when the error is temporary (file locked by another process, device busy).
- If the run record file is written but `last_run.json` is not, the run is rejected but the record stays on disk with `status = "in_progress"`.
- `end_run` ignores storage errors: the run is cleared in memory and `run_ended` is emitted while the file still says `in_progress`.

A naive fix (calling `start_new_run` again) would repeat side effects: a new `run_id` from the clock, a second record file, a second `run_started` signal.

### 1.2 Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | A storage write that fails with a transient error (`ERR_BUSY`, `ERR_FILE_ALREADY_IN_USE`, `ERR_FILE_CANT_OPEN`, `ERR_FILE_CANT_WRITE`, `ERR_LOCKED`, `ERR_TIMEOUT`) is retried up to 3 more times, waiting 50, 100 and 200 ms. If a retry succeeds, the operation succeeds. |
| AC-2 | Retries do not repeat side effects: one successful `start_new_run` gives exactly one `run_id`, one record file, one dungeon generation and one `run_started`; one successful `end_run` gives one `run_ended`. |
| AC-3 | Any other storage error is permanent and is not retried. |
| AC-4 | Start is all-or-nothing. If the record cannot be fully saved, no new record file remains, `last_run.json`, `current_run` and `last_run` keep their previous values, and no signal is emitted. |
| AC-5 | End is all-or-nothing. If the completed record cannot be saved, `end_run` returns `{ok: false, error}`, the run stays `in_progress` in memory and on disk, and `run_ended` is not emitted. Calling `end_run` again after the storage recovers completes the run once. |

### 1.3 Non-functional constraints

| ID | Constraint |
|---|---|
| NFR-1 | 100 concurrent start + end tasks with a 30% transient fault rate per write: p95 task time ≤ 3.0 s. |
| NFR-2 | Bounded retry: at most 4 attempts per write, at most 350 ms of waiting per write. |
| NFR-3 | Unit tests do not sleep and do not depend on random faults: delays and faults are injected. |
| NFR-4 | No change to generated layouts, to the record format, or to the results of the 39 existing tests. |

### 1.4 Invariant to protect

> A run is `in_progress` in memory if and only if its record file says `in_progress`, and every started run has exactly one record file and exactly one `run_started` event.

## 2. Implementation plan (written before code)

Planned files:

| File | Change |
|---|---|
| `scripts/run_management/run_record_repository.gd` | Injectable `write_file` and `sleep`; `_with_retry()` for writes; transient/permanent classification; rollback of the record file when `last_run.json` fails; `update()` returns an error. |
| `scripts/run_management/run_manager.gd` | Pass the injected writer/sleep to the repository; `end_run` returns a result and only clears the run after the record is saved. `start_new_run` keeps creating the record once, before any storage call. |
| `tests/test_run_retry.gd` (new) | State transition tests with a scripted fake storage. |
| `tests/run_tests.gd` | Register the new test file. |
| `tests/load_test_vt108.gd` (new) | 100 concurrent tasks with random transient faults and real waits. |

Key decision: retry at the lowest level where the operation is idempotent (overwriting the same file with the same content), not around `start_new_run`, which has side effects (clock-based `run_id`, signals).

### 2.1 Assumptions and review against the repository

| # | Assumption in the first plan | Verdict | Evidence (line numbers at `e7bb126`) |
|---|---|---|---|
| A1 | The "external service" is the run record storage; there is no network client. | Accepted | No `HTTPRequest` or network code in `procedural-dungeon/`; `run_record_repository.gd` only uses `FileAccess`/`DirAccess`. |
| A2 | Wrapping `start_new_run` in a retry loop is enough. | **Rejected** | `run_manager.gd:38` builds the record with `clock.call()` and `:88` makes `run_id` from it, so a retry after the clock ticks writes a second record; `:45` emits `run_started` inside the same call. |
| A3 | `RunRecordRepository.update()` reports failures, so `end_run` only needs a retry. | **Rejected** | `update()` is declared `-> void` and documented "Best-effort: a failed write is ignored"; `end_run` clears `current_run` and emits `run_ended` unconditionally. |
| A4 | Every storage error can be retried. | **Rejected** | `test_storage_failure_blocks_run_start` creates a file where the directory should be. That error can never succeed on retry and would only add delay. Errors need a transient/permanent split. |
| A5 | Backoff can use `await get_tree().create_timer()`. | **Rejected** | `start_new_run` is synchronous and returns a `Dictionary` (`architecture.md` §7.3); tests create `RunManager.new()` without a scene tree, so `get_tree()` is `null`. Waiting is done by an injectable `sleep` callable. |
| A6 | If `save_new_run()` fails, nothing is left on disk. | **Rejected** | It writes `<run_id>.json` first and `last_run.json` second; a failure on the second write keeps the first file. A rollback step is needed. |
| A7 | `end_run` can change its return type from `void` to `Dictionary` without breaking callers. | Accepted with a note | No caller uses the return value yet (only tests). It changes the §7.3 signature, so it needs team agreement (§7.7). |

## 3. Test design: state transition testing

States of a run, as seen by the caller and by the storage:

| State | In memory | On disk |
|---|---|---|
| S0 Idle | `current_run` empty | no record for a new run |
| S1 In progress | `current_run.status = in_progress` | record `in_progress`, `last_run.json` points to it |
| S2 Completed (then Idle) | `current_run` empty, `last_run.status = completed` | record `completed` |

Events: `start`, `end`, `replay`, each combined with a storage outcome: `ok`, `transient ×k` (k ≤ 3), `transient ×4` (retries exhausted), `permanent`, `partial` (record written, `last_run.json` fails).

| From | Event / storage outcome | To | Expected side effects |
|---|---|---|---|
| S0 | start / ok | S1 | 1 record, 1 `run_started` |
| S0 | start / transient ×2 on record | S1 | 1 record, 1 `run_started`, waits 50 + 100 ms |
| S0 | start / transient ×3 on `last_run.json` | S1 | boundary: last allowed retry |
| S0 | start / transient ×4 | S0 | no record, no signal, error returned |
| S0 | start / permanent | S0 | 1 attempt only, no wait |
| S0 | start / partial | S0 | record rolled back, old `last_run.json` kept |
| S1 | start | S1 | rejected, no write |
| S1 | end / transient ×1 | S2 → S0 | record `completed`, 1 `run_ended` |
| S1 | end / transient ×4 | S1 | `ok = false`, record still `in_progress`, no `run_ended` |
| S1 | end again / ok | S2 → S0 | exactly 1 `run_ended` in total |
| S0 | end | S0 | `ok = false`, no write, no signal |
| S0 (after a failed start) | replay | S1 | replays the previous successful run |

The test cases built from this table are in `tests/test_run_retry.gd` (`TC-xx` in each test name's comment).

## 4. How to run

See the "Running the tests" section of the repository `README.md`.
