# Phase 3 — Chisel Ledger & Gain: Tasks

## [x] 1. Debt scanner

- [x] 1.1 Create `lib/rubyn_code/chisel/debt.rb` with `Item` + `scan(root)` (refs Req 1.1, 1.2)
- [x] 1.2 Marker regex (comment leader + `chisel:` + note); source extensions; skip dirs (refs Req 1.1, 1.4)
- [x] 1.3 Per-file rescue; `[]` for nil/missing root (refs Req 1.5)
- [x] 1.4 Autoload `Chisel::Debt`

## [x] 2. Commands

- [x] 2.1 `/chisel-debt` — render ledger or clean message (refs Req 1.2, 1.3)
- [x] 2.2 `/chisel-gain` — mode + debt count + attributed reference + hint (refs Req 2.1–2.4)
- [x] 2.3 Register both + autoloads

## [x] 3. Docs

- [x] 3.1 Add `/chisel-debt` + `/chisel-gain` to the README Chisel section
- [x] 3.2 Check Phase 2 box in `docs/README.md`

## [x] 4. Validation

- [x] 4.1 Specs: `debt_spec.rb` (finds markers, ignores non-markers/skip-dirs, unreadable-file tolerance, nil root)
- [x] 4.2 Specs: `/chisel-debt` + `/chisel-gain` command specs
- [x] 4.3 Full suite + RuboCop (changed files) — green
- [x] 4.4 Manual smoke: seed a `chisel:` marker → it appears in `/chisel-debt` and the `/chisel-gain` count
- [x] 4.5 Update `docs/README.md` to check this phase's box
