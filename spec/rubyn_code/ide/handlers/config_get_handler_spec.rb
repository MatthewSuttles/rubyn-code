# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "tmpdir"
require "fileutils"

RSpec.describe RubynCode::IDE::Handlers::ConfigGetHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }
  let(:tmp_dir) { Dir.mktmpdir("rubyn-code-test") }
  let(:config_path) { File.join(tmp_dir, "config.yml") }

  before do
    allow(RubynCode::Config::Settings).to receive(:new).and_wrap_original do |_orig, **kwargs|
      _orig.call(config_path: config_path, **kwargs.except(:config_path))
    end
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "all settings (no key provided)" do
    it "returns a settings hash with all exposed keys" do
      result = handler.call({})

      expect(result).to have_key("settings")
      expect(result).to have_key("providers")

      described_class::EXPOSED_KEYS.each do |key|
        expect(result["settings"]).to have_key(key)
        expect(result["settings"][key]).to have_key("value")
        expect(result["settings"][key]).to have_key("default")
      end
    end

    it "returns default values when nothing is explicitly set" do
      result = handler.call({})

      expect(result["settings"]["provider"]["value"]).to eq(
        RubynCode::Config::Defaults::DEFAULT_PROVIDER
      )
      expect(result["settings"]["provider"]["default"]).to eq(
        RubynCode::Config::Defaults::DEFAULT_PROVIDER
      )
    end

    it "includes providers in the response" do
      result = handler.call({})

      expect(result["providers"]).to be_a(Hash)
      expect(result["providers"]).to have_key("anthropic")
    end
  end

  describe "single key request" do
    it "returns the value and source for a valid key" do
      result = handler.call({ "key" => "provider" })

      expect(result["key"]).to eq("provider")
      expect(result["value"]).not_to be_nil
      expect(result["source"]).to be_a(String)
    end

    it "reports source as config_file when key is explicitly set" do
      File.write(config_path, YAML.dump("provider" => "openai", "model" => "gpt-5.4"))

      result = handler.call({ "key" => "provider" })

      expect(result["source"]).to eq("config_file")
      expect(result["value"]).to eq("openai")
    end

    it "reports source as default when key is not explicitly set" do
      # Write a config that does not include max_iterations
      File.write(config_path, YAML.dump("provider" => "anthropic"))

      result = handler.call({ "key" => "max_iterations" })

      expect(result["source"]).to eq("default")
      expect(result["value"]).to eq(RubynCode::Config::Defaults::MAX_ITERATIONS)
    end

    it "handles unknown key gracefully" do
      result = handler.call({ "key" => "oauth_client_id" })

      expect(result["value"]).to be_nil
      expect(result["error"]).to include("Unknown config key")
    end

    it "handles completely bogus key gracefully" do
      result = handler.call({ "key" => "nonexistent_key" })

      expect(result["value"]).to be_nil
      expect(result["error"]).to include("Unknown config key")
    end
  end
end
