# Acceptance Criteria — Procedural Dungeon: Seeded Roguelike

## 1. Purpose
Define observable evidence for deciding whether key MVP requirements are complete. Refine these draft criteria as implementation details are agreed.

## 2. Dungeon Generation

### AC-GEN-01 — Generate a dungeon
- **Given** a supported generation configuration and a seed,
- **When** the generator runs,
- **Then** it returns a dungeon representation and required metadata without an unhandled error.

### AC-GEN-02 — Dungeon validity
- **Given** a generated dungeon,
- **When** validity checks run,
- **Then** it satisfies documented rules for start/end locations, traversable cells, and required connectivity.
- **Open item:** write the exact validity rules in the generator specification.

### AC-GEN-03 — Deterministic generation
- **Given** the same seed and identical generation configuration,
- **When** the generator runs at least twice,
- **Then** the canonical dungeon representations are identical.

### AC-GEN-04 — Different seeds
- **Given** two different seeds,
- **When** the generator runs with the same configuration,
- **Then** both seeds are accepted and both resulting dungeons are valid.
- **Note:** different seeds are not required to produce different layouts every time unless the algorithm explicitly guarantees that.

## 3. Player and Combat

### AC-GAME-01 — Player movement
- **Given** the player is in a playable dungeon,
- **When** the player uses supported movement controls,
- **Then** the player moves according to the control rules and cannot pass through blocked terrain.

### AC-GAME-02 — Combat result
- **Given** the player and an enemy are in a valid combat situation,
- **When** an attack is performed,
- **Then** health/damage state updates according to agreed combat rules and defeat is handled correctly.

### AC-GAME-03 — Enemy variety
- **Given** the MVP build,
- **When** enemy content is inspected or tested,
- **Then** at least three enemy types with documented distinguishing behaviors or attributes are present.

### AC-GAME-04 — Boss encounter
- **Given** the player reaches the boss encounter,
- **When** the encounter is played,
- **Then** the boss can participate in combat and defeat of the boss or player leads to the defined outcome.

## 4. Inventory

### AC-INV-01 — Inventory operations
- **Given** an available item and an inventory state,
- **When** the player performs a supported inventory operation,
- **Then** the item and inventory state update according to agreed rules, including any capacity or usage restrictions defined by the team.

## 5. Seed Saving and Replay

### AC-SEED-01 — Save and display seed
- **Given** a run has started,
- **When** its seed is assigned,
- **Then** the game makes the seed visible and stores it in the agreed run record.

### AC-SEED-02 — Replay a run
- **Given** a saved seed and associated generation configuration,
- **When** the player selects replay,
- **Then** the game regenerates a dungeon whose canonical representation matches the original dungeon for that run.

### AC-SEED-03 — Reproduce a bug
- **Given** a bug depends on a generated dungeon,
- **When** the bug is reported,
- **Then** the GitHub issue records the seed, relevant generation configuration, reproduction steps, expected behavior, and actual behavior.

## 6. Engineering Evidence

### AC-ENG-01 — Unit tests
- The repository contains runnable unit tests for key generator rules.
- The team documents how to run them.
- CI runs the relevant checks, or clearly documents checks not yet automated.

### AC-ENG-02 — Property tests
- Tests evaluate generator invariants across multiple seeds/configurations within the supported input range.
- A failure reports enough information, including seed/configuration where possible, to reproduce it.

### AC-ENG-03 — Benchmark
- The benchmark records test configuration, number of runs, and generation-time results.
- Results are committed or documented in the repository.

### AC-ENG-04 — CI
- The CI workflow runs on an agreed trigger, such as a push or pull request.
- A successful run verifies the checks actually configured.
- Do not claim a build/test check is covered until it is configured and has executed.

## 7. Run Outcome

### AC-RUN-01 — Win/loss conditions
- **Given** a run is in progress,
- **When** the player meets an agreed win or loss condition,
- **Then** the game displays the corresponding result and avoids an ambiguous run state.

## 8. Open Decisions
Before final sign-off, define:
- Dungeon validity rules and required connectivity.
- Dungeon dimensions and supported generation configuration.
- Canonical dungeon representation for deterministic comparisons.
- Combat, enemy, boss, and inventory rules.
- Run data stored in addition to the seed.
- Performance target, benchmark environment, and acceptable generation time.
