# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Model do
  subject(:command) { described_class.new }

  let(:llm_client) do
    instance_double(
      RubynCode::LLM::Client,
      provider_name: 'anthropic',
      model: 'claude-sonnet-4-20250514',
      models: RubynCode::LLM::Adapters::Anthropic::AVAILABLE_MODELS
    )
  end
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      llm_client: llm_client
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil, warning: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/model') }
  end

  describe '#execute' do
    context 'without arguments' do
      it 'shows the current provider and model' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/Provider: anthropic/)
        expect(renderer).to have_received(:info).with(/Current model:/)
      end

      it 'lists available models' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/Available:/)
      end

      it 'shows provider:model tip' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/provider:model/)
      end
    end

    context 'with a valid model (no provider prefix)' do
      it 'returns action to switch model' do
        result = command.execute(['claude-sonnet-4-20250514'], ctx)
        expect(result).to eq(action: :set_model, model: 'claude-sonnet-4-20250514')
      end

      it 'confirms the switch' do
        command.execute(['claude-sonnet-4-20250514'], ctx)
        expect(renderer).to have_received(:info).with(/switched/i)
      end
    end

    context 'with an unknown model (no provider prefix)' do
      it 'shows warning' do
        command.execute(['gpt-4'], ctx)
        expect(renderer).to have_received(:warning).with(/Unknown model/)
      end
    end

    context 'with provider:model syntax' do
      it 'returns set_provider action with provider and model' do
        result = command.execute(['openai:gpt-4o'], ctx)
        expect(result).to eq(action: :set_provider, provider: 'openai', model: 'gpt-4o')
      end

      it 'confirms the switch' do
        command.execute(['openai:gpt-4o'], ctx)
        expect(renderer).to have_received(:info).with(/Switched to provider: openai/)
      end

      it 'warns on unknown model for a known provider' do
        command.execute(['openai:fake-model'], ctx)
        expect(renderer).to have_received(:warning).with(/Unknown model.*fake-model/)
      end
    end

    context 'with provider-only syntax (trailing colon)' do
      it 'returns set_provider action with nil model' do
        result = command.execute(['openai:'], ctx)
        expect(result).to eq(action: :set_provider, provider: 'openai', model: nil)
      end
    end

    context 'with unknown provider' do
      it 'returns set_provider action (no validation for unknown providers)' do
        result = command.execute(['groq:llama-3'], ctx)
        expect(result).to eq(action: :set_provider, provider: 'groq', model: 'llama-3')
      end
    end
  end
end
