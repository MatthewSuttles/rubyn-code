# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Context::Manager, "compaction pipeline" do
  let(:llm_client) { instance_double(RubynCode::LLM::Client) }

  def user_msg(text)
    { role: "user", content: text }
  end

  def assistant_msg(text)
    { role: "assistant", content: [{ type: "text", text: text }] }
  end

  def tool_result_msg(id, content)
    { role: "user", content: [{ type: "tool_result", tool_use_id: id, content: content }] }
  end

  def tool_call_msg(id, name)
    { role: "assistant", content: [{ type: "tool_use", id: id, name: name, input: {} }] }
  end

  describe "#check_compaction!" do
    it "runs micro-compact when estimated tokens exceed 70% of threshold" do
      # Threshold of 400 means micro-compact triggers at 280 tokens;
      # this conversation is ~287 estimated tokens — just above the gate.
      manager = described_class.new(threshold: 400)
      conversation = double("conversation", messages: [
        user_msg("hi"),
        tool_call_msg("t1", "bash"),
        tool_result_msg("t1", "x" * 200),
        tool_call_msg("t2", "bash"),
        tool_result_msg("t2", "y" * 200),
        tool_call_msg("t3", "bash"),
        tool_result_msg("t3", "z" * 200)
      ])

      manager.check_compaction!(conversation)

      # Oldest tool result should be compacted (only keep_recent=2 preserved)
      first_result = conversation.messages[2][:content].first
      expect(first_result[:content]).to include("Previous")
    end

    it "tries context collapse before auto-compact when over threshold" do
      # Build a conversation big enough to exceed threshold but small enough
      # that collapse (keeping first + 6 recent) fits under it
      messages = []
      20.times do |i|
        messages << user_msg("Question #{i} with some padding text to increase size")
        messages << assistant_msg("Answer #{i} with some padding text to increase size")
      end

      # Set threshold between collapsed size and full size
      full_tokens = (JSON.generate(messages).length.to_f / 4).ceil
      manager = described_class.new(threshold: full_tokens / 2)

      conversation = double("conversation", messages: messages)

      allow(conversation).to receive(:replace_messages) do |new_msgs|
        allow(conversation).to receive(:messages).and_return(new_msgs)
      end
      allow(conversation).to receive(:respond_to?).with(:replace_messages).and_return(true)
      allow(conversation).to receive(:respond_to?).with(:llm_client).and_return(false)
      allow(conversation).to receive(:respond_to?).with(:messages=).and_return(false)

      manager.check_compaction!(conversation)

      # Should have been collapsed (fewer messages)
      expect(conversation.messages.size).to be < 40
      # Should have the snip marker
      snip = conversation.messages.find { |m| m[:content].is_a?(String) && m[:content].include?("snipped") }
      expect(snip).not_to be_nil
    end
  end
end
