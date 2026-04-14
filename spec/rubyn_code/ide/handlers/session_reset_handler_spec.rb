# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::SessionResetHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "missing sessionId" do
    it "returns reset: false with error" do
      result = handler.call({})
      expect(result["reset"]).to eq(false)
      expect(result["error"]).to include("Missing sessionId")
    end
  end

  describe "with an active prompt handler" do
    it "delegates to PromptHandler#reset_session" do
      prompt_handler = server.handler_instance(:prompt)
      expect(prompt_handler).to receive(:reset_session).with("sess-1")

      result = handler.call({ "sessionId" => "sess-1" })
      expect(result).to eq({ "reset" => true, "sessionId" => "sess-1" })
    end
  end
end
