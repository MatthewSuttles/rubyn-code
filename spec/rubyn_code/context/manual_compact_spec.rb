# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Context::ManualCompact do
  let(:llm_client) { double('llm_client') }
  let(:messages) do
    [
      { role: 'user', content: 'Hello' },
      { role: 'assistant', content: 'Hi there! How can I help?' },
      { role: 'user', content: 'Write a test for my app' }
    ]
  end

  before do
    allow(llm_client).to receive(:respond_to?).with(:chat).and_return(true)
    allow(llm_client).to receive(:chat).and_return('Summary of the conversation')
  end

  describe '.call' do
    it 'returns a single-element array with the compacted summary' do
      result = described_class.call(messages, llm_client: llm_client)

      expect(result.length).to eq(1)
      expect(result.first[:role]).to eq('user')
      expect(result.first[:content]).to include('[Context compacted — manual]')
      expect(result.first[:content]).to include('Summary of the conversation')
    end

    it 'calls the LLM client for summarization' do
      described_class.call(messages, llm_client: llm_client)

      expect(llm_client).to have_received(:chat).once
    end

    it 'passes the base instruction to the LLM' do
      described_class.call(messages, llm_client: llm_client)

      expect(llm_client).to have_received(:chat).with(
        messages: [hash_including(content: a_string_including('context compaction assistant'))],
        model: 'claude-sonnet-4-20250514'
      )
    end

    it 'includes focus in instruction when provided' do
      described_class.call(messages, llm_client: llm_client, focus: 'Focus on database changes')

      expect(llm_client).to have_received(:chat).with(
        messages: [hash_including(content: a_string_including('Focus on database changes'))],
        model: 'claude-sonnet-4-20250514'
      )
    end

    it 'does not include focus when focus is nil' do
      described_class.call(messages, llm_client: llm_client, focus: nil)

      expect(llm_client).to have_received(:chat).with(
        messages: [hash_including(content: a_string_excluding('Additional focus'))],
        model: 'claude-sonnet-4-20250514'
      )
    end

    it 'does not include focus when focus is empty string' do
      described_class.call(messages, llm_client: llm_client, focus: '   ')

      expect(llm_client).to have_received(:chat).with(
        messages: [hash_including(content: a_string_excluding('Additional focus'))],
        model: 'claude-sonnet-4-20250514'
      )
    end

    it 'saves transcript to directory when transcript_dir is given' do
      Dir.mktmpdir do |dir|
        described_class.call(messages, llm_client: llm_client, transcript_dir: dir)

        files = Dir.glob(File.join(dir, 'transcript_manual_*.json'))
        expect(files.length).to eq(1)

        saved = JSON.parse(File.read(files.first))
        expect(saved.length).to eq(3)
      end
    end

    it 'does not save transcript when transcript_dir is nil' do
      expect(FileUtils).not_to receive(:mkdir_p)

      described_class.call(messages, llm_client: llm_client, transcript_dir: nil)
    end

    it 'truncates long transcripts to MAX_TRANSCRIPT_CHARS' do
      long_messages = [{ role: 'user', content: 'x' * 100_000 }]

      described_class.call(long_messages, llm_client: llm_client)

      expect(llm_client).to have_received(:chat) do |args|
        content = args[:messages].first[:content]
        transcript_part = content.split("---\n\n").last
        expect(transcript_part.length).to be <= described_class::MAX_TRANSCRIPT_CHARS + 500
      end
    end

    context 'when LLM returns a String' do
      before do
        allow(llm_client).to receive(:chat).and_return('Plain string summary')
      end

      it 'uses the string directly as the summary' do
        result = described_class.call(messages, llm_client: llm_client)

        expect(result.first[:content]).to include('Plain string summary')
      end
    end

    context 'when LLM returns a Hash with :content key' do
      before do
        allow(llm_client).to receive(:chat).and_return({ content: 'Hash summary' })
      end

      it 'extracts content from the hash' do
        result = described_class.call(messages, llm_client: llm_client)

        expect(result.first[:content]).to include('Hash summary')
      end
    end

    context 'when LLM returns a Hash with string content key' do
      before do
        allow(llm_client).to receive(:chat).and_return({ 'content' => 'String-key hash summary' })
      end

      it 'extracts content from the hash' do
        result = described_class.call(messages, llm_client: llm_client)

        expect(result.first[:content]).to include('String-key hash summary')
      end
    end

    context 'when LLM returns an object with .text' do
      before do
        response = Struct.new(:text).new('Object text summary')
        allow(llm_client).to receive(:chat).and_return(response)
      end

      it 'extracts text from the response object' do
        result = described_class.call(messages, llm_client: llm_client)

        expect(result.first[:content]).to include('Object text summary')
      end
    end

    context 'when LLM returns an unknown type' do
      before do
        allow(llm_client).to receive(:chat).and_return(42)
      end

      it 'falls back to to_s' do
        result = described_class.call(messages, llm_client: llm_client)

        expect(result.first[:content]).to include('42')
      end
    end
  end
end

# Custom matcher for string exclusion
RSpec::Matchers.define :a_string_excluding do |unexpected|
  match { |actual| actual.is_a?(String) && !actual.include?(unexpected) }
  description { "a string not including #{unexpected.inspect}" }
end
