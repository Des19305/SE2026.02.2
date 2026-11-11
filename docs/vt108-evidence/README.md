# VT-108 evidence logs

Logs of the runs cited in `docs/vt108-retry.md` and in the BT3 report. Machine: Windows 11, 12 CPU threads, Godot 4.7.2 (console build, headless).

| File | Run | Commit |
|---|---|---|
| `00_baseline_e7bb126.log` | test suite on the baseline: 39/39 | `e7bb126` |
| `01_red_tests_before_patch.log` | new VT-108 tests before the patch: 10 of 53 fail | `d51dec2` |
| `02_green_tests_after_patch.log` | after the first patch: 53/53 | `45e977a` |
| `03_red_partial_end.log` | TC-15 added: 1 of 54 fails | `45e977a` + TC-15 |
| `04_green_after_atomic_write.log` | temp file + rename: 54/54 | `8f3ab28` |
| `05_probe_runid_collision.log` | same-second replay reuses `run_id` (not fixed) | `8f3ab28` |
| `06_mutation_M1_is_transient.log` | `is_transient` inverted: 10 fail | `mutation/vt108-transient-inverted` |
| `07_mutation_M2_end_run.log` | `end_run` save check inverted: 7 fail | `mutation/vt108-end-inverted` |
| `08_flaky_20_runs.log` | 30 runs, fixed and shuffled order | see headers in the file |
| `09_load_before_prune_fix.log` | first load check (shared temp name, weak oracle), trimmed | before `e603340` |
| `10_green_final.log` | final suite: 55/55 | `2864ca1` |
| `11_load_per_player_run{1,2,3}.log` | load check, one folder per task, 3 runs | `f5d7856` |
| `12_load_shared_folder_stress.log` | load check, `SHARED_DIR=1` | `f5d7856` |
| `13_mutation_M3_survives_54_tests.log` | failed rename not busy: survives 54 tests | `mutation/vt108-rename-not-busy` |
| `14_mutation_M3_killed_by_TC16.log` | same mutation with TC-16: 1 fails | same branch + TC-16 |
