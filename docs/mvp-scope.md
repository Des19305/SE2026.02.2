# MVP Scope — Procedural Dungeon: Seeded Roguelike

## 1. Purpose
Define the minimum playable product and separate required work from optional features.

## 2. MVP Goal
Deliver a playable 2D roguelike in which a player explores a procedurally generated dungeon, fights enemies, manages items, faces a boss, saves the run's seed, and replays the dungeon from that seed.

The same seed and generation configuration must produce the same dungeon.

## 3. Must Have — Required
### Dungeon Generation and Reproducibility
- Generate a dungeon procedurally.
- Apply agreed validity rules, including valid start/end locations and required connectivity.
- Use a seed to control dungeon generation.
- Save and display the seed for a run.
- Replay a run by regenerating its dungeon from the saved seed and generation configuration.

### Core Gameplay
- Player movement and environment collision.
- Combat.
- Inventory for storing and/or using items.
- At least three distinguishable enemy types.
- At least one boss.
- Clear win and loss conditions.

### Engineering Evidence
- Generator unit tests.
- Generator property tests.
- A dungeon-generation benchmark.
- A GitHub issue documenting a bug reproducible with a seed.
- A CI workflow/build check.
- Documentation and repository history that make the work reviewable.

## 4. Should Have — If Time Allows
- Clear HUD and result screens.
- More item variety and rewards.
- Improved balancing and player feedback.
- More detailed animations and sound effects.

## 5. Could Have — Optional Enhancements
- Additional dungeon themes.
- More advanced enemy behaviors.
- Extra abilities or progression mechanics.
- Visual polish beyond what is needed for a coherent MVP.

## 6. Won't Have in the MVP
Unless the team or instructor changes the scope:
- Multiplayer or online accounts.
- Online leaderboards.
- Complex persistent progression systems.
- Features unrelated to core gameplay or seed reproducibility.

## 7. MVP Completion Checklist
- [ ] Dungeon generation passes the agreed validity checks.
- [ ] Same seed and configuration produce the same dungeon representation.
- [ ] Player movement and navigation work.
- [ ] Combat works.
- [ ] Inventory works.
- [ ] At least three enemy types are implemented.
- [ ] At least one boss is implemented.
- [ ] A run's seed can be saved and viewed.
- [ ] Replay recreates the dungeon for the saved seed and configuration.
- [ ] Win/loss conditions are demonstrable.
- [ ] Required tests, benchmark, seed-based bug issue, and CI evidence are available.

## 8. Scope Change Policy
Evaluate any proposed feature outside Must Have against remaining time, risk, and its effect on the MVP. Record agreed changes in the backlog and update this document.
