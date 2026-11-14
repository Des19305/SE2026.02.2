# VT-107 — Traceability

Commit hashes are those of the student's branch `test/vt107-run-export` (baseline `7ae04c5`).
Evidence files are in `docs/vt107/evidence/`. "red" = the failing run before the patch, "green" = after.

## A. Acceptance criterion / risk -> test -> file -> commit -> result

Test files: `U` = `procedural-dungeon/tests/test_run_export.gd`, `C` = `.../tests/test_run_export_concurrency.gd`.

| Requirement | Test case (function) | File | Commits (test -> patch) | Result |
|---|---|---|---|---|
| AC-EXP-02 not authorized | TC-01 `test_invalid_requesters_are_not_authorized` | U | `1b8fe34` -> `d62c504` | red `01_red_slice1`: 4 failed; green `02_green_slice1`: 55/55 |
| AC-EXP-03 player cannot name another owner | TC-02 `test_player_cannot_export_another_owners_scope` | U | `1b8fe34` -> `d62c504` | same run as TC-01; killed mutant P4 (`win_09`, branch `34093e7`) |
| AC-EXP-03 scope resolution | TC-03 `test_scope_resolution_for_player_and_maintainer` | U | `1b8fe34` -> `d62c504` | same run; killed P5, S2, S3 |
| AC-EXP-03 only own records, real repository | TC-06 `test_player_exports_only_own_records_from_real_repository` | U | `1b8fe34` -> `d62c504` | same run; killed S1 |
| R-CONTRACT stored record has the keys the exporter reads | TC-13 `test_run_manager_record_has_every_key_the_exporter_reads` | U | `21db891` -> `339ca3e` | red `03_red_slice2`: 3 failed; green `04_green_slice2`: 58/58 |
| AC-EXP-01/03 flow RunManager -> export | TC-14 `test_owner_exports_only_own_runs_started_through_run_manager` | U | `21db891` -> `339ca3e` | same run |
| R-CONTRACT int vs float from the real repository | TC-19 `test_exported_numbers_are_ints_and_config_passes_run_config_validator` | U | `5fac95f` (case), `21db891` -> `339ca3e` | red showed `type 3` (float) and `Config key width must be an integer`; killed R1, R2 |
| AC-EXP-04 expiry boundary, order | TC-04 `test_select_records_drops_expired_and_orders_by_created_at_then_run_id` | U | `985125a` -> `f6f1247` | red `05_red_slice3`: 3 failed; green `06_green_slice3`: 66/66; killed E1, E2, M7, O1, O2 |
| AC-EXP-04 expired file still on disk | TC-08 `test_expired_record_still_on_disk_is_not_exported` | U | `985125a` -> `f6f1247` | same run; killed E1 |
| AC-EXP-03 records without owner | TC-10 `test_records_without_owner_are_only_visible_to_a_maintainer` | U | `985125a` -> `f6f1247` | same run; killed M4 |
| AC-EXP-03 invalid scope, requester first | TC-05 `test_invalid_scope_is_rejected_and_requester_is_checked_first` | U | `985125a` (passed at once) | red-check `07_redcheck_slice3` (`c0c237c`): killed M1; later P6 |
| AC-EXP-04 `last_run.json` is not a record | TC-07 `test_last_run_copy_is_not_exported_as_a_record` | U | `985125a` (passed at once) | killed M2 |
| AC-EXP-04 corrupt files, failure path | TC-09 `test_corrupt_files_are_skipped_and_counted` | U | `985125a` (passed at once) | killed M3, R3, X1 |
| NFR-2 read-only | TC-11 `test_export_does_not_change_stored_files` | U | `985125a` (passed at once) | killed M5 |
| AC-EXP-01 missing directory, failure path | TC-12 `test_missing_records_directory_exports_nothing_and_creates_nothing` | U | `985125a` (passed at once) | killed M6 |
| AC-EXP-01 documented fields only | TC-20 `test_export_exposes_only_documented_fields` | U | `b8eec3a` | `12_mutation_before`: F1 survived; `13_mutation_after`: killed |
| NFR-2 exported config is a copy | TC-21 `test_exported_config_is_a_copy_of_the_stored_one` | U | `b8eec3a` | F2 survived, then killed (12 -> 13) |
| AC-EXP-05 200 mixed tasks | TC-15 `test_mixed_writers_and_exporters_never_leak_or_duplicate` | C | `05fb8f8` -> `79607dc` | red `08_red_slice4_runner_crash`: 4 of 6 runs aborted; green `09_green_slice4`: 10/10; Windows 10/10 |
| AC-EXP-05 shared service instance | TC-16 `test_shared_service_instance_keeps_requesters_apart` | C | `05fb8f8` -> `79607dc` | killed C1 (only test that does) |
| AC-EXP-05 export while pruning | TC-17 `test_export_while_expired_files_are_pruned` | C | `05fb8f8` -> `79607dc` | green with 10/10 runs |
| NFR-1 p95 at most 5.0 s | TC-18 `test_200_concurrent_tasks_p95_is_within_5_seconds` + `tests/load_run_export.gd` | C | `05fb8f8`, `f1ff89f` | Linux p95 0.30-0.67 s; Windows 1.11-1.68 s (10 runs) |

## B. Evidence timeline

| Step | Commit | Evidence |
|---|---|---|
| Baseline | `7ae04c5` | `00_baseline_7ae04c5.log`: 51/51 |
| Spec, plan review, strategy | `1ecda91`, `5fac95f` | `01-spec-and-plan.md` (R1-R6), `02-test-strategy.md` |
| Slice 1 skeleton, red, green | `da96868`, `1b8fe34`, `d62c504` | `01_red_slice1`, `02_green_slice1` |
| Slice 2 skeleton, red, green | `eb5753d`, `21db891`, `339ca3e` | `03_red_slice2`, `04_green_slice2` |
| Slice 3 red, green, red-check | `985125a`, `f6f1247`, `c0c237c` | `05_red_slice3`, `06_green_slice3`, `07_redcheck_slice3` |
| Slice 4 red, fix, harness | `05fb8f8`, `79607dc`, `f1ff89f` | `08_red_slice4_runner_crash`, `09_green_slice4`, `10_redcheck_slice4`, `11_load_200_linux` |
| Slice 5 mutation, new tests | `ffc3f12`, `b8eec3a` | `12_mutation_before_tests_linux` (25/27), `13_mutation_after_tests_linux` (27/27), `14_green_slice5_linux` |
| Windows runs | `d54452c`, `b69f42b`, `2a9c98b`, `264b14a`, `4b485de` | `win_*` logs: slices 1-5, mutation 27/27, 10 repeat runs, branch mutation |
| Test-quality analysis | `bd6fb32`, `c91a1fe` | `04-test-quality.md` |
| Temporary mutation branch | `34093e7` on `mutation/vt107-remove-forbidden-check` | `win_09_mutation_P4.log`: 72 tests, 71 passed, 1 failed (TC-02) |

## C. Requirements without a dedicated test

- NFR-3 (additive change of the record, unchanged signatures): checked by the unchanged baseline tests (51) still passing in every run, and by TC-13; no test names it.
- NFR-4 (determinism): TC-04 (order) and the injected clock; not a test of its own.
