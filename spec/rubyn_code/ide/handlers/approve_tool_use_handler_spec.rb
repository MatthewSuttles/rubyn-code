# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "rubyn_code/ide/adapters/tool_output"

RSpec.describe RubynCode::IDE::Handlers::ApproveToolUseHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "with no active session" do
    it "returns resolved: false with error when no adapter is installed" do
      result = handler.call({ "requestId" => "req-1", "approved" => true })
      expect(result["resolved"]).to eq(false)
      expect(result["error"]).to include("No active session")
    end
  end

  describe "missing requestId" do
    it "returns resolved: false with error" do
      result = handler.call({ "approved" => true })
      expect(result["resolved"]).to eq(false)
      expect(result["error"]).to include("Missing requestId")
    end
  end

  describe "with an active adapter" do
    let(:adapter) { instance_double(RubynCode::IDE::Adapters::ToolOutput) }

    before { server.tool_output_adapter = adapter }

    it "delegates to adapter.resolve_approval and returns resolved=true on approve" do
      expect(adapter).to receive(:resolve_approval).with("req-1", true).and_return(true)
      result = handler.call({ "requestId" => "req-1", "approved" => true })
      expect(result).to eq({ "resolved" => true, "requestId" => "req-1" })
    end

    it "returns resolved=true with requestId echoed on deny" do
      expect(adapter).to receive(:resolve_approval).with("req-2", false).and_return(true)
      result = handler.call({ "requestId" => "req-2", "approved" => false })
      expect(result).to eq({ "resolved" => true, "requestId" => "req-2" })
    end

    it "returns error when adapter reports no matching pending request" do
      allow(adapter).to receive(:resolve_approval).and_return(false)
      result = handler.call({ "requestId" => "unknown", "approved" => true })
      expect(result["resolved"]).to eq(false)
      expect(result["error"]).to include("No pending request")
    end

    it "coerces truthy/falsy `approved` values to booleans" do
      expect(adapter).to receive(:resolve_approval).with("req-3", true).and_return(true)
      handler.call({ "requestId" => "req-3", "approved" => "yes" })

      expect(adapter).to receive(:resolve_approval).with("req-4", false).and_return(true)
      handler.call({ "requestId" => "req-4", "approved" => nil })
    end
  end
end
