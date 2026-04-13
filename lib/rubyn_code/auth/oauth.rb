# frozen_string_literal: true

require 'securerandom'
require 'digest'
require 'base64'
require 'faraday'
require 'json'

module RubynCode
  module Auth
    module OAuth
      # Base class for OAuth 2.0 + PKCE flow.
      # Subclasses provide provider-specific configuration (client_id, urls, scopes, etc.).
      class Base
        class StateMismatchError < RubynCode::AuthenticationError
        end

        class TokenExchangeError < RubynCode::AuthenticationError
        end

        class RefreshError < RubynCode::AuthenticationError
        end

        VERIFIER_LENGTH = 43

        # Subclasses must override these methods
        def provider_name
          raise NotImplementedError, "#{self.class} must implement #provider_name"
        end

        def client_id
          raise NotImplementedError, "#{self.class} must implement #client_id"
        end

        def redirect_uri
          raise NotImplementedError, "#{self.class} must implement #redirect_uri"
        end

        def authorize_url
          raise NotImplementedError, "#{self.class} must implement #authorize_url"
        end

        def token_url
          raise NotImplementedError, "#{self.class} must implement #token_url"
        end

        def scopes
          raise NotImplementedError, "#{self.class} must implement #scopes"
        end

        def authenticate!
          code_verifier = generate_code_verifier
          code_challenge = derive_code_challenge(code_verifier)
          state = SecureRandom.hex(24)

          result = perform_browser_auth(code_challenge, state)
          validate_state!(result[:state], state)

          tokens = exchange_code(code: result[:code], code_verifier:)
          persist_tokens(tokens)
          tokens
        end

        def refresh!
          stored = TokenStore.load_for_provider(provider_name)
          raise RefreshError, 'No stored refresh token available' unless stored&.dig(:refresh_token)

          response = post_refresh_request(stored[:refresh_token])
          raise_refresh_error(response) unless response.success?

          body = parse_json(response.body)
          raise RefreshError, 'Invalid response from token endpoint' unless body

          save_refreshed_tokens(body, stored)
        end

        private

        def generate_code_verifier
          SecureRandom.urlsafe_base64(32).slice(0, VERIFIER_LENGTH)
        end

        def derive_code_challenge(verifier)
          digest = Digest::SHA256.digest(verifier)
          Base64.urlsafe_encode64(digest, padding: false)
        end

        def build_authorization_url(code_challenge:, state:)
          params = URI.encode_www_form(
            response_type: 'code',
            client_id: client_id,
            redirect_uri: redirect_uri,
            scope: scopes,
            state: state,
            code_challenge: code_challenge,
            code_challenge_method: 'S256'
          )

          "#{authorize_url}?#{params}"
        end

        def exchange_code(code:, code_verifier:)
          response = post_code_exchange(code, code_verifier)
          raise_exchange_error(response) unless response.success?

          body = parse_json(response.body)
          raise TokenExchangeError, 'Invalid response from token endpoint' unless body

          { access_token: body['access_token'], refresh_token: body['refresh_token'], expires_in: body['expires_in'] }
        end

        def post_code_exchange(code, code_verifier)
          http_client.post(token_url) do |req|
            req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(
              grant_type: 'authorization_code', client_id: client_id,
              code: code, redirect_uri: redirect_uri, code_verifier: code_verifier
            )
          end
        end

        def raise_exchange_error(response)
          body = parse_json(response.body)
          error_msg = body&.dig('error_description') || body&.dig('error') || response.body
          raise TokenExchangeError, "Code exchange failed (#{response.status}): #{error_msg}"
        end

        def perform_browser_auth(code_challenge, state)
          auth_url = build_authorization_url(code_challenge:, state:)
          callback_server = Server.new
          open_browser(auth_url)
          callback_server.wait_for_callback(timeout: 120)
        end

        def validate_state!(received, expected)
          return if secure_compare(received, expected)

          raise StateMismatchError, 'OAuth state parameter mismatch — possible CSRF attack'
        end

        def persist_tokens(tokens)
          TokenStore.save(
            access_token: tokens[:access_token],
            refresh_token: tokens[:refresh_token],
            expires_at: Time.now + tokens[:expires_in].to_i
          )
        end

        def post_refresh_request(refresh_token)
          http_client.post(token_url) do |req|
            req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            req.body = URI.encode_www_form(
              grant_type: 'refresh_token',
              client_id: client_id,
              refresh_token: refresh_token
            )
          end
        end

        def raise_refresh_error(response)
          body = parse_json(response.body)
          error_msg = body&.dig('error_description') || body&.dig('error') || response.body
          raise RefreshError, "Token refresh failed (#{response.status}): #{error_msg}"
        end

        def save_refreshed_tokens(body, stored)
          effective_refresh = body['refresh_token'] || stored[:refresh_token]

          TokenStore.save(
            access_token: body['access_token'],
            refresh_token: effective_refresh,
            expires_at: Time.now + body['expires_in'].to_i
          )

          {
            access_token: body['access_token'],
            refresh_token: effective_refresh,
            expires_in: body['expires_in']
          }
        end

        def open_browser(url)
          launcher = case RUBY_PLATFORM
                     when /darwin/       then 'open'
                     when /linux/        then 'xdg-open'
                     when /mingw|mswin/  then 'start'
                     end
          launcher ||= 'xdg-open'

          system(launcher, url, exception: false)
        end

        def http_client
          @http_client ||= Faraday.new do |f|
            f.options.timeout = 30
            f.options.open_timeout = 10
            f.adapter Faraday.default_adapter
          end
        end

        def parse_json(body)
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end

        def secure_compare(left, right) # rubocop:disable Naming/PredicateMethod
          return false if left.nil? || right.nil?
          return false unless left.bytesize == right.bytesize

          left_bytes = left.unpack('C*')
          right_bytes = right.unpack('C*')
          left_bytes.zip(right_bytes).reduce(0) { |acc, (lhs, rhs)| acc | (lhs ^ rhs) }.zero?
        end
      end

      # Anthropic-specific OAuth implementation.
      class Anthropic < Base
        def provider_name
          'anthropic'
        end

        def client_id
          Config::Defaults::OAUTH_CLIENT_ID
        end

        def redirect_uri
          Config::Defaults::OAUTH_REDIRECT_URI
        end

        def authorize_url
          Config::Defaults::OAUTH_AUTHORIZE_URL
        end

        def token_url
          Config::Defaults::OAUTH_TOKEN_URL
        end

        def scopes
          Config::Defaults::OAUTH_SCOPES
        end
      end

      # Backward compatibility alias
      AnthropicOAuth = Anthropic
    end
  end
end
