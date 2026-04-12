# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Auth::TokenStore do
  let(:tmpdir) { Dir.mktmpdir('rubyn_auth_test_') }
  let(:tokens_file) { File.join(tmpdir, 'tokens.yml') }

  before do
    stub_const('RubynCode::Config::Defaults::TOKENS_FILE', tokens_file)
    # Bypass real system credentials — without this, the chain finds actual
    # Claude Code tokens on the host and the TOKENS_FILE stub is meaningless.
    allow_any_instance_of(RubynCode::Auth::Strategies::Keychain).to receive(:call).and_return(nil)
    allow_any_instance_of(RubynCode::Auth::Strategies::CredentialsFile).to receive(:call).and_return(nil)
    # Prevent tests from passing for the wrong reason when the dev has
    # ANTHROPIC_API_KEY set in their shell (PR #42, Matthew's feedback).
    # Tests that need the env var can override this locally.
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY', nil).and_return(nil)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.save and .load_for_provider' do
    it 'persists and retrieves tokens for anthropic' do
      expires = Time.now + 3600
      described_class.save(access_token: 'abc', refresh_token: 'xyz', expires_at: expires)

      tokens = described_class.load_for_provider('anthropic')
      expect(tokens[:access_token]).to eq('abc')
      expect(tokens[:refresh_token]).to eq('xyz')
      expect(tokens[:expires_at]).to be_within(1).of(expires)
    end

    it 'sets restrictive file permissions' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now)
      mode = File.stat(tokens_file).mode & 0o777
      expect(mode).to eq(0o600)
    end
  end

  describe '.valid_for?' do
    it 'returns true when token is fresh' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now + 3600)
      expect(described_class.valid_for?('anthropic')).to be true
    end

    it 'returns false when token is expired' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now - 60)
      expect(described_class.valid_for?('anthropic')).to be false
    end

    it 'returns false when no tokens file exists' do
      expect(described_class.valid_for?('anthropic')).to be false
    end

    it 'returns true for api_key type (no expiration check)' do
      allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return('sk-test')
      expect(described_class.valid_for?('openai')).to be true
    end
  end

  describe '.access_token_for' do
    it 'returns just the token string' do
      described_class.save(access_token: 'my-token', refresh_token: 'r', expires_at: Time.now + 3600)
      expect(described_class.access_token_for('anthropic')).to eq('my-token')
    end

    it 'returns nil when no token exists' do
      expect(described_class.access_token_for('anthropic')).to be_nil
    end
  end

  describe '.clear!' do
    it 'removes the tokens file' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now)
      described_class.clear!
      expect(described_class.exists_for?('anthropic')).to be false
    end
  end

  describe '.load_for_provider' do
    it 'reads OPENAI_API_KEY for openai provider' do
      allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return('sk-openai-test')
      tokens = described_class.load_for_provider('openai')
      expect(tokens[:access_token]).to eq('sk-openai-test')
      expect(tokens[:type]).to eq(:api_key)
      expect(tokens[:source]).to eq(:env)
    end

    it 'reads GROQ_API_KEY for groq provider' do
      allow(ENV).to receive(:fetch).with('GROQ_API_KEY', nil).and_return('gsk-test')
      tokens = described_class.load_for_provider('groq')
      expect(tokens[:access_token]).to eq('gsk-test')
    end

    it 'returns nil when provider env var is not set' do
      allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return(nil)
      tokens = described_class.load_for_provider('openai')
      expect(tokens).to be_nil
    end

    it 'constructs env key from provider name for unknown providers' do
      allow(ENV).to receive(:fetch).with('MYAI_API_KEY', nil).and_return('key-123')
      tokens = described_class.load_for_provider('myai')
      expect(tokens[:access_token]).to eq('key-123')
    end
  end

  describe 'strategy chain for anthropic' do
    let(:valid_keychain_creds) do
      {
        'claudeAiOauth' => {
          'accessToken' => 'sk-ant-from-keychain',
          'refreshToken' => 'sk-ant-refresh-keychain',
          'expiresAt' => ((Time.now.to_f * 1000) + 3_600_000).to_i
        }
      }
    end

    let(:valid_credentials_file_creds) do
      {
        'claudeAiOauth' => {
          'accessToken' => 'sk-ant-from-credentials-file',
          'refreshToken' => 'sk-ant-refresh-credentials-file',
          'expiresAt' => ((Time.now.to_f * 1000) + 3_600_000).to_i
        }
      }
    end

    it 'prefers keychain over credentials file on macOS' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin24')
      # Override the global stub — let the real keychain strategy run, but
      # intercept the `security` CLI call.
      allow_any_instance_of(RubynCode::Auth::Strategies::Keychain).to receive(:call).and_call_original
      allow_any_instance_of(RubynCode::Auth::Strategies::Keychain)
        .to receive(:read_keychain).and_return(JSON.generate(valid_keychain_creds))

      tokens = described_class.load_for_provider('anthropic')
      expect(tokens[:access_token]).to eq('sk-ant-from-keychain')
      expect(tokens[:source]).to eq(:keychain)
    end

    it 'falls back to credentials file when keychain is not available' do
      # Override the CredentialsFile stub to run the real strategy
      allow_any_instance_of(RubynCode::Auth::Strategies::CredentialsFile).to receive(:call).and_call_original

      credentials_path = File.expand_path('~/.claude/.credentials.json')
      stub_const('RubynCode::Config::Defaults::CLAUDE_CREDENTIALS_FILE', credentials_path)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(credentials_path).and_return(true)
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(credentials_path).and_return(instance_double(File::Stat, mode: 0o100600))
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(credentials_path).and_return(JSON.generate(valid_credentials_file_creds))

      tokens = described_class.load_for_provider('anthropic')
      expect(tokens[:access_token]).to eq('sk-ant-from-credentials-file')
      expect(tokens[:source]).to eq(:credentials_file)
    end

    it 'falls back to local file when previous strategies fail' do
      described_class.save(access_token: 'sk-from-local-file', refresh_token: 'rf', expires_at: Time.now + 3600)

      tokens = described_class.load_for_provider('anthropic')
      expect(tokens[:access_token]).to eq('sk-from-local-file')
      expect(tokens[:source]).to eq(:file)
    end

    it 'falls back to env var when all other strategies fail' do
      # Ensure no local tokens file
      File.delete(tokens_file) if File.exist?(tokens_file)

      allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY', nil).and_return('sk-from-env')

      tokens = described_class.load_for_provider('anthropic')
      expect(tokens[:access_token]).to eq('sk-from-env')
      expect(tokens[:type]).to eq(:api_key)
      expect(tokens[:source]).to eq(:env)
    end
  end
end
