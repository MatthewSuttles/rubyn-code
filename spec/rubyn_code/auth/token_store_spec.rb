# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Auth::TokenStore do
  let(:tmpdir) { Dir.mktmpdir('rubyn_auth_test_') }
  let(:tokens_file) { File.join(tmpdir, 'tokens.yml') }
  let(:credentials_file) { File.join(tmpdir, '.credentials.json') }

  before do
    stub_const('RubynCode::Config::Defaults::TOKENS_FILE', tokens_file)
    stub_const('RubynCode::Config::Defaults::HOME_DIR', tmpdir)
    stub_const('RubynCode::Config::Defaults::CLAUDE_CREDENTIALS_FILE', credentials_file)
    # Bypass macOS Keychain — without this, .load finds real Claude tokens
    # and the TOKENS_FILE stub becomes meaningless
    allow(described_class).to receive(:load_from_keychain).and_return(nil)
    # Ensure ANTHROPIC_API_KEY doesn't leak from the test environment
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY', nil).and_return(nil)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.save and .load' do
    it 'persists and retrieves tokens' do
      expires = Time.now + 3600
      described_class.save(access_token: 'abc', refresh_token: 'xyz', expires_at: expires)

      tokens = described_class.load
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

  describe '.valid?' do
    it 'returns true when token is fresh' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now + 3600)
      expect(described_class.valid?).to be true
    end

    it 'returns false when token is expired' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now - 60)
      expect(described_class.valid?).to be false
    end

    it 'returns false when no tokens file exists' do
      expect(described_class.valid?).to be false
    end
  end

  describe ".valid_tokens?" do
    it "returns true for a fresh oauth token" do
      tokens = { access_token: "a", expires_at: Time.now + 3600, type: :oauth }
      expect(described_class.valid_tokens?(tokens)).to be true
    end

    it "returns false for a token inside the expiry buffer" do
      tokens = { access_token: "a", expires_at: Time.now + 60, type: :oauth }
      expect(described_class.valid_tokens?(tokens)).to be false
    end

    it "returns true for an api key regardless of expiry" do
      tokens = { access_token: "a", expires_at: nil, type: :api_key }
      expect(described_class.valid_tokens?(tokens)).to be true
    end

    it "returns false for nil tokens" do
      expect(described_class.valid_tokens?(nil)).to be false
    end
  end

  describe '.clear!' do
    it 'removes the tokens file' do
      described_class.save(access_token: 'a', refresh_token: 'r', expires_at: Time.now)
      described_class.clear!
      expect(described_class.exists?).to be false
    end
  end

  describe '.load_for_provider' do
    it 'delegates to .load for anthropic' do
      described_class.save(access_token: 'abc', refresh_token: 'xyz', expires_at: Time.now + 3600)
      tokens = described_class.load_for_provider('anthropic')
      expect(tokens[:access_token]).to eq('abc')
    end

    it 'reads OPENAI_API_KEY for openai provider' do
      allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return('sk-openai-test')
      tokens = described_class.load_for_provider('openai')
      expect(tokens[:access_token]).to eq('sk-openai-test')
      expect(tokens[:type]).to eq(:api_key)
      expect(tokens[:source]).to eq(:env)
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

    it 'returns stored key before checking env var' do
      described_class.save_provider_key('groq', 'stored-key')
      tokens = described_class.load_for_provider('groq')
      expect(tokens[:access_token]).to eq('stored-key')
      expect(tokens[:source]).to eq(:stored)
    end

    it 'falls back to env when no stored key exists' do
      allow(ENV).to receive(:fetch).with('GROQ_API_KEY', nil).and_return('env-key')
      tokens = described_class.load_for_provider('groq')
      expect(tokens[:access_token]).to eq('env-key')
      expect(tokens[:source]).to eq(:env)
    end
  end

  describe '.save_provider_key and .load_provider_key' do
    it 'stores and retrieves a provider API key' do
      described_class.save_provider_key('groq', 'gsk-test-key')
      expect(described_class.load_provider_key('groq')).to eq('gsk-test-key')
    end

    it 'stores multiple provider keys' do
      described_class.save_provider_key('groq', 'gsk-key')
      described_class.save_provider_key('together', 'tog-key')
      expect(described_class.load_provider_key('groq')).to eq('gsk-key')
      expect(described_class.load_provider_key('together')).to eq('tog-key')
    end

    it 'returns nil for unknown providers' do
      expect(described_class.load_provider_key('unknown')).to be_nil
    end

    it 'does not clobber existing Anthropic tokens' do
      described_class.save(access_token: 'abc', refresh_token: 'xyz', expires_at: Time.now + 3600)
      described_class.save_provider_key('groq', 'gsk-key')

      tokens = described_class.load
      expect(tokens[:access_token]).to eq('abc')
      expect(described_class.load_provider_key('groq')).to eq('gsk-key')
    end

    it 'sets restrictive file permissions' do
      described_class.save_provider_key('groq', 'gsk-key')
      mode = File.stat(tokens_file).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it 'stores keys encrypted on disk' do
      described_class.save_provider_key('groq', 'gsk-secret')
      raw = YAML.safe_load_file(tokens_file)
      stored_value = raw.dig('provider_keys', 'groq')
      expect(stored_value).to start_with('enc:v1:')
      expect(stored_value).not_to include('gsk-secret')
    end

    it 'auto-migrates plaintext keys to encrypted on read' do
      # Simulate a pre-encryption tokens.yml with a plaintext key
      data = { 'provider_keys' => { 'groq' => 'gsk-plaintext' } }
      File.write(tokens_file, YAML.dump(data))

      # Reading should return the plaintext value
      expect(described_class.load_provider_key('groq')).to eq('gsk-plaintext')

      # And the file should now be encrypted
      raw = YAML.safe_load_file(tokens_file)
      expect(raw.dig('provider_keys', 'groq')).to start_with('enc:v1:')
    end

    it 'deletes only the named provider key' do
      described_class.save(access_token: 'oauth', refresh_token: 'refresh', expires_at: Time.now + 3600)
      described_class.save_provider_key('groq', 'gsk-key')
      described_class.save_provider_key('together', 'tog-key')

      expect(described_class.delete_provider_key('groq')).to be(true)
      expect(described_class.load_provider_key('groq')).to be_nil
      expect(described_class.load_provider_key('together')).to eq('tog-key')
      expect(described_class.load[:access_token]).to eq('oauth')
    end

    it 'reports false without creating a token file for an unknown provider' do
      FileUtils.rm_f(tokens_file)
      expect(described_class.delete_provider_key('missing')).to be(false)
      expect(File).not_to exist(tokens_file)
    end
  end

  describe '.load_from_credentials_file' do
    before do
      # Let the real method run
      allow(described_class).to receive(:load_from_credentials_file).and_call_original
    end

    let(:valid_credentials) do
      {
        'claudeAiOauth' => {
          'accessToken' => 'sk-ant-oat01-linux-test-token',
          'refreshToken' => 'sk-ant-ort01-linux-refresh',
          'expiresAt' => (Time.now.to_f * 1000 + 3_600_000).to_i
        }
      }
    end

    context 'when credentials file exists with valid OAuth data' do
      before do
        File.write(credentials_file, JSON.generate(valid_credentials))
        File.chmod(0o600, credentials_file)
      end

      it 'loads OAuth tokens from the credentials file' do
        tokens = described_class.load
        expect(tokens[:access_token]).to eq('sk-ant-oat01-linux-test-token')
        expect(tokens[:refresh_token]).to eq('sk-ant-ort01-linux-refresh')
        expect(tokens[:type]).to eq(:oauth)
        expect(tokens[:source]).to eq(:keychain)
      end

      it 'parses expiresAt from milliseconds to Time' do
        tokens = described_class.load
        expect(tokens[:expires_at]).to be_a(Time)
        expect(tokens[:expires_at]).to be_within(2).of(Time.now + 3600)
      end
    end

    context 'when credentials file does not exist' do
      it 'returns nil and falls through to next strategy' do
        expect(described_class.send(:load_from_credentials_file)).to be_nil
      end
    end

    context 'when credentials file has no claudeAiOauth key' do
      before do
        File.write(credentials_file, JSON.generate({ 'other' => 'data' }))
      end

      it 'returns nil' do
        expect(described_class.send(:load_from_credentials_file)).to be_nil
      end
    end

    context 'when credentials file has invalid JSON' do
      before do
        File.write(credentials_file, '{{not json}}')
      end

      it 'returns nil without raising' do
        expect(described_class.send(:load_from_credentials_file)).to be_nil
      end
    end

    context 'when credentials file has insecure permissions' do
      before do
        File.write(credentials_file, JSON.generate(valid_credentials))
        File.chmod(0o644, credentials_file)
      end

      it 'warns about insecure permissions' do
        expect { described_class.send(:load_from_credentials_file) }
          .to output(/WARNING.*#{Regexp.escape(credentials_file)}.*0644.*expected 0600/).to_stderr
      end

      it 'still loads the tokens despite the warning' do
        tokens = nil
        expect { tokens = described_class.send(:load_from_credentials_file) }.to output(anything).to_stderr
        expect(tokens[:access_token]).to eq('sk-ant-oat01-linux-test-token')
      end
    end
  end

  describe 'LOAD_STRATEGIES order' do
    it 'defines a scannable fallback chain' do
      expect(described_class::LOAD_STRATEGIES).to eq(%i[
        load_from_keychain
        load_from_credentials_file
        load_from_file
        load_from_env
      ])
    end
  end
end
