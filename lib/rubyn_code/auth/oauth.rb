# frozen_string_literal: true

require 'securerandom'
require 'digest'
require 'base64'
require 'faraday'
require 'json'

module RubynCode
  module Auth
    class OAuth
      class StateMismatchError < RubynCode::AuthenticationError
      end

      class TokenExchangeError < RubynCode::AuthenticationError
      end

      class RefreshError < RubynCode::AuthenticationError
      end

      VERIFIER_LENGTH = 43

      def authenticate!
        code_verifier = generate_code_verifier
        code_challenge = derive_code_challenge(code_verifier)
        state = SecureRandom.hex(24)

        auth_url = build_authorization_url(code_challenge:, state:)

        callback_server = Server.new
        open_browser(auth_url)

        result = callback_server.wait_for_callback(timeout: 120)

        unless secure_compare(result[:state], state)
          raise StateMismatchError, 'OAuth state parameter mismatch — possible CSRF attack'
        end

        tokens = exchange_code(code: result[:code], code_verifier:)

        TokenStore.save(
          access_token: tokens[:access_token],
          refresh_token: tokens[:refresh_token],
          expires_at: Time.now + tokens[:expires_in].to_i
        )

        tokens
      end

      def refresh!
        stored = TokenStore.load
        raise RefreshError, 'No stored refresh token available' unless stored&.dig(:refresh_token)

        response = http_client.post(token_url) do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = URI.encode_www_form(
            grant_type: 'refresh_token',
            client_id: client_id,
            refresh_token: stored[:refresh_token]
          )
        end

        unless response.success?
          body = parse_json(response.body)
          error_msg = body&.dig('error_description') || body&.dig('error') || response.body
          raise RefreshError, "Token refresh failed (#{response.status}): #{error_msg}"
        end

        body = parse_json(response.body)
        raise RefreshError, 'Invalid response from token endpoint' unless body

        TokenStore.save(
          access_token: body['access_token'],
          refresh_token: body['refresh_token'] || stored[:refresh_token],
          expires_at: Time.now + body['expires_in'].to_i
        )

        {
          access_token: body['access_token'],
          refresh_token: body['refresh_token'] || stored[:refresh_token],
          expires_in: body['expires_in']
        }
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
        response = http_client.post(token_url) do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = URI.encode_www_form(
            grant_type: 'authorization_code',
            client_id: client_id,
            code: code,
            redirect_uri: redirect_uri,
            code_verifier: code_verifier
          )
        end

        unless response.success?
          body = parse_json(response.body)
          error_msg = body&.dig('error_description') || body&.dig('error') || response.body
          raise TokenExchangeError, "Code exchange failed (#{response.status}): #{error_msg}"
        end

        body = parse_json(response.body)
        raise TokenExchangeError, 'Invalid response from token endpoint' unless body

        {
          access_token: body['access_token'],
          refresh_token: body['refresh_token'],
          expires_in: body['expires_in']
        }
      end

      def open_browser(url)
        launcher = case RUBY_PLATFORM
                   when /darwin/  then 'open'
                   when /linux/   then 'xdg-open'
                   when /mingw|mswin/ then 'start'
                   else 'xdg-open'
                   end

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

      def secure_compare(a, b)
        return false if a.nil? || b.nil?
        return false unless a.bytesize == b.bytesize

        l = a.unpack('C*')
        r = b.unpack('C*')
        l.zip(r).reduce(0) { |acc, (x, y)| acc | (x ^ y) }.zero?
      end

      def client_id     = Config::Defaults::OAUTH_CLIENT_ID
      def redirect_uri  = Config::Defaults::OAUTH_REDIRECT_URI
      def authorize_url = Config::Defaults::OAUTH_AUTHORIZE_URL
      def token_url     = Config::Defaults::OAUTH_TOKEN_URL
      def scopes        = Config::Defaults::OAUTH_SCOPES
    end
  end
end
