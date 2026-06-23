# Phase 3 — Chisel Ledger & Gain: Design

## Overview

One new module (`Chisel::Debt`) does the mechanical scan for `chisel:` markers;
two thin commands render its output. Unlike Phase 2's inspection (which delegates
judgment to the agent), harvesting markers is a deterministic grep — stdlib does
it, so no LLM round-trip. That's Chisel's own ladder applied to Chisel.

**Design principles:** KISS (a regex over source files, not an agent call), SRP
(`Debt` scans; commands render), DRY (`/chisel-gain` reuses `Debt.scan` and
`Chisel.mode` rather than recomputing).

## Architecture

### `RubynCode::Chisel::Debt` (new — `lib/rubyn_code/chisel/debt.rb`)

```ruby
Debt::Item = Data.define(:file, :line, :note)
Debt.scan(root) -> Array<Item>   # [] when root is nil/missing
```

**Responsibility:** find `chisel:` comment markers under a project root and return
them as structured items (relative path, 1-based line, note text).
**Collaborators:** the filesystem only.
**Why a module, not inline in the command?** Both commands consume the scan
(`/chisel-debt` lists it, `/chisel-gain` counts it); centralizing the marker
format and the scan in one place keeps them consistent.

Details:
- Marker regex: `/(?:#|\/\/)\s*chisel:\s*(\S.*)/i` — a `#` or `//` comment leader,
  then `chisel:`, then the note. (The leader + whitespace-only gap means this
  module's own regex literal doesn't match itself.)
- Scans source extensions only: `.rb .rake .erb .ru .gemspec`.
- Skips `.git node_modules vendor coverage tmp log`.
- `File.foreach` with a per-file `rescue` so an unreadable file is skipped, never
  fatal.

### Commands

```ruby
class ChiselDebt < Base   # /chisel-debt
  def execute(_args, ctx)
    items = Chisel::Debt.scan(ctx.project_root)
    # empty -> "clean" message; else "file:line — note" per item
  end
end

class ChiselGain < Base   # /chisel-gain
  def execute(_args, ctx)
    # Chisel.mode + Debt.scan(...).size + attributed reference figure + hint
  end
end
```

Both registered in `repl_commands.rb` and autoloaded. They use `ctx.renderer.info`
and `ctx.project_root` (already on the Context Data type). `/chisel-gain` cites the
reference benchmark with attribution rather than inventing per-user numbers.

## Test strategy

- **Unit (`spec/.../chisel/debt_spec.rb`):** scanning a tmp dir finds markers with
  correct file/line/note; ignores non-marker comments and skipped dirs; tolerates
  an unreadable file; returns `[]` for a nil/missing root.
- **Unit (command specs):** `/chisel-debt` renders the ledger or the clean message;
  `/chisel-gain` renders mode + debt count + reference line. Use a tmp `project_root`
  with a seeded marker and an `instance_double` renderer capturing `info`.

## Migration / rollout

Pure addition — two commands + one module. Inert until invoked. Rollback = revert.

## Future enhancements

- Persist the ledger to `.rubyn-code/chisel-debt.md`.
- A `--resolve` flow to strip a marker once paid down.
- Real savings instrumentation feeding `/chisel-gain`.
