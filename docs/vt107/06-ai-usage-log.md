# VT-107 — AI usage log (DRAFT, the student must check every row)

Rule of the assignment: "the AI said it is right" is never evidence. Every row below points to an
artifact the student can run. Tool in every row: Claude (claude.ai chat with a code sandbox, Godot 4.7.2 on
Linux). Rows marked * come from sessions this draft could not see; the student must complete them from
the original chats. "Student review" must be filled by the student, honestly.

| # | Main prompt (summary) | Output used | Changed or rejected | Evidence | Student review |
|---|---|---|---|---|---|
| 1 | Analyze the VT-107 assignment against the uploaded repository; what is missing? | gap list; finding that the repo has no HTTP, user or database, and that run records exist only on `feature/run-record` | rejected: building on the player branch | git graph, grep for networking and owner/role (`01-spec-and-plan.md` section 6) | |
| 2 | Plan before coding: two options, files, assumptions | option A (`RunExportService`), 8-file list | rejected option B (HTTP); corrected or rejected 5 draft points R2-R6 against the repo | `01-spec-and-plan.md` sections 6-8 | |
| 3 | Risk-based test strategy and a table of at least 10 cases with a concurrency technique | 18 cases, then 21 | TC-19 added after the float finding; TC-20, TC-21 after mutation survivors | `02-test-strategy.md` | |
| 4 | Slice 1: skeleton, failing tests, patch | `authorize`, `select_records`, `export_runs`, `list_records`, tests TC-01/02/03/06 | none rejected; the exported-keys check of TC-06 was later found circular (row 11) | `01_red_slice1` -> `02_green_slice1`, commits `1b8fe34`, `d62c504` | |
| 5 | Slice 2: owner_id and number types | `RunManager.owner_id`, `_restore_ints` | decision: owner in a property, not in `config` | `03_red_slice2` -> `04_green_slice2` | |
| 6 | Slice 3: expiry, order, corrupt files, read-only | expiry and order in `select_records`; 8 tests | 5 tests passed at once, so they were checked by 7 temporary mutants | `05_red_slice3` -> `06_green_slice3`, `07_redcheck_slice3` | |
| 7 | Slice 4: concurrency and 200-task load | workload, TC-15..18, load harness, `ErrorCollector` Mutex | rejected `WorkerThreadPool` (no overlap, measured); reversed the earlier "0 torn reads" conclusion | `08_red_slice4_runner_crash`, `09_green_slice4`, `11_load_200_linux`, `03-concurrency-notes.md` | |
| 8* | Mutation over the export module | 27 mutants, script `mutation_vt107.py`, TC-20 and TC-21 | 2 survivors (F1, F2) fixed by tests, not by production code | `12`, `13`, `win_07` (27/27) | |
| 9 | Test-quality analysis, README | `04-test-quality.md`, `README.md` | the first explanation of why F1 survived was a guess; corrected after reading the mutant and the test (`c91a1fe`) | `04-test-quality.md` | |
| 10 | Commands to run on the student's Windows machine, repeat script | `win_*` runs, `repeat_windows.bat`, temporary mutation branch | several path and download problems fixed with the student | `win_01..win_09`, `264b14a`, `34093e7` | |

## Two AI outputs that looked right and were not trustworthy at first

1. **"200 concurrent tasks" that never overlapped.** The first concurrency tests used `WorkerThreadPool`
   and passed 5 of 5 runs. On the 1-CPU machine the pool has one worker, so `max_concurrent` was 1: the tests
   checked nothing about concurrency. Found by measuring overlap; fixed with one `Thread` per task and an
   assertion `max_concurrent >= 2` (evidence: `03-concurrency-notes.md` finding 1).
2. **An assertion that follows the bug (TC-06).** The test checked that every exported key is in
   `RunExportService.EXPORT_FIELDS`, the constant of the code under test. Mutant F1 (adds `expires_at` to that
   constant) survived 25 of 27 mutants run. Found by the mutation run; fixed by TC-20 which names the fields
   that must not leave (evidence: `12` vs `13`).
3. *(extra)* **A confident conclusion from an empty experiment.** The first spike reported "0 torn reads in
   10,100 reads" and the plan review used it to weaken a risk. It ran on the same non-overlapping pool; with
   real threads the torn reads appear (410 unreadable files in 20 runs). The plan review R4 now carries the
   correction.
