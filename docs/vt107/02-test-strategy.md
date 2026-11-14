# VT-107 — Risk-based test strategy and test cases

Baseline `7ae04c5`. Spec: `01-spec-and-plan.md` (AC-EXP-01..05, NFR-1..4, invariant).
Status: DRAFT for review; no test or code exists yet.

## 1. Risks that drive the tests

| Risk | Why it matters here | Tests that answer it |
|---|---|---|
| **R-CONTRACT** (VT-107 focus): a mock hides a wrong contract with storage | `RunRecordRepository` also writes `last_run.json`, keeps expired files until the next save, and a file can be corrupt. A fake repository has none of these. | integration tests on the real repository, plus a contract test on what `RunManager` really writes |
| **R-LEAK**: a requester gets records outside their scope | The invariant of the change request | unit tests for the decision, integration tests for the data |
| **R-CONC**: shared state or interleaving breaks scoping under load | 200 concurrent tasks (VT-107) | concurrency tests |
| **R-STATE**: export changes stored data | NFR-2 | read-only test |
| **R-PERF**: p95 above 5.0 s at 200 tasks | NFR-1 | load harness |

## 2. Levels

- **Unit** (no files): `RunExportService.authorize()` and `select_records()` as pure
  functions on in-memory dictionaries. Fast, covers the decision table of AC-EXP-02/03 and
  the expiry boundary and ordering.
- **Integration / API** (real `RunRecordRepository`, real temporary directory under
  `user://`): `export_runs()` end to end through the public API. This is the level that
  answers R-CONTRACT; no fake repository is used anywhere in the suite.
- **Cross-module flow** (`RunManager` → repository → exporter, still headless, no UI): one
  test that a run started with an owner shows up in that owner's export.
- **Concurrency** (`WorkerThreadPool`, real files): section 4.

**Not needed, and why**
- **UI / full E2E:** no export screen, HUD or network exists, so there is nothing to click.
  The cross-module flow test is the closest honest equivalent.
- **HTTP/socket tests:** option B was rejected (spec section 6).
- **Generator, validator and seed tests:** code is unchanged; the 51 baseline tests already
  run in the same suite as regression protection.
- **Full role × scope × record matrix:** replaced by equivalence classes (own, other,
  missing, legacy owner) to keep the suite small.
- **Fuzzing JSON:** three corrupt-file shapes (truncated, wrong type, empty) are enough
  for this slice.

## 3. Test cases

Priority: P0 = must pass, covers the invariant; P1 = important; P2 = useful.
"Real repo" = `RunRecordRepository` on a temp directory, records written with
`save_new_run`.

| ID | Risk / requirement | Level | Precondition / input | Expected result | Pri |
|---|---|---|---|---|---|
| TC-01 | AC-EXP-02, R-LEAK (negative) | Unit | requesters `{}`, no `id`, `id=""`, `id=42`, role `"guest"`, role missing, `null` | `authorize` returns `Not authorized` for every one | P0 |
| TC-02 | AC-EXP-03, R-LEAK (negative) | Unit | player `alice`, scope `owner_id="bob"` | `Forbidden: scope outside requester` | P0 |
| TC-03 | AC-EXP-03 | Unit | player `alice`, scope `{}`; maintainer, scope `{}`; maintainer, scope `owner_id="bob"` | player scoped to `alice`; maintainer all; maintainer scoped to `bob` | P1 |
| TC-04 | AC-EXP-04, NFR-4 (boundary) | Unit | records with `expires_at` = now-1, now, now+1; shuffled `created_at`; equal `created_at` with run ids `b`,`a` | now-1 and now excluded, now+1 kept; order by `created_at` then `run_id` | P1 |
| TC-05 | AC-EXP-03 (negative) | Unit | scope `owner_id=7` (int), scope not a Dictionary | `Invalid scope` | P2 |
| TC-06 | AC-EXP-01, AC-EXP-03, R-LEAK | Integration, real repo | 3 records each for `alice`, `bob`; player `alice` exports | exactly alice's 3 records, `ok=true`, nothing of bob | P0 |
| TC-07 | AC-EXP-04, **R-CONTRACT** | Integration, real repo | 4 saved runs, so `last_run.json` also exists on disk | 4 records returned, no duplicate `run_id` | P0 |
| TC-08 | AC-EXP-04 | Integration, real repo | one record already expired on disk (not yet pruned), injected clock | expired record absent from the result | P1 |
| TC-09 | AC-EXP-04, R-CONTRACT (**failure path**) | Integration, real repo | 2 valid records + one truncated JSON file + one file containing `[]` + one empty file | `ok=true`, 2 records, `skipped=3`, no script error beyond the declared `expect_error` | P0 |
| TC-10 | AC-EXP-03 | Integration, real repo | one record without `owner_id` + one owned by alice | alice: only hers; maintainer: both | P1 |
| TC-11 | NFR-2, R-STATE | Integration, real repo | directory with valid, expired and corrupt files; run a successful export and a denied export | file names and byte contents identical before and after both calls | P1 |
| TC-12 | AC-EXP-01 (**failure/edge path**) | Integration | `records_dir` does not exist | `ok=true`, `records=[]`, `skipped=0`, directory not created | P2 |
| TC-13 | **R-CONTRACT** | Contract | run started through `RunManager` with `owner_id="alice"`, file read back from disk | the file contains every key the exporter reads (`run_id`, `created_at`, `expires_at`, `owner_id`) and every field in `EXPORT_FIELDS` | P0 |
| TC-14 | AC-EXP-01, AC-EXP-03 | Cross-module flow | alice and bob each `start_new_run`, alice `end_run(true, "boss")` | alice's export: one record, `status=completed`, `won=true`; bob's record not visible | P1 |
| TC-15 | AC-EXP-05, R-CONC | Concurrency | 30 seed records (10 per owner) + 100 writer tasks + 100 exporter tasks in one group | every export `ok`, only own-owner records for players, no duplicate `run_id`, each export contains at least the 10 seed records of its owner; after the join, the final export has all 130 | P0 |
| TC-16 | AC-EXP-05, R-CONC, R-LEAK (negative) | Concurrency | one shared `RunExportService` instance, 200 tasks alternating alice, bob, invalid, maintainer | invalid always gets 0 records; alice never sees bob's and vice versa (catches state kept between calls) | P0 |
| TC-17 | AC-EXP-05, R-CONC (failure path) | Concurrency | 20 expired seed records, writers keep calling `save_new_run` (which prunes) while exporters read | no crash, no expired record returned, only valid records | P2 |
| TC-18 | NFR-1, R-PERF | Load harness | same mix as TC-15 with 200 tasks, per-task duration measured | p95 at most 5.0 s; harness prints p50/p95/max and the machine used | P1 |
| TC-19 | AC-EXP-01, **R-CONTRACT** | Integration, real repo | record with int `seed`, `created_at`, `generation_version` and an int `config` saved by the real repository, then exported | the exported numbers have type int (the file format makes them float), and `RunConfigValidator.validate` accepts the exported config | P0 |
| TC-20 | AC-EXP-01, R-LEAK | Unit | a record with `expires_at` and an extra field `internal_note`, exported through `select_records` | the exported record has neither `expires_at` nor `internal_note`, and still has `run_id` and `owner_id` | P1 |
| TC-21 | AC-EXP-01, NFR-2 | Unit | `select_records` on a record with a `config` dictionary; the caller then changes the exported `config` | the stored record's `config` is unchanged (the export is a deep copy) | P2 |

Negative tests: TC-01, TC-02, TC-05 (and TC-16 for invalid requesters under load).
Failure-path tests tied to their own risk: TC-09 (corrupt file, R-CONTRACT),
TC-12 (missing directory), TC-17 (race with pruning, R-CONC).

TC-19 was added while implementing slice 1: `JSON.parse_string` returns every number as float,
so the real repository hands the exporter `42.0` where an in-memory fake gives `42`, and
`RunConfigValidator` requires `TYPE_INT` for config values. A fake repository would not show it.

## 4. Concurrency testing technique

**What is tested.** Safety properties that must hold for any interleaving, not one
particular output: *no leak*, *no duplicate*, *no invalid result*, *nothing lost* (a
record that existed before the group started is always returned to its owner).

**How tasks are run.** One `Thread` per task (200 threads), all released together by a start
gate (`Semaphore`), then every thread is joined (the runner does not support `await`, see plan
review R5). `WorkerThreadPool` was tried first and rejected: it starts as many workers as CPUs, so on
the 1-CPU development machine the tasks never overlapped (`max_concurrent = 1`, measured); the
tests now assert `max_concurrent >= 2`. Each task reads its own index, so its role (writer, player, maintainer, invalid) is fixed by
that index and does not depend on scheduling.

**Test data choice**
- **Fixed, index-derived data.** Three owners `alice`, `bob`, `carol` by `index % 3`;
  run ids `t<index>_<owner>`; `created_at` from a fixed base plus the index. A failure is
  reproducible from the task index in the message, and nothing uses wall time or random.
- **Own run ids, written directly through the repository.** `RunManager` builds ids as
  `<unix second>_<seed>`, so two runs with the same seed in the same second collide. That is
  a known limitation unrelated to the export; the concurrency tests avoid it deliberately
  and do not depend on it.
- **Pre-seeded records** (10 per owner, never expired) give every exporter a lower bound that
  holds no matter when it runs, so assertions use "at least these, and only these owners"
  instead of an exact count that depends on timing.
- **Final state check after the join** is exact (130 records), because by then no task runs.
- **Shared counters** are updated under a `Mutex`; assertions run on the main thread after
  the join so the runner's collector is not hit from worker threads for failures.

**Bugs this technique is meant to catch:** state kept in the service between calls
(TC-16), scope logic that depends on directory order or on a half-finished listing
(TC-15), a race between export and pruning (TC-17).

**Limit.** The development machine has one CPU: threads are time-sliced, not truly parallel. The
measured overlap is large (60-179 tasks inside the task body at once) because file I/O blocks and
releases the CPU, but the result must be repeated on a multi-core machine before claiming more than
"no failure observed". The student's Windows run is the second environment.

## 5. Flaky-test risks planned for review

- **Time:** expiry uses the injected clock; the only real-time assertion is the p95 in TC-18,
  whose threshold (5.0 s) is far above the 0.3-0.4 s measured in the spike.
- **Order / shared state:** existing tests share `user://test_runs`; the new tests use their own
  `user://test_run_export/<id>` root and clean only that; result order is explicit.
- **Concurrency:** assertions are interleaving-independent (section 4).
- **Environment:** worker threads and `FileAccess` were only spiked on Linux; re-run on Windows.

## 6. Order of work

1. Skeleton `RunExportService` that returns a wrong answer, so tests fail on assertions and not
   on "cannot load script" (the runner reports that as a different kind of failure).
2. TC-01..TC-03 and TC-06 (first slice: authorization and scope), see them fail, then patch.
3. TC-04, TC-07..TC-14, then concurrency TC-15..TC-17, then load TC-18.
