# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Hooks::Runner do
  let(:registry) { RubynCode::Hooks::Registry.new }
  subject(:runner) { described_class.new(registry: registry) }

  describe "#fire" do
    it "calls all hooks for a generic event" do
      called = false
      registry.on(:post_llm_call) { |**_| called = true }
      runner.fire(:post_llm_call, response: {})
      expect(called).to be true
    end

    it "returns nil for generic events" do
      registry.on(:on_error) { |**_| "ignored" }
      expect(runner.fire(:on_error, error: "boom")).to be_nil
    end
  end

  describe "pre_tool_use deny gating" do
    it "returns deny hash when a hook denies" do
      registry.on(:pre_tool_use) do |**_context|
        { deny: true, reason: "blocked" }
      end

      result = runner.fire(:pre_tool_use, tool_name: "bash", tool_input: {})
      expect(result).to eq({ deny: true, reason: "blocked" })
    end

    it "returns nil when no hook denies" do
      registry.on(:pre_tool_use) { |**_| nil }
      result = runner.fire(:pre_tool_use, tool_name: "read_file", tool_input: {})
      expect(result).to be_nil
    end
  end

  describe "post_tool_use output transform" do
    it "allows hooks to transform the output" do
      registry.on(:post_tool_use) do |result:, **_|
        result.upcase
      end

      output = runner.fire(:post_tool_use, tool_name: "bash", result: "hello")
      expect(output).to eq("HELLO")
    end

    it "chains multiple transforms" do
      registry.on(:post_tool_use, priority: 10) { |result:, **_| "#{result}+A" }
      registry.on(:post_tool_use, priority: 20) { |result:, **_| "#{result}+B" }

      output = runner.fire(:post_tool_use, tool_name: "t", result: "start")
      expect(output).to eq("start+A+B")
    end
  end
end
