# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::Registry do
  # Define a named test tool class so constants resolve properly
  before(:all) do
    RubynCode::Tools.const_set(:FakeTool, Class.new(RubynCode::Tools::Base) {
      self.const_set(:TOOL_NAME, "fake_tool")
      self.const_set(:DESCRIPTION, "A fake tool for testing")
      self.const_set(:PARAMETERS, {}.freeze)
      self.const_set(:RISK_LEVEL, :read)
    })
  end

  after(:all) do
    RubynCode::Tools.send(:remove_const, :FakeTool) if RubynCode::Tools.const_defined?(:FakeTool)
  end

  let(:fake_tool) { RubynCode::Tools::FakeTool }

  before { described_class.reset! }
  after { described_class.reset! }

  describe ".register and .get" do
    it "registers and retrieves a tool class by name" do
      described_class.register(fake_tool)
      expect(described_class.get("fake_tool")).to eq(fake_tool)
    end

    it "raises ToolNotFoundError for an unknown tool" do
      expect { described_class.get("nonexistent") }
        .to raise_error(RubynCode::ToolNotFoundError, /Unknown tool/)
    end
  end

  describe ".all" do
    it "returns all registered tool classes" do
      described_class.register(fake_tool)
      expect(described_class.all).to include(fake_tool)
    end
  end

  describe ".tool_definitions" do
    it "returns schema definitions for all registered tools" do
      described_class.register(fake_tool)
      defs = described_class.tool_definitions
      expect(defs.length).to eq(1)
      expect(defs.first[:name]).to eq("fake_tool")
    end
  end

  describe ".tool_names" do
    it "returns sorted tool names" do
      described_class.register(fake_tool)
      expect(described_class.tool_names).to eq(["fake_tool"])
    end
  end

  describe ".reset!" do
    it "clears all registered tools" do
      described_class.register(fake_tool)
      described_class.reset!
      expect(described_class.all).to be_empty
    end
  end
end
