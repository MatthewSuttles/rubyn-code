# Phase 2 — Chisel Inspection: Tasks

## [x] 1. Shared detector

- [x] 1.1 Create `lib/rubyn_code/chisel/inspection.rb` with `prompt(scope:, target:)` (refs Req 1.1, 2.1, 3.1)
- [x] 1.2 Reuse `Chisel::LADDER` + `Chisel::SAFETY_FLOOR` as the rubric / exclusion (refs Req 3.1, 3.2)
- [x] 1.3 Output contract: ranked list, per item location + rung + simpler form (refs Req 1.3, 2.3)
- [x] 1.4 Read-only guardrail in the prompt (refs Req 1.4, 2.4)
- [x] 1.5 Raise `ArgumentError` on unknown scope
- [x] 1.6 Autoload `Chisel::Inspection`

## [x] 2. Commands

- [x] 2.1 Create `/chisel-review` command (base ref arg, default `main`) (refs Req 1.1, 1.2)
- [x] 2.2 Create `/chisel-audit` command (optional path arg) (refs Req 2.1, 2.2)
- [x] 2.3 Register both + autoloads (refs Req 1.1, 2.1)

## [x] 3. Docs

- [x] 3.1 Note `/chisel-review` + `/chisel-audit` in the README Chisel section
- [x] 3.2 Check Phase 1 box + add detail in `docs/README.md`

## [x] 4. Validation

- [x] 4.1 Specs: `inspection_spec.rb` (scope/target wording, ladder, contract, read-only, safety floor, bad scope raises)
- [x] 4.2 Specs: review + audit command specs (send_message called with scoped prompt)
- [x] 4.3 Run full suite + RuboCop (changed files) — green
- [x] 4.4 Manual smoke: `/chisel-review` prompt names the base + ladder; `/chisel-audit app/` names the path
- [x] 4.5 Update `docs/README.md` to check this phase's box
