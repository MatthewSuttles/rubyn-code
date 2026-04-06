# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Shared JSON parsing for adapters and streaming parsers.
      # Swallows parse errors and returns nil — callers decide how to handle.
      module JsonParsing
        private

        def parse_json(str)
          return nil if str.nil? || (str.respond_to?(:strip) && str.strip.empty?)

          JSON.parse(str)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
