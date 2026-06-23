# frozen_string_literal: true

module RubynCode
  # Chisel is rubyn-code's opt-in "write the minimum that works" enforcement
  # layer. It is OFF by default and only changes the agent's behavior once a
  # user turns it on (via `/chisel full` or the config key `chisel_mode`).
  #
  # The single source of truth for:
  #   - which intensity modes exist (off/lite/full/ultra),
  #   - which mode is currently active (env override → config → default),
  #   - the ruleset text injected into the system prompt at each intensity.
  #
  # The decision ladder is adapted from the open-source `ponytail` plugin and
  # rebuilt natively here; the safety floor (validation, error/data-loss
  # handling, security, accessibility) is never on the chopping block.
  module Chisel
    # On-demand over-engineering audit shared by /chisel-review and /chisel-audit.
    autoload :Inspection, 'rubyn_code/chisel/inspection'
    # Harvests inline `chisel:` deferral markers for /chisel-debt and /chisel-gain.
    autoload :Debt, 'rubyn_code/chisel/debt'

    MODES = %w[off lite full ultra].freeze
    DEFAULT_MODE = 'off'
    ENV_KEY = 'RUBYN_CHISEL_MODE'
    CONFIG_KEY = 'chisel_mode'

    # The decision ladder — injected at every non-off intensity.
    LADDER = <<~LADDER.strip
      # Chisel — write the minimum that works

      Before writing code, stop at the first rung that holds:
      1. Does this need to exist? If not, don't write it. (YAGNI)
      2. Does Ruby's stdlib already do it? Use it.
      3. Does the framework or runtime already do it? Use it.
      4. Does an already-installed gem do it? Use it — don't add a dependency.
      5. Is it one line? Write one line.
      6. Only then: the smallest change that fully solves the task.
    LADDER

    # Extra guidance layered on at `full` and above.
    FULL_ADDENDUM = <<~FULL.strip
      Prefer editing existing code over adding new files, classes, or layers of
      indirection. Don't introduce an abstraction until a second concrete caller
      exists — three similar lines beat a premature framework.
    FULL

    # Extra guidance layered on at `ultra` only.
    ULTRA_ADDENDUM = <<~ULTRA.strip
      Be aggressive: question every new method, parameter, option, and file. If
      you can't name the second caller, inline it. When you finish, briefly note
      what you deliberately chose NOT to build.
    ULTRA

    # The safety floor — appended at every non-off intensity, last so it is
    # never overridden by the "delete more" guidance above it.
    SAFETY_FLOOR = <<~SAFETY.strip
      Lazy, not negligent. Never chisel away: input and trust-boundary
      validation, error and data-loss handling, security, or accessibility.
    SAFETY

    module_function

    # @param value [#to_s]
    # @return [Boolean] whether the value is a recognized mode
    def valid?(value)
      MODES.include?(value.to_s)
    end

    # Resolve the active mode: env override → persisted config → default.
    # Each layer is normalized (trimmed + downcased) the same way the
    # `/chisel` command normalizes its argument, so `RUBYN_CHISEL_MODE=Full`
    # and a hand-edited `chisel_mode: " Full "` both resolve cleanly. Any
    # unrecognized value falls through rather than raising, so a typo can
    # never break a turn.
    #
    # @return [String] one of MODES
    def mode
      normalize(ENV.fetch(ENV_KEY, nil)) ||
        normalize(configured_mode) ||
        DEFAULT_MODE
    end

    # Trim + downcase a candidate mode, returning it only if recognized,
    # otherwise nil so the caller can fall through to the next layer.
    #
    # @param value [#to_s, nil]
    # @return [String, nil]
    def normalize(value)
      return nil if value.nil?

      candidate = value.to_s.strip.downcase
      valid?(candidate) ? candidate : nil
    end

    # @return [Boolean]
    def enabled?
      mode != 'off'
    end

    # The text Chisel contributes to the system prompt for the active mode.
    #
    # @return [String] "" when off; otherwise ladder + intensity addenda +
    #   safety floor.
    def prompt_section
      current = mode
      return '' if current == 'off'

      parts = [LADDER]
      parts << FULL_ADDENDUM if %w[full ultra].include?(current)
      parts << ULTRA_ADDENDUM if current == 'ultra'
      parts << SAFETY_FLOOR
      parts.join("\n\n")
    end

    # The persisted mode from config, or nil if unreadable. Isolated so prompt
    # assembly never dies on a malformed config file.
    #
    # @return [String, nil]
    def configured_mode
      # No default needed — chisel_mode lives in Settings::DEFAULT_MAP, so an
      # unset key already resolves to DEFAULT_MODE.
      Config::Settings.new.get(CONFIG_KEY)
    rescue StandardError
      nil
    end
  end
end
