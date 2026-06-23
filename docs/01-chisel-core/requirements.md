# Phase 1 — Chisel Core: Requirements

## Overview

Chisel Core ships the foundation of the "write the minimum that works" feature:
a persisted intensity setting, the decision-ladder ruleset text at three
intensities, a `/chisel` command to set/report intensity, and injection of the
ruleset into the agent's system prompt on every turn — but only when the user
has turned it on. With `chisel.mode = off` (the default), nothing changes.

## Glossary

- **Mode / intensity** — one of `off`, `lite`, `full`, `ultra`. Controls whether
  Chisel injects guidance and how aggressive that guidance is.
- **Decision ladder** — the ordered set of questions the agent asks before
  writing code (does this need to exist? → stdlib? → framework? → installed gem?
  → one line? → minimum that works).
- **Safety floor** — the categories Chisel must never tell the agent to cut:
  trust-boundary/input validation, error & data-loss handling, security,
  accessibility.

## Requirements

### Requirement 1: Persisted opt-in mode

**User story:** As a rubyn-code user, I want Chisel off until I turn it on, so
that my agent's behavior never changes without my action.

**Acceptance criteria:**

1. The system SHALL default `chisel.mode` to `off` when no config value is set.
2. The system SHALL persist a user-set mode to `~/.rubyn-code/config.yml` so it
   survives across sessions.
3. The system SHALL accept exactly the modes `off`, `lite`, `full`, `ultra`.
4. When an unknown mode value is present in config or the environment, the system
   SHALL treat Chisel as `off` rather than raising.
5. The system SHALL let the `RUBYN_CHISEL_MODE` environment variable override the
   persisted mode for the current process.

### Requirement 2: `/chisel` command

**User story:** As a user, I want a slash command to set and check the Chisel
intensity, so that I can control it without editing config files.

**Acceptance criteria:**

1. When invoked with no argument, the command SHALL report the current mode and
   list the available modes.
2. When invoked with a valid mode, the command SHALL persist it and confirm the
   change.
3. If invoked with an invalid argument, the command SHALL warn and leave the
   current mode unchanged.

### Requirement 3: Ruleset injection

**User story:** As a user who turned Chisel on, I want its guidance to actually
reach the agent, so that the agent writes less code.

**Acceptance criteria:**

1. When mode is not `off`, the system SHALL include the Chisel ruleset in the
   agent's system prompt.
2. When mode is `off`, the system SHALL add nothing to the system prompt (no
   header, no whitespace section).
3. The injected ruleset SHALL always include the safety floor, regardless of
   intensity.
4. The injected ruleset SHALL scale: `ultra` includes everything `full` does,
   and `full` includes everything `lite` does.

## Out of scope

- `/chisel-review` and `/chisel-audit` (Phase 2)
- `/chisel-debt` ledger and `/chisel-gain` metrics (Phase 3)
- Per-project (vs. global) mode overrides — global only for now
