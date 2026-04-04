# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::MessageBuilder do
  subject(:builder) { described_class.new }

  describe '#build_system_prompt' do
    it 'returns a non-empty system prompt' do
      prompt = builder.build_system_prompt
      expect(prompt).to be_a(String)
      expect(prompt.length).to be > 50
    end

    it 'includes skills when provided' do
      prompt = builder.build_system_prompt(skills: ['## Guard Clauses\nReturn early.'])
      expect(prompt).to include('Guard Clauses')
    end

    it 'includes instincts when provided' do
      prompt = builder.build_system_prompt(instincts: ['Use frozen_string_literal always'])
      expect(prompt).to include('frozen_string_literal')
    end

    it 'includes project path when provided' do
      prompt = builder.build_system_prompt(project_path: '/my/cool/project')
      expect(prompt).to include('/my/cool/project')
    end

    it 'returns a clean prompt with no extras' do
      prompt = builder.build_system_prompt(skills: [], instincts: [])
      expect(prompt).not_to include('Available Skills')
    end
  end

  describe '#format_messages' do
    it 'passes through simple string-content messages' do
      msgs = [{ role: 'user', content: 'hello' }]
      result = builder.format_messages(msgs)
      expect(result).to eq([{ role: 'user', content: 'hello' }])
    end

    it 'formats array content blocks' do
      msgs = [{ role: 'user', content: [{ type: 'text', text: 'hello' }] }]
      result = builder.format_messages(msgs)
      expect(result.first[:content]).to be_an(Array)
    end

    it 'handles mixed message types' do
      msgs = [
        { role: 'user', content: 'plain text' },
        { role: 'assistant', content: [{ type: 'text', text: 'response' }] }
      ]
      result = builder.format_messages(msgs)
      expect(result.size).to eq(2)
    end
  end

  describe '#format_tool_results' do
    it 'creates a user message with tool_result blocks' do
      results = [{ tool_use_id: 'toolu_abc', content: 'file contents' }]
      msg = builder.format_tool_results(results)

      expect(msg[:role]).to eq('user')
      expect(msg[:content]).to be_an(Array)
      block = msg[:content].first
      expect(block[:type]).to eq('tool_result')
      expect(block[:tool_use_id]).to eq('toolu_abc')
      expect(block[:content]).to eq('file contents')
    end

    it 'marks errors with is_error flag' do
      results = [{ tool_use_id: 'toolu_abc', content: 'error', is_error: true }]
      msg = builder.format_tool_results(results)

      block = msg[:content].first
      expect(block[:is_error]).to be true
    end

    it 'does not include is_error when not an error' do
      results = [{ tool_use_id: 'toolu_abc', content: 'ok' }]
      msg = builder.format_tool_results(results)

      block = msg[:content].first
      expect(block).not_to have_key(:is_error)
    end

    it 'batches multiple results into one user message' do
      results = [
        { tool_use_id: 'toolu_1', content: 'result1' },
        { tool_use_id: 'toolu_2', content: 'result2' }
      ]
      msg = builder.format_tool_results(results)

      expect(msg[:content].size).to eq(2)
    end

    it 'falls back to :id when :tool_use_id is missing' do
      results = [{ id: 'toolu_fallback', content: 'ok' }]
      msg = builder.format_tool_results(results)

      block = msg[:content].first
      expect(block[:tool_use_id]).to eq('toolu_fallback')
    end
  end
end
