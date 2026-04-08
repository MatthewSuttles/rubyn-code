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

  describe ".load_from_keychain" do
    let(:credentials_path) { File.expand_path("~/.claude/.credentials.json") }

    let(:valid_credentials) do
      {
        "claudeAiOauth" => {
          "accessToken" => "sk-ant-oat01-linux-test-token",
          "refreshToken" => "sk-ant-ort01-linux-test-refresh",
          "expiresAt" => (Time.now.to_f * 1000 + 3_600_000).to_i,
          "scopes" => ["user:inference"],
          "subscriptionType" => "max"
        }
      }
    end

    before do
      # Remove the global stub so we test the real load_from_keychain
      allow(described_class).to receive(:load_from_keychain).and_call_original
    end

    context "on Linux" do
      before { stub_const("RUBY_PLATFORM", "x86_64-linux") }

      it "reads OAuth tokens from ~/.claude/.credentials.json" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(credentials_path).and_return(JSON.generate(valid_credentials))

        tokens = described_class.load
        expect(tokens[:access_token]).to eq("sk-ant-oat01-linux-test-token")
        expect(tokens[:refresh_token]).to eq("sk-ant-ort01-linux-test-refresh")
        expect(tokens[:type]).to eq(:oauth)
        expect(tokens[:source]).to eq(:keychain)
      end

      it "parses expiresAt as a Time object" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(credentials_path).and_return(JSON.generate(valid_credentials))

        tokens = described_class.load
        expect(tokens[:expires_at]).to be_a(Time)
        expect(tokens[:expires_at]).to be > Time.now
      end

      it "returns nil when credentials file does not exist" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(credentials_path).and_return(false)

        tokens = described_class.load
        expect(tokens).to be_nil
      end

      it "returns nil when credentials file has no claudeAiOauth key" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(credentials_path).and_return(JSON.generate({"other" => "data"}))

        tokens = described_class.load
        expect(tokens).to be_nil
      end

      it "returns nil when accessToken is missing" do
        creds = {"claudeAiOauth" => {"refreshToken" => "only-refresh"}}
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(credentials_path).and_return(JSON.generate(creds))

        tokens = described_class.load
        expect(tokens).to be_nil
      end

      it "returns nil on invalid JSON without raising" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(credentials_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(credentials_path).and_return("not valid json{{{")

        expect { described_class.load }.not_to raise_error
        expect(described_class.load).to be_nil
      end
    end

    context "on macOS" do
      before { stub_const("RUBY_PLATFORM", "arm64-darwin24") }

      it "reads from macOS Keychain" do
        allow(described_class).to receive(:`).and_return(JSON.generate(valid_credentials))

        tokens = described_class.load
        expect(tokens[:access_token]).to eq("sk-ant-oat01-linux-test-token")
        expect(tokens[:type]).to eq(:oauth)
        expect(tokens[:source]).to eq(:keychain)
      end

      it "returns nil when keychain returns empty output" do
        allow(described_class).to receive(:`).and_return("")

        tokens = described_class.load
        expect(tokens).to be_nil
      end
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
  end
end
