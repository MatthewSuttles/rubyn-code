# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::Base do
  subject(:adapter) { described_class.new }

  describe '#chat' do
    it 'raises NotImplementedError' do
      expect { adapter.chat(messages: [], model: 'test', max_tokens: 100) }
        .to raise_error(NotImplementedError, /chat must be implemented/)
    end
  end

  describe '#provider_name' do
    it 'raises NotImplementedError' do
      expect { adapter.provider_name }
        .to raise_error(NotImplementedError, /provider_name must be implemented/)
    end
  end

  describe '#models' do
    it 'raises NotImplementedError' do
      expect { adapter.models }
        .to raise_error(NotImplementedError, /models must be implemented/)
    end
  end
end
