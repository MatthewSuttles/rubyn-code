---
name: megaplan
description: Phased project planning. Interview the user one question at a time, then scaffold numbered phase folders (requirements/design/tasks). Trigger phrases include "megaplan", "mega plan", "plan phases", "phase this out", or any feature spanning 3+ PRs.
tags:
  - planning
  - process
  - phases
  - megaplan
triggers:
  - megaplan
  - mega plan
  - plan phases
  - phase this out
---

# Megaplan — Phased Project Planning

Ship in vertical slices. Each phase merges cleanly and leaves the trunk working.

## Don't use for

- Single-PR features — just do them
- Pure research / exploration — nothing shippable
- Work where the *shape* (not just the details) will change weekly — plan something smaller first

## Design principles to apply throughout

Hold the work to these when proposing phases and reviewing each `design.md`:

- **Vertical slices, not horizontal.** A phase touches every layer it needs to be end-to-end testable. The classic anti-pattern this skill exists to prevent: "Phase 1: all models. Phase 2: all controllers. Phase 3: all views." Trunk is unshippable until Phase 3 and Phase 2 has nothing to test. Instead: "Phase 1: one feature, full-stack, behind a flag."
- **SOLID, applied lightly.** Single Responsibility and Dependency Inversion are the two that actually bite at the phase-design level. The others usually take care of themselves if those two are clean.
- **KISS.** Skip the abstraction until you have two concrete callers. Three similar lines beat a premature framework. Inline before you extract.
- **Justify abstractions.** Every new module/service/class in `design.md` needs a one-sentence reason it exists separately. If you can't write it, inline the code.

## The workflow

### 1. Interview first

Don't propose phases until you understand the shape. Walk through the agenda below **one question per turn** — never dump the full list in a single message. The point is to let the operator steer at every step.

**How to ask:**

- **One topic per turn.** Pick the next unanswered item from the agenda. Ask only about that.
- **Number the options.** Whenever the question has 2+ plausible answers, present them as a numbered list so the operator can reply with just the number. Include a **recommended** pick (the one you'd default to given what you know so far) and say *why* it's the recommendation in one short line.
- **Restate locked-in answers at the top of each follow-up.** A running "Decisions so far:" block of one-line bullets, so the operator can spot drift and you can spot contradictions.
- **Open-ended questions are fine** when no obvious option set exists (e.g. "What's the end-state in user-facing terms?"). Still ask one at a time.
- **Stop when you're 95% sure of the shape.** Don't run the whole agenda for its own sake — skip topics that are already obvious from context. The agenda is a checklist *for you*, not a script to read aloud.

**Agenda (interviewer's checklist, not a dump):**

- **Goal** — end state in user-facing terms
- **Constraints** — deadlines, infra limits, things you can't break
- **Existing assets** — what's there to build on or rip out
- **Natural ordering** — dependency sequence (data → API → UI)?
- **External dependencies** — other teams, third-party APIs, infra access, design review. These reorder phases more than technical concerns do.
- **Destructive operations** — schema drops, data deletes, deprecations. These need their own phase with an explicit rollback note.
- **Test strategy** — what coverage is needed?
- **Done-per-phase** — minimum manual test that proves each phase shipped?

### 2. Propose phases, get agreement

A good phase:
- Is a vertical slice — testable end-to-end at merge time
- Ships independently — trunk works at every boundary
- Has a clear definition of done
- Is roughly 1–3 days of focused work
- Has a name that survives the PR title. If it adds *and* removes, capture both (e.g. "TX-Only Checkout + Geofencing Removal").

A good phase list:
- 3–8 phases for most projects
- Ordered by dependency, not priority
- Destructive operations isolated to their own phase
- Ends with a phase that visibly delivers the goal

Propose as a numbered outline. Let the user reorder, merge, or split before any files exist.

### 3. Scaffold the structure

```
docs/
  README.md                # roadmap tracker
  NN-slug/
    requirements.md        # user stories + acceptance criteria
    design.md              # architecture + interfaces + test strategy
    tasks.md               # numbered checklist
```

Numbering: zero-padded (`01-`, `02-`). Slugs: kebab-case, ≤4 words.

Default: fully scaffold the *current* phase; future phases stay as one-liners in `README.md` until you start them. Later phases mutate based on what's learned early — don't pre-write what you'll have to rewrite.

### 4. Implement phase-by-phase

For each phase:
1. **Read the running architecture doc first** (`CLAUDE.md` or equivalent). That's how you don't repeat decisions or miss constraints from earlier phases.
2. Branch off main: `git checkout -b phase-NN-slug`
3. Work `tasks.md` top-to-bottom, checking subtasks as you go
4. Commit at section boundaries: `Phase N (M/X): description` — where `M` is the current section number and `X` is the total number of sections in `tasks.md`
5. Run full test suite + lint + format at each commit boundary
6. When `tasks.md` is fully checked, push and open a PR (see PR description shape below)
7. After merge: check the box in `docs/README.md`, update the running architecture doc if anything moved

## File templates

### requirements.md

Use RFC 2119 SHALL/SHOULD/MAY language for acceptance criteria. They're contracts — write them as something a QA tester could check.

Sections: Overview, Glossary, Requirements (per requirement: user story + numbered SHALL criteria), Out of scope.

### design.md

Sections: Overview, Architecture (each component gets Responsibility, Collaborators, "Why not inline?"), Data model changes, Test strategy, Migration / rollout, Future enhancements.

Every new abstraction needs a justification line. If you can't answer "why not inline this", inline it.

### tasks.md

Sections (`## [ ] N. <name>`) and tasks (`- [ ] N.M ...`) both get checkboxes. A section ticks only when every task under it ticks. Reference requirements by ID (`refs Req 1.1`) so coverage gaps are visible. Always end with a Validation section that includes the manual smoke flow.

## PR description shape

Three bullets. Don't pad them.

```
## What shipped
- <user-facing capability or removal>

## What proves it
- <new tests, smoke flow, manual check>

## What's deferred
- <link to later phase, or "none">
```

## Patterns and pitfalls

**Patterns to keep:**
- **Branch per phase:** `phase-NN-slug` — disposable, one PR per branch
- **Squash-merge:** one phase = one commit on main, full PR description preserved
- **Plan before code:** `requirements.md` is finalized and `design.md` is sketched before any task in `tasks.md` gets implemented.
- **Semantic test anchors** so later phases don't break earlier tests
- **One running architecture doc** kept current — read it before each phase, update it after

**When to break the rules:**
- **Phase grew mid-stream?** Split it. Add `NN-a-slug` / `NN-b-slug` or renumber.
- **Later phase invalidates an earlier requirement?** Update the earlier doc with a "Superseded by Phase N" note.
- **Phase ships nothing user-visible** (e.g. refactor prep)? Still its own PR — but say so in the description.

**Pitfalls to avoid:**
- **Horizontal-slice phases** (all models / all controllers / all views). Trunk is unshippable until the last phase merges.
- **Scaffolding all phases upfront in full detail** — later phases get invalidated by what you learn early.
- **Phases longer than ~3 days** — the phase should split. Long phases hide scope creep.
- **Requirements without acceptance criteria** — "Make X work" isn't a requirement; "When <condition>, the system SHALL <observable behavior>" is.
- **Tasks that don't reference requirements** — if you can't cite which requirement a task serves, the task probably isn't load-bearing.
- **Destructive operations mixed with feature work** — schema drops, deletes, deprecations belong in their own phase with a rollback note.
