# frozen_string_literal: true

module RubynCode
  module Auth
    # Immutable result object for a successful token load.
    # Validates the contract that all strategies must follow.
    class TokenResult
      attr_reader :access_token, :refresh_token, :expires_at, :type, :source

      # @param access_token [String] the API key or OAuth token (required, non-empty)
      # @param refresh_token [String, nil] OAuth refresh token (optional)
      # @param expires_at [Time, nil] OAuth token expiration (optional)
      # @param type [Symbol] :oauth or :api_key (required)
      # @param source [Symbol] where the token came from (required, for debugging)
      # @raise [ArgumentError] if contract is violated
      def initialize(access_token:, type:, source:, refresh_token: nil, expires_at: nil)
        @access_token = validate_token!(access_token)
        @refresh_token = refresh_token
        @expires_at = expires_at
        @type = validate_type!(type)
        @source = validate_source!(source)
      end

      # Convert to a hash (for backward compatibility with existing code).
      #
      # @return [Hash]
      def to_h
        {
          access_token: @access_token,
          refresh_token: @refresh_token,
          expires_at: @expires_at,
          type: @type,
          source: @source
        }
      end

      private

      def validate_token!(token)
        return token if token.is_a?(String) && !token.empty?

        raise ArgumentError, "access_token must be a non-empty String, got #{token.inspect}"
      end

      def validate_type!(type)
        return type if %i[oauth api_key].include?(type)

        raise ArgumentError, "type must be :oauth or :api_key, got #{type.inspect}"
      end

      def validate_source!(source)
        return source if source.is_a?(Symbol)

        raise ArgumentError, "source must be a Symbol, got #{source.inspect}"
      end
    end
  end
end
