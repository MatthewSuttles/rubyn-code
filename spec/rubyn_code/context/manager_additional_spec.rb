# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Context::Manager, 'additional coverage' do
  describe '#estimated_tokens' do
    subject(:manager) { described_class.new(threshold: 500) }

    it 'returns 0 when JSON generation fails' do
      # Stub JSON.generate to raise JSON::GeneratorError
      allow(JSON).to receive(:generate).and_raise(JSON::GeneratorError, 'nesting too deep')
      expect(manager.estimated_tokens([{ role: 'user', content: 'x' }])).to eq(0)
    end

    it 'returns correct estimate for empty messages array' do
      expect(manager.estimated_tokens([])).to be_a(Integer)
      expect(manager.estimated_tokens([])).to be >= 0
    end
  end

  describe '#track_usage' do
    subject(:manager) { described_class.new(threshold: 500) }

    it 'handles nil token counts via to_i' do
      usage = double(input_tokens: nil, output_tokens: nil)
      manager.track_usage(usage)
      expect(manager.total_input_tokens).to eq(0)
      expect(manager.total_output_tokens).to eq(0)
    end

    it 'handles string token counts via to_i' do
      usage = double(input_tokens: '42', output_tokens: '13')
      manager.track_usage(usage)
      expect(manager.total_input_tokens).to eq(42)
      expect(manager.total_output_tokens).to eq(13)
    end
  end

  describe '#llm_client=' do
    subject(:manager) { described_class.new(threshold: 500) }

    it 'sets the llm_client' do
      client = double('llm_client')
      manager.llm_client = client
      expect(manager.instance_variable_get(:@llm_client)).to eq(client)
    end
  end

  describe '#check_compaction!' do
    context 'when context collapse returns nil and llm_client is present' do
      let(:llm_client) { instance_double(RubynCode::LLM::Client) }
      let(:manager) { described_class.new(threshold: 10, llm_client: llm_client) }

      it 'falls through to LLM-driven auto-compact' do
        conversation = double('conversation')
        messages = [{ role: 'user', content: 'x' * 200 }]
        allow(conversation).to receive(:messages).and_return(messages)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(nil)

        compactor = instance_double(RubynCode::Context::Compactor)
        new_messages = [{ role: 'user', content: 'compacted by llm' }]
        allow(RubynCode::Context::Compactor).to receive(:new).and_return(compactor)
        allow(compactor).to receive(:auto_compact!).and_return(new_messages)

        allow(conversation).to receive(:respond_to?).with(:replace_messages).and_return(true)
        allow(conversation).to receive(:replace_messages)

        manager.check_compaction!(conversation)

        expect(compactor).to have_received(:auto_compact!).with(messages)
        expect(conversation).to have_received(:replace_messages).with(new_messages)
      end
    end

    context 'when context collapse returns nil and no llm_client' do
      let(:manager) { described_class.new(threshold: 10) }

      it 'does not attempt LLM-driven compaction' do
        conversation = double('conversation')
        messages = [{ role: 'user', content: 'x' * 200 }]
        allow(conversation).to receive(:messages).and_return(messages)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(nil)

        expect(RubynCode::Context::Compactor).not_to receive(:new)

        manager.check_compaction!(conversation)
      end
    end

    context 'when conversation responds to messages= but not replace_messages' do
      let(:manager) { described_class.new(threshold: 10) }

      it 'uses messages= setter to apply compacted messages' do
        conversation = double('conversation')
        messages = [{ role: 'user', content: 'x' * 200 }]
        allow(conversation).to receive(:messages).and_return(messages)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        collapsed = [{ role: 'user', content: 'collapsed' }]
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(collapsed)

        allow(conversation).to receive(:respond_to?).with(:replace_messages).and_return(false)
        allow(conversation).to receive(:respond_to?).with(:messages=).and_return(true)
        allow(conversation).to receive(:messages=)

        manager.check_compaction!(conversation)

        expect(conversation).to have_received(:messages=).with(collapsed)
      end
    end

    context 'when conversation responds to neither replace_messages nor messages=' do
      let(:manager) { described_class.new(threshold: 10) }

      it 'does not raise' do
        conversation = double('conversation')
        messages = [{ role: 'user', content: 'x' * 200 }]
        allow(conversation).to receive(:messages).and_return(messages)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        collapsed = [{ role: 'user', content: 'collapsed' }]
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(collapsed)

        allow(conversation).to receive(:respond_to?).with(:replace_messages).and_return(false)
        allow(conversation).to receive(:respond_to?).with(:messages=).and_return(false)

        expect { manager.check_compaction!(conversation) }.not_to raise_error
      end
    end
  end

  describe 'MICRO_COMPACT_RATIO' do
    it 'is 0.7' do
      expect(described_class::MICRO_COMPACT_RATIO).to eq(0.7)
    end
  end

  describe 'CHARS_PER_TOKEN' do
    it 'is 4' do
      expect(described_class::CHARS_PER_TOKEN).to eq(4)
    end
  end
end
