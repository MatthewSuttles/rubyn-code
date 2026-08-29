# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::ProviderUpsertHandler do
  let(:server) { instance_double(RubynCode::IDE::Server, notify: nil) }
  let(:settings) { instance_double(RubynCode::Config::Settings, add_provider: nil) }
  let(:handler) { described_class.new(server) }

  before do
    allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)
    allow(RubynCode::Auth::TokenStore).to receive(:save_provider_key)
  end

  it "persists a compatible provider and stores its key without returning it" do
    result = handler.call(
      "name" => "MiniMax",
      "baseUrl" => "https://api.minimax.io/v1/",
      "apiFormat" => "openai",
      "models" => ["MiniMax-M2.5", "MiniMax-M2.5"],
      "apiKey" => "secret"
    )

    expect(settings).to have_received(:add_provider).with(
      "minimax",
      base_url: "https://api.minimax.io/v1",
      env_key: nil,
      models: ["MiniMax-M2.5"],
      api_format: "openai"
    )
    expect(RubynCode::Auth::TokenStore).to have_received(:save_provider_key).with("minimax", "secret")
    expect(result.dig("provider", "apiKey")).to be_nil
    expect(result["updated"]).to be(true)
  end

  it "rejects invalid formats and URLs before writing" do
    result = handler.call(
      "name" => "minimax",
      "baseUrl" => "file:///tmp/socket",
      "apiFormat" => "custom",
      "models" => []
    )

    expect(result["updated"]).to be(false)
    expect(settings).not_to have_received(:add_provider)
  end
end
