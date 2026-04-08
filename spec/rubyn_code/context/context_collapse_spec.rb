# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Context::ContextCollapse do
  def user_msg(text)
    { role: 'user', content: text }
  end

  def assistant_msg(text)
    { role: 'assistant', content: [{ type: 'text', text: text }] }
  end

  def build_conversation(turns)
    messages = []
    turns.times do |i|
      messages << user_msg("Question #{i}")
      messages << assistant_msg("Answer #{i}")
    end
    messages
  end

  describe '.call' do
    it 'returns nil when conversation is too short to collapse' do
      messages = build_conversation(3)
      result = described_class.call(messages, threshold: 50_000)
      expect(result).to be_nil
    end

    it 'snips middle messages and keeps first + recent' do
      messages = build_conversation(20)
      result = described_class.call(messages, threshold: 50_000, keep_recent: 4)

      expect(result).not_to be_nil
      # First message preserved
      expect(result.first).to eq(messages.first)
      # Snip marker present
      snip = result[1]
      expect(snip[:role]).to eq('user')
      expect(snip[:content]).to include('snipped')
      # Last 4 messages preserved
      expect(result.last(4)).to eq(messages.last(4))
    end

    it 'includes the count of snipped messages in the marker' do
      messages = build_conversation(15) # 30 messages total
      result = described_class.call(messages, threshold: 50_000, keep_recent: 6)

      snip = result[1]
      # 30 total - 1 first - 6 recent = 23 snipped
      expect(snip[:content]).to include('23')
    end

    it 'returns nil when collapse does not bring context under threshold' do
      messages = build_conversation(10)
      # Threshold so low that even collapsed messages won't fit
      result = described_class.call(messages, threshold: 1)
      expect(result).to be_nil
    end

    it 'returns collapsed messages when under threshold' do
      messages = build_conversation(20)
      result = described_class.call(messages, threshold: 50_000)

      expect(result).not_to be_nil
      expect(result.size).to be < messages.size
    end

    context 'when first message is a system injection' do
      it 'preserves both the system injection and the first real user message' do
        messages = [
          { role: 'user', content: '[system] Project profile loaded' },
          user_msg('Please fix the login bug'),
          assistant_msg("I'll look at the login code"),
          *build_conversation(15)
        ]

        result = described_class.call(messages, threshold: 50_000, keep_recent: 4)

        expect(result).not_to be_nil
        # First message is the system injection (preserved — may contain critical context)
        expect(result[0][:content]).to eq('[system] Project profile loaded')
        # Second message is the first real user message
        expect(result[1][:content]).to eq('Please fix the login bug')
        # Snip marker follows both anchors
        expect(result[2][:content]).to include('snipped')
      end

      it 'falls back to just the first message when all user messages are system injections' do
        messages = (0...20).flat_map do |i|
          [
            { role: 'user', content: "[system] injection #{i}" },
            assistant_msg("ok #{i}")
          ]
        end

        result = described_class.call(messages, threshold: 50_000, keep_recent: 4)

        expect(result).not_to be_nil
        expect(result.first[:content]).to eq('[system] injection 0')
      end

      it 'handles non-string content gracefully' do
        messages = [
          { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't1', content: 'result' }] },
          user_msg('Real question here'),
          assistant_msg('Sure'),
          *build_conversation(15)
        ]

        result = described_class.call(messages, threshold: 50_000, keep_recent: 4)

        expect(result).not_to be_nil
        # Non-string content is not a system injection, so it's kept as the sole anchor
        expect(result.first[:content]).to be_an(Array)
      end
    end
  end
end
