# frozen_string_literal: true

module RubynCode
  module Observability
    # Tracks detailed token usage breakdown by category (system prompt,
    # skills, context files, conversation, tool output) and reports
    # savings from efficiency features. Powers the enhanced /cost command.
    class TokenAnalytics
      CHARS_PER_TOKEN = 4

      CATEGORIES = %i[
        system_prompt skills_loaded context_files
        conversation tool_output code_written
        explanations tool_calls
      ].freeze

      attr_reader :input_breakdown, :output_breakdown, :savings

      def initialize
        @input_breakdown = Hash.new(0)
        @output_breakdown = Hash.new(0)
        @savings = Hash.new(0)
        @start_time = Time.now
        @turn_count = 0
      end

      # Record input token usage by category.
      def record_input(category, tokens)
        @input_breakdown[category.to_sym] += tokens.to_i
      end

      # Record output token usage by category.
      def record_output(category, tokens)
        @output_breakdown[category.to_sym] += tokens.to_i
      end

      # Record tokens saved by an efficiency feature.
      def record_savings(feature, tokens)
        @savings[feature.to_sym] += tokens.to_i
      end

      # Increment the turn counter.
      def record_turn!
        @turn_count += 1
      end

      # Total input tokens across all categories.
      def total_input_tokens
        @input_breakdown.values.sum
      end

      # Total output tokens across all categories.
      def total_output_tokens
        @output_breakdown.values.sum
      end

      # Total tokens saved across all features.
      def total_tokens_saved
        @savings.values.sum
      end

      # Session duration in minutes.
      def session_minutes
        ((Time.now - @start_time) / 60.0).round(1)
      end

      # Format a complete analytics report.
      def report(**)
        lines = [header]
        lines.concat(input_section)
        lines << ''
        lines.concat(output_section)
        lines << ''
        lines.concat(savings_section) if @savings.any?
        lines.join("\n")
      end

      private

      def header
        duration = session_minutes
        "Session: #{duration} min | #{@turn_count} turns"
      end

      def input_section
        total = total_input_tokens
        lines = ['Input tokens:'.rjust(20) + "  #{fmt(total)}"]

        @input_breakdown.each do |cat, tokens|
          pct = total.positive? ? ((tokens.to_f / total) * 100).round(0) : 0
          lines << ("  #{humanize(cat)}:".ljust(22) + "#{fmt(tokens).rjust(8)}  (#{pct}%)")
        end

        lines
      end

      def output_section
        total = total_output_tokens
        lines = ['Output tokens:'.rjust(20) + "  #{fmt(total)}"]

        @output_breakdown.each do |cat, tokens|
          pct = total.positive? ? ((tokens.to_f / total) * 100).round(0) : 0
          lines << ("  #{humanize(cat)}:".ljust(22) + "#{fmt(tokens).rjust(8)}  (#{pct}%)")
        end

        lines
      end

      def savings_section
        total = total_tokens_saved
        lines = ['Savings applied:']

        @savings.each do |feature, tokens|
          lines << ("  #{humanize(feature)}:".ljust(22) + "-#{fmt(tokens)} tokens saved")
        end

        lines << ('  Total saved:'.ljust(22) + "-#{fmt(total)} tokens")
        lines
      end

      def humanize(sym)
        sym.to_s.tr('_', ' ').capitalize
      end

      def fmt(num)
        num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
      end
    end
  end
end
