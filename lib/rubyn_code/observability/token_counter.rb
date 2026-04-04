# frozen_string_literal: true

require 'json'

module RubynCode
  module Observability
    # Estimates token counts from text using a character-based heuristic.
    #
    # This provides a fast approximation (~4 characters per token) suitable for
    # budget tracking and context-window management. For exact counts, use the
    # API's reported usage fields instead.
    module TokenCounter
      # Average characters per token for English text and source code.
      CHARS_PER_TOKEN = 4

      class << self
        # Estimates the token count for a given string.
        #
        # @param text [String, nil] the text to estimate
        # @return [Integer] estimated token count (minimum 0)
        def estimate(text)
          return 0 if text.nil? || text.empty?

          (text.bytesize.to_f / CHARS_PER_TOKEN).ceil
        end

        # Estimates the token count for an array of messages by serializing
        # them to JSON first. Accounts for the structural overhead of message
        # formatting (role tags, separators, etc.).
        #
        # @param messages [Array<Hash>] messages in the API conversation format
        # @return [Integer] estimated token count (minimum 0)
        def estimate_messages(messages)
          return 0 if messages.nil? || messages.empty?

          json = JSON.generate(messages)
          estimate(json)
        end
      end
    end
  end
end
