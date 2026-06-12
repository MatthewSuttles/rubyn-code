# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Cached access to the Anthropic credential.
      #
      # TokenStore.load shells out to the macOS keychain, so the loaded
      # tokens are cached per adapter instance. The cache drops itself once
      # the token nears expiry (picking up an externally refreshed
      # credential) and must be invalidated on 401 responses.
      module TokenCaching
        private

        def oauth_token?
          return @oauth_token unless @oauth_token.nil?

          @oauth_token = access_token.include?('sk-ant-oat')
        end

        def ensure_valid_token!
          return if Auth::TokenStore.valid_tokens?(tokens)

          raise Client::AuthExpiredError,
                'No valid authentication. Run `rubyn-code --auth` or set ANTHROPIC_API_KEY.'
        end

        def access_token
          token = tokens&.fetch(:access_token, nil)
          raise Client::AuthExpiredError, 'No stored access token' unless token

          token
        end

        def tokens
          invalidate_token_cache! if token_cache_stale?
          @tokens ||= Auth::TokenStore.load
        end

        def token_cache_stale?
          expires_at = @tokens&.fetch(:expires_at, nil)
          return false unless expires_at

          expires_at <= Time.now + Auth::TokenStore::EXPIRY_BUFFER_SECONDS
        end

        def invalidate_token_cache!
          @tokens = nil
          @oauth_token = nil
        end
      end
    end
  end
end
