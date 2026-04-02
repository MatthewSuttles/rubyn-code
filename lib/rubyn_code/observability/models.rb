# frozen_string_literal: true

module RubynCode
  module Observability
    # Immutable record of a single API call's cost, stored in the database.
    CostRecord = Data.define(
      :id,
      :session_id,
      :model,
      :input_tokens,
      :output_tokens,
      :cache_read_tokens,
      :cache_write_tokens,
      :cost_usd,
      :request_type,
      :created_at
    )

    # Snapshot of metrics for a single agent turn (request/response cycle).
    TurnMetrics = Data.define(
      :model,
      :input_tokens,
      :output_tokens,
      :cost_usd,
      :duration_ms,
      :tool_calls_count
    )
  end
end
