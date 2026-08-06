# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::PhoneAFriend do
  let(:llm_client) { instance_double('LLMClient', provider_name: 'anthropic', model: 'claude-sonnet-5') }

  def make_text_response(text)
    text_block = instance_double('TextBlock', type: 'text', text: text)
    instance_double('Response', content: [text_block], stop_reason: 'end_turn')
  end

  def build_tool(project_root:, client: llm_client)
    tool = described_class.new(project_root: project_root)
    tool.llm_client = client
    tool
  end

  # Clear provider API keys so tests don't depend on the developer's env
  around do |example|
    original_env = {
      'ANTHROPIC_API_KEY' => ENV['ANTHROPIC_API_KEY'],
      'OPENAI_API_KEY' => ENV['OPENAI_API_KEY']
    }
    ENV.delete('ANTHROPIC_API_KEY')
    ENV.delete('OPENAI_API_KEY')
    example.run
  ensure
    original_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe 'tool metadata' do
    it 'is registered under phone_a_friend' do
      expect(RubynCode::Tools::Registry.get('phone_a_friend')).to eq(described_class)
    end

    it 'is external risk level' do
      expect(described_class.risk_level).to eq(:external)
    end
  end

  describe '#execute' do
    it 'returns an error message when no LLM client is injected' do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect(tool.execute(question: 'Which approach?')).to include('no LLM client')
      end
    end

    context 'when no other provider has an API key' do
      it 'escalates to the active provider top-tier model via the active client' do
        with_temp_project do |dir|
          captured = nil
          allow(llm_client).to receive(:chat) do |**kwargs|
            captured = kwargs
            make_text_response('Use approach B because it is simpler.')
          end

          tool = build_tool(project_root: dir)
          result = tool.execute(question: 'Approach A or B?')

          expect(captured[:model]).to eq('claude-opus-5')
          expect(captured[:tools]).to be_nil
          expect(result).to include('## Second Opinion — anthropic/claude-opus-5')
          expect(result).to include('Use approach B')
        end
      end
    end

    context 'when another provider has an API key' do
      it 'phones the other provider top-tier model via a fresh client' do
        with_temp_project do |dir|
          ENV['OPENAI_API_KEY'] = 'test-key'
          friend = instance_double('LLMClient')
          captured = nil
          factory_args = nil
          allow(friend).to receive(:chat) do |**kwargs|
            captured = kwargs
            make_text_response('Second opinion text.')
          end

          tool = build_tool(project_root: dir)
          tool.client_factory = lambda { |provider, model|
            factory_args = [provider, model]
            friend
          }
          result = tool.execute(question: 'Is this design sound?')

          expect(factory_args).to eq(%w[openai gpt-5.4])
          expect(captured[:model]).to eq('gpt-5.4')
          expect(result).to include('## Second Opinion — openai/gpt-5.4')
        end
      end
    end

    it 'includes the context in the message sent to the friend' do
      with_temp_project do |dir|
        captured = nil
        allow(llm_client).to receive(:chat) do |**kwargs|
          captured = kwargs
          make_text_response('Answer.')
        end

        tool = build_tool(project_root: dir)
        tool.execute(question: 'Why does this fail?', context: 'NoMethodError on line 3')

        content = captured[:messages].first[:content]
        expect(content).to include('Why does this fail?')
        expect(content).to include('## Context')
        expect(content).to include('NoMethodError on line 3')
      end
    end

    it 'sends the question alone when no context is given' do
      with_temp_project do |dir|
        captured = nil
        allow(llm_client).to receive(:chat) do |**kwargs|
          captured = kwargs
          make_text_response('Answer.')
        end

        tool = build_tool(project_root: dir)
        tool.execute(question: 'Just the question')

        expect(captured[:messages].first[:content]).to eq('Just the question')
      end
    end

    it 'reports a friendly error when the call fails' do
      with_temp_project do |dir|
        allow(llm_client).to receive(:chat).and_raise(RubynCode::Error, 'rate limited')

        tool = build_tool(project_root: dir)
        result = tool.execute(question: 'Anything?')

        expect(result).to include('phone_a_friend: call to anthropic/claude-opus-5 failed')
        expect(result).to include('rate limited')
      end
    end

    it 'reports when the friend returns no text' do
      with_temp_project do |dir|
        empty = instance_double('Response', content: [], stop_reason: 'end_turn')
        allow(llm_client).to receive(:chat).and_return(empty)

        tool = build_tool(project_root: dir)
        result = tool.execute(question: 'Anything?')

        expect(result).to include('returned no text')
      end
    end
  end
end
