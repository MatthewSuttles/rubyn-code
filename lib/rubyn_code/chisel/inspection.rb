# frozen_string_literal: true

module RubynCode
  module Chisel
    # Builds the over-engineering audit instruction shared by /chisel-review
    # (scope: :diff) and /chisel-audit (scope: :repo). Both judge by the same
    # decision ladder and exclude the same safety floor, so the two commands
    # can never drift apart — they differ only in what code they look at.
    #
    # Detection is delegated to the agent and its tools (git_diff, bash, grep,
    # read_file); this module only assembles the prompt.
    module Inspection
      SMELLS = <<~SMELLS.strip
        Flag code that skips a rung of the ladder:
        - speculative abstractions, wrappers, or base classes with a single caller
        - reinvented stdlib or already-installed-gem functionality
        - needless indirection, configurability, or options nobody uses
        - dead parameters, unused branches, premature generalization
        - a class where a method would do; a method where one line would do
      SMELLS

      OUTPUT_CONTRACT = <<~CONTRACT.strip
        Return a ranked deletion/simplification list, most impactful first. For
        each item give:
        - `file:line`
        - what it is (one line)
        - which rung of the ladder it skipped
        - the concrete simpler form (delete it / inline it / replace with stdlib X)

        If nothing is over-engineered, say so plainly instead of inventing work.
      CONTRACT

      READ_ONLY_NOTE = 'This is a READ-ONLY review: report the list, do not edit any files.'

      module_function

      # @param scope [Symbol] :diff (review changes) or :repo (audit codebase)
      # @param target [String, nil] base ref for :diff (default "main"),
      #   or an optional path to scope :repo
      # @return [String] the full instruction to send to the agent
      # @raise [ArgumentError] on an unknown scope
      def prompt(scope:, target: nil)
        [lead_in(scope, target), Chisel::LADDER, SMELLS, OUTPUT_CONTRACT, guardrails]
          .join("\n\n")
      end

      # Read-only guard + the shared safety floor, reused verbatim from Chisel
      # so the exclusion list can never drift from the always-on ruleset.
      #
      # @return [String]
      def guardrails
        "#{READ_ONLY_NOTE}\n\n#{Chisel::SAFETY_FLOOR}\n" \
          'Those are never over-engineering — leave them even if they add code.'
      end

      # @return [String]
      def lead_in(scope, target)
        case scope
        when :diff then diff_lead_in(presence(target) || 'main')
        when :repo then repo_lead_in(presence(target))
        else raise ArgumentError, "unknown Chisel inspection scope: #{scope.inspect}"
        end
      end

      # @param value [#to_s, nil]
      # @return [String, nil] the trimmed value, or nil if blank
      def presence(value)
        str = value.to_s.strip
        str.empty? ? nil : str
      end

      def diff_lead_in(base)
        <<~LEAD.strip
          Chisel review — find over-engineering in my current changes.

          Gather the diff with `git diff #{base}...` plus any uncommitted changes
          (`git diff` and `git diff --staged`). Judge ONLY the added or changed
          lines against the Chisel decision ladder below.
        LEAD
      end

      def repo_lead_in(path)
        scope_line = path ? "Scope the sweep to `#{path}`." : 'Sweep the whole repository.'
        <<~LEAD.strip
          Chisel audit — find accumulated over-engineering in this codebase.

          #{scope_line} Use grep and file reads to survey the code, then judge it
          against the Chisel decision ladder below.
        LEAD
      end
    end
  end
end
