# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::LLM::MessageBuilder do
  subject(:builder) { described_class.new }

  describe "#build_system_prompt" do
    it "includes the project path" do
      prompt = builder.build_system_prompt(project_path: "/my/project")
      expect(prompt).to include("/my/project")
    end

    it "includes skills when provided" do
      prompt = builder.build_system_prompt(skills: ["Rails generator"])
      expect(prompt).to include("Rails generator")
      expect(prompt).to include("Available Skills")
    end

    it "includes instincts when provided" do
      prompt = builder.build_system_prompt(instincts: ["Prefer RSpec"])
      expect(prompt).to include("Prefer RSpec")
      expect(prompt).to include("Learned Instincts")
    end

    it "omits sections when empty" do
      prompt = builder.build_system_prompt
      expect(prompt).not_to include("Available Skills")
      expect(prompt).not_to include("Learned Instincts")
    end
  end

  describe "#format_messages" do
    it "formats simple string-content messages" do
      msgs = [{ role: "user", content: "hello" }]
      result = builder.format_messages(msgs)
      expect(result.first).to eq({ role: "user", content: "hello" })
    end

    it "formats messages with block arrays" do
      text_block = RubynCode::LLM::TextBlock.new(text: "hi")
      msgs = [{ role: "assistant", content: [text_block] }]
      result = builder.format_messages(msgs)
      expect(result.first[:content].first[:type]).to eq("text")
    end
  end

  describe "#format_tool_results" do
    it "wraps results in user role with tool_result content" do
      results = [{ tool_use_id: "t1", content: "output" }]
      formatted = builder.format_tool_results(results)
      expect(formatted[:role]).to eq("user")
      expect(formatted[:content].first[:type]).to eq("tool_result")
    end
  end
end
