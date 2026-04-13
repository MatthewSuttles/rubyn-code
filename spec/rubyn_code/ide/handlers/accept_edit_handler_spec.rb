# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "rubyn_code/ide/adapters/tool_output"

RSpec.describe RubynCode::IDE::Handlers::AcceptEditHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "with no active session" do
    it "returns applied: false with error when no adapter is installed" do
      result = handler.call({ "editId" => "edit-1", "accepted" => true })
      expect(result["applied"]).to eq(false)
      expect(result["error"]).to include("No active session")
    end
  end

  describe "missing editId" do
    it "returns applied: false with error" do
      result = handler.call({ "accepted" => true })
      expect(result["applied"]).to eq(false)
      expect(result["error"]).to include("Missing editId")
    end
  end

  describe "with an active adapter" do
    let(:adapter) { instance_double(RubynCode::IDE::Adapters::ToolOutput) }

    before { server.tool_output_adapter = adapter }

    it "delegates to adapter.resolve_edit and returns applied=true on accept" do
      expect(adapter).to receive(:resolve_edit).with("edit-1", true).and_return(true)
      result = handler.call({ "editId" => "edit-1", "accepted" => true })
      expect(result).to eq({ "applied" => true })
    end

    it "returns applied=false on reject" do
      expect(adapter).to receive(:resolve_edit).with("edit-2", false).and_return(true)
      result = handler.call({ "editId" => "edit-2", "accepted" => false })
      expect(result).to eq({ "applied" => false })
    end

    it "returns an error when adapter reports no matching pending edit" do
      allow(adapter).to receive(:resolve_edit).and_return(false)
      result = handler.call({ "editId" => "unknown", "accepted" => true })
      expect(result["applied"]).to eq(false)
      expect(result["error"]).to include("No pending edit")
    end

    it "coerces truthy/falsy `accepted` values to booleans" do
      expect(adapter).to receive(:resolve_edit).with("edit-3", true).and_return(true)
      handler.call({ "editId" => "edit-3", "accepted" => "yes" })

      expect(adapter).to receive(:resolve_edit).with("edit-4", false).and_return(true)
      handler.call({ "editId" => "edit-4", "accepted" => nil })
    end
  end
end
