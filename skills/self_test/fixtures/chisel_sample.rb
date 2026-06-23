# frozen_string_literal: true

# Chisel self-test fixture — a DELIBERATELY over-engineered Ruby file.
#
# rubyn-code points Chisel at this file to get consistent, repeatable results:
#   - `Chisel::Debt.scan` on this directory must harvest EXACTLY the three
#     own-line `chisel:` markers below — and none of the decoys at the bottom.
#   - `/chisel-review` and `/chisel-audit` have real over-engineering to flag.
#
# Do NOT "clean this up" — the smells and the markers are the point. The smoke
# test that asserts on this file lives in skills/self_test/chisel_smoke.rb and
# spec/rubyn_code/chisel/self_test_fixture_spec.rb. If you change a marker, the
# line/note it sits on, or add/remove one, update those two in lock-step.
module ChiselFixture
  # An abstract factory with exactly one product shape — classic premature
  # abstraction. A plain method (or just calling the class) would do.
  class GreeterFactory
    # chisel: collapse this factory into a single build method
    def self.create(kind)
      case kind
      when :formal then FormalGreeter.new
      when :casual then CasualGreeter.new
      end
    end
  end

  class FormalGreeter
    def greet(name) = "Good day, #{name}."
  end

  class CasualGreeter
    def greet(name) = "hey #{name}"
  end

  # A stateful wrapper that adds nothing over Array#sum.
  class Accumulator
    def initialize = (@total = 0)

    # chisel: replace this class with Array#sum at the single call site
    def add(amount)
      @total += amount
      self
    end

    def total = @total
  end

  # Single-reader config indirection.
  DEFAULTS = { retries: 3 }.freeze

  def self.retries
    # chisel: inline DEFAULTS[:retries] since there is only one reader
    DEFAULTS.fetch(:retries)
  end

  # --- decoys: these MUST NOT be harvested as debt markers ---

  def self.decoy
    # The next line has "chisel:" inside a string AND as a trailing comment;
    # neither is an own-line marker, so the scanner must ignore both.
    label = 'see # chisel: this is data, not a marker' # chisel: trailing, ignored
    label
  end
end
