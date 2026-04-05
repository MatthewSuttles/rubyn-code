# frozen_string_literal: true

# Shared contract for all LLM adapters.
# Every adapter must satisfy these expectations regardless of provider.
#
# Usage:
#   RSpec.describe RubynCode::LLM::Adapters::Anthropic do
#     it_behaves_like 'an LLM adapter'
#   end

RSpec.shared_examples 'an LLM adapter' do
  describe 'adapter contract' do
    it 'responds to #chat' do
      expect(subject).to respond_to(:chat)
    end

    it 'responds to #provider_name and returns a string' do
      expect(subject.provider_name).to be_a(String)
      expect(subject.provider_name).not_to be_empty
    end

    it 'responds to #models and returns an array of strings' do
      expect(subject.models).to be_an(Array)
      expect(subject.models).to all(be_a(String))
      expect(subject.models).not_to be_empty
    end
  end
end
