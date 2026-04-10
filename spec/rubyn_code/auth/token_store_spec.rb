# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe RubynCode::Auth::TokenStore do
  let(:tmpdir) { Dir.mktmpdir("rubyn_auth_test_") }
  let(:tokens_file) { File.join(tmpdir, "tokens.yml") }

  before do
    stub_const("RubynCode::Config::Defaults::TOKENS_FILE", tokens_file)
    # Bypass macOS Keychain — without this, .load finds real Claude tokens
    # and the TOKENS_FILE stub becomes meaningless
    allow(described_class).to receive(:load_from_keychain).and_return(nil)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe ".save and .load" do
    it "persists and retrieves tokens" do
      expires = Time.now + 3600
      described_class.save(access_token: "abc", refresh_token: "xyz", expires_at: expires)

      tokens = described_class.load
      expect(tokens[:access_token]).to eq("abc")
      expect(tokens[:refresh_token]).to eq("xyz")
      expect(tokens[:expires_at]).to be_within(1).of(expires)
    end

    it "sets restrictive file permissions" do
      described_class.save(access_token: "a", refresh_token: "r", expires_at: Time.now)
      mode = File.stat(tokens_file).mode & 0o777
      expect(mode).to eq(0o600)
    end
  end

  describe ".valid?" do
    it "returns true when token is fresh" do
      described_class.save(access_token: "a", refresh_token: "r", expires_at: Time.now + 3600)
      expect(described_class.valid?).to be true
    end

    it "returns false when token is expired" do
      described_class.save(access_token: "a", refresh_token: "r", expires_at: Time.now - 60)
      expect(described_class.valid?).to be false
    end

    it "returns false when no tokens file exists" do
      expect(described_class.valid?).to be false
    end
  end

  describe ".clear!" do
    it "removes the tokens file" do
      described_class.save(access_token: "a", refresh_token: "r", expires_at: Time.now)
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
  end
end
