# Dungeon Generation — Implementation Notes

Owner: Nguyễn Thanh Hùng (Issue #4). Status as of commit `e6bf4d7` on `feature/run-record` (PR #6).

This document explains what the generator does today, how other modules should call it, and what is still open. The agreed contract itself lives in `architecture.md` §5–§7.2; this file only describes the implementation and must not contradict it.

## 1. Files

| File | Purpose |
|---|---|
| `procedural-dungeon/scripts/generation/dungeon_generator.gd` | Generator and validator. Pure data, no nodes or scenes. |
| `procedural-dungeon/scripts/generation/seed_utils.gd` | Creating a new seed, reading a seed typed by a player, seed text for the HUD and for bug reports. |
| `procedural-dungeon/tests/test_dungeon_generator.gd` | Generator and validator tests. |
| `procedural-dungeon/tests/test_seed_utils.gd` | Seed utility tests. |
| `procedural-dungeon/tests/run_tests.gd` | Headless test runner (shared with the Run Management tests). |
| `procedural-dungeon/tests/test_case.gd` | `check()`, `check_eq()` and `expect_error()` helpers used by the tests. |

The script has no `class_name`. Load it with `preload`:

```gdscript
const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")
```

## 2. Public API

### `generate_dungeon(seed: int, config: Dictionary) -> Dictionary`

1. Checks `config` with `check_config()`. If it is invalid, returns `INVALID_CONFIG` without generating anything.
2. Tries up to `config.max_attempts` times (default `DEFAULT_MAX_ATTEMPTS = 10`). Each attempt builds a layout with BSP, then runs `validate_dungeon(dungeon, config)`.
3. Returns the first valid layout. If no attempt is valid, returns `GENERATION_FAILED`.

Success result (keys from `architecture.md` §7.2, plus two extra keys):

| Key | Type | Notes |
|---|---|---|
| `ok` | `bool` | `true` |
| `error` | `String` | `""` |
| `seed`, `width`, `height` | `int` | |
| `tiles` | `Array` of `Array` of `int` | `tiles[y][x]`, `0` = wall, `1` = walkable, origin top-left |
| `rooms` | `Array` of `{position: Vector2i, size: Vector2i}` | Stable order (BSP leaf order) |
| `start_cell`, `boss_cell` | `Vector2i` | Centre of the first room / of the room farthest from it (Manhattan distance) |
| `generator_version` | `int` | Extra key, see §4 |
| `attempts` | `int` | Extra key: how many attempts were needed (1 = first try) |

Failure result: the same keys, with `ok = false`, empty `tiles` and `rooms`, `start_cell = boss_cell = Vector2i.ZERO`, and:

| `error` | When | `error_message` example |
|---|---|---|
| `INVALID_CONFIG` | `check_config()` rejected the config | `missing config key: height` |
| `GENERATION_FAILED` | Config is valid but no attempt produced a valid dungeon | `No valid dungeon after 10 attempts (attempt 0: only 4 rooms fit, need at least 12 \| ...)` |
| `INVALID_DUNGEON` | Defined as a constant, not returned by the generator yet (see §7) | |

Callers must check `ok` before using any layout field. `error` is meant for code (`match`, tests); `error_message` is meant for logs and bug reports and its wording may change.

### `check_config(config: Dictionary) -> String`

Returns `""` when the config is valid, otherwise the first problem found. It never raises on malformed input. Rules (`architecture.md` §5.2):

- `width`, `height`, `min_rooms`, `max_rooms`, `min_room_size`, `max_room_size` exist, are `int` and are `> 0`.
- `min_rooms <= max_rooms` and `min_room_size <= max_room_size`.
- `max_room_size <= min(width, height)`.
- Optional `max_attempts`, if present, is a positive `int`.

A config can pass these rules and still be impossible to generate (for example, many large rooms on a small map). That case is reported as `GENERATION_FAILED`, not `INVALID_CONFIG`.

### `validate_dungeon(dungeon: Dictionary, config: Dictionary = {}) -> Dictionary`

Returns `{"valid": bool, "errors": Array}`, where each error is a readable string. It never raises: wrong types, missing keys or `null` values become errors.

Always checked:

- All result keys are present; `width` and `height` are positive integers.
- `tiles` has `height` rows of `width` integer tiles, each `0` or `1`.
- Each room has `Vector2i` `position` and `size`, a positive size, lies inside the map, contains only walkable tiles and does not overlap another room.
- `start_cell` and `boss_cell` are `Vector2i`, inside the map, walkable and distinct.
- The boss is reachable from the start, and every walkable tile is reachable from the start (4-direction flood fill).

Only checked when `config` is passed: the config itself is valid, the grid size matches it, the room count is within `min_rooms..max_rooms`, and each room side is within `min_room_size..max_room_size`.

The optional `config` parameter is an addition to the §7.2 signature. Existing calls with one argument still work.

## 3. Determinism and retries

- Every random choice comes from a `RandomNumberGenerator` created for the attempt. Nothing uses the global `randi()` / `randf()`.
- Attempt `k` (0-based) seeds its RNG with `seed + k * ATTEMPT_SEED_STRIDE`, where `ATTEMPT_SEED_STRIDE = 1_000_003`. Any attempt can therefore be reproduced from the run seed alone, and no unrecorded seed is ever used. This is the strategy `architecture.md` §6.4 still lists as unsettled; it should be copied there once the team agrees.
- The same seed, config and `GENERATOR_VERSION` give the same `tiles`, `rooms` (same order), `start_cell` and `boss_cell`.

### Creating and reading seeds (`seed_utils.gd`)

A seed is an `int` from `0` to `SeedUtils.MAX_SEED` (2 147 483 647, at most 10 digits), so it can be shown on the HUD, typed back by a player, and pasted into a bug report.

| Function | Use |
|---|---|
| `new_seed(rng = null) -> int` | New random seed when the player starts a game without choosing one. This is the only place where unseeded randomness is allowed: the seed is picked before generation and then stored with the run. Pass a seeded `RandomNumberGenerator` to get a repeatable sequence in tests. |
| `parse_seed(text) -> {ok, seed, error}` | Reads a seed typed by the player. Ignores surrounding spaces and leading zeros. Rejects empty text (`Seed is empty`), any character other than `0-9`, including `-` and `+` (`Seed must contain only digits 0-9`), and values above `MAX_SEED` (`Seed must be at most 2147483647`). Never crashes on very long input. |
| `is_valid_seed(seed) -> bool` | `0 <= seed <= MAX_SEED`. |
| `format_seed(seed) -> String` | Text for the HUD and end screen; `parse_seed()` reads it back. |
| `seed_report(seed, config) -> String` | One line for logs and seed-based bug issues (AC-SEED-03), for example `seed=12345 generator_version=1 config={height=50, max_room_size=10, ...}`. Config keys are sorted. |

Typical start of a new game (Run Management / UI):

```gdscript
const SeedUtils := preload("res://scripts/generation/seed_utils.gd")

var seed_value := SeedUtils.new_seed()            # player did not choose a seed
# or: var parsed := SeedUtils.parse_seed(seed_input.text)
#     if not parsed["ok"]: show parsed["error"]; return
#     seed_value = parsed["seed"]
var result := run_manager.start_new_run(seed_value, config)
hud_seed_label.text = "Seed: " + SeedUtils.format_seed(seed_value)
print(SeedUtils.seed_report(seed_value, config))  # for bug reports
```

`RunConfigValidator` still only rejects negative seeds. Rejecting seeds above `MAX_SEED` there too is a small change for the Run Management owner.

## 4. `GENERATOR_VERSION` — when to change it

`GENERATOR_VERSION` (currently `1`) identifies the algorithm. Increase it whenever a change can give a different layout for an existing seed and config. Examples: changing the BSP split rule, the room placement, the corridor shape, or the number or order of RNG calls.

`test_known_seed_layout_is_unchanged` pins the layout of seed `12345` with the default config (room count, start, boss and a hash of `tiles`). If that test fails after your change, either the change was accidental (fix it), or it is intended. In the second case, bump `GENERATOR_VERSION`, update the pinned values, and say so in the PR, because saved seeds will no longer replay to the same map.

Commit `e6bf4d7` did not change any layout: 1000 seeds were compared against the previous commit `4f92e44` and all four layout fields matched.

## 5. Using the generator from other modules

```gdscript
const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")

var dungeon := DungeonGenerator.generate_dungeon(seed, config)
if not dungeon["ok"]:
	push_error("%s: %s" % [dungeon["error"], dungeon["error_message"]])
	return  # do not build the scene or place entities
var grid_result := DungeonGrid.from_dungeon(dungeon)  # Player/Render module (PR #7)
```

- Run Management (`run_manager.gd`) already calls the generator this way. It stores the effective config, including the `max_attempts` default, in the run record so replay uses the same values.
- For `DungeonGrid` (PR #7): `tiles[y][x]` is confirmed as the convention, and tiles are always `int` `0`/`1`.
- Do not modify the returned dictionary in place if other code still uses it. Make a copy first, as `DungeonGrid` does.

## 6. Configs and measured results

| Config | Use | Seeds tested | Result |
|---|---|---|---|
| 50 × 50, 8–12 rooms, room side 5–10 | Default (`architecture.md` §5.2) | 1000 | All generated on the first attempt, no room overlap |
| 30 × 30, 2–4 rooms, room side 3–6 | Debug (used in tests; not yet agreed) | 100 | All valid |
| 30 × 30, 8–12 rooms, room side 5–10 | Debug with default room counts | 100 | None generated: BSP fits only about 4 rooms at this size |

Timing for the default config, 1000 seeds, generation + validation + retries, no rendering: average 1.0 ms, p95 1.2 ms (target: average < 100 ms, p95 < 200 ms). Measured on 2026-11-05 with Godot 4.7.2 on Windows 11, on commit `4f92e44`. It has not been re-measured after `e6bf4d7`, which adds more validation checks, and the benchmark is not yet a script in the repository (see §7).

## 7. Running the tests

From the repository root:

```bash
godot --headless --path procedural-dungeon -s res://tests/run_tests.gd
```

At `e6bf4d7`: 39 tests, 39 passed (19 generator tests, 20 Run Management tests). With the seed utility: 51 tests, 51 passed (12 more in `test_seed_utils.gd`). The runner exits with code `1` if any test fails or if the engine reports a script error during a test. A test that deliberately triggers an engine error must call `expect_error("<part of the message>")` first.

The checks were confirmed to catch real faults: disabling `check_config()` or the overlap check makes three tests fail.

CI does not run these tests yet. `ci.yml` validates the empty `project.godot` in the repository root instead of `procedural-dungeon/`.

## 8. Open items

| Item | Needs |
|---|---|
| Add the retry strategy (§3) to `architecture.md` §6.4 | Agreement from Long (docs owner) |
| Accept the optional `config` parameter of `validate_dungeon` | Agreement from Long (shared API) |
| Agree on a debug config for 30 × 30 | Team decision; tests currently use 2–4 rooms, side 3–6 |
| Return `INVALID_DUNGEON` somewhere, or remove the constant | Team decision; today only Run Management re-validates and it reports a text message |
| Commit a benchmark script (1000 seeds, average/p95, failures, retries) | Issue for AC-ENG-03 |
| Make CI run `tests/run_tests.gd` on `procedural-dungeon/` | CI owner |
| Merge `tests/run_tests.gd` with the runner in PR #7 | Agreement with Duy (both PRs add this file) |
| Use `SeedUtils` when a game starts (random seed or typed seed) and show `format_seed()` on the HUD | Kiên (Run Management, HUD) |
| Run record retention is 70 days in `run_manager.gd`; review on PR #6 asks for 35 | Kiên / Long (Run Management) |
