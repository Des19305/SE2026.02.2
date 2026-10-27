# Software Architecture — Procedural Dungeon Roguelike

## 1. Overview

This document describes the software architecture of the GAME-2D-02 project, **Procedural Dungeon: A Seed-Reproducible Roguelike**.

The game is a 2D roguelike in which dungeons are generated procedurally. The same seed and generation configuration must produce the same dungeon, allowing players and developers to reproduce gameplay environments for replay, debugging, and testing.

The architecture separates the game into functional modules so that team members can develop, test, and integrate their work independently.

## 2. Technology Stack

The project uses the following technologies and development practices:

- **Game engine:** Godot 4.7.2 Stable ([official download archive](https://godotengine.org/download/archive/4.7.2-stable/)).
- **Programming language:** GDScript.
- **Scene and UI management:** Godot's scene and node system.
- **Version control:** Git.
- **Repository hosting and collaboration:** GitHub.
- **Automated verification:** GitHub Actions CI, with project validation, automated tests, and build verification introduced incrementally as the project develops.

### 2.1. Development Environment

All team members should use Godot 4.7.2 Stable for development and testing. The same engine version should also be used in the project's CI environment whenever supported.

Team members **must not** upgrade the project engine version independently. Any version change should be discussed by the team, tested against the existing project, and recorded in the project documentation.

The project should use the standard Godot distribution with GDScript; the .NET-enabled distribution is not required unless the team explicitly decides to introduce C#.

### 2.2. Deterministic Dungeon Generation

The dungeon generator must use controlled, seed-based random number generation rather than relying on uncontrolled global randomness.

Given the same seed, generation configuration, algorithm implementation, and relevant engine behavior, the generator should produce the same dungeon layout. Random decisions that affect the layout must use the controlled random-number generator.

Changes to generation rules should be covered by regression tests to detect unexpected changes in dungeon output. The team should record the seed and relevant configuration when reporting a generation bug.

### 2.3. Testing and Continuous Integration

GitHub Actions should validate the project in a headless environment and progressively run automated tests as they become available.

The verification strategy should include:

- **Unit tests:** Verify individual generation and gameplay functions.
- **Property tests:** Check dungeon validity across multiple seeds and configurations.
- **Determinism tests:** Verify that the same seed and configuration produce the same layout.
- **Integration tests:** Verify that connected gameplay modules work together.
- **Performance benchmarks:** Measure dungeon generation time against the project's agreed performance targets.

CI checks should be updated as new tests and build requirements are implemented. The documentation must distinguish between checks that are already working and those that are planned.

### 2.4. Version Control and Resource Management

GitHub is the shared source of truth for project files. Team members should use branches and pull requests, review changes before merging, and avoid committing generated cache files or temporary editor files.

Godot scenes and resources may reference other project files. When moving or renaming scenes, scripts, or resources, team members should verify affected references and run the relevant project validation and tests.

The team should follow the repository's `.gitignore` rules and preserve required project files and resources when committing changes.

## 3. High-Level Architecture

The game is organized into functional modules:

- **Main:** Initializes the game and coordinates the main gameplay flow.
- **Generation:** Generates dungeon layouts, rooms, corridors, and required positions.
- **Player:** Handles player movement, collision, and player-related state.
- **Combat:** Handles attacks, damage, cooldowns, health changes, and combat outcomes.
- **Enemies:** Implements enemy behavior, including three enemy types and one boss.
- **Inventory:** Manages items and item usage.
- **Run Management:** Manages the current run, seed, generation configuration, and replay.
- **UI:** Displays the HUD, health, inventory, seed information, and win/loss screens.

The architecture separates dungeon generation logic from dungeon presentation. The generation module should produce data that can be validated and tested independently of the visual scene.

## 4. Module Responsibilities

### 4.1 Main

Responsibilities:

- Initialize the game and start a run.
- Coordinate interactions between major modules.
- Request dungeon generation and initialize gameplay using the generated result.
- Coordinate transitions between gameplay and end-of-run states.

Main should coordinate modules rather than contain all gameplay logic.

### 4.2 Generation

Responsibilities:

- Generate dungeon layouts from a seed and configuration.
- Create rooms and connect them with corridors.
- Determine valid starting and boss positions.
- Validate generated dungeon data.
- Report generation failure when a valid dungeon cannot be produced within the configured retry limit.

The generator should not depend on visual rendering in order to generate and validate dungeon data.

### 4.3 Player

Responsibilities:

- Handle player movement and collision.
- Maintain player-specific state.
- Interact with enemies, combat, and inventory through defined interfaces.

### 4.4 Combat

Responsibilities:

- Process attack requests.
- Calculate damage and apply combat rules.
- Handle attack cooldowns and health changes.
- Detect defeated characters and communicate combat outcomes.

Combat rules should be implemented consistently for the player, ordinary enemies, and the boss.

### 4.5 Enemies

Responsibilities:

- Implement the behavior of three enemy types and one boss.
- Maintain enemy-specific behavior and configuration.
- Interact with the combat module to process attacks and damage.
- Communicate when an enemy or boss is defeated.

### 4.6 Inventory

Responsibilities:

- Maintain the player's item collection.
- Support adding, removing, and using items.
- Validate item-use requests.
- Provide inventory information to the UI.

### 4.7 Run Management

Responsibilities:

- Create or accept the seed for a run.
- Maintain the seed and generation configuration used for that run.
- Request dungeon generation.
- Provide the information needed to replay a run.
- Communicate run status and results to the UI.

For the MVP, replay means generating a new dungeon and starting a new run with the same seed and generation configuration. Restoring the complete combat and inventory state of a previous run is outside this definition unless it becomes an explicit requirement.

### 4.8 UI

Responsibilities:

- Display player health and relevant gameplay information.
- Display inventory contents and item counts.
- Show the current seed.
- Provide the necessary controls for starting or replaying a run.
- Display win/loss states and other relevant feedback.

The UI should use module interfaces rather than independently implementing gameplay rules.

## 5. Dungeon Generation

### 5.1. Proposed Algorithm

The proposed dungeon generation algorithm is **Binary Space Partitioning (BSP)** with rectangular rooms connected by corridors.

BSP recursively divides the dungeon area into smaller regions. Rooms are placed within suitable regions, and corridors connect the rooms to create a traversable dungeon.

The generation process consists of the following steps:

1. Initialize the generator using the provided random seed and dungeon configuration.
2. Partition the dungeon area into smaller regions using BSP.
3. Place rectangular rooms within suitable regions while respecting the configured room-size constraints.
4. Connect the rooms with corridors to create a connected dungeon layout.
5. Select a valid starting position and a boss room or boss position.
6. Validate the generated dungeon before returning it to the game.

The generator should be implemented independently of Godot's visual scene system. It should produce dungeon data that can be validated and tested without creating or rendering game scenes.

### 5.2. Initial Generation Configuration

The following values are initial design targets and may be adjusted after implementation and testing.

| Configuration key | Initial value |
|---|---|
| `width` | 50 tiles |
| `height` | 50 tiles |
| `min_rooms` | 8 |
| `max_rooms` | 12 |
| `min_room_size` | 5 tiles |
| `max_room_size` | 10 tiles |

A 30 × 30 map may be used for early development and debugging. Room side lengths must stay within the configured minimum and maximum, and must not exceed the map dimensions.

All configuration values must be positive integers. `min_rooms <= max_rooms` and `min_room_size <= max_room_size`.

The retry limit is provisional. The implementation must use a clearly defined limit and report failure when it is reached. The initial corridor width of 1–2 tiles is a design target, but corridor width is not currently one of the agreed configuration keys.

### 5.3. Dungeon Validity Requirements

A generated dungeon is valid only when all of the following conditions hold:

- Configuration values for `width`, `height`, `min_rooms`, `max_rooms`, `min_room_size`, and `max_room_size` are positive integers.
- `min_rooms <= max_rooms`, `min_room_size <= max_room_size`, and room dimensions do not exceed map dimensions.
- The grid matches the configured width and height and contains only `0` (wall) or `1` (walkable) tiles.
- The room count is within the configured limits. Rooms have valid in-bounds positions and sizes, and do not overlap; corridors may connect to rooms.
- `start_cell` and `boss_cell` are distinct, in bounds, and on walkable tiles.
- The boss is reachable from the start, and every walkable tile is reachable from `start_cell`.
- Reachability uses four-direction movement: up, down, left, and right.

A BFS or flood fill from `start_cell` may check boss reachability and connectivity of all walkable tiles. The validator returns `valid: bool` and `errors: Array` with specific validation errors.

### 5.4. Seed and Determinism

The dungeon generator must use controlled, seed-based random number generation.

Given the same seed, generation configuration, generator version, and compatible Godot environment, generation must produce identical `tiles`, `rooms`, `start_cell`, and `boss_cell`, with stable `rooms` ordering.

The seed and configuration must be available for debugging and reproducibility. When a generation bug is reported, the team should record the seed, configuration, and relevant error details so the issue can be reproduced.

A change to the generation algorithm may change the resulting layout for an existing seed. Such changes should be covered by regression tests.

### 5.5. Generation Failure Handling

The generator must validate its output before the game uses it.

If a generated dungeon is invalid, the generator may retry using the configured retry limit. Each attempt must follow the documented seed-handling strategy so that failures and results can be reproduced.

If a valid configuration cannot produce a compliant dungeon within the retry limit, return an explicit failure; do not silently return invalid data or a dungeon with too few rooms, and do not start gameplay.

The caller must check the generation result before initializing the dungeon scene or placing gameplay entities.

## 6. Seed and Replay Design

### 6.1. Seed-Based Generation

The dungeon generator receives a seed and a generation configuration.

All random decisions that affect dungeon generation must use controlled, seed-based random number generation. Uncontrolled random sources must not affect the generated layout.

The same seed, equivalent generation configuration, and same generation algorithm and rules must produce the same dungeon layout under the same relevant engine behavior.

The generation configuration must retain the complete effective configuration used for the run, including the agreed width, height, room-count, and room-size keys.

### 6.2. Replay

For the MVP, replay means generating a new run with the original seed and complete effective generation configuration. It does not restore the previous gameplay state.

The replay process consists of:

1. Retaining the seed used by the original run.
2. Retaining the generation configuration used by the original run.
3. Passing the retained seed and configuration to the generator.
4. Generating and validating the dungeon.
5. Starting a new run only if generation and validation succeed.

The project must make the current run's seed available for inspection and debugging. The seed and complete effective generation configuration must be retained for as long as they are needed to support replay.

Replay does not automatically restore the previous player's health, inventory, enemy states, or combat progress.

### 6.3. Configuration and Compatibility

The generation configuration must contain all parameters that can affect the generated layout. Replay must use the original run's configuration rather than silently substituting current default values.

Changes to the algorithm, random-number generation, the order of random-number calls, or generation rules may affect reproducibility.

For the MVP, reproducibility is guaranteed only when the seed, generation configuration, generation implementation, and relevant engine behavior are equivalent.

Recording a `generator_version` is proposed for identifying algorithm changes, but is not yet a required field in the agreed contract.

### 6.4. Random Number Generation and Retry Behavior

The generator must follow a consistent random-number generation strategy so that generation behavior can be reproduced during debugging and testing.

For the MVP, the generator should initialize its controlled RNG from the supplied seed. Retries must use a documented deterministic RNG strategy and must not silently switch to an unrecorded random seed. The final retry limit and exact retry/RNG strategy remain unsettled.

If generation fails and a retry is required, the retry process must follow the strategy defined in Section 5. The implementation must not introduce uncontrolled randomness between attempts.

A generation failure must be reported explicitly. The game must not start a run with an invalid dungeon.

### 6.5. Testing Requirements

The following tests should be included as the generator and replay functionality are implemented:

- **Determinism test:** Generate twice with the same seed and configuration; compare `tiles`, `rooms`, `start_cell`, and `boss_cell`, with stable room ordering.
- **Configuration test:** Verify that the generator respects the supplied configuration.
- **Multiple-seed validity test:** Generate dungeons using multiple seeds and verify that they satisfy the dungeon validity requirements.
- **Replay test:** Verify that replay uses the original seed and configuration and produces the same layout while starting a fresh run.

These tests should be automated where practical and included in the project's verification workflow.

## 7. Module API Contracts

This section defines the public interfaces between the main project modules. All team members should follow the agreed function signatures, data structures, and signals when implementing their modules.

Any incompatible API change must be discussed with the team and documented before dependent modules are updated.

### 7.1. General Conventions

- Use GDScript for module implementation.
- Use function calls when an immediate result is required and Godot signals to communicate events.
- Use `Dictionary` for structured results and configuration, `Array` for collections, and `Vector2i` for tile-grid coordinates.
- Each module owns its internal state. Other modules must use its public API instead of directly modifying that state.
- Functions that can fail must return a documented result or status. Callers must check success before using returned data.
- Shared function signatures, dictionary keys, and signal definitions must remain consistent across modules.

### 7.2. Dungeon Generation API

**Module:** `scripts/generation/`

**Responsibility:** Generate and validate dungeon layouts independently of the visual scene system.

#### Public functions

`generate_dungeon(seed: int, config: Dictionary) -> Dictionary`

Generates a dungeon using the supplied seed and configuration. Required positive-integer configuration keys are `width`, `height`, `min_rooms`, `max_rooms`, `min_room_size`, and `max_room_size`. Require `min_rooms <= max_rooms`, `min_room_size <= max_room_size`, and room dimensions no larger than the map.

On success, the result dictionary contains `ok: bool`, `error: String`, `seed: int`, `width: int`, `height: int`, `tiles: Array`, `rooms: Array`, `start_cell: Vector2i`, and `boss_cell: Vector2i`. Each room entry contains `position: Vector2i` and `size: Vector2i`.

The grid uses `0` for walls and `1` for walkable tiles. The origin `(0, 0)` is top-left; x increases right and y increases down. Access the grid as `tiles[y][x]`. Rooms must not overlap; corridors may connect to rooms.

On failure, return `ok = false` and a stable `error` code: `INVALID_CONFIG`, `GENERATION_FAILED`, or `INVALID_DUNGEON`. An `error_message` field may be added for a human-readable explanation. A valid configuration that cannot produce a compliant dungeon within the retry limit must fail, not silently return a map with too few rooms. Callers must not use failed dungeon data as a valid layout.

`validate_dungeon(dungeon: Dictionary) -> Dictionary`

Returns its separate validation result: `valid: bool` and `errors: Array` containing specific validation errors. Validation checks configuration constraints, grid dimensions and tile values, room count, bounds, size and overlap, distinct in-bounds walkable start and boss cells, boss reachability, and connectivity of every walkable tile from the start using four-direction movement. BFS or flood fill may be used.

Runtime coordinates and sizes use `Vector2i`. When storing JSON, encode coordinates as dictionaries such as `{"x": 5, "y": 8}`. The save/load layer validates decoded values before converting them back to `Vector2i`; conversion is not the generator's responsibility.

**Determinism:** With the same seed, configuration, generator version, and compatible Godot environment, results must have identical `tiles`, `rooms`, `start_cell`, and `boss_cell`. The order of entries in `rooms` must be stable.

### 7.3. Run Management API

**Module:** `scripts/run_management/`

**Responsibility:** Manage run initialization, seed and configuration retention, replay, and run completion.

#### Public functions

`start_new_run(seed: int, config: Dictionary) -> Dictionary`

Requests dungeon generation and validation. Returns a result containing `ok: bool`, `error: String`, `seed: int`, and `dungeon: Dictionary` on success. Gameplay must not start if generation or validation fails.

`replay_last_run() -> Dictionary`

Starts a fresh run using the previous run's seed and complete effective generation configuration. Replay regenerates the dungeon but does not restore previous health, inventory, enemy states, or combat progress.

`end_run(won: bool, reason: String) -> void`

Marks the current run as completed.

#### Signals

- `run_started(seed: int, dungeon: Dictionary)`
- `run_ended(won: bool, reason: String)`

Emit `run_started` only after a valid dungeon has been generated and the run has been initialized. Emit `run_ended` when the run finishes.

### 7.4. Combat, Player, and Enemy APIs

**Modules:** `scripts/combat/`, `scenes/player/`, and `scenes/enemies/`

**Responsibilities:** Combat resolves attacks. Player and enemy entities own their health and alive/dead states.

#### Public functions

`resolve_attack(attacker: Node, target: Node, base_damage: int) -> Dictionary`

Attempts to resolve an attack and returns:

- `ok: bool`
- `error: String`
- `damage: int`
- `target_hp: int`

Invalid targets, defeated targets, or invalid damage values must be handled safely without unintended health changes.

`take_damage(amount: int, source: Node) -> Dictionary`

Implemented by damage-receiving entities. Applies damage and returns:

- `ok: bool`
- `hp: int`
- `defeated: bool`

Health must not fall below zero.

#### Signals

Entity signals:

- `health_changed(current_hp: int, max_hp: int)`
- `died(source: Node)`

Combat signal:

- `attack_resolved(attacker: Node, target: Node, damage: int)`

Entities emit `health_changed` when their health changes and `died` once when they transition from alive to defeated. Combat emits `attack_resolved` after a successful attack. The entity's `died` signal is the authoritative notification that it has been defeated; Combat must not emit a duplicate death event.

Cooldowns, attack range, and damage calculation must follow the gameplay rules agreed by the team.

### 7.5. Inventory API

**Module:** `scripts/inventory/`

**Responsibility:** Manage item quantities and item-use rules.

Items are identified by stable string IDs.

#### Public functions

`add_item(item_id: String, amount: int = 1) -> bool`

Adds the specified quantity of an item. Returns `false` if the operation cannot be completed.

`remove_item(item_id: String, amount: int = 1) -> bool`

Removes the specified quantity. If the item or quantity is invalid or insufficient, the operation must fail without changing the inventory.

`use_item(item_id: String, user: Node) -> Dictionary`

Attempts to use an item and returns:

- `ok: bool`
- `error: String`
- `item_id: String`
- `consumed: bool`

An item must only be consumed after its use has been validated and its effect has been applied successfully.

#### Signals

- `inventory_changed(items: Array)`
- `item_used(item_id: String, result: Dictionary)`

Emit `inventory_changed` after a successful inventory modification. Emit `item_used` after an item-use attempt has been processed.

### 7.6. UI and Main Game Integration

**Modules:** `scenes/ui/` and `scenes/main/`

**UI responsibility:** Display game state and forward player actions to the appropriate module.

**Main Game responsibility:** Initialize gameplay, coordinate modules, and connect relevant signals without duplicating module logic.

The UI must support the following interactions:

- Display the current seed, player health, inventory, and run status.
- Request item use through the Inventory API.
- Request replay through Run Management.
- Display generation errors, victory, and defeat.

The main game flow is:

1. Request a new run through Run Management.
2. Check the returned result and stop initialization if it failed.
3. Use valid dungeon data to construct the dungeon scene and place the player and boss.
4. Connect the required entity, inventory, and run signals.
5. Forward relevant outcomes to Run Management and UI.
6. Initialize a fresh run when replay is requested.

The UI must not implement generation, combat, or inventory rules itself.

### 7.7. API Verification and Change Control

Before merging module implementations, the team should verify that:

- Function signatures, return structures, and signal definitions match this section.
- Failure cases are handled without unintended state changes.
- Dungeon generation is deterministic for the same seed and configuration.
- Integration tests cover interactions between the major modules.

Any change to a shared function signature, return structure, signal, or module responsibility must be discussed and documented before dependent implementations are updated.

## 8. Dungeon Validity and Testing Strategy

A generated dungeon is valid only when it satisfies the complete requirements in Sections 5.3 and 7.2.

Initial validity requirements:

- Configuration values are positive integers, with `min_rooms <= max_rooms` and `min_room_size <= max_room_size`; room dimensions do not exceed map dimensions.
- The grid dimensions match configuration and contain only `0` for walls and `1` for walkable tiles.
- Room count is within the configured range; rooms are in bounds, within configured size limits, and non-overlapping.
- `start_cell` and `boss_cell` are distinct, in bounds, and walkable.
- The boss and every walkable tile are reachable from the start using four-direction movement.
- The same seed, configuration, generator version, and compatible Godot environment produce identical `tiles`, `rooms`, `start_cell`, and `boss_cell`, with stable room ordering.

### 8.1 Unit Testing

Unit tests should verify individual generation functions, room creation, corridor creation, random-number initialization, and dungeon data structures.

### 8.2 Property Testing

Property tests should generate dungeons using multiple seeds and verify general properties such as dimensions, boundaries, connectivity, and required positions.

Failed test cases should record the seed and configuration so that the failure can be reproduced.

### 8.3 Determinism Testing

Run the generator at least twice using the same seed and configuration. Compare the resulting dungeon data to verify that the results are identical.

### 8.4 Integration Testing

Integration tests should verify that the game can consume generated dungeon data and initialize the player and boss at valid positions.

Testing should be incorporated into development rather than postponed until the project is complete.

## 9. Initial Performance Targets

The following performance targets are provisional and must be validated through measurement.

| Metric | Initial Target |
|---|---|
| Benchmark dungeon size | 50 × 50 tiles |
| Number of test seeds | 1,000 |
| Average generation time | Below 100 ms |
| P95 generation time | Below 200 ms |
| Successful-output validation | 100% of successful outputs pass the validator |
| Determinism | Identical layouts for repeated runs with the same seed and configuration |

### 9.1. Benchmark Methodology

Benchmarking measures generation, validation, and retries, excluding full game startup, scene initialization, and rendering.

For each test seed, the benchmark should:

1. Use the same documented dungeon generation configuration.
2. Measure generation, validation, and retry time; exclude rendering.
3. Record whether generation succeeds and whether retries are required.
4. Record the generated layout for determinism checks.

The average generation time and P95 generation time should be calculated from the recorded measurements. The P95 represents the generation time at the 95th percentile of the measured results.

The same seed set and configuration should be used when comparing different implementations of the generator.

### 9.2. Validity and Determinism

Every generated dungeon in the benchmark seed set must satisfy the validity requirements defined in Section 5.

Report separately: 100% of successful outputs must pass validation, and the seed success rate is the percentage of tested seeds generating valid dungeons within the retry limit. Record failures; no minimum seed success-rate target is agreed.

For determinism testing, repeated runs with the same seed/configuration must produce identical `tiles`, `rooms`, `start_cell`, and `boss_cell` under the same generator version and compatible Godot environment. Room ordering must be stable.

### 9.3. Environment and Reporting

Each benchmark report must document:

- Godot engine version.
- Hardware and operating system used for testing.
- Dungeon generation configuration.
- Test seed set.
- Number of measured generations.
- Average and P95 generation times.
- Number of successful outputs that pass validation, generation failures, and failed attempts.
- Number of retries, where applicable.
- Number of determinism failures.

These values are targets, not measured results. If the implementation does not meet them, the team should investigate the cause and revise the implementation or targets based on measured evidence.

## 10. Architecture Principles

The project follows the following architectural principles:

1. **Separation of Concerns:** Each module has a clearly defined responsibility. Dungeon generation, combat, inventory, run management, and user interface logic should remain separate.

2. **Reproducibility:** Dungeon generation must be controlled by the seed and the complete generation configuration. The same seed and configuration must produce the same dungeon under the same generation implementation and relevant engine behavior.

3. **Testability:** Core game logic, especially dungeon generation and validation, should be testable independently of visual rendering and scene initialization whenever practical.

4. **Explicit Interfaces:** Module APIs, input and output data, error handling, and signals must be agreed upon before parallel implementation.

5. **Controlled Dependencies:** Modules should communicate through documented interfaces rather than accessing each other's internal state unnecessarily.

6. **Dungeon Validity:** Every successfully generated dungeon must satisfy the defined validity requirements, including valid starting and boss positions, in-bounds rooms and corridors, and a reachable boss room.

7. **Incremental Development:** The architecture should support implementation and testing in small steps. Changes should be based on evolving requirements, test results, and implementation evidence.

8. **Traceability:** Architectural decisions and module responsibilities should remain consistent with the project requirements, MVP scope, and acceptance criteria.