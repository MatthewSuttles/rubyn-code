# frozen_string_literal: true

module RubynCode
  module LLM
    # Backward-compatibility shim.
    # Delegates to Adapters::AnthropicStreaming so existing references
    # to LLM::Streaming keep working during the migration.
    Streaming = Adapters::AnthropicStreaming
  end
end
