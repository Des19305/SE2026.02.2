## Reading Guide: Focus on Your Assigned Responsibilities

The `architecture.md` and `workflow.md` documents describe different aspects of the project:

- **`architecture.md`** defines the technical design, module responsibilities, shared APIs, seed reproducibility, replay behavior, and testing requirements.
- **`workflow.md`** defines how the team organizes tasks, creates branches, tests changes, reviews pull requests, and integrates code.

Each team member should prioritize the sections related to their assigned responsibilities. Read the required sections before implementation, and refer to the supporting sections whenever needed. You do not need to study every technical detail of another member's module unless your work depends on it.

### 1. Member 1 — Nguyễn Trọng Hiển Long
**Role: Team Lead & Integration**

**Primary focus:** Project structure, development workflow, CI, shared interfaces, integration, and code quality.

**Read in `architecture.md`:**
- **Section 1 — Overview:** Understand the overall project goal.
- **Section 2 — Technology Stack:** Confirm the required tools, Godot version, testing approach, and resource-management rules.
- **Section 3 — High-Level Architecture:** Understand how the main modules fit together.
- **Section 4.1 — Main:** Understand the responsibilities of the main game coordinator.
- **Section 4.8 — UI:** Understand the UI's role in the overall game flow.
- **Section 7.1 — General Conventions:** Understand the rules for shared APIs, data structures, error handling, and signals.
- **Section 7.6 — UI and Main Game Integration:** Understand how the major modules interact.
- **Section 7.7 — API Verification and Change Control:** Coordinate interface changes and verify integration.
- **Sections 8–9 — Testing Strategy and Performance Targets:** Understand project-wide verification and performance reporting.
- **Section 10 — Architecture Principles:** Apply the common architectural rules.

**Read in `workflow.md`:**
- **Section 2 — Team Responsibilities and Branch Strategy**
- **Sections 3–6 — Iteration Planning, Issues, Branching, Pull Requests, and Merge Requirements**
- **Section 7.3 — CI Workflow**
- **Sections 8–12 — AI-Assisted Code, Bug Resolution, Requirement Changes, Integration Failures, and Definition of Done**

**Expected outcome:** Maintain a clear backlog, establish the shared development process, keep CI checks accurate, coordinate API agreements, and help the team integrate modules without breaking the `main` branch.

### 2. Member 2 — Nguyễn Thanh Hùng
**Role: Dungeon Generation**

**Primary focus:** BSP generation, seeded randomness, dungeon validity, reproducibility, and generator testing.

**Read in `architecture.md`:**
- **Section 2.1 — Development Environment:** Use the agreed Godot version.
- **Section 2.2 — Deterministic Dungeon Generation:** Understand controlled randomness.
- **Section 3 — High-Level Architecture:** Understand the generator's place in the game.
- **Section 4.2 — Generation:** Understand the generator's responsibilities.
- **Section 5 — Dungeon Generation:** Study the proposed BSP algorithm, initial configuration, validity requirements, determinism, and failure handling.
- **Section 6 — Seed and Replay Design:** Understand configuration consistency and reproducible generation.
- **Sections 7.1–7.2 — General Conventions and Dungeon Generation API:** Follow the agreed function signatures and data structures.
- **Section 8 — Dungeon Validity and Testing Strategy:** Implement unit, property, determinism, and relevant integration tests.
- **Section 9 — Initial Performance Targets:** Understand how to benchmark and report actual performance.
- **Section 10 — Architecture Principles:** Follow the shared design principles.

**Read in `workflow.md`:**
- **Section 2 — Team Responsibilities and Branch Strategy**
- **Sections 3–6 — Iterations, Issues, Branching, Pull Requests, and Merge Requirements**
- **Sections 7.1–7.3 — Local Testing, Generator Testing, and CI Workflow**
- **Section 9 — Bug Reporting and Resolution**
- **Sections 10–11 — Requirement Changes and Integration Failures**

**Expected outcome:** Produce valid dungeon data, ensure that the same seed and configuration reproduce the same layout, report generation failures explicitly, and provide meaningful tests and benchmark results.

### 3. Member 3 — Trần Văn Duy
**Role: Player & Combat**

**Primary focus:** Player movement, collision, health, attacks, damage handling, enemies, boss behavior, and win/loss conditions.

**Read in `architecture.md`:**
- **Sections 2.1 and 3 — Development Environment and High-Level Architecture:** Understand the technical environment and module boundaries.
- **Sections 4.3–4.5 — Player, Combat, and Enemies:** Study your module responsibilities.
- **Section 7.1 — General Conventions:** Understand the shared interface and error-handling rules.
- **Section 7.4 — Combat, Player, and Enemy APIs:** Follow the agreed attack and damage functions, return values, and signals.
- **Sections 7.6–7.7 — UI and Main Game Integration, API Verification and Change Control:** Understand how combat outcomes connect to the game flow and other modules.
- **Section 8 — Dungeon Validity and Testing Strategy:** Understand the dungeon assumptions your gameplay code relies on, especially valid player and boss positions.
- **Section 10 — Architecture Principles:** Follow the shared design principles.

**Read in `workflow.md`:**
- **Section 2 — Team Responsibilities and Branch Strategy**
- **Sections 3–6 — Iterations, Issues, Branching, Pull Requests, and Merge Requirements**
- **Section 7.1 — Local Testing Before Pull Requests**
- **Section 8 — Coding Agent and AI-Generated Code Policy**
- **Sections 9–11 — Bug Resolution, Requirement Changes, and Integration Failures**

**Expected outcome:** Implement player and enemy behavior consistently, handle health and defeat states correctly, test gameplay edge cases, and communicate changes to shared signals or combat interfaces before integration.

### 4. Member 4 — Đặng Chí Kiên
**Role: Inventory, UI & Run Management**

**Primary focus:** Item management, item usage, HUD, seed display, run status, and replay functionality.

**Read in `architecture.md`:**
- **Sections 2.1 and 3 — Development Environment and High-Level Architecture:** Understand the technical environment and module boundaries.
- **Sections 4.6–4.8 — Inventory, Run Management, and UI:** Study your module responsibilities.
- **Section 6 — Seed and Replay Design:** Understand what must be retained for replay and what replay does not restore.
- **Section 7.1 — General Conventions:** Understand shared APIs, return structures, and signals.
- **Section 7.3 — Run Management API:** Follow the run initialization, replay, and run-completion contracts.
- **Section 7.5 — Inventory API:** Follow the item-management functions, return values, and signals.
- **Sections 7.6–7.7 — UI and Main Game Integration, API Verification and Change Control:** Understand how the UI interacts with the underlying modules.
- **Section 8 — Dungeon Validity and Testing Strategy:** Understand the validity and determinism requirements that affect replay.
- **Section 10 — Architecture Principles:** Follow the shared design principles.

**Read in `workflow.md`:**
- **Section 2 — Team Responsibilities and Branch Strategy**
- **Sections 3–6 — Iterations, Issues, Branching, Pull Requests, and Merge Requirements**
- **Section 7.1 — Local Testing Before Pull Requests**
- **Section 8 — Coding Agent and AI-Generated Code Policy**
- **Sections 9–11 — Bug Resolution, Requirement Changes, and Integration Failures**

**Expected outcome:** Keep inventory operations consistent, display the correct game state, retain the original seed and generation configuration, and ensure replay starts a fresh run with the same dungeon layout.

### 5. Shared Reading Requirements

Regardless of your assigned module, every team member must understand the following:

- **`architecture.md` Section 1:** The project goal and the importance of reproducible dungeon generation.
- **`architecture.md` Section 2.1:** The agreed development environment and Godot version.
- **`architecture.md` Section 3:** The high-level module structure.
- **`architecture.md` Section 7.1:** Shared API conventions, data structures, and error handling.
- **`architecture.md` Section 7.7:** The process for coordinating and changing shared interfaces.
- **`architecture.md` Section 10:** The project's architecture principles.
- **`workflow.md` Sections 2, 3, 5, 6, 8, and 12:** Team responsibilities, iteration planning, branching, pull-request requirements, AI-assisted code review, and the Definition of Done.

### 6. How to Use This Guide

1. Read the sections marked for your role before implementing your assigned module.
2. Check the relevant API contract in `architecture.md` before defining a public function, return structure, or signal.
3. Refer to the relevant testing requirements before considering a task complete.
4. Read other modules' sections when your implementation depends on their APIs or behavior.
5. Coordinate with the affected module owners before changing shared interfaces.
6. Follow the same Git, pull-request, testing, and review workflow for all changes.

This guide prioritizes reading; it does not replace either document. The full documents remain the source of truth for project architecture and team workflow.