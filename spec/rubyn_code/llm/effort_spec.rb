# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Effort (output_config.effort) plumbing' do
  describe RubynCode::LLM::Adapters::Anthropic do
    let(:adapter) { described_class.new }

    describe '#apply_effort' do
      it 'sets body[:output_config][:effort] when effort is present' do
        body = {}
        adapter.send(:apply_effort, body, 'high')
        expect(body[:output_config]).to eq(effort: 'high')
      end

      it 'leaves body untouched when effort is nil' do
        body = { model: 'm' }
        adapter.send(:apply_effort, body, nil)
        expect(body).to eq(model: 'm')
      end

      it 'merges into an existing output_config hash rather than overwriting it' do
        body = { output_config: { task_budget: { total: 10 } } }
        adapter.send(:apply_effort, body, 'max')
        expect(body[:output_config]).to eq(task_budget: { total: 10 }, effort: 'max')
      end
    end

    describe '#build_request_body' do
      it 'includes output_config.effort when effort is passed' do
        body = adapter.send(:build_request_body,
                            messages: [], tools: nil, system: nil,
                            model: 'claude-opus-4-8', max_tokens: 4096,
                            stream: false, effort: 'low')
        expect(body[:output_config]).to eq(effort: 'low')
      end

      it 'omits output_config when effort is not passed' do
        body = adapter.send(:build_request_body,
                            messages: [], tools: nil, system: nil,
                            model: 'claude-opus-4-8', max_tokens: 4096,
                            stream: false)
        expect(body).not_to have_key(:output_config)
      end
    end
  end

  describe RubynCode::LLM::Client do
    let(:fake_adapter) do
      instance_double(RubynCode::LLM::Adapters::Anthropic).tap do |a|
        empty = RubynCode::LLM::Response.new(
          id: 'r', content: [], stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 0, output_tokens: 0)
        )
        allow(a).to receive(:chat) { empty }
        allow(a).to receive(:provider_name).and_return('anthropic')
        allow(a).to receive(:models).and_return(['claude-opus-4-8'])
      end
    end

    it 'starts with effort unset' do
      client = described_class.new(adapter: fake_adapter)
      expect(client.effort).to be_nil
    end

    it 'forwards effort to adapter when set' do
      client = described_class.new(adapter: fake_adapter)
      client.effort = 'xhigh'
      client.chat(messages: [{ role: 'user', content: 'hi' }])
      expect(fake_adapter).to have_received(:chat).with(hash_including(effort: 'xhigh'))
    end

    it 'omits effort when unset' do
      client = described_class.new(adapter: fake_adapter)
      client.chat(messages: [{ role: 'user', content: 'hi' }])
      expect(fake_adapter).to have_received(:chat) { |kwargs| expect(kwargs).not_to have_key(:effort) }
    end
  end
end
