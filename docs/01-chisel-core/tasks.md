# Phase 1 — Chisel Core: Tasks

## [x] 1. Chisel module

- [x] 1.1 Create `lib/rubyn_code/chisel.rb` with `MODES`, `mode`, `enabled?`, `valid?`, `prompt_section` (refs Req 1.3, 1.4, 1.5, 3.1–3.4)
- [x] 1.2 Write the ruleset constant: ladder (all) + intensity addenda (full/ultra) + safety floor (all) (refs Req 3.3, 3.4)
- [x] 1.3 Resolve mode env → config → default with invalid-value fallback to `off` (refs Req 1.1, 1.4, 1.5)
- [x] 1.4 Autoload `Chisel` in `lib/rubyn_code.rb`

## [x] 2. Config wiring

- [x] 2.1 Add `Defaults::CHISEL_MODE = 'off'` (refs Req 1.1)
- [x] 2.2 Add `:chisel_mode` to `CONFIGURABLE_KEYS` and `DEFAULT_MAP` (refs Req 1.1, 1.2)
- [x] 2.3 Add `chisel_mode` enum property to `config/schema.json` (refs Req 1.3)

## [x] 3. Prompt injection

- [x] 3.1 Add `append_chisel_ruleset` to `SystemPromptBuilder#build_static_prompt_sections`, guarded so it never breaks the prompt (refs Req 3.1, 3.2)

## [x] 4. /chisel command

- [x] 4.1 Create `lib/rubyn_code/cli/commands/chisel.rb` (report / set / warn) (refs Req 2.1, 2.2, 2.3)
- [x] 4.2 Register `Commands::Chisel` in `repl_commands.rb` (refs Req 2.1)

## [x] 5. Docs

- [x] 5.1 Add `lib/rubyn_code/chisel.rb`'s module doc + a `RUBYN.md`-style note if the dir warrants it
- [x] 5.2 Note Chisel in `README.md` features

## [x] 6. Validation

- [x] 6.1 Specs: `chisel_spec.rb` (resolution, fallback, prompt_section nesting + safety floor)
- [x] 6.2 Specs: settings `chisel_mode` default + round-trip; `/chisel` command report/set/warn
- [x] 6.3 Run full suite + RuboCop — all green
- [x] 6.4 Manual smoke: `chisel_mode off` → prompt has no Chisel section; `full` → it does
- [x] 6.5 Update `docs/README.md` to check this phase's box
