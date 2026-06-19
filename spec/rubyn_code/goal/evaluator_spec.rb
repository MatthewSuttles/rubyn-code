# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Goal::Evaluator do
  let(:llm_client) { instance_double(RubynCode::LLM::Client) }
  subject(:evaluator) { described_class.new(llm_client: llm_client) }

  def response(text)
    { content: [{ type: 'text', text: text }] }
  end

  describe '#call' do
    it 'returns true when the judge answers YES' do
      allow(llm_client).to receive(:chat).and_return(response("YES\nlooks complete"))

      expect(evaluator.call(condition: 'ship it')).to be(true)
    end

    it 'returns false when the judge answers NO' do
      allow(llm_client).to receive(:chat).and_return(response("NO\nnot done yet"))

      expect(evaluator.call(condition: 'ship it')).to be(false)
    end

    it 'is conservative on an ambiguous answer' do
      allow(llm_client).to receive(:chat).and_return(response('maybe?'))

      expect(evaluator.call(condition: 'ship it')).to be(false)
    end

    it 'returns false (keep working) when the LLM call raises' do
      allow(llm_client).to receive(:chat).and_raise(StandardError, 'network down')

      expect(evaluator.call(condition: 'ship it')).to be(false)
    end

    it 'includes recent conversation work in the judge prompt' do
      conversation = RubynCode::Agent::Conversation.new
      conversation.add_user_message('please add a test')
      allow(llm_client).to receive(:chat).and_return(response('YES'))

      evaluator.call(condition: 'add a test', conversation: conversation)

      expect(llm_client).to have_received(:chat) do |messages:, **_|
        expect(messages.first[:content]).to include('please add a test')
      end
    end
  end
end
