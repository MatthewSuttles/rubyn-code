# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::SubAgents::Runner do
  let(:llm_client) { instance_double('RubynCode::LLM::Client') }
  let(:project_root) { Dir.tmpdir }

  before do
    allow(RubynCode::Tools::Registry).to receive(:all).and_return([])
    allow(RubynCode::Tools::Registry).to receive(:tool_names).and_return(%w[read_file glob grep bash])
  end

  describe '.call' do
    it 'returns a summarized string when LLM responds with text only' do
      allow(llm_client).to receive(:chat).and_return('Here is the answer.')

      result = described_class.call(
        prompt: 'Explain the code',
        llm_client: llm_client,
        project_root: project_root,
        max_iterations: 5
      )

      expect(result).to be_a(String)
      expect(result).to include('Here is the answer')
    end

    it 'respects the max_iterations hard limit' do
      runner = described_class.new(
        prompt: 'loop forever',
        llm_client: llm_client,
        project_root: project_root,
        agent_type: :explore,
        max_iterations: 999
      )
      # MAX_ITERATIONS_HARD_LIMIT is 50
      expect(runner.instance_variable_get(:@max_iterations)).to be <= 50
    end

    it 'handles Hash response with content array' do
      hash_response = {
        content: [{ type: 'text', text: 'Hash answer.' }],
        stop_reason: 'end_turn',
        usage: { input_tokens: 10, output_tokens: 5 }
      }
      allow(llm_client).to receive(:chat).and_return(hash_response)

      result = described_class.call(
        prompt: 'Explain',
        llm_client: llm_client,
        project_root: project_root,
        max_iterations: 5
      )

      expect(result).to include('Hash answer')
    end

    it 'handles Hash response with string keys' do
      hash_response = {
        'content' => [{ 'type' => 'text', 'text' => 'String key answer.' }],
        'stop_reason' => 'end_turn',
        'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
      }
      allow(llm_client).to receive(:chat).and_return(hash_response)

      result = described_class.call(
        prompt: 'Explain',
        llm_client: llm_client,
        project_root: project_root,
        max_iterations: 5
      )

      expect(result).to include('String key answer')
    end

    it 'prevents sub-agents from spawning other sub-agents' do
      tool_call_response = [
        { type: 'tool_use', id: 't1', name: 'sub_agent', input: { prompt: 'hi' } }
      ]
      text_response = 'Done'

      allow(llm_client).to receive(:chat).and_return(tool_call_response, text_response)

      result = described_class.call(
        prompt: 'Do something',
        llm_client: llm_client,
        project_root: project_root,
        max_iterations: 5
      )

      expect(result).to be_a(String)
      expect(result).to include('Done')
    end
  end
end
