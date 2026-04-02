# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::LLM::Client do
  subject(:client) { described_class.new(model: "claude-sonnet-4-20250514") }

  before do
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::Auth::TokenStore).to receive(:load).and_return({
      access_token: "test-token", expires_at: Time.now + 3600
    })
  end

  describe "#chat" do
    it "sends a proper request and parses the response" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with(
          headers: { "Authorization" => "Bearer test-token", "anthropic-version" => "2023-06-01" }
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
  end
end
