# Stakeholder Analysis — Procedural Dungeon: Seeded Roguelike

## 1. Purpose
Identify the project's initial stakeholders, their needs, and how the team should consider those needs. This is a working draft to validate with the team.

## 2. Stakeholders

| Stakeholder | Main needs / interests | Project response |
|---|---|---|
| Player | Understandable controls, exploration, combat, inventory, enemies, and a boss encounter | Deliver a coherent 2D roguelike gameplay loop and clear feedback |
| Development team (4 members) | Clear responsibilities, manageable modules, frequent integration, reproducible bugs | Shared backlog, module interfaces, code review, automated tests, seed-based reproduction |
| Instructor / evaluator | A working MVP and verifiable engineering evidence | Runnable project, documentation, tests, benchmark, seed-based bug issue, and CI evidence |
| Tester / teammate | Recreate a dungeon and investigate a failure | Record the seed and generation configuration needed to reproduce the dungeon |

## 3. Stakeholder Priorities
1. **Reproducibility and testability:** the same seed and generation configuration should recreate the same dungeon.
2. **Playable MVP:** the player can explore, fight enemies, manage items, and encounter the boss.
3. **Maintainability and teamwork:** modules can be developed and reviewed without unnecessary conflicts.
4. **Verifiable evidence:** requirements and tests should demonstrate important behavior.

## 4. Assumptions to Validate
- The player is the primary end user.
- The instructor/evaluator will assess both the playable result and required engineering evidence.
- The team consists of four members and will work incrementally through GitHub.
- Godot 4 will be used unless the team explicitly chooses another engine.

These are assumptions, not results of user research. Confirm them with the team and instructor where necessary.

## 5. Questions to Resolve
- Are there additional grading requirements or submission formats?
- What minimum gameplay experience should the MVP demonstrate?
- Does replay reproduce only the dungeon layout, or gameplay events as well?
- What evidence is expected for tests, benchmark, bug reproduction, and CI?

## 6. Review
Review this document when new information appears, the MVP scope changes, or stakeholder needs conflict.
