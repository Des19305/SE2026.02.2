# Software Requirements — Procedural Dungeon: Seeded Roguelike

## 1. Purpose
Record initial functional requirements, non-functional requirements, constraints, and assumptions. These drafts should be refined into testable tasks by the team.

## 2. Product Context
The product is a 2D roguelike with procedurally generated dungeons. Its central technical objective is reproducibility: the same seed and generation configuration should produce the same dungeon so bugs and test cases can be recreated.

## 3. Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-01 | The system shall generate a dungeon procedurally. | Must |
| FR-02 | The generated dungeon shall satisfy the team's validity rules, including valid start/end locations and required connectivity. | Must |
| FR-03 | The generator shall use a seed to control random choices used for dungeon generation. | Must |
| FR-04 | Given the same seed and identical generation configuration, the generator shall produce the same dungeon representation. | Must |
| FR-05 | The player shall be able to move through the dungeon and interact with the environment. | Must |
| FR-06 | The game shall handle collisions between the player and relevant environment objects. | Must |
| FR-07 | The game shall provide combat with defined damage and health behavior. | Must |
| FR-08 | The game shall provide an inventory supporting the item operations agreed by the team. | Must |
| FR-09 | The game shall include at least three distinguishable enemy types. | Must |
| FR-10 | The game shall include at least one boss encounter. | Must |
| FR-11 | The game shall save and display the seed associated with a run. | Must |
| FR-12 | The game shall allow replay by regenerating the dungeon using the saved seed and generation configuration. | Must |
| FR-13 | The game shall provide clear win and loss conditions. | Must |
| FR-14 | The repository shall include generator unit tests, property tests, a generation benchmark, a seed-based bug issue, and a CI workflow/build check. | Must |

## 4. Non-Functional Requirements

| ID | Requirement | Verification |
|---|---|---|
| NFR-01 | **Reproducibility:** generation is deterministic for the same seed and configuration. | Generate twice and compare canonical dungeon representations. |
| NFR-02 | **Validity:** generated dungeons satisfy documented validity rules. | Unit and property tests. |
| NFR-03 | **Performance:** generation time is measured and reported for a documented setup. | Benchmark with recorded configuration and results; numeric target TBD. |
| NFR-04 | **Maintainability:** generation, combat, inventory, and run management have clear responsibilities and interfaces. | Architecture and code review. |
| NFR-05 | **Testability:** important generator rules can be tested without relying only on manual gameplay. | Automated tests and documented commands. |
| NFR-06 | **Integration quality:** changes pass agreed CI checks before merging into the main branch. | CI results and pull-request review. |
| NFR-07 | **Usability:** essential controls, seed information, and run outcomes are understandable. | Team playtest against agreed checks. |

## 5. Constraints
- The project is a 2D roguelike.
- The team has four members.
- Development follows an iterative and incremental process.
- Godot 4 is proposed; the team should confirm the final engine choice.
- Required engineering evidence includes generator unit tests, property tests, a benchmark, a seed-based bug issue, and CI.
- MVP gameplay includes dungeon generation, combat, inventory, at least three enemy types, at least one boss, seed saving, and replay.

## 6. Assumptions and Decisions to Confirm
- Seeded randomness will be controlled centrally by the generator.
- The team will define a canonical representation for comparing dungeon layouts.
- Replay currently means reproducing the dungeon layout from the saved seed and generation configuration, not replaying every player action, unless the team decides otherwise.
- Dungeon dimensions, algorithm, item rules, combat values, performance targets, and supported hardware are not yet specified.

## 7. Traceability
Link each requirement to one or more GitHub Issues and to verification evidence (test, manual check, benchmark, or demonstration). Keep requirement IDs stable when editing.

## 8. Change Management
When a requirement changes, record the reason, affected requirements/modules/tests, and team decision in the relevant issue or pull request. Update this document and acceptance criteria accordingly.
