# Phase 3 — Chisel Ledger & Gain: Requirements

## Overview

Two small reporting commands that close out the Chisel feature. `/chisel-debt`
harvests inline `chisel:` deferral markers from the codebase into a ledger view,
so simplifications you consciously postponed don't get lost. `/chisel-gain`
reports Chisel's current status and impact. Both are read-only and work whether
or not the always-on mode is enabled.

## Glossary

- **Debt marker** — an inline code comment of the form `# chisel: <note>` left
  when a simplification is deliberately deferred (e.g. "collapse this adapter
  once a second caller exists").
- **Ledger** — the collected list of debt markers (file, line, note).

## Requirements

### Requirement 1: `/chisel-debt`

**User story:** As a developer who deferred simplifications with `chisel:` notes,
I want to list them all in one place, so that I can come back and pay them down.

**Acceptance criteria:**

1. The command SHALL scan the project's source files for `chisel:` markers in
   code comments.
2. For each marker, the ledger SHALL show the file, line number, and note text.
3. When no markers exist, the command SHALL say so plainly rather than showing an
   empty list.
4. The scan SHALL skip non-source directories (`.git`, `node_modules`, `vendor`,
   `coverage`, `tmp`, `log`).
5. The scan SHALL never raise on an unreadable file — it skips it.

### Requirement 2: `/chisel-gain`

**User story:** As a user, I want a quick read on Chisel's status and what it's
for, so that I know whether it's on and what it buys me.

**Acceptance criteria:**

1. The command SHALL report the current Chisel mode.
2. The command SHALL report the count of outstanding `chisel:` debt markers.
3. The command SHALL show a clearly-attributed reference impact figure (not
   fabricated per-user metrics, which aren't instrumented).
4. When mode is `off`, the command SHALL hint how to enable it.

## Out of scope

- Writing the ledger to a file (render to screen only for now)
- Auto-resolving or removing markers
- Real per-user savings instrumentation (would require tracking generated vs.
  baseline code over time)
