# Rubyn Code v0.7.0 — Chisel

**Write the minimum that works.**

This release introduces **Chisel**, an opt-in discipline that teaches the agent to stop over-engineering — and gives you commands to find and pay down over-engineering that already exists. Around it ships a wave of extensibility work that brings Rubyn to parity with the conventions you already use (external hooks, custom sub-agents, user-defined slash commands, `@path` mentions, `AGENTS.md`, MCP resources and prompts), three new session-control commands (`/goal`, `/loop`, `/rewind`), and a performance pass that removes the slow paths from session startup and scaling.

---

## Chisel

Chisel is a single idea applied everywhere: before writing code, walk the decision ladder — *does this need to exist at all? can stdlib do it? can the framework? can an installed gem? can it be one line? what is the minimum that works?* It is **off by default** and never changes the agent's behavior until you turn it on.

### Always-on mode

`/chisel` sets the intensity. Four levels:

| Mode | Behavior |
|------|----------|
| `off` | Default. Nothing changes. |
| `lite` | Gentle nudge toward the simpler option. |
| `full` | The decision ladder is injected on every turn. |
| `ultra` | Aggressive minimalism — justify every abstraction. |

The mode persists to `~/.rubyn-code/config.yml` across sessions, and `RUBYN_CHISEL_MODE` overrides it for a single process. An unknown mode is treated as `off` rather than raising.

```
rubyn-code> /chisel full
Chisel set to full — the decision ladder is now injected each turn.
```

### Inspection commands

Two read-only audits apply the same decision ladder on demand. They report; they never edit. They work whether or not always-on mode is enabled — running the command is its own opt-in.

- **`/chisel-review [base]`** — inspects the current branch's diff (against `main` by default, including uncommitted changes) and returns a ranked deletion/simplification list. Each item cites a location, the rung it skipped, and the concrete simpler form. Run it before you open a PR.
- **`/chisel-audit [path]`** — sweeps the whole repo, or a scoped path, for accumulated over-engineering and returns the same ranked list. Run it on a codebase you inherited.

### Ledger and status

- **`/chisel-debt`** — harvests inline `# chisel:` markers into a ledger (file, line, note), so simplifications you consciously deferred don't get lost. Skips non-source directories and never raises on an unreadable file.
- **`/chisel-gain`** — reports the current mode, the count of outstanding debt markers, and a clearly-attributed reference impact figure. When mode is `off`, it tells you how to turn it on.

### Safety floor

Chisel never tells the agent to cut input validation, error and data-loss handling, security, or accessibility. Inspection and audit exclude these categories from what they flag. "Minimum that works" never means "minimum that's safe."

---

## Extensibility

A run of features that make Rubyn extend the way the rest of your toolchain already does — drop a file in the right place and it is picked up.

- **External hooks via `settings.json`** — Claude Code-style hooks. Run external commands at lifecycle points without touching Rubyn's source.
- **Custom sub-agents from markdown** — define a specialized agent in a markdown file and Rubyn loads it as a spawnable teammate.
- **User-defined slash commands from markdown** — author your own `/commands` as markdown files; no Ruby required.
- **`@path` file mentions** — reference a file inline in a prompt with `@path/to/file` and Rubyn expands its contents.
- **`AGENTS.md` project instructions** — Rubyn now reads the `AGENTS.md` convention for project-level instructions.
- **MCP resources and prompts** — MCP support extends beyond tools to resources and prompts.
- **`ask_user` over IDE RPC** — the `ask_user` tool is wired through the IDE's bidirectional RPC, so prompts surface in the editor.

---

## Session control

- **`/goal`** — set a session goal and Rubyn keeps working until it is met, running past the per-turn tool-iteration cap while a goal is active.
- **`/loop`** — repeat a prompt or slash command on an interval.
- **`/rewind`** — checkpoint and restore both code and conversation, so you can explore a direction and roll all of it back.
- **Portable instincts** — export and import learned instincts to carry them across machines.

---

## Performance

A pass to make startup and scaling cheap:

- Removed `O(n^2)` hotspots in token counting, persistence, diffing, and formatting that grew with session length.
- Memoized system-prompt sections per turn instead of rebuilding them.
- Cached keychain token lookups in the LLM adapter.
- Lazy-load `pastel`, `rouge`, and `faraday`; fixed a `Config` autoload.
- Made AutoSuggest and the version check non-blocking at REPL start.
- Codebase index does incremental single-file updates and dedupes its edges.

---

## Platform and reliability

- **Linux support for Claude Code OAuth** — authentication now works on Linux, not just macOS.
- Fixed order-dependent spec flakiness (auth, SIGINT trap, cancel race) and eager-require `faraday` in `RegistryClient`.
- Made the compressor and memory self-test checks deterministic.
- Added a deterministic Chisel smoke test plus an over-engineered fixture.
- CI honesty gate: the test job no longer silently runs a subset on a keychain-dependent exit, and the build checks for "0 failures" rather than trusting a platform-dependent exit code.

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

None. Chisel is off by default and every new feature is additive. Existing commands, tools, and workflows behave exactly as before.

---

## Numbers

| Metric | Value |
|--------|-------|
| Commits since v0.6.0 | 29 |
| Files changed | 158 |
| Lines added | 8,305 |
| Test examples | 2,706 |
| Failures | 0 |
| New Chisel commands | 5 (`/chisel`, `/chisel-review`, `/chisel-audit`, `/chisel-debt`, `/chisel-gain`) |

---

## Full changelog

### Chisel
- Phase 1 — Core: opt-in `off`/`lite`/`full`/`ultra` modes, decision-ladder ruleset injection, `/chisel` command (#124)
- Phase 2 — Inspection: `/chisel-review` and `/chisel-audit` (#125)
- Phase 3 — Ledger & Gain: `/chisel-debt` and `/chisel-gain` (#127)
- Deterministic Chisel smoke test and over-engineered fixture (#129)

### Extensibility
- Claude Code-style external hooks via `settings.json` (#123)
- Custom sub-agent definitions from markdown files (#116)
- User-defined slash commands from markdown files (#115)
- Expand `@path` file mentions in prompts (#114)
- Load `AGENTS.md` project instructions (Codex convention) (#113)
- Support MCP resources and prompts, not just tools (#117)
- Wire `ask_user` through IDE bidirectional RPC (#110)

### Session control
- `/goal` — keep working until a session goal is met (#111)
- `/loop` — repeat a prompt or slash command on an interval (#112)
- `/rewind` — checkpoint and restore code and conversation (#118)
- Export/import instincts for portability across machines (#119)
- Let an active goal run past the tool-iteration cap (#121, #122)

### Performance
- Remove `O(n^2)` session-scaling hotspots in tokens, persistence, diff, formatting (#107)
- Lazy-load pastel/rouge/faraday and fix Config autoload (#106)
- Cache keychain token lookups in the LLM adapter (#105)
- Memoize system-prompt sections per turn (#104)
- Make AutoSuggest and version check non-blocking at REPL start (#103)
- Dedup index test edges and add incremental single-file updates (#102)

### Platform and fixes
- Add Linux support for Claude Code OAuth authentication (#108)
- Eager-require faraday in `RegistryClient` to fix order-dependent specs (#128)
- Fix order-dependent CI flakiness (auth, SIGINT trap, cancel race) (#126)
- Make compressor and memory self-test checks deterministic (#109)
- Cover the new parity features in self-test plus smoke checks (#120)
- Honest CI gate: stop silently running a spec subset on keychain-dependent exit (#130)
