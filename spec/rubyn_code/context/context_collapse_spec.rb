# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Context::ContextCollapse do
  def user_msg(text)
    { role: "user", content: text }
  end

  def assistant_msg(text)
    { role: "assistant", content: [{ type: "text", text: text }] }
  end

  def build_conversation(turns)
    messages = []
    turns.times do |i|
      messages << user_msg("Question #{i}")
      messages << assistant_msg("Answer #{i}")
    end
    messages
  end

  describe ".call" do
    it "returns nil when conversation is too short to collapse" do
      messages = build_conversation(3)
      result = described_class.call(messages, threshold: 50_000)
      expect(result).to be_nil
    end

    it "snips middle messages and keeps first + recent" do
      messages = build_conversation(20)
      result = described_class.call(messages, threshold: 50_000, keep_recent: 4)

      expect(result).not_to be_nil
      # First message preserved
      expect(result.first).to eq(messages.first)
      # Snip marker present
      snip = result[1]
      expect(snip[:role]).to eq("user")
      expect(snip[:content]).to include("snipped")
      # Last 4 messages preserved
      expect(result.last(4)).to eq(messages.last(4))
    end

    it "includes the count of snipped messages in the marker" do
      messages = build_conversation(15) # 30 messages total
      result = described_class.call(messages, threshold: 50_000, keep_recent: 6)

      snip = result[1]
      # 30 total - 1 first - 6 recent = 23 snipped
      expect(snip[:content]).to include("23")
    end

    it "returns nil when collapse does not bring context under threshold" do
      messages = build_conversation(10)
      # Threshold so low that even collapsed messages won't fit
      result = described_class.call(messages, threshold: 1)
      expect(result).to be_nil
    end

    it "returns collapsed messages when under threshold" do
      messages = build_conversation(20)
      result = described_class.call(messages, threshold: 50_000)

      expect(result).not_to be_nil
      expect(result.size).to be < messages.size
    end
  end
end
