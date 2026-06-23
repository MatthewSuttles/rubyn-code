# frozen_string_literal: true

# Chisel smoke test — runs rubyn-code's Chisel layer against a committed,
# deliberately over-engineered fixture and asserts a CONSISTENT result every
# time. Deterministic and offline (no LLM): the debt scanner, mode resolution,
# inspection-prompt assembly, and command registration are all pure.
#
#   $ bundle exec ruby skills/self_test/chisel_smoke.rb
#
# Prints one `CHISEL <area>: PASS/FAIL` line per area, a final `CHISEL: PASS`
# (or `FAIL`), and exits non-zero if anything failed — so CI and the
# /skill self-test scorecard can both consume it.

require_relative '../../lib/rubyn_code'

C = RubynCode::Chisel
FIXTURE_DIR = File.expand_path('fixtures', __dir__)

# The exact, repeatable output the scanner must produce for the fixture. If you
# edit skills/self_test/fixtures/chisel_sample.rb, update this table to match.
EXPECTED_DEBT = [
  { file: 'chisel_sample.rb', line: 18, note: 'collapse this factory into a single build method' },
  { file: 'chisel_sample.rb', line: 39, note: 'replace this class with Array#sum at the single call site' },
  { file: 'chisel_sample.rb', line: 52, note: 'inline DEFAULTS[:retries] since there is only one reader' }
].freeze

results = {}

# 1. Debt scanner — the consistent-result core. Scan only the fixture dir so
#    the outcome never depends on the rest of the tree.
scanned = RubynCode::Chisel::Debt.scan(FIXTURE_DIR)
actual = scanned.map { |i| { file: i.file, line: i.line, note: i.note } }
results['debt'] = (actual == EXPECTED_DEBT)
warn("  debt mismatch — expected #{EXPECTED_DEBT.inspect}, got #{actual.inspect}") unless results['debt']

# 2. Engine — off injects nothing; lite/full/ultra layer the right addenda and
#    ALWAYS keep the safety floor; a garbage mode never crashes or leaks through.
#    Driven via RUBYN_CHISEL_MODE so it ignores this machine's chisel_mode config.
ENV['RUBYN_CHISEL_MODE'] = 'off'
off_ok = !C.enabled? && C.mode == 'off' && C.prompt_section.empty?

ENV['RUBYN_CHISEL_MODE'] = 'lite'
lite = C.prompt_section
lite_ok = C.enabled? && lite.include?(C::LADDER) && lite.include?(C::SAFETY_FLOOR) && !lite.include?(C::FULL_ADDENDUM)

ENV['RUBYN_CHISEL_MODE'] = 'full'
full = C.prompt_section
full_ok = full.include?(C::FULL_ADDENDUM) && full.include?(C::SAFETY_FLOOR) && !full.include?(C::ULTRA_ADDENDUM)

ENV['RUBYN_CHISEL_MODE'] = 'ultra'
ultra = C.prompt_section
ultra_ok = ultra.include?(C::ULTRA_ADDENDUM) && ultra.include?(C::SAFETY_FLOOR)

ENV['RUBYN_CHISEL_MODE'] = 'definitely-not-a-mode'
typo_ok = C::MODES.include?(C.mode) && C.mode != 'definitely-not-a-mode'
ENV.delete('RUBYN_CHISEL_MODE')
results['engine'] = off_ok && lite_ok && full_ok && ultra_ok && typo_ok

# 3. Inspection — both scopes assemble a String carrying the ladder + safety
#    floor and naming the fixture; an unknown scope raises instead of emitting junk.
insp = RubynCode::Chisel::Inspection
diff_p = insp.prompt(scope: :diff, target: 'main')
repo_p = insp.prompt(scope: :repo, target: FIXTURE_DIR)
raised = begin
  insp.prompt(scope: :bogus)
  false
rescue ArgumentError
  true
end
results['inspection'] = diff_p.is_a?(String) && diff_p.include?(C::LADDER) &&
                        diff_p.include?(C::SAFETY_FLOOR) &&
                        repo_p.include?(C::LADDER) && repo_p.include?(FIXTURE_DIR) && raised

# 4. Command registry — all five Chisel commands register and resolve by name.
reg = RubynCode::CLI::Commands::Registry.new
[RubynCode::CLI::Commands::Chisel, RubynCode::CLI::Commands::ChiselReview,
 RubynCode::CLI::Commands::ChiselAudit, RubynCode::CLI::Commands::ChiselDebt,
 RubynCode::CLI::Commands::ChiselGain].each { |cmd| reg.register(cmd) }
results['commands'] = %w[/chisel /chisel-review /chisel-audit /chisel-debt /chisel-gain].all? { |n| reg.known?(n) }

results.each { |area, ok| puts "CHISEL #{area}: #{ok ? 'PASS' : 'FAIL'}" }
all_ok = results.values.all?
puts(all_ok ? 'CHISEL: PASS' : 'CHISEL: FAIL')
exit(all_ok ? 0 : 1)
