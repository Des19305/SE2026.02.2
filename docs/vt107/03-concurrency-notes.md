# VT-107 — Concurrency and load notes (slice 4)

Tests: `tests/test_run_export_concurrency.gd` (TC-15, TC-16, TC-17, TC-18).
Shared workload: `tests/workload_run_export.gd`. Load harness: `tests/load_run_export.gd`.
Evidence: `evidence/08` to `evidence/11`. Environment of every number below: Linux sandbox,
1 logical CPU, Godot 4.7.2, local disk, one process.

## What the workload does

200 tasks at once, one `Thread` each, released together. Even index = writer (saves a record
through the real `RunRecordRepository`), odd index = exporter (alice, bob, carol as players, a
maintainer, an invalid requester, in rotation). Role, owner, run id and timestamps come from the
task index only (no random numbers, no wall time). 30 seed records (10 per owner) exist before
the start, so every exporter has a lower bound that holds for any interleaving.

Checked for every task (safety properties, not one fixed output): no run exported twice, a player
never receives another owner's record, an invalid requester gets zero records, no expired record,
every seed record of the requester's scope present. After the join: the final export is exactly
the seeds plus every record a writer saved, with nothing unreadable left.

## Findings

1. **`WorkerThreadPool` gave no concurrency here.** `max_concurrent = 1` in 3 runs on the 1-CPU
   machine: the first version of the tests passed without ever overlapping two tasks. Replaced by
   one `Thread` per task (`max_concurrent` 60-179 over 20 runs); the tests now assert overlap.
2. **Torn reads are real** (this reverses plan review R4). In 20 mixed runs, 410 files were read
   while half written and were skipped (`skipped` counter). The invariants held in all 20 runs and in
   10 further full-suite runs (0 violations). Product meaning: an export may omit a record that is
   being written at that instant; it never leaks or duplicates one.
3. **The test runner crashed.** With real overlap, `ErrorCollector` (a `Logger` that the engine calls
   from any thread) appended to a plain `Array` from many threads: 4 of 6 runs aborted with heap
   corruption (`evidence/08`). Guarding it with a `Mutex` gave 10 of 10 passing runs
   (`evidence/09`). The bug was in shared test infrastructure, not in the export code.
4. **The concurrency tests catch what sequential tests cannot.** Mutant C1 keeps the access decision
   in a member variable of the service. All 66 sequential tests still pass with it; TC-16 (one shared
   service, 200 threads) fails in 6 of 6 runs with `alice received record seed_bob_0 of owner bob`
   (`evidence/10`, `evidence/redcheck_slice4.py`).

## Load result (TC-18, `evidence/11_load_200_linux.log`)

200 concurrent tasks, 5 runs: per-task latency p95 between 0.41 and 0.67 s (target at most 5.0 s),
p99 up to 0.69 s, worst task 0.72 s, whole run 0.49 to 0.75 s. Invariant violations: 0 in 5 runs.

## Limits of these conclusions

- One CPU, Linux, local disk, one process. It does not show behavior on several cores, on a
  network file system, or with real network latency; "200 users" is modeled as 200 threads.
- Latency includes waiting for the CPU among 200 threads, which is why p50 is not tiny; it is not
  the cost of one export alone.
- A margin of about 7x under the target says the target is not at risk in this setup; it does not
  predict a different machine. The Windows run of the student is the second data point.
- `last_run.json` is written by many writers at once (last writer wins); the export ignores it, and
  nothing here checks what it ends up containing.
