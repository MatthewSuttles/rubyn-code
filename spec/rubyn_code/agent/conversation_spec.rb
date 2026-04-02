# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::Conversation do
  subject(:conversation) { described_class.new }

  describe "#add_user_message" do
    it "appends a user message and returns it" do
      msg = conversation.add_user_message("hello")
      expect(msg).to eq(role: "user", content: "hello")
      expect(conversation.messages.last).to eq(msg)
    end
  end

  describe "#add_assistant_message" do
    it "normalizes a string into a text block" do
      conversation.add_assistant_message("hi there")
      blocks = conversation.messages.last[:content]
      expect(blocks).to eq([{ type: "text", text: "hi there" }])
    end

    it "includes tool_use blocks when provided" do
      tc = { id: "t1", name: "read_file", input: { path: "x.rb" } }
      conversation.add_assistant_message("thinking", tool_calls: [tc])
      blocks = conversation.messages.last[:content]
      expect(blocks.length).to eq(2)
      expect(blocks.last[:type]).to eq("tool_use")
      expect(blocks.last[:name]).to eq("read_file")
    end

    it "skips empty string content" do
      conversation.add_assistant_message("")
      expect(conversation.messages.last[:content]).to eq([])
    end
  end

  describe "#add_tool_result" do
    it "creates a user message with a tool_result block" do
      conversation.add_tool_result("t1", "read_file", "file contents")
      msg = conversation.messages.last
      expect(msg[:role]).to eq("user")
      expect(msg[:content].first[:type]).to eq("tool_result")
      expect(msg[:content].first[:tool_use_id]).to eq("t1")
    end

    it "batches consecutive tool results into one user message" do
      conversation.add_tool_result("t1", "read_file", "out1")
      conversation.add_tool_result("t2", "grep", "out2")
      expect(conversation.length).to eq(1)
      expect(conversation.messages.last[:content].length).to eq(2)
    end

    it "marks errors with is_error" do
      conversation.add_tool_result("t1", "bash", "fail", is_error: true)
      block = conversation.messages.last[:content].first
      expect(block[:is_error]).to be true
    end
  end

  describe "#to_api_format" do
    it "returns messages with role and content keys" do
      conversation.add_user_message("hi")
      api = conversation.to_api_format
      expect(api).to eq([{ role: "user", content: "hi" }])
    end
  end

  describe "#undo_last!" do
    it "removes the last user+assistant pair" do
      conversation.add_user_message("q")
      conversation.add_assistant_message("a")
      conversation.undo_last!
      expect(conversation.length).to eq(0)
    end

    it "does nothing on an empty conversation" do
      expect { conversation.undo_last! }.not_to raise_error
    end
  end

  describe "#last_assistant_text" do
    it "returns the text of the most recent assistant message" do
      conversation.add_assistant_message("first")
      conversation.add_user_message("q")
      conversation.add_assistant_message("second")
      expect(conversation.last_assistant_text).to eq("second")
    end

    it "returns nil when there is no assistant message" do
      expect(conversation.last_assistant_text).to be_nil
    end
  end

  describe "#length" do
    it "returns the number of messages" do
      conversation.add_user_message("a")
      conversation.add_user_message("b")
      expect(conversation.length).to eq(2)
    end
  end

  describe "#clear!" do
    it "removes all messages" do
      conversation.add_user_message("x")
      conversation.clear!
      expect(conversation.length).to eq(0)
    end
  end
end
