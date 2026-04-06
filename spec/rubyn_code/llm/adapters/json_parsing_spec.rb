# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::JsonParsing do
  let(:parser_class) do
    Class.new do
      include RubynCode::LLM::Adapters::JsonParsing
      public :parse_json
    end
  end

  subject(:parser) { parser_class.new }

  describe '#parse_json' do
    context 'with valid JSON' do
      it 'parses a JSON object' do
        result = parser.parse_json('{"key": "value"}')
        expect(result).to eq({ 'key' => 'value' })
      end

      it 'parses a JSON array' do
        result = parser.parse_json('[1, 2, 3]')
        expect(result).to eq([1, 2, 3])
      end

      it 'parses nested JSON' do
        result = parser.parse_json('{"a": {"b": [1, 2]}}')
        expect(result).to eq({ 'a' => { 'b' => [1, 2] } })
      end
    end

    context 'with nil input' do
      it 'returns nil' do
        expect(parser.parse_json(nil)).to be_nil
      end
    end

    context 'with empty string' do
      it 'returns nil' do
        expect(parser.parse_json('')).to be_nil
      end
    end

    context 'with whitespace-only string' do
      it 'returns nil' do
        expect(parser.parse_json('   ')).to be_nil
      end

      it 'returns nil for tabs and newlines' do
        expect(parser.parse_json("\t\n  \r\n")).to be_nil
      end
    end

    context 'with invalid JSON' do
      it 'returns nil for malformed JSON' do
        expect(parser.parse_json('{invalid}')).to be_nil
      end

      it 'returns nil for truncated JSON' do
        expect(parser.parse_json('{"key": ')).to be_nil
      end

      it 'returns nil for random text' do
        expect(parser.parse_json('not json at all')).to be_nil
      end
    end

    context 'with non-string input that does not respond to strip' do
      it 'raises TypeError for integer input (not rescued)' do
        # Integer does not respond to strip, and JSON.parse raises TypeError
        # which is not rescued (only JSON::ParserError is rescued)
        expect { parser.parse_json(42) }.to raise_error(TypeError)
      end
    end
  end
end
