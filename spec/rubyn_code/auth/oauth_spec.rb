# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Auth::AnthropicOAuth do
  subject(:oauth) { described_class.new }

  let(:token_url) { RubynCode::Config::Defaults::OAUTH_TOKEN_URL }
  let(:authorize_url) { RubynCode::Config::Defaults::OAUTH_AUTHORIZE_URL }
  let(:client_id) { RubynCode::Config::Defaults::OAUTH_CLIENT_ID }
  let(:redirect_uri) { RubynCode::Config::Defaults::OAUTH_REDIRECT_URI }
  let(:scopes) { RubynCode::Config::Defaults::OAUTH_SCOPES }

  let(:mock_server) { instance_double(RubynCode::Auth::Server) }
  let(:state) { SecureRandom.hex(24) }
  let(:auth_code) { 'test-authorization-code' }

  let(:token_response_body) do
    {
      'access_token' => 'access-token-123',
      'refresh_token' => 'refresh-token-456',
      'expires_in' => 3600
    }
  end

  before do
    allow(RubynCode::Auth::Server).to receive(:new).and_return(mock_server)
    allow(RubynCode::Auth::TokenStore).to receive(:save)
    allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).with('anthropic')
    allow(oauth).to receive(:system)
    allow(SecureRandom).to receive(:hex).with(24).and_return(state)
  end

  describe '#authenticate!' do
    before do
      allow(mock_server).to receive(:wait_for_callback)
        .with(timeout: 120)
        .and_return({ code: auth_code, state: state })

      stub_request(:post, token_url)
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: token_response_body.to_json
        )
    end

    context 'happy path' do
      it 'returns a token hash with access_token, refresh_token, and expires_in' do
        result = oauth.authenticate!

        expect(result).to include(
          access_token: 'access-token-123',
          refresh_token: 'refresh-token-456',
          expires_in: 3600
        )
      end
    end

    context 'when the state parameter does not match' do
      before do
        allow(mock_server).to receive(:wait_for_callback)
          .with(timeout: 120)
          .and_return({ code: auth_code, state: 'wrong-state-value' })
      end

      it 'raises StateMismatchError' do
        expect { oauth.authenticate! }.to raise_error(
          described_class::StateMismatchError,
          /state parameter mismatch/
        )
      end
    end

    context 'when token exchange fails with HTTP 400' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 400,
            headers: { 'Content-Type' => 'application/json' },
            body: { 'error' => 'invalid_grant', 'error_description' => 'Code has expired' }.to_json
          )
      end

      it 'raises TokenExchangeError with the error description' do
        expect { oauth.authenticate! }.to raise_error(
          described_class::TokenExchangeError,
          /Code exchange failed \(400\): Code has expired/
        )
      end
    end

    context 'when token exchange returns invalid JSON' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: 'not-valid-json{{'
          )
      end

      it 'raises TokenExchangeError about invalid response' do
        expect { oauth.authenticate! }.to raise_error(
          described_class::TokenExchangeError,
          /Invalid response from token endpoint/
        )
      end
    end

    context 'when token exchange succeeds' do
      it 'saves tokens to TokenStore with correct parameters' do
        freeze_time = Time.now
        allow(Time).to receive(:now).and_return(freeze_time)

        oauth.authenticate!

        expect(RubynCode::Auth::TokenStore).to have_received(:save).with(
          access_token: 'access-token-123',
          refresh_token: 'refresh-token-456',
          expires_at: freeze_time + 3600
        )
      end
    end

    context 'browser opening' do
      it 'opens the browser with the correct authorization URL containing PKCE params' do
        oauth.authenticate!

        expect(oauth).to have_received(:system) do |_launcher, url, **_opts|
          uri = URI.parse(url)
          expect(uri.to_s).to start_with(authorize_url)

          params = URI.decode_www_form(uri.query).to_h
          expect(params['response_type']).to eq('code')
          expect(params['client_id']).to eq(client_id)
          expect(params['redirect_uri']).to eq(redirect_uri)
          expect(params['scope']).to eq(scopes)
          expect(params['state']).to eq(state)
          expect(params['code_challenge']).not_to be_nil
          expect(params['code_challenge_method']).to eq('S256')
        end
      end
    end

    context 'PKCE code verifier and challenge' do
      it 'generates a code verifier of exactly 43 characters' do
        captured_verifier = nil

        allow(oauth).to receive(:system) do |_launcher, url, **_opts|
          # We can't directly capture the verifier, but we can verify it
          # through the code_challenge sent in the URL and the token exchange body
        end

        # Capture the code_verifier from the token exchange request
        stub_request(:post, token_url)
          .with { |request|
            params = URI.decode_www_form(request.body).to_h
            captured_verifier = params['code_verifier']
            true
          }
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: token_response_body.to_json
          )

        oauth.authenticate!

        expect(captured_verifier).not_to be_nil
        expect(captured_verifier.length).to eq(43)
      end

      it 'sends a code challenge that is the S256 hash of the code verifier' do
        captured_verifier = nil
        captured_challenge = nil

        stub_request(:post, token_url)
          .with { |request|
            params = URI.decode_www_form(request.body).to_h
            captured_verifier = params['code_verifier']
            true
          }
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: token_response_body.to_json
          )

        allow(oauth).to receive(:system) do |_launcher, url, **_opts|
          params = URI.decode_www_form(URI.parse(url).query).to_h
          captured_challenge = params['code_challenge']
        end

        oauth.authenticate!

        expected_challenge = Base64.urlsafe_encode64(
          Digest::SHA256.digest(captured_verifier),
          padding: false
        )
        expect(captured_challenge).to eq(expected_challenge)
      end
    end

    context 'when the callback returns nil state' do
      before do
        allow(mock_server).to receive(:wait_for_callback)
          .with(timeout: 120)
          .and_return({ code: auth_code, state: nil })
      end

      it 'raises StateMismatchError' do
        expect { oauth.authenticate! }.to raise_error(
          described_class::StateMismatchError
        )
      end
    end

    context 'when token exchange fails with non-JSON error body' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 500,
            headers: { 'Content-Type' => 'text/plain' },
            body: 'Internal Server Error'
          )
      end

      it 'raises TokenExchangeError with the raw body as message' do
        expect { oauth.authenticate! }.to raise_error(
          described_class::TokenExchangeError,
          /Code exchange failed \(500\): Internal Server Error/
        )
      end
    end
  end

  describe '#refresh!' do
    let(:stored_tokens) do
      {
        access_token: 'old-access-token',
        refresh_token: 'old-refresh-token',
        expires_at: Time.now - 60
      }
    end

    let(:refresh_response_body) do
      {
        'access_token' => 'new-access-token',
        'refresh_token' => 'new-refresh-token',
        'expires_in' => 7200
      }
    end

    before do
      allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).with('anthropic').and_return(stored_tokens)
    end

    context 'happy path' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: refresh_response_body.to_json
          )
      end

      it 'exchanges the stored refresh token and returns new tokens' do
        result = oauth.refresh!

        expect(result).to eq(
          access_token: 'new-access-token',
          refresh_token: 'new-refresh-token',
          expires_in: 7200
        )
      end

      it 'sends the correct refresh token request' do
        oauth.refresh!

        expect(
          a_request(:post, token_url)
            .with { |req|
              params = URI.decode_www_form(req.body).to_h
              params['grant_type'] == 'refresh_token' &&
                params['client_id'] == client_id &&
                params['refresh_token'] == 'old-refresh-token'
            }
        ).to have_been_made.once
      end

      it 'saves new tokens to TokenStore' do
        freeze_time = Time.now
        allow(Time).to receive(:now).and_return(freeze_time)

        oauth.refresh!

        expect(RubynCode::Auth::TokenStore).to have_received(:save).with(
          access_token: 'new-access-token',
          refresh_token: 'new-refresh-token',
          expires_at: freeze_time + 7200
        )
      end
    end

    context 'when no stored token is available' do
      before do
        allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).with('anthropic').and_return(nil)
      end

      it 'raises RefreshError' do
        expect { oauth.refresh! }.to raise_error(
          described_class::RefreshError,
          /No stored refresh token available/
        )
      end
    end

    context 'when stored token has no refresh_token' do
      before do
        allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).with('anthropic').and_return(
          { access_token: 'some-token', refresh_token: nil }
        )
      end

      it 'raises RefreshError' do
        expect { oauth.refresh! }.to raise_error(
          described_class::RefreshError,
          /No stored refresh token available/
        )
      end
    end

    context 'when HTTP request fails' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 401,
            headers: { 'Content-Type' => 'application/json' },
            body: { 'error' => 'invalid_grant', 'error_description' => 'Refresh token revoked' }.to_json
          )
      end

      it 'raises RefreshError with status and error message' do
        expect { oauth.refresh! }.to raise_error(
          described_class::RefreshError,
          /Token refresh failed \(401\): Refresh token revoked/
        )
      end
    end

    context 'when HTTP request fails with non-JSON body' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 503,
            headers: { 'Content-Type' => 'text/plain' },
            body: 'Service Unavailable'
          )
      end

      it 'raises RefreshError with the raw body' do
        expect { oauth.refresh! }.to raise_error(
          described_class::RefreshError,
          /Token refresh failed \(503\): Service Unavailable/
        )
      end
    end

    context 'when response body is invalid JSON' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: '{{not json}}'
          )
      end

      it 'raises RefreshError about invalid response' do
        expect { oauth.refresh! }.to raise_error(
          described_class::RefreshError,
          /Invalid response from token endpoint/
        )
      end
    end

    context 'when the new response does not include a refresh_token' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: {
              'access_token' => 'new-access-token',
              'refresh_token' => nil,
              'expires_in' => 7200
            }.to_json
          )
      end

      it 'preserves the old refresh_token in the result' do
        result = oauth.refresh!

        expect(result[:refresh_token]).to eq('old-refresh-token')
      end

      it 'saves with the old refresh_token' do
        oauth.refresh!

        expect(RubynCode::Auth::TokenStore).to have_received(:save).with(
          hash_including(refresh_token: 'old-refresh-token')
        )
      end
    end
  end

  describe 'private method behavior via public API' do
    describe 'secure_compare (via state validation)' do
      before do
        allow(mock_server).to receive(:wait_for_callback)
          .with(timeout: 120)
          .and_return({ code: auth_code, state: state })

        stub_request(:post, token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: token_response_body.to_json
          )
      end

      context 'when states differ in length' do
        before do
          allow(mock_server).to receive(:wait_for_callback)
            .with(timeout: 120)
            .and_return({ code: auth_code, state: 'short' })
        end

        it 'raises StateMismatchError' do
          expect { oauth.authenticate! }.to raise_error(
            described_class::StateMismatchError
          )
        end
      end

      context 'when states match' do
        it 'does not raise' do
          expect { oauth.authenticate! }.not_to raise_error
        end
      end
    end

    describe 'open_browser' do
      before do
        allow(mock_server).to receive(:wait_for_callback)
          .with(timeout: 120)
          .and_return({ code: auth_code, state: state })

        stub_request(:post, token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: token_response_body.to_json
          )
      end

      it 'calls system with the authorization URL' do
        oauth.authenticate!

        expect(oauth).to have_received(:system).with(
          anything,
          a_string_starting_with(authorize_url),
          exception: false
        )
      end
    end
  end
end
