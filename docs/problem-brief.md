# Problem Brief — Procedural Dungeon: Seeded Roguelike

## 1. Project Overview

- **Project code:** GAME-2D-02
- **Project type:** 2D roguelike game
- **Development approach:** Iterative and Incremental Development
- **Proposed engine:** Godot 4 (to be confirmed by the team)

## 2. Problem Statement

Procedurally generated dungeons can be difficult to debug and test when a particular map or gameplay situation cannot be reproduced reliably. If a map changes every time it is generated, the team may struggle to reproduce bugs, verify fixes, and compare test results.

This project addresses that problem by developing a 2D roguelike game that generates dungeons from a seed. Given the same seed and the same generation configuration, the generator should produce the same dungeon so that a run can be reproduced for debugging and testing.

## 3. Product Goal

Build a playable 2D roguelike MVP in which players can explore procedurally generated dungeons, fight enemies, manage items, face a boss, and replay a run using its saved seed.

The project must also provide engineering evidence that the dungeon generator is reliable and reproducible, including automated tests, a benchmark, a documented seed-based bug report, and a CI build.

## 4. Target Stakeholders

- **Players:** need a playable game with understandable controls, exploration, combat, and item management.
- **Development team:** needs reproducible dungeon generation to debug issues and verify fixes.
- **Instructor/evaluator:** needs a working MVP and verifiable evidence of implementation and testing.
- **Testers/team members:** need to recreate a dungeon using a saved seed when checking a bug or regression.

These stakeholders and needs are initial assumptions for the team to confirm.

## 5. MVP Scope

### Must Have

1. Generate a valid dungeon procedurally.
2. Ensure the dungeon has the required connectivity and valid start/end locations according to rules agreed by the team.
3. Reproduce the same dungeon when given the same seed and generation configuration.
4. Support basic player movement and environment collision.
5. Include a combat system.
6. Include an inventory system.
7. Include at least three enemy types.
8. Include at least one boss.
9. Save and display the seed for a run.
10. Allow a player to replay a run using the saved seed.
11. Provide a playable flow with clear win/loss conditions.
12. Include generator unit tests, property tests, a benchmark, a GitHub issue documenting a seed-based bug, and a CI build.

### Out of Scope for the MVP

The following are not required for the first playable version and should only be considered if time remains:

- Multiplayer or online accounts.
- Online leaderboards.
- Complex skill trees or extensive progression systems.
- Multiple elaborate dungeon themes or advanced animation systems.
- Features that do not directly support the core gameplay or seed reproducibility.

## 6. Success Criteria

The MVP will be considered successful when:

- The game can generate a dungeon that satisfies the team's validity rules.
- Repeated generation with the same seed and configuration produces an identical dungeon representation.
- A player can move through the dungeon, fight enemies, use the inventory, and encounter the boss.
- The game can save a run's seed and use it to regenerate the corresponding dungeon.
- Automated tests, a benchmark, a seed-based bug issue, and CI evidence are available in the GitHub repository.
- The team can demonstrate a complete playable run or a clearly defined win/loss outcome.

Performance targets, dungeon dimensions, and exact gameplay rules will be agreed and measured during later planning rather than assumed in this brief.

## 7. Key Risks and Assumptions

| Risk or assumption | Initial response |
|---|---|
| The generator may create disconnected or unusable maps. | Define dungeon validity rules and add unit/property tests early. |
| The same seed may produce different results due to uncontrolled randomness or execution order. | Centralize seeded randomness and test repeatability. |
| Gameplay systems may be difficult to integrate. | Agree on module interfaces and integrate small increments frequently. |
| The four-person team may run short of time. | Prioritize MVP requirements and defer optional features. |
| Engine choice is not yet explicitly confirmed in this brief. | Confirm Godot 4 or Unity with the team before implementation. |

## 8. Development Approach

The team will use an iterative and incremental process. Each iteration should deliver a small, testable improvement to the playable game. The team will plan work, implement it, test it, review the result, reflect on issues, and update the backlog.

Dungeon generation and seed reproducibility should be addressed early because they are central to the project and have important testing implications.

## 9. Open Questions

The team should confirm the following before or during implementation:

- Which engine will be used: Godot 4 or Unity?
- What dungeon dimensions and generation algorithm will be used?
- What exact rules define a valid dungeon?
- Does replay need to reproduce only the dungeon layout, or also the sequence of gameplay events?
- What performance threshold and benchmark environment will be used?
- What are the agreed controls, combat rules, and inventory behavior?

---

**Document status:** Initial draft for team review. Update this brief when the team makes decisions or changes the MVP scope.
