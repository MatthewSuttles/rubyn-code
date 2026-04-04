# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::LLM::Client do
  subject(:client) { described_class.new(model: "claude-sonnet-4-20250514") }

  before do
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::Auth::TokenStore).to receive(:load).and_return({
      access_token: "sk-ant-oat-test-token", expires_at: Time.now + 3600, source: :keychain
    })
  end

  describe "#chat" do
    it "sends a proper OAuth request and parses the response" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with(
          headers: {
            "Authorization" => "Bearer sk-ant-oat-test-token",
            "anthropic-version" => "2023-06-01",
            "anthropic-beta" => "oauth-2025-04-20",
            "x-app" => "cli"
          }
        )
        .to_return(
          status: 200,
          body: JSON.generate({
            "id" => "msg_test",
            "content" => [{ "type" => "text", "text" => "Hello!" }],
            "stop_reason" => "end_turn",
            "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
          }),
          headers: { "Content-Type" => "application/json" }
        )

      response = client.chat(messages: [{ role: "user", content: "Hi" }])

      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.text).to eq("Hello!")
      expect(response.usage.input_tokens).to eq(10)
    end

    it "includes the OAuth gate in the system prompt" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with { |req|
          body = JSON.parse(req.body)
          system_blocks = body["system"]
          system_blocks.is_a?(Array) &&
            system_blocks.first["text"].include?("Claude Code") &&
            system_blocks.last["cache_control"] == { "type" => "ephemeral" }
        }
        .to_return(
          status: 200,
          body: JSON.generate({
            "id" => "msg_test",
            "content" => [{ "type" => "text", "text" => "OK" }],
            "stop_reason" => "end_turn",
            "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
          })
        )

      client.chat(messages: [{ role: "user", content: "Hi" }], system: "Be helpful.")
    end

    it "raises RequestError on non-success status" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: '{"error":{"type":"server_error","message":"boom"}}')

      expect { client.chat(messages: [{ role: "user", content: "Hi" }]) }
        .to raise_error(RubynCode::LLM::Client::RequestError, /boom/)
    end

    it "raises AuthExpiredError on 401" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 401, body: '{"error":{"type":"auth","message":"expired"}}')

      expect { client.chat(messages: [{ role: "user", content: "Hi" }]) }
        .to raise_error(RubynCode::LLM::Client::AuthExpiredError)
    end

    it "raises PromptTooLongError on 413" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 413, body: '{"error":{"type":"invalid_request_error","message":"prompt is too long"}}')

      expect { client.chat(messages: [{ role: "user", content: "Hi" }]) }
        .to raise_error(RubynCode::LLM::Client::PromptTooLongError)
    end
  end
end
