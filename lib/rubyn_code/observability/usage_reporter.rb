# frozen_string_literal: true

require 'time'

module RubynCode
  module Observability
    # Generates human-readable cost and usage summaries from recorded cost data.
    class UsageReporter
      TABLE_NAME = BudgetEnforcer::TABLE_NAME

      # @param db [DB::Connection] database connection
      # @param formatter [Output::Formatter] output formatter for colorized text
      def initialize(db, formatter:)
        @db        = db
        @formatter = formatter
      end

      # Returns a formatted summary of cost and usage for a given session.
      #
      # @param session_id [String]
      # @return [String] multi-line formatted summary
      def session_summary(session_id)
        rows = @db.query(
          "SELECT model, input_tokens, output_tokens, cost_usd FROM #{TABLE_NAME} WHERE session_id = ?",
          [session_id]
        ).to_a

        return "No usage data for session #{session_id}." if rows.empty?

        total_input   = rows.sum { |r| fetch_int(r, 'input_tokens') }
        total_output  = rows.sum { |r| fetch_int(r, 'output_tokens') }
        total_cost    = rows.sum { |r| fetch_float(r, 'cost_usd') }
        turns         = rows.size
        avg_cost      = turns.positive? ? total_cost / turns : 0.0

        lines = [
          header('Session Summary'),
          field('Session', session_id),
          field('Turns', turns.to_s),
          field('Input tokens', format_number(total_input)),
          field('Output tokens', format_number(total_output)),
          field('Total tokens', format_number(total_input + total_output)),
          field('Total cost', format_usd(total_cost)),
          field('Avg cost/turn', format_usd(avg_cost))
        ]

        lines.join("\n")
      end

      # Returns a formatted summary of today's total cost across all sessions.
      #
      # @return [String] multi-line formatted summary
      def daily_summary
        today = Time.now.utc.strftime('%Y-%m-%d')
        rows = @db.query(
          'SELECT session_id, SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens, ' \
          "SUM(cost_usd) AS cost_usd, COUNT(*) AS turns FROM #{TABLE_NAME} " \
          'WHERE created_at >= ? GROUP BY session_id',
          ["#{today}T00:00:00Z"]
        ).to_a

        return 'No usage data for today.' if rows.empty?

        total_input  = rows.sum { |r| fetch_int(r, 'input_tokens') }
        total_output = rows.sum { |r| fetch_int(r, 'output_tokens') }
        total_cost   = rows.sum { |r| fetch_float(r, 'cost_usd') }
        total_turns  = rows.sum { |r| fetch_int(r, 'turns') }
        sessions     = rows.size

        lines = [
          header("Daily Summary (#{today})"),
          field('Sessions', sessions.to_s),
          field('Total turns', total_turns.to_s),
          field('Input tokens', format_number(total_input)),
          field('Output tokens', format_number(total_output)),
          field('Total cost', format_usd(total_cost))
        ]

        lines.join("\n")
      end

      # Returns a cost breakdown by model for a given session.
      #
      # @param session_id [String]
      # @return [String] multi-line formatted breakdown
      def model_breakdown(session_id)
        rows = @db.query(
          'SELECT model, SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens, ' \
          "SUM(cost_usd) AS cost_usd, COUNT(*) AS calls FROM #{TABLE_NAME} " \
          'WHERE session_id = ? GROUP BY model ORDER BY cost_usd DESC',
          [session_id]
        ).to_a

        return "No usage data for session #{session_id}." if rows.empty?

        lines = [header('Cost by Model')]

        rows.each do |row|
          model   = row['model'] || row[:model]
          cost    = fetch_float(row, 'cost_usd')
          calls   = fetch_int(row, 'calls')
          input_t = fetch_int(row, 'input_tokens')
          output_t = fetch_int(row, 'output_tokens')

          lines << "  #{@formatter.pastel.bold(model)}"
          lines << "    Calls: #{calls}  |  Input: #{format_number(input_t)}  |  Output: #{format_number(output_t)}  |  Cost: #{format_usd(cost)}"
        end

        lines.join("\n")
      end

      private

      def header(title)
        bar = @formatter.pastel.dim('-' * 40)
        "#{bar}\n  #{@formatter.pastel.bold(title)}\n#{bar}"
      end

      def field(label, value)
        "  #{@formatter.pastel.dim("#{label}:")} #{value}"
      end

      def format_usd(amount)
        '$%.4f' % amount
      end

      def format_number(n)
        n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      def fetch_int(row, key)
        (row[key] || row[key.to_sym] || 0).to_i
      end

      def fetch_float(row, key)
        (row[key] || row[key.to_sym] || 0.0).to_f
      end
    end
  end
end
