# frozen_string_literal: true

require 'spec_helper'

# Ensure LLM data classes are loaded (they live behind autoload)

RSpec.describe RubynCode::Agent::Conversation do
  subject(:conversation) { described_class.new }

  describe '#add_user_message' do
    it 'appends a user message and returns it' do
      msg = conversation.add_user_message('hello')
      expect(msg).to eq(role: 'user', content: 'hello')
      expect(conversation.messages.last).to eq(msg)
    end
  end

  describe '#add_assistant_message' do
    it 'normalizes a string into a text block' do
      conversation.add_assistant_message('hi there')
      blocks = conversation.messages.last[:content]
      expect(blocks).to eq([{ type: 'text', text: 'hi there' }])
    end

    it 'includes tool_use blocks when provided' do
      tc = { type: 'tool_use', id: 't1', name: 'read_file', input: { path: 'x.rb' } }
      conversation.add_assistant_message('thinking', tool_calls: [tc])
      blocks = conversation.messages.last[:content]
      expect(blocks.length).to eq(2)
      expect(blocks.last[:type]).to eq('tool_use')
      expect(blocks.last[:name]).to eq('read_file')
    end

    it 'skips empty string content' do
      conversation.add_assistant_message('')
      expect(conversation.messages.last[:content]).to eq([])
    end
  end

  describe '#add_tool_result' do
    it 'creates a user message with a tool_result block' do
      conversation.add_tool_result('t1', 'read_file', 'file contents')
      msg = conversation.messages.last
      expect(msg[:role]).to eq('user')
      expect(msg[:content].first[:type]).to eq('tool_result')
      expect(msg[:content].first[:tool_use_id]).to eq('t1')
    end

    it 'batches consecutive tool results into one user message' do
      conversation.add_tool_result('t1', 'read_file', 'out1')
      conversation.add_tool_result('t2', 'grep', 'out2')
      expect(conversation.length).to eq(1)
      expect(conversation.messages.last[:content].length).to eq(2)
    end

    it 'marks errors with is_error' do
      conversation.add_tool_result('t1', 'bash', 'fail', is_error: true)
      block = conversation.messages.last[:content].first
      expect(block[:is_error]).to be true
    end
  end

  describe '#to_api_format' do
    it 'returns messages with role and content keys' do
      conversation.add_user_message('hi')
      api = conversation.to_api_format
      expect(api).to eq([{ role: 'user', content: 'hi' }])
    end
  end

  describe '#undo_last!' do
    it 'removes the last user+assistant pair' do
      conversation.add_user_message('q')
      conversation.add_assistant_message('a')
      conversation.undo_last!
      expect(conversation.length).to eq(0)
    end

    it 'does nothing on an empty conversation' do
      conversation.undo_last!
      expect(conversation.length).to eq(0)
    end
  end

  describe '#last_assistant_text' do
    it 'returns the text of the most recent assistant message' do
      conversation.add_assistant_message('first')
      conversation.add_user_message('q')
      conversation.add_assistant_message('second')
      expect(conversation.last_assistant_text).to eq('second')
    end

    it 'returns nil when there is no assistant message' do
      expect(conversation.last_assistant_text).to be_nil
    end
  end

  describe '#length' do
    it 'returns the number of messages' do
      conversation.add_user_message('a')
      conversation.add_user_message('b')
      expect(conversation.length).to eq(2)
    end
  end

  describe '#clear!' do
    it 'removes all messages' do
      conversation.add_user_message('x')
      conversation.clear!
      expect(conversation.length).to eq(0)
    end
  end

  describe '#to_api_format' do
    it 'repairs orphaned tool_use blocks by adding interrupted results' do
      # An assistant message with a tool_use that has no corresponding tool_result
      conversation.add_user_message('do something')
      conversation.add_assistant_message(
        'Calling tool...',
        tool_calls: [
          { type: 'tool_use', id: 'toolu_orphan', name: 'bash', input: { command: 'ls' } }
        ]
      )
      # No tool_result added — it's orphaned

      formatted = conversation.to_api_format

      # Should have a synthetic tool_result for the orphan
      last_msg = formatted.last
      expect(last_msg[:role]).to eq('user')
      expect(last_msg[:content]).to be_an(Array)
      result_block = last_msg[:content].find { |b| b[:type] == 'tool_result' }
      expect(result_block[:tool_use_id]).to eq('toolu_orphan')
      expect(result_block[:content]).to include('[interrupted]')
      expect(result_block[:is_error]).to be true
    end

    it 'inserts orphan repair before subsequent user messages' do
      conversation.add_user_message('do something')
      conversation.add_assistant_message(
        'Calling tool...',
        tool_calls: [
          { type: 'tool_use', id: 'toolu_orphan', name: 'bash', input: { command: 'ls' } }
        ]
      )
      # Simulate Ctrl-C: no tool_result, user sends a new message
      conversation.add_user_message('never mind, just read the file')

      formatted = conversation.to_api_format

      # The repair should be inserted right after the assistant message,
      # before the subsequent user message
      assistant_idx = formatted.index { |m| m[:role] == 'assistant' }
      repair_msg = formatted[assistant_idx + 1]
      next_user_msg = formatted[assistant_idx + 2]

      expect(repair_msg[:role]).to eq('user')
      expect(repair_msg[:content].first[:type]).to eq('tool_result')
      expect(repair_msg[:content].first[:tool_use_id]).to eq('toolu_orphan')
      expect(next_user_msg[:role]).to eq('user')
      expect(next_user_msg[:content]).to eq('never mind, just read the file')
    end
  end

  describe '#replace!' do
    it 'replaces all messages with the new array' do
      conversation.add_user_message('old message')
      conversation.add_assistant_message('old reply')

      new_messages = [
        { role: 'user', content: 'compacted question' },
        { role: 'assistant', content: [{ type: 'text', text: 'compacted answer' }] }
      ]

      conversation.replace!(new_messages)

      expect(conversation.length).to eq(2)
      expect(conversation.messages.first[:content]).to eq('compacted question')
      expect(conversation.messages.last[:content]).to eq([{ type: 'text', text: 'compacted answer' }])
    end
  end

  describe 'content normalization' do
    it 'passes through string content as a text block' do
      conversation.add_assistant_message('simple string')
      blocks = conversation.messages.last[:content]
      expect(blocks).to eq([{ type: 'text', text: 'simple string' }])
    end

    it 'converts block content that responds to .type into a hash' do
      text_block = RubynCode::LLM::TextBlock.new(text: 'from object')
      conversation.add_assistant_message([text_block])
      blocks = conversation.messages.last[:content]
      expect(blocks.first).to eq({ type: 'text', text: 'from object' })
    end

    it 'converts a single content object that responds to .type (non-Array, non-String)' do
      text_block = RubynCode::LLM::TextBlock.new(text: 'single object')
      conversation.add_assistant_message(text_block)
      blocks = conversation.messages.last[:content]
      expect(blocks.first).to eq({ type: 'text', text: 'single object' })
    end

    it 'passes through Hash content directly' do
      hash_content = { type: 'text', text: 'hash passthrough' }
      conversation.add_assistant_message(hash_content)
      blocks = conversation.messages.last[:content]
      expect(blocks.first).to eq({ type: 'text', text: 'hash passthrough' })
    end
  end

  describe 'block_to_hash' do
    it 'handles tool_result blocks with is_error flag' do
      tool_result = RubynCode::LLM::ToolResultBlock.new(
        tool_use_id: 'tu_123',
        content: 'error output',
        is_error: true
      )
      conversation.add_assistant_message([tool_result])
      block = conversation.messages.last[:content].first

      expect(block[:type]).to eq('tool_result')
      expect(block[:tool_use_id]).to eq('tu_123')
      expect(block[:content]).to eq('error output')
      expect(block[:is_error]).to be true
    end

    it 'handles tool_result blocks without is_error' do
      tool_result = RubynCode::LLM::ToolResultBlock.new(
        tool_use_id: 'tu_456',
        content: 'success output'
      )
      conversation.add_assistant_message([tool_result])
      block = conversation.messages.last[:content].first

      expect(block[:type]).to eq('tool_result')
      expect(block).not_to have_key(:is_error)
    end

    it 'handles unknown block types with to_h' do
      unknown_block = Struct.new(:type, :data) do
        def to_h
          { type: type.to_s, data: data }
        end
      end.new(type: 'custom', data: 'value')

      conversation.add_assistant_message([unknown_block])
      block = conversation.messages.last[:content].first

      expect(block).to eq({ type: 'custom', data: 'value' })
    end

    it 'passes through unknown objects without to_h as-is' do
      Struct.new(:type).new(type: 'opaque')
      # Remove to_h if present (Struct has it by default), test the passthrough
      # Actually Struct responds to to_h, so let's use a minimal object
      opaque = Object.new
      def opaque.type = 'opaque'

      conversation.add_assistant_message([opaque])
      block = conversation.messages.last[:content].first
      expect(block).to eq(opaque)
    end

    it 'passes through Hash blocks unchanged' do
      hash_block = { type: 'tool_use', id: 'tu_789', name: 'bash', input: { command: 'ls' } }
      conversation.add_assistant_message([hash_block])
      block = conversation.messages.last[:content].first

      expect(block).to eq(hash_block)
    end
  end

  describe 'extract_text' do
    it 'returns nil for nil content' do
      # extract_text is private, test through last_assistant_text
      # Add an assistant message with nil content blocks
      conversation.instance_variable_get(:@messages) << { role: 'assistant', content: nil }
      expect(conversation.last_assistant_text).to be_nil
    end

    it 'returns the string directly for string content' do
      conversation.instance_variable_get(:@messages) << { role: 'assistant', content: 'direct string' }
      expect(conversation.last_assistant_text).to eq('direct string')
    end

    it 'returns nil for array content with no text blocks' do
      conversation.instance_variable_get(:@messages) << {
        role: 'assistant',
        content: [{ type: 'tool_use', id: 'tu_1', name: 'bash', input: {} }]
      }
      expect(conversation.last_assistant_text).to be_nil
    end
  end
end
