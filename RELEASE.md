# Rubyn Code v0.8.0 — Claude 5

**The Claude 5 family is now the default.**

This release moves Rubyn onto Anthropic's Claude 5 generation: **Claude Opus 5 is the default model**, the model router's tiers are Haiku 4.5 / Sonnet 5 / Opus 5, and Claude Fable 5 joins the catalog with first-class handling for its refusal stop reason and server-side fallbacks. Around the model work ships a built-in **codegraph** (a Prism-powered call graph exposed as a default tool), the `/effort` and `/think` controls for the new API surfaces, and the Claude Code parity wave: image input, a live TodoWrite checklist, `.mcp.json` auto-discovery, custom-command frontmatter, and `/export`.

---

## Claude 5 by default

### New defaults

The default model is now `claude-opus-5` (previously `claude-opus-4-8`), across first-run setup, the settings seed, and the provider tiers. The model router's three rungs are now:

| Tier | Model |
|------|-------|
| cheap | `claude-haiku-4-5` |
| mid | `claude-sonnet-5` |
| top | `claude-opus-5` |

Opus 5 is priced the same as Opus 4.8 ($5 / $25 per MTok), so the upgrade is a straight capability win at the top tier. `claude-opus-4-8` stays in the catalog as the previous-gen Opus.

### Refreshed catalog

`AVAILABLE_MODELS` was stale — one retired model and one that never existed. The catalog is now the current lineup: Fable 5, Opus 5, Opus 4.8/4.7/4.6, Sonnet 5, Sonnet 4.6, Haiku 4.5. Pricing for Opus 4.6 was also corrected (actual $5 / $25 — it was listed at 3x, over-reporting cost).

### Fable 5 support

`claude-fable-5` is in the catalog at $10 / $50 per MTok, with two behaviors specific to the Fable/Mythos family:

- **Refusal handling.** Fable 5's safety classifiers can decline a request with HTTP 200 and `stop_reason: "refusal"`. Previously that surfaced as a silently empty assistant turn; the agent loop now detects it and reports the refusal and its category.
- **Server-side fallbacks.** Fable/Mythos requests opt into a server-side Opus 4.8 fallback (`fallbacks:` param plus the fallback beta header), so a declined-at-the-edge request still gets answered. Applied only to this model family; every other model is untouched.

### Adaptive thinking, `/effort`, and task budgets

The Claude 4.6+ API surface changed, and Rubyn now speaks it correctly:

- **Adaptive thinking.** `/think` now emits `thinking: {type: adaptive}` on 4.6+ models. The old `enabled + budget_tokens` shape returns a 400 on Opus 4.8/4.7, Sonnet 5, and Fable 5 — which included our own default model, so `/think` was broken on every default install. Legacy models keep the old shape.
- **`/effort <level>`** — sets `output_config.effort` (`low` / `medium` / `high` / `xhigh` / `max`), the GA replacement for token-budget thinking on 4.6+ models. `/effort` alone shows the current value; `/effort off` returns to the model default.
- **Task budgets on the wire.** The task budget the agent already computed now actually reaches the API as `output_config.task_budget`, sent as the *remaining* budget so the model paces against what is left. Sent only on supporting models (Fable/Mythos, Sonnet 5, Opus 5, Opus 4.7/4.8) and only above the API's 20k-token minimum.

---

## Built-in codegraph

Rubyn's codebase index now builds a real call graph and exposes it as a default tool:

- **Prism-powered indexing** — symbols get real line spans, owning namespaces, and method-to-method call edges (regex remains the fallback for unparseable files). Edges are pruned to methods defined in the project, so stdlib and gem calls don't swamp the graph.
- **`code_graph` tool** — one query returns matching definitions with verbatim line-numbered source, callers, callees, and affected files including specs. It replaces a grep + read_file loop and is registered in the base toolset, exposed on every turn.
- The agent is steered to reach for `code_graph` first when an index exists, and an index `format_version` makes pre-span indexes rebuild instead of silently serving degraded data.

---

## Claude Code parity

The parity wave that motivated the 0.8.0 version bump:

- **Extended thinking** with a `/think` toggle.
- **Image / vision input** — reference an image inline with `@screenshot.png` and it is sent as an image block.
- **TodoWrite live checklist** — the agent maintains a visible task list as it works.
- **`.mcp.json` auto-discovery** — MCP servers are picked up from the standard project file, and `/mcp` tags each server `[project]` or `[user]`.
- **Custom-command frontmatter** — `argument-hint`, `allowed-tools`, and `model` in user-defined slash commands, with enforcement.
- **`/export`** — dump the conversation transcript as markdown or JSONL.

---

## Fixes and reliability

- Session restore got a proper UX and real error surfacing instead of failing quietly.
- Fixed `filtered_tool_definitions` being undefined in the agent (missed by the tool-filtering PR).
- Fixed content-block autoloads and a missing `base64` require in `ImageReader`.
- Fixed a crash in the MCP connect messages (`config[:name]` on a `Data` object).
- Cleared all RuboCop offenses, stale spec doubles, and a registry reset leak that broke later specs.
- Added an end-to-end integration test composing every parity feature in one turn, plus self-test smoke checks.

---

## Upgrade

```bash
gem update rubyn-code
```

Or from source:

```bash
cd rubyn-code
git pull
bundle install
ruby -Ilib exe/rubyn-code
```

### Breaking changes

None. Note the default model changes to `claude-opus-5` on default configs; pin `model` in `~/.rubyn-code/config.yml` if you want to stay on a previous model. Explicitly configured models are untouched.

---

## Numbers

| Metric | Value |
|--------|-------|
| Commits since v0.7.0 | 26 |
| Files changed | 119 |
| Lines added | 5,346 |
| Test examples | 2,837 |
| Failures | 0 |
| Default model | `claude-opus-5` |

---

## Full changelog

### Claude 5 models
- Add Claude Opus 5 and make the Claude 5 family the defaults (#152)
- Handle Fable 5 refusal stop reason and opt Fable/Mythos into server-side fallbacks (#150)
- Refresh model catalog; adaptive thinking on 4.6+ models; fix Opus 4.6 pricing (#147)
- `/effort` command for `output_config.effort` (#148)
- Wire task budgets to the Anthropic adapter (#149)

### Codegraph
- Built-in codegraph: Prism call graph + `code_graph` tool, steered first when an index exists (#153)

### Claude Code parity
- Extended thinking with `/think` toggle (phase-04)
- Image / vision input via `@image.png` (#133)
- TodoWrite live checklist (#134)
- Custom-command frontmatter: `argument-hint`, `allowed-tools`, `model` (#135)
- Auto-discover MCP servers from `.mcp.json` (#136)
- `/export` conversation transcript, markdown or JSONL (#137)
- `/mcp` shows `[project]` vs `[user]` source tags (#139)
- Enforce custom-command frontmatter; wire MCP discovery into the REPL (#138)

### Fixes and reliability
- Session restore: proper UX and actual error surfacing (#146)
- Define `filtered_tool_definitions` missed by the tool-filtering PR (#151)
- Autoload content blocks; require `base64` in `ImageReader` (#140, #141)
- Clear lint offenses, stale spec doubles, and registry reset leak (#154)
- Chisel out dead and reinvented code (#131)
- End-to-end parity integration test and self-test smoke checks (#144, #145)
- Parity docs nested under `docs/04-feature-parity/`; restore docs tree lost in a squash-merge (#142)
