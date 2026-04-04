# frozen_string_literal: true

require 'spec_helper'

# Ensure LLM data classes are loaded (they live behind autoload)
RubynCode::LLM::MessageBuilder

RSpec.describe RubynCode::Learning::Extractor do
  let(:llm_client) { instance_double("RubynCode::LLM::Client") }
  let(:messages) { [{ role: "user", content: "Fix the migration" }] }

  describe ".call" do
    it "returns extracted patterns from LLM response" do
      json_array = JSON.generate([{
        "type" => "error_resolution",
        "pattern" => "Check index before migration",
        "context_tags" => ["rails"],
        "confidence" => 0.6
      }])

      response = RubynCode::LLM::Response.new(
        id: "msg_1",
        content: [RubynCode::LLM::TextBlock.new(text: json_array)],
        stop_reason: "end_turn",
        usage: RubynCode::LLM::Usage.new(input_tokens: 50, output_tokens: 50)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      results = described_class.call(messages, llm_client: llm_client, project_path: "/proj")

      expect(results.size).to eq(1)
      expect(results.first[:pattern]).to include("error_resolution")
      expect(results.first[:confidence]).to be_between(0.3, 0.8)
    end

    it "returns empty array when LLM fails" do
      allow(llm_client).to receive(:chat).and_raise(StandardError, "timeout")

      results = described_class.call(messages, llm_client: llm_client, project_path: "/proj")
      expect(results).to eq([])
    end

    it 'returns empty array for empty messages' do
      results = described_class.call([], llm_client: llm_client, project_path: '/proj')
      expect(results).to eq([])
    end
  end

  describe 'request_extraction message parsing' do
    it 'parses assistant messages with Array content blocks (text strings)' do
      messages = [
        { role: 'assistant', content: [{ text: 'block one' }, { text: 'block two' }] }
      ]

      json_array = JSON.generate([{
        'type' => 'error_resolution',
        'pattern' => 'Array content pattern',
        'context_tags' => ['test'],
        'confidence' => 0.5
      }])

      response = RubynCode::LLM::Response.new(
        id: 'msg_arr',
        content: [RubynCode::LLM::TextBlock.new(text: json_array)],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 10)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      results = described_class.call(messages, llm_client: llm_client, project_path: '/proj')
      expect(results.size).to eq(1)
      expect(results.first[:pattern]).to include('Array content pattern')
    end

    it 'parses assistant messages with object content (responds to .text)' do
      text_block = RubynCode::LLM::TextBlock.new(text: 'object content')
      messages = [
        { role: 'assistant', content: [text_block] }
      ]

      json_array = JSON.generate([{
        'type' => 'debugging_technique',
        'pattern' => 'Object content pattern',
        'context_tags' => ['debug'],
        'confidence' => 0.6
      }])

      response = RubynCode::LLM::Response.new(
        id: 'msg_obj',
        content: [RubynCode::LLM::TextBlock.new(text: json_array)],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 10)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      results = described_class.call(messages, llm_client: llm_client, project_path: '/proj')
      expect(results.size).to eq(1)
      expect(results.first[:pattern]).to include('Object content pattern')
    end
  end

  describe 'save_instincts! failure handling' do
    it 'logs the error and swallows it' do
      json_array = JSON.generate([{
        'type' => 'error_resolution',
        'pattern' => 'Save failure test',
        'context_tags' => ['test'],
        'confidence' => 0.5
      }])

      response = RubynCode::LLM::Response.new(
        id: 'msg_save_fail',
        content: [RubynCode::LLM::TextBlock.new(text: json_array)],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 10)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      # Make DB::Connection.instance raise to simulate save failure
      fake_db = instance_double('RubynCode::DB::Connection')
      allow(RubynCode::DB::Connection).to receive(:instance).and_return(fake_db)
      allow(fake_db).to receive(:execute).and_raise(StandardError, 'DB write failed')

      expect {
        results = described_class.call(messages, llm_client: llm_client, project_path: '/proj')
        expect(results.size).to eq(1)
      }.to output(/Failed to save instincts/).to_stderr
    end
  end

  describe 'parse_response edge cases' do
    it 'returns empty array when parse_extraction response has no JSON array' do
      response = RubynCode::LLM::Response.new(
        id: 'msg_no_json',
        content: [RubynCode::LLM::TextBlock.new(text: 'no json here')],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 10)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      results = described_class.call(messages, llm_client: llm_client, project_path: '/proj')
      expect(results).to eq([])
    end

    it 'returns empty array for malformed JSON' do
      response = RubynCode::LLM::Response.new(
        id: 'msg_bad_json',
        content: [RubynCode::LLM::TextBlock.new(text: '[{broken json}]')],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 10)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      expect {
        results = described_class.call(messages, llm_client: llm_client, project_path: '/proj')
        expect(results).to eq([])
      }.to output(/Failed to parse extraction response/).to_stderr
    end
  end

  describe 'extract_text with Hash response' do
    it 'extracts text from a Hash response using dig' do
      hash_response = { 'content' => [{ 'text' => 'extracted from hash' }] }

      # Use send to test private method directly
      text = described_class.send(:extract_text, hash_response)
      expect(text).to eq('extracted from hash')
    end

    it 'returns nil for Hash with missing content path' do
      hash_response = { 'other_key' => 'no content' }

      text = described_class.send(:extract_text, hash_response)
      expect(text).to be_nil
    end
  end

  describe 'decay_rate_for_type mapping' do
    it 'maps project_specific to 0.02' do
      rate = described_class.send(:decay_rate_for_type, 'project_specific')
      expect(rate).to eq(0.02)
    end

    it 'maps error_resolution to 0.03' do
      rate = described_class.send(:decay_rate_for_type, 'error_resolution')
      expect(rate).to eq(0.03)
    end

    it 'maps debugging_technique to 0.04' do
      rate = described_class.send(:decay_rate_for_type, 'debugging_technique')
      expect(rate).to eq(0.04)
    end

    it 'maps user_correction to 0.05' do
      rate = described_class.send(:decay_rate_for_type, 'user_correction')
      expect(rate).to eq(0.05)
    end

    it 'maps workaround to 0.07' do
      rate = described_class.send(:decay_rate_for_type, 'workaround')
      expect(rate).to eq(0.07)
    end

    it 'maps unknown types to 0.05' do
      rate = described_class.send(:decay_rate_for_type, 'totally_unknown')
      expect(rate).to eq(0.05)
    end
  end
end
