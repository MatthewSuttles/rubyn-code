# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "tmpdir"
require "fileutils"

RSpec.describe RubynCode::IDE::Handlers::ConfigSetHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }
  let(:tmp_dir) { Dir.mktmpdir("rubyn-code-test") }
  let(:config_path) { File.join(tmp_dir, "config.yml") }

  before do
    allow(RubynCode::Config::Settings).to receive(:new).and_wrap_original do |_orig, **kwargs|
      _orig.call(config_path: config_path, **kwargs.except(:config_path))
    end
    allow(server).to receive(:notify)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "updating a valid key" do
    it "updates a string key and persists" do
      result = handler.call({ "key" => "model", "value" => "gpt-5.4" })

      expect(result["updated"]).to eq(true)
      expect(result["key"]).to eq("model")
      expect(result["value"]).to eq("gpt-5.4")

      # Verify persistence
      persisted = YAML.safe_load(File.read(config_path))
      expect(persisted["model"]).to eq("gpt-5.4")
    end

    it "updates a numeric key and persists" do
      result = handler.call({ "key" => "max_iterations", "value" => 50 })

      expect(result["updated"]).to eq(true)
      expect(result["value"]).to eq(50)
    end

    it "coerces string-encoded numbers to numeric types" do
      result = handler.call({ "key" => "max_iterations", "value" => "25" })

      expect(result["updated"]).to eq(true)
      expect(result["value"]).to eq(25)
    end

    it "coerces string-encoded floats for budget keys" do
      result = handler.call({ "key" => "session_budget_usd", "value" => "5.50" })

      expect(result["updated"]).to eq(true)
      expect(result["value"]).to eq(5.50)
    end
  end

  describe "rejecting disallowed keys" do
    it "rejects an oauth key" do
      result = handler.call({ "key" => "oauth_client_id", "value" => "secret" })

      expect(result["updated"]).to eq(false)
      expect(result["error"]).to include("Unknown config key: oauth_client_id")
    end

    it "rejects a completely unknown key" do
      result = handler.call({ "key" => "nonexistent_key", "value" => "anything" })

      expect(result["updated"]).to eq(false)
      expect(result["error"]).to include("Unknown config key: nonexistent_key")
    end
  end

  describe "config/changed notification" do
    it "sends a config/changed notification after successful update" do
      handler.call({ "key" => "provider", "value" => "openai" })

      expect(server).to have_received(:notify).with(
        "config/changed",
        { "key" => "provider", "value" => "openai" }
      )
    end

    it "does not send notification when key is rejected" do
      handler.call({ "key" => "bogus", "value" => "whatever" })

      expect(server).not_to have_received(:notify)
    end
  end
end
