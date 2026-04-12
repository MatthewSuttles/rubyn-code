# frozen_string_literal: true

require_relative '../token_result'

module RubynCode
  module Auth
    module Strategies
      # Abstract base class for token loading strategies.
      #
      # Each strategy is responsible for:
      #   1. Returning nil if it cannot produce a token (missing file,
      #      wrong platform, empty env var, etc.)
      #   2. Rescuing its own exceptions — the chain must never crash.
      #   3. Returning a TokenResult on success.
      #
      # Each strategy MUST define:
      #   - SOURCE (Symbol) — the identifier returned in TokenResult.source
      #   - display_name (String) — human-readable name for "Authenticated via X"
      #   - setup_hint (String|nil) — how to set up this auth method (nil if not applicable)
      class Base
        # @return [TokenResult, nil]
        def call
          raise NotImplementedError, "#{self.class} must implement #call"
        end

        # Human-readable name for "Authenticated via X" messages.
        # Must be overridden in subclasses.
        #
        # @return [String]
        def self.display_name
          raise NotImplementedError, "#{self} must define self.display_name"
        end

        # Hint shown when no auth is found, describing how to set up this strategy.
        # Return nil if this strategy should not be advertised (e.g., platform-specific).
        #
        # @return [String, nil]
        def self.setup_hint
          nil
        end

        protected

        # Builds a TokenResult from a raw hash. Returns nil if the hash
        # fails validation, so strategies don't have to rescue ArgumentError.
        #
        # @return [TokenResult, nil]
        def build_result(**attrs)
          TokenResult.new(**attrs)
        rescue ArgumentError => e
          RubynCode::Debug.warn("[#{self.class.name}] invalid token result: #{e.message}") if defined?(RubynCode::Debug)
          nil
        end
      end
    end
  end
end
