# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "tmpdir"
require "fileutils"

RSpec.describe RubynCode::IDE::Handlers::ModelsListHandler do
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

  describe "#call" do
    it "returns models grouped by provider with tier info" do
      result = handler.call({})

      expect(result).to have_key("models")
      expect(result["models"]).to be_an(Array)
      expect(result["models"]).not_to be_empty

      first = result["models"].first
      expect(first).to have_key("provider")
      expect(first).to have_key("model")
      expect(first).to have_key("tier")
    end

    it "includes anthropic and openai models from default config" do
      result = handler.call({})

      providers = result["models"].map { |m| m["provider"] }.uniq
      expect(providers).to include("anthropic")
      expect(providers).to include("openai")
    end

    it "includes all tier levels" do
      result = handler.call({})

      tiers = result["models"].map { |m| m["tier"] }.uniq
      expect(tiers).to include("cheap", "mid", "top")
    end

    it "returns the active provider and model" do
      result = handler.call({})

      expect(result["activeProvider"]).to eq(RubynCode::Config::Defaults::DEFAULT_PROVIDER)
      expect(result["activeModel"]).to eq(RubynCode::Config::Defaults::DEFAULT_MODEL)
    end

    it "returns model_mode defaulting to auto" do
      result = handler.call({})

      expect(result["modelMode"]).to eq("auto")
    end

    it "reflects a manually set model_mode" do
      File.write(config_path, YAML.dump(
        "provider" => "anthropic",
        "model" => "claude-opus-4-6",
        "model_mode" => "manual"
      ))

      result = handler.call({})

      expect(result["modelMode"]).to eq("manual")
    end

    it "skips providers without models hash" do
      File.write(config_path, YAML.dump(
        "provider" => "anthropic",
        "model" => "claude-opus-4-6",
        "providers" => {
          "custom_provider" => { "base_url" => "https://example.com" },
          "openai" => {
            "env_key" => "OPENAI_API_KEY",
            "models" => { "cheap" => "gpt-5.4-nano", "mid" => "gpt-5.4-mini", "top" => "gpt-5.4" }
          }
        }
      ))

      result = handler.call({})

      providers = result["models"].map { |m| m["provider"] }.uniq
      expect(providers).not_to include("custom_provider")
      expect(providers).to include("openai")
    end
  end
end
