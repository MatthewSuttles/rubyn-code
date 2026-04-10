# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::CancelHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "missing sessionId" do
    it "returns cancelled: false with an error message" do
      result = handler.call({})
      expect(result["cancelled"]).to eq(false)
      expect(result["error"]).to include("Missing sessionId")
    end
  end

  describe "with valid sessionId" do
    it "delegates cancellation to the prompt handler" do
      prompt_handler = instance_double(RubynCode::IDE::Handlers::PromptHandler)
      allow(server).to receive(:handler_instance).with(:prompt).and_return(prompt_handler)
      expect(prompt_handler).to receive(:cancel_session).with("abc-123")

      result = handler.call({ "sessionId" => "abc-123" })
      expect(result["cancelled"]).to eq(true)
      expect(result["sessionId"]).to eq("abc-123")
    end
  end

  describe "when prompt handler is not available" do
    it "still returns cancelled: true without raising" do
      allow(server).to receive(:handler_instance).with(:prompt).and_return(nil)

      result = handler.call({ "sessionId" => "orphan" })
      expect(result["cancelled"]).to eq(true)
    end
  end
end
