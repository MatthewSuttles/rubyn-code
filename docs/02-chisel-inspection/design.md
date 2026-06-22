# Phase 2 — Chisel Inspection: Design

## Overview

Two thin slash commands (`/chisel-review`, `/chisel-audit`) that build a prompt and
hand it to the agent via `ctx.send_message`, exactly like the existing `/review` and
`/megaplan` commands. The over-engineering criteria live once in
`Chisel::Inspection`; each command supplies only its scope. No Ruby-side analysis —
the agent already has `git_diff`, `bash`, `grep`, and `read_file`.

**Design principles:** vertical slice (command → shared detector → agent, runnable
end-to-end), SRP (`Inspection` owns the analysis prompt; commands own argument
parsing + dispatch), KISS (delegate detection to the agent rather than building a
static analyzer), DRY (one ladder, one safety floor, two scopes).

## Architecture

### `RubynCode::Chisel::Inspection` (new — `lib/rubyn_code/chisel/inspection.rb`)

```ruby
Inspection.prompt(scope:, target: nil)
# scope: :diff -> review against a base ref (target = base, default "main")
# scope: :repo -> sweep the repo  (target = path, default whole repo)
# -> String, the full instruction the command sends to the agent
```

**Responsibility:** produce the over-engineering audit instruction — shared criteria
(the decision ladder, reused from `Chisel::LADDER`), the deletion-list output
contract, and the safety-floor exclusion — parameterized by scope and target.
**Collaborators:** reads `Chisel::LADDER` and `Chisel::SAFETY_FLOOR` so the audit
judges by the same rules the always-on ruleset injects.
**Why a separate module, not inline in the commands?** Two commands need byte-identical
criteria; centralizing prevents review and audit from drifting apart. It also keeps
the always-on `Chisel` module (modes + injection) uncluttered by analysis text.

`prompt` assembles, in order: a scope-specific lead-in (what to look at and how to
gather it), the ladder as the judging rubric, the list of over-engineering smells,
the output contract (ranked list; per item: `file:line`, what it is, which rung it
skipped, the simpler form), and the read-only + safety-floor guardrails.

### Commands (`lib/rubyn_code/cli/commands/chisel_review.rb`, `chisel_audit.rb`)

```ruby
class ChiselReview < Base
  def self.command_name = '/chisel-review'
  def execute(args, ctx)
    ctx.send_message(Chisel::Inspection.prompt(scope: :diff, target: args.first || 'main'))
  end
end

class ChiselAudit < Base
  def self.command_name = '/chisel-audit'
  def execute(args, ctx)
    ctx.send_message(Chisel::Inspection.prompt(scope: :repo, target: args.first))
  end
end
```

Both registered in `repl_commands.rb` and autoloaded in `lib/rubyn_code.rb`. They mirror
`Review`'s shape: parse a positional arg, build a prompt, `send_message`. Naming: the
command classes are `ChiselReview`/`ChiselAudit` (distinct from the `Chisel` toggle
command and the `RubynCode::Chisel` engine module).

## Test strategy

- **Unit (`spec/.../chisel/inspection_spec.rb`):** `prompt(scope: :diff, target: 'develop')`
  mentions the diff/base and the ladder; `prompt(scope: :repo, target: 'app/')`
  mentions the path; both include the deletion-list contract, the read-only guard, and
  the safety-floor exclusion; an unknown scope raises `ArgumentError`.
- **Unit (`spec/.../cli/commands/chisel_review_spec.rb`, `chisel_audit_spec.rb`):** each
  command calls `ctx.send_message` once with a prompt that reflects its scope; the
  optional arg is threaded through (review → base ref; audit → path). Use an
  `instance_double` ctx capturing `send_message`, mirroring how other command specs work.

No new prompt-injection paths, so no system-prompt spec changes.

## Migration / rollout

Pure addition — two new commands. Nothing changes unless a user runs them. Rollback =
revert the PR.

## Future enhancements

- A `--fix` flag that lets the agent apply the cuts (deferred; report-only for now).
- Feed confirmed deferrals into the Phase 3 `chisel:` ledger.
