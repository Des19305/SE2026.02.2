# Workflow — Team Collaboration and Development Process

## 1. Purpose

This document defines the lightweight collaboration and development workflow for the four-member GAME-2D-02 team. Keep it simple and actionable: how we create work, how we review and merge it, and how we treat CI, tests, and documentation.

## 2. Team Roles and Responsibilities

The team has four members. These roles are suggestions that preserve the four-person team structure; assign names inside the team repository or an issue if you prefer:

- Team Lead / Integrator
  - Maintain the backlog, coordinate releases, merge PRs after review, and keep the CI and project health visible.
  - Ensure project decisions are recorded in issues or docs.

- Generator & Tests Engineer
  - Implement and maintain the dungeon generator, determinism and validation tests, and generation benchmarks.
  - Own the generation API contract and determinism test suite.

- Gameplay Engineer
  - Implement player movement, combat, enemies, and boss behavior.
  - Own gameplay integration with run management and the combat API.

- UI & QA Engineer
  - Implement the UI for seed display, HUD, and end screens; coordinate playtests and bug reproduction reporting.
  - Own run replay UX and documentation for reproducing bugs with seeds.

Note: these role names are guidance only. The team must not add members beyond the existing four.

## 3. Issue and Task Workflow

- Create small, focused GitHub Issues that describe one change, bug, or feature.
- Each Issue is tagged with a priority and an estimate (relative or t-shirt).
- Assign Issues to a single owner for implementation.
- Link PRs to their Issue using the issue number in the PR description (e.g., "Fixes #42").

## 4. Branching and Naming Conventions

- Branch from the default branch (do not assume its name). Create short-lived feature branches.
- Branch name examples:
  - feature/generation-bsp
  - fix/retry-limit
  - chore/update-docs
  - hotfix/ci-import

## 5. Commit Messages

Use a conventional-style short summary that includes a type and optional scope:

- feat(generation): add BSP partitioning core
- fix(combat): prevent negative health
- docs(workflow): consolidate docs
- test(generator): add determinism unit test

Keep the body short and reference issues when relevant.

## 6. Pull Request Requirements

Before merging a PR into the default branch, ensure:

- The PR description links the related Issue and summarizes the change.
- The PR has at least one approving review from a team member who is not the author.
- CI passes the checks that are configured (see Section 8); if CI is not yet configured for the change type, the PR description must document manual verification steps.
- Changes to public module APIs or signals include an API note in the PR description and a short update to docs/architecture.md if required.
- If any AI/coding agent was used to generate code, list the portions created and the prompts used in the PR description and ensure manual review and tests cover generated code.

## 7. Code Review and Merge Rules

- At least one non-author reviewer must approve the change.
- The Team Lead or Integrator may merge after approval and passing CI checks.
- Prefer small, focused PRs to simplify review and reduce merge conflicts.

## 8. CI, Tests, and Quality Gates

Current CI: .github/workflows/ci.yml imports and validates the Godot project using Godot 4.7.2 in a headless environment. It does not currently run unit or property tests or benchmarks.

Planned CI checks (to be implemented incrementally):
- Unit tests (generator and core gameplay logic).
- Property/determinism tests for generation across multiple seeds.
- Benchmark job to measure generation performance (optional as a nightly or manual workflow).
- Linting or static checks where applicable.

Mark which checks are implemented in the PR description. Do not claim a check is passing unless the workflow is present and has executed.

## 9. Definition of Done (DoD)

A task is done when:
- The related Issue is updated and linked in the PR.
- Code compiles and runs in headless project import (CI step).
- Unit tests that cover the change are added or updated where applicable.
- Changes are reviewed and have at least one approval.
- Docs/architecture.md and docs/requirements.md are updated for any API or requirement changes.
- The PR is merged into the default branch by the Integrator.

## 10. Handling Merge Conflicts and Integration

- Rebase feature branches onto the current default branch before merging to reduce conflicts.
- Run the headless project import locally after rebasing to detect broken resource references.
- If merge conflicts affect Godot scene files, open the scenes in the Godot editor to resolve reference inconsistencies.

## 11. Bug Reporting and Regression Testing

- When reporting a reproducible bug tied to a dungeon, include the seed, generation configuration, and reproduction steps in the GitHub Issue.
- Add regression tests when a bug fix is merged that could reoccur (especially generation determinism bugs).

## 12. Responsible Use of AI and Coding Agents

- AI-generated code is allowed as a tool only; all generated code must be clearly documented in the PR and manually reviewed and tested.
- Do not rely on agents for security-sensitive logic or to replace design decisions without a human review.

## 13. Requirement and Architecture Changes

- Significant requirement or architecture changes must be proposed as Issues and discussed by the team.
- Update docs/architecture.md and docs/requirements.md after agreement, and reference the decision in the Issue.

## 14. Minimal Release and Tagging

- For milestone releases, tag the default branch with a semantic version (e.g., v0.1.0).
- Record what changed and which issues were closed in the release notes.

---

Document status: Consolidated workflow for a four-person student team. Update role names and assignments in the repository or an Issue as needed.