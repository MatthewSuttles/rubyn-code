# Phase 2 — Chisel Inspection: Requirements

## Overview

Two commands that turn Chisel's philosophy into an on-demand audit: `/chisel-review`
inspects the current git diff for over-engineering, and `/chisel-audit` sweeps the
whole repo (or a path). Both apply the same decision-ladder criteria and return a
ranked deletion/simplification list. They are read-only — they report, they don't
edit. They work regardless of whether Chisel mode is on (an explicit command is its
own opt-in).

## Glossary

- **Over-engineering** — code that skips a rung of the decision ladder: speculative
  abstractions with one caller, reinvented stdlib/gem functionality, needless
  indirection or configurability, dead parameters, premature generalization.
- **Deletion list** — the command's output: ranked items, each with a location, what
  it is, which rung it skipped, and the concrete simpler form.
- **Detector** — the shared instruction set (`Chisel::Inspection`) both commands feed
  to the agent so review and audit judge by identical criteria.

## Requirements

### Requirement 1: `/chisel-review`

**User story:** As a developer about to open a PR, I want Chisel to flag
over-engineering in my changes, so that I can cut it before review.

**Acceptance criteria:**

1. The command SHALL analyze the git diff of the current branch against a base
   (default `main`), including uncommitted changes.
2. When invoked with an argument, the command SHALL treat it as the base ref.
3. The command SHALL instruct the agent to return a ranked deletion/simplification
   list, each item citing a location, the violated rung, and the simpler form.
4. The command SHALL be read-only: it SHALL instruct the agent to report, not edit.

### Requirement 2: `/chisel-audit`

**User story:** As a developer inheriting a codebase, I want Chisel to find
accumulated over-engineering across the repo, so that I know what to simplify.

**Acceptance criteria:**

1. The command SHALL sweep the repository for over-engineering.
2. When invoked with an argument, the command SHALL scope the sweep to that path.
3. The command SHALL return the same shape of ranked deletion list as review.
4. The command SHALL be read-only.

### Requirement 3: Shared criteria + safety floor

**User story:** As a user, I want review and audit to judge by the same rules Chisel
uses everywhere, so that guidance is consistent.

**Acceptance criteria:**

1. Both commands SHALL derive their criteria from the same `Chisel` decision ladder.
2. Both commands SHALL exclude the safety floor (validation, error/data-loss
   handling, security, accessibility) from what they flag.

## Out of scope

- Auto-applying the deletions (the commands report only)
- The `chisel:` debt ledger and `/chisel-gain` metrics (Phase 3)
- A non-LLM static analyzer — detection is delegated to the agent + its tools
