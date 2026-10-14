# Development Workflow — Procedural Dungeon Roguelike

## 1. Purpose

This document defines how the team plans, implements, tests, reviews, and integrates the Procedural Dungeon Roguelike project.

The workflow is designed to support parallel development across four team members while maintaining consistent module interfaces, reproducible dungeon generation, code quality, and reliable integration.

The team uses GitHub Issues to track tasks, Git branches and pull requests to manage changes, and GitHub Actions to automate project validation and testing.

## 2. Team Responsibilities and Branch Strategy

Each team member owns a primary area of responsibility. Members should coordinate with other module owners whenever their work affects shared interfaces or gameplay behavior.

| Member | Role | Primary Responsibilities |
|---|---|---|
| Nguyễn Trọng Hiển Long | Team Lead & Integration | Manage backlog, GitHub Issues, project structure, coding conventions, integration, merge conflicts, CI, pull request reviews, and documentation. |
| Nguyễn Thanh Hùng | Dungeon Generation | Implement grid-based dungeon generation, seed-based reproducibility, connectivity validation, start and boss positions, unit tests, property tests, and performance benchmarks. |
| Trần Văn Duy | Player & Combat | Implement player movement, collision, health, attacks, damage handling, three enemy types, and coordinate boss behavior and win/loss conditions. |
| Đặng Chí Kiên | Inventory, UI & Run Management | Implement inventory, item usage, HUD, seed display, run status, replay functionality, and tests for inventory, seed retention, and replay. |

### 2.1. Shared Responsibilities

- Every member is responsible for the correctness, testing, and documentation of their own changes.
- Members must follow the shared API contracts in `architecture.md`, especially Section 7.
- Members must notify affected teammates before changing shared function signatures, return structures, signals, or module responsibilities.
- The team lead coordinates integration but does not replace the technical responsibility of individual module owners.
- Work involving multiple modules must have a clearly identified primary owner and cooperating members.

## 3. Iteration Planning and Review

The team uses **one-week iterations** as the initial development cycle. The duration may be adjusted if the team's schedule or assignment requirements change.

Each iteration follows four stages:

### 3.1. Planning

At the beginning of each iteration, the team should:

1. Review outstanding GitHub Issues and the current project status.
2. Select tasks that can reasonably be completed within the iteration.
3. Assign each task an owner, priority, and clear acceptance criteria.
4. Identify dependencies between modules and confirm any required API contracts.
5. Agree on the iteration goal and required tests.

Tasks should be small enough to review and test independently whenever practical.

### 3.2. Implementation

During implementation, each member should:

- Work on an assigned issue and a separate feature or bug-fix branch.
- Follow the agreed module responsibilities and public interfaces.
- Commit changes regularly using meaningful commit messages.
- Run relevant tests before opening a pull request.
- Update the related issue if the implementation reveals a new requirement, dependency, or blocker.

### 3.3. Integration and Verification

Before the iteration review, the team should:

- Review and merge completed pull requests.
- Resolve integration problems and verify affected module interactions.
- Run the available automated tests and project validation.
- Confirm that the main branch remains in a usable state.
- Record incomplete tasks and newly discovered bugs.

### 3.4. Iteration Review and Retrospective

At the end of each iteration, the team should review:

- Completed features against their acceptance criteria.
- Test results, CI status, and known defects.
- Integration problems and changes to shared interfaces.
- Remaining tasks and blockers.
- Improvements to the team's workflow for the next iteration.

Only work that has been implemented and verified should be reported as completed.

## 4. Task and Backlog Management

GitHub Issues is the team's primary task and bug-tracking system.

Each issue should contain, where applicable:

- A clear title and description.
- The responsible member.
- Priority and relevant labels.
- Acceptance criteria or expected behavior.
- Dependencies on other modules or tasks.
- Testing requirements.
- Relevant seed and configuration details for reproducible generation bugs.

Suggested labels include:

- `feature`
- `bug`
- `documentation`
- `testing`
- `integration`
- `performance`
- `blocked`

An issue should be closed only when its acceptance criteria are satisfied and the required verification has been completed.

## 5. Git Branching and Commit Conventions

### 5.1. Branching Strategy

The team uses `main` as the shared, stable integration branch.

Each task should be implemented on a separate branch created from an up-to-date `main` branch.

Suggested branch naming conventions:

| Branch Type | Example |
|---|---|
| Feature | `feature/dungeon-generation` |
| Feature | `feature/player-combat` |
| Feature | `feature/inventory-ui` |
| Bug fix | `fix/dungeon-connectivity` |
| Testing | `test/generator-properties` |
| Documentation | `docs/update-workflow` |

### 5.2. Task Ownership

Each team member should work on a separate branch based on their assigned responsibilities. The `main` branch is reserved for stable, reviewed, and integrated changes. Branches should be created when work begins rather than all being created in advance.

| Team Member | Suggested Branch | Main Responsibilities |
|---|---|---|
| Member 1 — Hiển Long | `ci/setup-validation` | CI setup, project structure, integration, and code review |
| Member 2 — Thanh Hùng | `feature/dungeon-generation` | Dungeon generator, seed reproducibility, and unit/property tests |
| Member 3 — Văn Duy | `feature/player-combat` | Player mechanics, combat, enemies, and boss |
| Member 4 — Chí Kiên | `feature/inventory-run-management` | Inventory, UI, seed management, and replay |

**Branch Workflow:**
1. Create a branch from the latest `main` before starting a task.
2. Commit changes regularly using clear commit messages.
3. Push the branch to GitHub and open a Pull Request targeting `main`.
4. Review the changes and verify applicable checks before merging.
5. Update the local `main` after the Pull Request is merged.

**Note:** These branches are initial suggestions. If a task is too large, a member may create smaller branches for individual features or fixes. All members must coordinate changes to shared APIs, signals, and data structures before integration.

### 5.3. Commit Messages

Commit messages should be concise and describe the purpose of the change.

Use the following format:

`type: short description`

Examples:

- `feat: implement seeded dungeon generation`
- `fix: correct boss reachability validation`
- `test: add generator property tests`
- `docs: update module API contracts`
- `ci: validate Godot project in headless mode`

Commits should contain logically related changes. Temporary files, editor caches, generated build artifacts, and unrelated modifications must not be included.

### 5.4. Pull Requests

All changes intended for `main` should be submitted through a pull request.

Each pull request should:

1. Reference the relevant GitHub Issue.
2. Summarize the changes and their purpose.
3. Identify affected modules and shared interfaces.
4. Describe tests performed and their results.
5. Disclose known limitations or remaining work.

At least one other team member should review the pull request before it is merged. Changes to shared interfaces or cross-module behavior should be reviewed by the affected module owners.

The author should address review comments before merging. If the team lead submits a pull request, another member should review it as well.

## 6. Pull Request Review and Merge Requirements

A pull request may be merged when all applicable conditions below are satisfied:

- The implementation matches the issue's acceptance criteria.
- Changes follow the responsibilities and API contracts defined in `architecture.md`.
- Relevant tests have been added or updated and pass locally.
- The reviewer has checked correctness, readability, and error handling.
- No unresolved critical review comments remain.
- Required CI checks pass.
- Changes to shared interfaces are agreed upon and documented.
- Godot scenes, resources, and script references remain valid.

If a required test or CI check is not yet implemented, the pull request must state this limitation and include an appropriate manual verification result. Missing automation must not be reported as a passing automated check.

The team lead coordinates final integration and verifies the stability of `main`.

## 7. Testing and Continuous Integration

Testing is performed throughout development rather than postponed until the end of the project.

### 7.1. Local Testing Before Pull Requests

Each member should run the tests relevant to their changes.

| Module | Required Verification |
|---|---|
| Dungeon Generation | Unit tests, multi-seed validity tests, connectivity checks, and determinism tests. |
| Player & Combat | Movement and collision checks, damage and health tests, enemy behavior checks, and defeat handling. |
| Inventory | Add/remove item tests, item-use validation, quantity consistency, and failure handling. |
| Run Management | Seed retention, replay with the original configuration, generation failure handling, and fresh-run behavior. |
| UI & Integration | Seed and health display, inventory interactions, win/loss feedback, and integration with the underlying modules. |

### 7.2. Generator Testing

The generator owner should ensure that:

- The grid dimensions match the configuration.
- Rooms and corridors remain within map boundaries.
- Start and boss positions are valid and walkable.
- The boss is reachable from the starting position.
- Multiple seeds satisfy the dungeon validity requirements.
- Repeated generation with the same seed and configuration produces identical dungeon data.
- Failed generation returns an explicit error rather than invalid data.

Performance benchmarks should use a documented configuration and seed set. The provisional targets in `architecture.md` Section 9 must be measured and reported rather than assumed to have been achieved.

### 7.3. CI Workflow

GitHub Actions should progressively validate the project as the implementation develops.

The planned verification stages are:

1. Check out the repository.
2. Install or configure the agreed Godot version.
3. Validate and import the project in headless mode.
4. Run automated tests that have been implemented and configured.
5. Add build or export verification if required by the project.

The team lead maintains the CI workflow, while module owners are responsible for ensuring their tests can be executed by the shared verification process.

The team must distinguish between existing CI checks and planned checks in project documentation.

## 8. Coding Agent and AI-Generated Code Policy

Team members may use coding agents or AI tools to assist with implementation, testing, debugging, and documentation. However, generated code must be reviewed and verified by the member responsible for the change.

Before submitting AI-assisted work, the author must:

1. Understand the code and be able to explain its purpose and behavior.
2. Check that it follows the project's architecture and API contracts.
3. Review edge cases, error handling, and possible unintended state changes.
4. Run relevant tests and inspect the results.
5. Verify that no unrelated files, credentials, or temporary artifacts have been introduced.
6. Disclose important limitations or unverified behavior in the pull request.

AI-generated tests must be checked to ensure they test meaningful requirements rather than merely reproduce the implementation's assumptions.

The team remains responsible for all code committed to the repository, regardless of how it was produced.

## 9. Bug Reporting and Resolution

Bugs should be recorded as GitHub Issues instead of being tracked only through chat messages.

A bug report should include:

- A concise description of the problem.
- Steps to reproduce it.
- Expected and actual behavior.
- Relevant logs, screenshots, or error messages.
- The Godot version and environment when relevant.
- The seed and generation configuration for dungeon-related bugs.

For reproducible dungeon bugs, the responsible member should preserve the failing seed and add a regression test when practical.

The bug owner should identify the cause, implement a fix on a separate branch, run the relevant tests, and submit a pull request linked to the issue.

Critical bugs that prevent the project from running or invalidate core dungeon generation should receive priority over nonessential features.

## 10. Requirement Changes and Architecture Changes

Changes to requirements or implementation plans must be recorded in GitHub Issues and discussed with affected team members.

For a change that affects shared APIs, module boundaries, seed reproducibility, replay behavior, or testing requirements, the team should:

1. Describe the reason for the change.
2. Identify affected modules and existing tests.
3. Agree on the revised behavior and interface.
4. Update `architecture.md` or other relevant documentation.
5. Update dependent implementations and tests.
6. Verify the integrated result before closing the issue.

The team should avoid introducing incompatible changes without notifying members who depend on the affected interface.

## 11. Merge Conflicts and Integration Failures

When a merge conflict occurs, the involved members should coordinate to preserve the intended behavior of both changes.

The responsible member should:

1. Update their branch with the latest relevant changes from `main`.
2. Resolve conflicts carefully rather than blindly accepting one side.
3. Review the final diff for accidental deletions or duplicated logic.
4. Run project validation and relevant tests.
5. Request additional review if the conflict affects shared APIs, scenes, resources, or gameplay behavior.

Conflicts involving shared module contracts should be resolved with the affected module owners and the team lead.

If an integration change breaks `main`, the team should prioritize restoring a working state, identify the cause, and add regression coverage where appropriate.

## 12. Communication and Definition of Done

Members should communicate blockers, interface changes, and integration risks as early as possible through the relevant GitHub Issue or the team's agreed communication channel.

A task is considered **Done** when:

- Its acceptance criteria are satisfied.
- The implementation follows the agreed architecture and interfaces.
- Relevant tests have passed, or any verification limitation is explicitly documented.
- The pull request has been reviewed and merged.
- Required documentation has been updated.
- The change does not introduce known unresolved critical defects.

A feature must not be considered complete solely because its code has been written. It must also be verified and integrated with the rest of the project.