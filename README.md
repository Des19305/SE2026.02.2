# SE2026.02.2

Procedural Dungeon: a seeded roguelike in Godot 4.7.2. The Godot project is in `procedural-dungeon/`, the team documents are in `docs/`.

## Running the tests

You need Godot 4.7.2. On Windows, use the console build (`Godot_v4.7.2-stable_win64_console.exe`) so the output appears in the terminal. In the commands below, replace `godot` with the path to your Godot executable.

From the repository root:

```bash
godot --headless --path procedural-dungeon --import
```

```bash
godot --headless --path procedural-dungeon -s res://tests/run_tests.gd
```

The first command is only needed once after cloning. The second one runs every `test_*` method in `tests/test_dungeon_generator.gd`, `tests/test_run_manager.gd` and `tests/test_run_retry.gd`. It prints `PASS`/`FAIL` per test and a summary line, and exits with code `1` if any test fails.

To look for order-dependent tests, set `TEST_SHUFFLE_SEED` to any integer; the tests of each file then run in a shuffled order:

```bash
TEST_SHUFFLE_SEED=7 godot --headless --path procedural-dungeon -s res://tests/run_tests.gd
```

### VT-108 load check

`tests/load_test_vt108.gd` runs 100 concurrent tasks (start a run, then end it) with 0%, 30% and 50% transient storage faults and checks p95 ≤ 3.0 s and that disk and memory agree. It takes a few seconds and is not part of `run_tests.gd`.

```bash
godot --headless --path procedural-dungeon -s res://tests/load_test_vt108.gd
```

Options: `TASKS=<n>`, `FAULT_RATES=0,0.3`, and `SHARED_DIR=1` for the stress case where all tasks share one records folder. Details and results: `docs/vt108-retry.md`.
