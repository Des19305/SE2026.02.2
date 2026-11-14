# VT-107 — Who tests the tests? Mutation, coverage, flaky risks, load

Baseline `7ae04c5`. Suite at the time of writing: 72 tests (51 baseline + 21 new), all passing.
Numbers come from `evidence/` (Linux sandbox, 1 CPU) and from the student's Windows machine
(`evidence/win_*`). Nothing here is a claim that the suite is "good"; it lists what was checked and
what was not.

## 1. Mutation experiment: "remove an important validation" (VT-107)

`evidence/mutation_vt107.py` applies ONE temporary mutant at a time to the export module, runs the
whole suite, records KILLED or SURVIVED, and puts the original bytes back (check: the `git diff` of
`procedural-dungeon/scripts` is empty after every run). Mutants are never committed to the
submission branch. 27 mutants in 9 groups: permission checks P1-P6, owner scope S1-S3, projection
F1-F2, order O1-O2, expiry E1-E2, result X1, repository R1-R3, slice-3 mutants M1-M7, concurrency C1.

The headline "remove one validation" mutants:

| Mutant | What is removed | Killed by |
|---|---|---|
| P4 | the check that stops a player naming another owner (`Forbidden`) | `test_player_cannot_export_another_owners_scope` |
| S1 | the owner filter in `select_records` | 3+ tests (TC-06, TC-14, TC-10, ...) |
| P1 | the role check (any role string accepted) | `test_invalid_requesters_are_not_authorized` and one more |
| E1 | the expiry filter | TC-04, TC-08 |

**First run: 25 of 27 killed (93%), two survivors** (`evidence/12_mutation_before_tests_linux.log`):

- **F1** the mutant adds `expires_at` to the `EXPORT_FIELDS` allow-list, so the internal retention
  timestamp leaves the module. It survived because the only check was circular: TC-06 asserted that every
  returned key is in `RunExportService.EXPORT_FIELDS`, the same constant the mutant had changed, so the
  assertion followed the bug. A real gap: nothing pinned which fields must NOT leave, independently of the code.
- **F2** `config` is no longer deep-copied. No test changed the exported config and then looked at the
  stored record. A real gap: a caller could change the shared data.

Both survived because the tests checked the expected behavior but nothing that would break when the code
misbehaved in these two ways. Added: **TC-20** (`test_export_exposes_only_documented_fields`) and **TC-21**
(`test_exported_config_is_a_copy_of_the_stored_one`); no production code changed.
**Second run: 27 of 27 killed** (`evidence/13_mutation_after_tests_linux.log`); on Windows 27 of 27
killed as well (`evidence/win_07_mutation_slice5.log`, reported by the student). An independent
re-run during review: 26 killed in one run and C1 killed in a separate run (2 plain test failures and
1 runner crash out of 3 runs).

**What a mutation score does not say.** The 27 mutants were chosen by the author and the AI, all in
`run_export_service.gd` and `run_record_repository.gd`. None mutates `RunManager` (the `owner_id`
write), none touches `.json` file filtering, and equivalent mutants were not analyzed. 100% means "these
27 changes are detected", not "the suite finds every defect".

## 2. Coverage

**Line and branch coverage tools are not available** for GDScript in Godot 4.7.2 (no built-in
coverage report and no tool in the project), so no percentage is given. Instead: (a) every decision in
the new code was listed and mapped to the test and mutant that exercises it, and (b) risk coverage by
acceptance criterion.

### 2a. Decision inventory (`run_export_service.gd`, `list_records`)

| Decision | Tests | Mutant that proves a test depends on it |
|---|---|---|
| requester is a Dictionary (line 34) | TC-01 | P3 |
| id is a non-empty String (38) | TC-01 | P2 |
| role is player or maintainer (40) | TC-01 | P1 |
| scope is a Dictionary (42) | TC-05 | P6 |
| `owner_id` in scope is a non-empty String (47) | TC-05 | M1 |
| player names another owner (52) | TC-02 | P4 |
| player is limited to own id (54) | TC-03, TC-06 | P5 |
| maintainer with / without owner (55-57) | TC-03, TC-10 | S2, S3 |
| owner filter (68) | TC-06, TC-10, TC-14 | S1, M4 |
| `expires_at` numeric (71) and `<= now` (73) | TC-04, TC-08 | E1, E2, M7 |
| projection to `EXPORT_FIELDS` (76-78) | TC-06, TC-20, TC-21 | F1, F2 |
| order created_at then run_id (102-104) | TC-04 | O1, O2 |
| denied export returns early (88) | TC-01, TC-11, TC-16 | P-group, C1 |
| directory missing (list_records 40) | TC-12 | M6 |
| `last_run.json` skipped (43) | TC-06, TC-07 | M2 |
| record is a Dictionary, else skipped (46-49) | TC-09 | R3, M3, X1 |
| whole floats turned back into ints (`_restore_ints`) | TC-19 | R1, R2 |

**Not covered by any test or mutant (known gaps):**

- the `.ends_with(".json")` half of line 43: no test puts a non-JSON file in the directory;
- the `created_at` fallback `0` in `_is_before` for records without `created_at`;
- `RunManager` writing `owner_id` is checked only by TC-13 and TC-14, and not by mutation;
- a record whose `owner_id` is not a String (for example a number) is not tested.

### 2b. Risk coverage by acceptance criterion

| AC / risk | Test cases | Evidence of strength | Residual |
|---|---|---|---|
| AC-EXP-01 valid export, order, fields | TC-03, 04, 06, 14, 19, 20, 21 | O1, O2, F1, F2, R1, R2 killed | field values other than numbers are not type-checked |
| AC-EXP-02 not authorized | TC-01, 05, 11, 16 | P1-P3, P6 killed | no test with a role in a different letter case or with spaces |
| AC-EXP-03 scope by owner | TC-02, 03, 06, 10, 14 | P4, P5, S1-S3, M4 killed | `owner_id` of non-String type |
| AC-EXP-04 data validity | TC-04, 07, 08, 09, 11, 12 | E1, E2, M2, M3, M5-M7, R3, X1 killed | non-JSON files; two corrupt shapes beyond the three tried |
| AC-EXP-05 concurrency + p95 | TC-15 to 18 | C1 killed (only by TC-16); 10/10 + 10/10 suite runs | 1-CPU Linux and one Windows machine; no network |
| R-CONTRACT (mock hides wrong contract) | TC-07, 09, 13, 19 | real repository everywhere; found float vs int (TC-19 red) | the contract with `RunManager` is covered by 2 tests, 0 mutants |

## 3. Flaky-test review (at least 2 risks required)

| Risk class | Found | Evidence | Action |
|---|---|---|---|
| **Concurrency** (shared mutable state in the runner) | yes, real | 4 of 6 runs aborted with heap corruption (`evidence/08`) | `ErrorCollector` guarded by a Mutex; 10/10 Linux runs (`evidence/09`) and 10/10 Windows runs (`evidence/win_08_repeat10_slice5.log`) |
| **Concurrency** (test that never overlapped) | yes, real | `WorkerThreadPool` on 1 CPU: `max_concurrent = 1`, so tests passed without testing anything | one Thread per task, and the tests assert `max_concurrent >= 2` (measured 60-188) |
| **Concurrency** (torn reads) | yes, real | 410 unreadable files in 20 runs; count varies from 0 to 19 per run | tests assert invariants, never the exact `skipped` count |
| **Time** | one wall-clock assertion | TC-18 p95: 0.30-0.67 s Linux, 1.11-1.68 s Windows, target 5.0 s | everything else uses the injected clock; margin on Windows is 3x, the thinnest in the suite |
| **Order / shared state** | low | each test uses its own `user://test_run_export/<id>` directory and cleans only that; results are sorted | existing tests still share `user://test_runs` (not changed) |
| **Random data** | none | all data derive from fixed names and task indexes | none |
| **Network** | none | no sockets in the module or tests | none |
| **Platform** | yes | mutant C1 crashes the runner on Linux (exit -6, -11) but only fails one test on Windows (3/3) | the correct code is unaffected; the runner is not robust against memory errors caused by a buggy mutant |

## 4. Load experiment (200 concurrent tasks, p95 at most 5.0 s)

Harness: `tests/load_run_export.gd` (and TC-18 in the suite). 200 tasks, 100 writers and 100 exporters,
one `Thread` per task released together, real files. Per-task latency, nearest-rank percentile.

| Machine | Runs | p95 | Overlap | Invariant violations |
|---|---|---|---|---|
| Linux sandbox, 1 CPU, Godot 4.7.2 | 5 harness runs + 10 suite runs | 0.30-0.67 s | 109-172 tasks | 0 |
| Student's Windows machine, Godot 4.7.2 | 10 suite runs | 1.11-1.68 s | 180-188 tasks | 0 |

Both are far below 5.0 s. **Limits of the conclusion:** in-process threads and local disk, not 200
network users; latency includes waiting for CPU among 200 threads; the Windows CPU count has not been
recorded in the evidence; the result says nothing about a real server, a slower disk or a larger records directory.
