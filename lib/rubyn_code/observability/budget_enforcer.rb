# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "models"
require_relative "cost_calculator"

module RubynCode
  module Observability
    # Tracks API spend and halts the agent when session or daily budgets are
    # exceeded. Cost records are persisted to SQLite so budgets survive restarts.
    class BudgetEnforcer
      DEFAULT_SESSION_LIMIT = 5.00
      DEFAULT_DAILY_LIMIT   = 10.00

      TABLE_NAME = "cost_records"

      # @param db [DB::Connection] database connection
      # @param session_id [String] current session identifier
      # @param session_limit [Float] maximum USD spend per session
      # @param daily_limit [Float] maximum USD spend per calendar day
      def initialize(db, session_id:, session_limit: DEFAULT_SESSION_LIMIT, daily_limit: DEFAULT_DAILY_LIMIT)
        @db            = db
        @session_id    = session_id
        @session_limit = session_limit.to_f
        @daily_limit   = daily_limit.to_f

        ensure_table_exists
      end

      # Records a cost entry for an API call and persists it to the database.
      #
      # @param model [String] the model identifier
      # @param input_tokens [Integer] input token count
      # @param output_tokens [Integer] output token count
      # @param cache_read_tokens [Integer] cache-read token count
      # @param cache_write_tokens [Integer] cache-write token count
      # @param request_type [String] the type of request (e.g., "chat", "compact")
      # @return [CostRecord] the persisted cost record
      def record!(model:, input_tokens:, output_tokens:, cache_read_tokens: 0, cache_write_tokens: 0, request_type: "chat")
        cost = CostCalculator.calculate(
          model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cache_read_tokens: cache_read_tokens,
          cache_write_tokens: cache_write_tokens
        )

        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        @db.execute(
          "INSERT INTO #{TABLE_NAME} (id, session_id, model, input_tokens, output_tokens, " \
          "cache_read_tokens, cache_write_tokens, cost_usd, request_type, created_at) " \
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [id, @session_id, model, input_tokens, output_tokens,
           cache_read_tokens, cache_write_tokens, cost, request_type, now]
        )

        CostRecord.new(
          id: id,
          session_id: @session_id,
          model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cache_read_tokens: cache_read_tokens,
          cache_write_tokens: cache_write_tokens,
          cost_usd: cost,
          request_type: request_type,
          created_at: now
        )
      end

      # Raises BudgetExceededError if either the session or daily budget is exceeded.
      #
      # @raise [BudgetExceededError] when spend exceeds a limit
      # @return [void]
      def check!
        sc = session_cost
        if sc >= @session_limit
          raise BudgetExceededError,
                "Session budget exceeded: $#{"%.4f" % sc} >= $#{"%.2f" % @session_limit} limit"
        end

        dc = daily_cost
        if dc >= @daily_limit
          raise BudgetExceededError,
                "Daily budget exceeded: $#{"%.4f" % dc} >= $#{"%.2f" % @daily_limit} limit"
        end
      end

      # Returns the total cost accumulated in the current session.
      #
      # @return [Float] total session cost in USD
      def session_cost
        rows = @db.query(
          "SELECT COALESCE(SUM(cost_usd), 0.0) AS total FROM #{TABLE_NAME} WHERE session_id = ?",
          [@session_id]
        ).to_a
        extract_total(rows)
      end

      # Returns the total cost accumulated today (UTC).
      #
      # @return [Float] total daily cost in USD
      def daily_cost
        today = Time.now.utc.strftime("%Y-%m-%d")
        rows = @db.query(
          "SELECT COALESCE(SUM(cost_usd), 0.0) AS total FROM #{TABLE_NAME} WHERE created_at >= ?",
          ["#{today}T00:00:00Z"]
        ).to_a
        extract_total(rows)
      end

      # Returns the smaller of the session and daily remaining budgets.
      #
      # @return [Float] remaining budget in USD
      def remaining_budget
        session_remaining = @session_limit - session_cost
        daily_remaining   = @daily_limit - daily_cost
        [session_remaining, daily_remaining].min
      end

      private

      def ensure_table_exists
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_write_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL DEFAULT 0.0,
            request_type TEXT NOT NULL DEFAULT 'chat',
            created_at TEXT NOT NULL
          )
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_cost_records_session_id ON #{TABLE_NAME} (session_id)
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_cost_records_created_at ON #{TABLE_NAME} (created_at)
        SQL
      end

      def extract_total(rows)
        return 0.0 if rows.nil? || rows.empty?

        row = rows.first
        (row["total"] || row[:total] || 0.0).to_f
      end
    end
  end
end
