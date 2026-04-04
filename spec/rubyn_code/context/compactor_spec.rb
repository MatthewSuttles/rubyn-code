# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Context::Compactor do
  let(:llm_client) { double('llm_client') }
  subject(:compactor) { described_class.new(llm_client: llm_client, threshold: 100) }

  describe '#micro_compact!' do
    it 'delegates to MicroCompact with the messages array' do
      messages = [{ role: 'user', content: 'hello' }]
      allow(RubynCode::Context::MicroCompact).to receive(:call).with(messages).and_return(2)

      result = compactor.micro_compact!(messages)

      expect(RubynCode::Context::MicroCompact).to have_received(:call).with(messages)
      expect(result).to eq(2)
    end
  end

  describe '#auto_compact!' do
    it 'delegates to AutoCompact with messages and llm_client' do
      messages = [{ role: 'user', content: 'hi' }]
      compacted = [{ role: 'user', content: '[Context compacted]\n\nSummary' }]

      allow(RubynCode::Context::AutoCompact).to receive(:call)
        .with(messages, llm_client: llm_client, transcript_dir: nil)
        .and_return(compacted)

      result = compactor.auto_compact!(messages)

      expect(RubynCode::Context::AutoCompact).to have_received(:call)
        .with(messages, llm_client: llm_client, transcript_dir: nil)
      expect(result).to eq(compacted)
    end

    it 'passes transcript_dir when configured' do
      dir_compactor = described_class.new(llm_client: llm_client, threshold: 100, transcript_dir: '/tmp/transcripts')
      messages = [{ role: 'user', content: 'hi' }]

      allow(RubynCode::Context::AutoCompact).to receive(:call).and_return([])

      dir_compactor.auto_compact!(messages)

      expect(RubynCode::Context::AutoCompact).to have_received(:call)
        .with(messages, llm_client: llm_client, transcript_dir: '/tmp/transcripts')
    end

    it 'raises when no LLM client is configured' do
      no_llm = described_class.new(llm_client: nil, threshold: 100)

      expect { no_llm.auto_compact!([]) }
        .to raise_error(RubynCode::Error, /LLM client is required/)
    end
  end

  describe '#manual_compact!' do
    it 'delegates to ManualCompact with focus' do
      messages = [{ role: 'user', content: 'hi' }]
      allow(RubynCode::Context::ManualCompact).to receive(:call).and_return([])

      compactor.manual_compact!(messages, focus: 'database queries')

      expect(RubynCode::Context::ManualCompact).to have_received(:call)
        .with(messages, llm_client: llm_client, transcript_dir: nil, focus: 'database queries')
    end

    it 'raises when no LLM client is configured' do
      no_llm = described_class.new(llm_client: nil, threshold: 100)

      expect { no_llm.manual_compact!([], focus: 'test') }
        .to raise_error(RubynCode::Error, /LLM client is required/)
    end
  end

  describe '#should_auto_compact?' do
    it 'returns false when estimated tokens are under threshold' do
      expect(compactor.should_auto_compact?([{ role: 'user', content: 'hi' }])).to be false
    end

    it 'returns true when estimated tokens exceed threshold' do
      big = [{ role: 'user', content: 'x' * 1000 }]
      expect(compactor.should_auto_compact?(big)).to be true
    end

    it 'uses chars_per_token ratio of 4 for estimation' do
      # threshold is 100 tokens = 400 chars of JSON
      # A message with ~380 chars of content should be near the boundary
      # depending on JSON overhead
      small_enough = [{ role: 'user', content: 'a' * 300 }]
      too_big = [{ role: 'user', content: 'a' * 500 }]

      expect(compactor.should_auto_compact?(small_enough)).to be false
      expect(compactor.should_auto_compact?(too_big)).to be true
    end
  end
end
