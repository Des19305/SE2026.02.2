# VT-107 — export of run records (GAME-2D-02, team SE2026-T27)

Student: Trần Văn Duy, 23001856. Baseline commit `7ae04c5` (head of `feature/run-record`).
Branch: `test/vt107-run-export`. Not merged: waits for team review.

## Run the tests

Godot 4.7.2 (console build on Windows). From the repository root:

```
cd procedural-dungeon
godot --headless --path . --import          # first time only
godot --headless --path . -s res://tests/run_tests.gd
```

Expected: `72 tests, 72 passed, 0 failed`, exit code 0 (`echo %ERRORLEVEL%` on Windows).
The VT-107 tests are `tests/test_run_export.gd` and `tests/test_run_export_concurrency.gd`.

## Load harness (200 concurrent tasks, p95 target 5.0 s)

```
godot --headless --path . -s res://tests/load_run_export.gd -- --tasks=200 --repeats=5
```

It prints one line per run and `worst p95 ... PASS` at the end. Lines starting with `ERROR: Parse JSON failed`
are expected: they are files read while another thread is writing them (counted as `skipped`, never exported).

## Mutation experiment (needs Python 3, run on a clean tree)

```
python docs/vt107/evidence/mutation_vt107.py --godot "<path to Godot console exe>"
```

Applies 27 temporary mutants one at a time and restores the files. Expected: `27 killed of 27`.

## Where things are

| File | Content |
|---|---|
| `01-spec-and-plan.md` | problem, acceptance criteria, invariant, options A/B, plan review |
| `02-test-strategy.md` | test strategy and the 21 test cases |
| `03-concurrency-notes.md` | concurrency technique, findings, load result |
| `04-test-quality.md` | mutation, coverage, flaky review, load |
| `evidence/` | numbered logs: red and green per slice, mutation, load, Windows runs |
