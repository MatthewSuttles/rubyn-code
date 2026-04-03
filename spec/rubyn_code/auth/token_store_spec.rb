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
end
