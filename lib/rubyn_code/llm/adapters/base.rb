# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Abstract base for all LLM provider adapters.
      #
      # Every adapter must implement #chat, #provider_name, and #models.
      # The Client facade delegates to whichever adapter is active.
      class Base
        # @param messages [Array<Hash>] Conversation messages
        # @param model [String] Model identifier
        # @param max_tokens [Integer] Max output tokens
        # @param tools [Array<Hash>, nil] Tool schemas
        # @param system [String, nil] System prompt text
        # @param on_text [Proc, nil] Streaming text callback
        # @param task_budget [Hash, nil] Optional task budget context
        # @return [LLM::Response]
        def chat(messages:, model:, max_tokens:, tools: nil, system: nil, on_text: nil, task_budget: nil) # rubocop:disable Metrics/ParameterLists -- LLM adapter interface requires these params
          raise NotImplementedError, "#{self.class}#chat must be implemented"
        end

        # @return [String] Provider identifier (e.g. 'anthropic', 'openai')
        def provider_name
          raise NotImplementedError, "#{self.class}#provider_name must be implemented"
        end

        # @return [Array<String>] Available model identifiers
        def models
          raise NotImplementedError, "#{self.class}#models must be implemented"
        end
      end
    end
  end
end
