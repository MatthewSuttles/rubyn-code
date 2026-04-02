# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::MCP::ToolBridge do
  let(:mcp_client) { instance_double("RubynCode::MCP::Client") }

  before do
    # Store original tools and restore after
    @original_tools = RubynCode::Tools::Registry.all.dup
  end

  after do
    RubynCode::Tools::Registry.reset!
    @original_tools.each { |t| RubynCode::Tools::Registry.register(t) }
  end

  describe ".bridge" do
    it "returns empty array when client has no tools" do
      allow(mcp_client).to receive(:tools).and_return([])
      expect(described_class.bridge(mcp_client)).to eq([])
    end

    it "creates and registers tool classes from MCP definitions" do
      tool_defs = [
        {
          "name" => "search-docs",
          "description" => "Search documentation",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "query" => { "type" => "string", "description" => "Search query" }
            },
            "required" => ["query"]
          }
        }
      ]
      allow(mcp_client).to receive(:tools).and_return(tool_defs)

      classes = described_class.bridge(mcp_client)

      expect(classes.size).to eq(1)
      klass = classes.first
      expect(klass.tool_name).to eq("mcp_search_docs")
      expect(klass.const_get(:RISK_LEVEL)).to eq(:external)
      expect(RubynCode::Tools::Registry.tool_names).to include("mcp_search_docs")
    end

    it "handles nil tools from client" do
      allow(mcp_client).to receive(:tools).and_return(nil)
      expect(described_class.bridge(mcp_client)).to eq([])
    end
  end
end
