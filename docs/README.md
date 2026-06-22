# Chisel — Roadmap

Top-level tracker for the Chisel feature: an opt-in "write the minimum that
works" enforcement layer for rubyn-code, ported in spirit from the open-source
`ponytail` plugin but rebuilt natively and renamed.

Chisel is **off by default**. It only changes the agent's behavior once a user
turns it on (`/chisel full`). The off-by-default mode flag doubles as the
feature flag, so every phase ships safely with zero impact on existing behavior.

Check the box when a phase is fully merged.

## Phases

- [ ] **[Phase 1 — Chisel Core](01-chisel-core/)** — opt-in `chisel.mode` flag, the decision-ladder ruleset at lite/full/ultra, the `/chisel` toggle command, and ruleset injection into the agent's system prompt when enabled.
- [ ] **Phase 2 — Chisel Inspection** — `/chisel-review` (over-engineering in the git diff) and `/chisel-audit` (whole repo), sharing one detector that returns a ranked deletion list.
- [ ] **Phase 3 — Chisel Ledger & Gain** — inline `chisel:` deferral markers harvested via `/chisel-debt`, and `/chisel-gain` savings stats.

## Conventions

- One folder per phase, numbered: `docs/NN-slug/`
- Three files per phase: `requirements.md`, `design.md`, `tasks.md`
- `[ ]` / `[x]` checkboxes track progress at section and task level
- When a phase ships, check the box here and check `## [x]` on every section of its `tasks.md`
- Branch per phase: `phase-NN-slug`, one PR per branch, squash-merged
