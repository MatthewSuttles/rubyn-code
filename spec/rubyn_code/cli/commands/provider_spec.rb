# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Provider do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double('Renderer', info: nil, warning: nil, success: nil) }
  let(:ctx) do
    instance_double(RubynCode::CLI::Commands::Context, renderer: renderer)
  end

  let(:settings) do
    instance_double(RubynCode::Config::Settings, data: settings_data, save!: nil)
  end
  let(:settings_data) do
    {
      'providers' => {
        'anthropic' => { 'env_key' => 'ANTHROPIC_API_KEY', 'models' => { 'top' => 'claude-opus-4-6' } },
        'openai' => { 'env_key' => 'OPENAI_API_KEY', 'models' => { 'top' => 'gpt-4o' } },
        'groq' => { 'base_url' => 'https://api.groq.com/openai/v1', 'models' => %w[llama-3.3-70b] }
      }
    }
  end

  before do
    allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/provider') }
  end

  describe '#execute' do
    context 'with no arguments' do
      it 'shows usage' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/Usage:/)
      end
    end

    context 'with "list"' do
      it 'lists all configured providers' do
        command.execute(['list'], ctx)
        expect(renderer).to have_received(:info).with(/anthropic/)
        expect(renderer).to have_received(:info).with(/openai/)
        expect(renderer).to have_received(:info).with(/groq/)
      end

      it 'shows models for each provider' do
        command.execute(['list'], ctx)
        expect(renderer).to have_received(:info).with(/claude-opus-4-6/)
        expect(renderer).to have_received(:info).with(/llama-3.3-70b/)
      end

      it 'shows api_format when set' do
        settings_data['providers']['proxy'] = {
          'base_url' => 'https://proxy.example.com/v1',
          'api_format' => 'anthropic',
          'models' => %w[claude-sonnet-4-6]
        }

        command.execute(['list'], ctx)
        expect(renderer).to have_received(:info).with(/proxy \(anthropic\)/)
      end
    end

    context 'with "add"' do
      it 'requires name and base_url' do
        command.execute(['add'], ctx)
        expect(renderer).to have_received(:warning).with(/Usage:/)
      end

      it 'requires base_url' do
        command.execute(%w[add groq], ctx)
        expect(renderer).to have_received(:warning).with(/Usage:/)
      end

      it 'adds a provider with just name and base_url' do
        allow(settings).to receive(:add_provider)

        command.execute(%w[add together https://api.together.xyz/v1], ctx)

        expect(settings).to have_received(:add_provider).with(
          'together',
          base_url: 'https://api.together.xyz/v1',
          env_key: nil,
          models: [],
          api_format: nil
        )
        expect(renderer).to have_received(:success).with(/Provider 'together' added/)
      end

      it 'passes --format flag' do
        allow(settings).to receive(:add_provider)

        command.execute(%w[add proxy https://proxy.example.com/v1 --format anthropic], ctx)

        expect(settings).to have_received(:add_provider).with(
          'proxy',
          base_url: 'https://proxy.example.com/v1',
          env_key: nil,
          models: [],
          api_format: 'anthropic'
        )
        expect(renderer).to have_received(:success).with(/anthropic format/)
      end

      it 'passes --env-key flag' do
        allow(settings).to receive(:add_provider)

        command.execute(%w[add groq https://api.groq.com/openai/v1 --env-key GROQ_API_KEY], ctx)

        expect(settings).to have_received(:add_provider).with(
          'groq',
          base_url: 'https://api.groq.com/openai/v1',
          env_key: 'GROQ_API_KEY',
          models: [],
          api_format: nil
        )
      end

      it 'passes --models flag as comma-separated list' do
        allow(settings).to receive(:add_provider)

        command.execute(%w[add groq https://api.groq.com/openai/v1 --models llama-3.3-70b,mixtral-8x7b], ctx)

        expect(settings).to have_received(:add_provider).with(
          'groq',
          base_url: 'https://api.groq.com/openai/v1',
          env_key: nil,
          models: %w[llama-3.3-70b mixtral-8x7b],
          api_format: nil
        )
      end

      it 'passes all flags together' do
        allow(settings).to receive(:add_provider)

        command.execute(%w[
          add myproxy https://proxy.example.com/v1
          --format anthropic --env-key PROXY_KEY --models claude-sonnet-4-6,claude-haiku-4-5
        ], ctx)

        expect(settings).to have_received(:add_provider).with(
          'myproxy',
          base_url: 'https://proxy.example.com/v1',
          env_key: 'PROXY_KEY',
          models: %w[claude-sonnet-4-6 claude-haiku-4-5],
          api_format: 'anthropic'
        )
      end

      it 'shows switch hint after adding' do
        allow(settings).to receive(:add_provider)

        command.execute(%w[add groq https://api.groq.com/openai/v1 --models llama-3.3-70b], ctx)

        expect(renderer).to have_received(:info).with(%r{/model groq:llama-3.3-70b})
      end

      it 'stores API key via --key flag' do
        allow(settings).to receive(:add_provider)
        allow(RubynCode::Auth::TokenStore).to receive(:save_provider_key)

        command.execute(%w[add groq https://api.groq.com/openai/v1 --key gsk-secret --models llama-3.3-70b], ctx)

        expect(RubynCode::Auth::TokenStore).to have_received(:save_provider_key).with('groq', 'gsk-secret')
        expect(renderer).to have_received(:info).with(/api_key: stored/)
      end

      it 'does not store key when --key is not provided' do
        allow(settings).to receive(:add_provider)
        allow(RubynCode::Auth::TokenStore).to receive(:save_provider_key)

        command.execute(%w[add groq https://api.groq.com/openai/v1], ctx)

        expect(RubynCode::Auth::TokenStore).not_to have_received(:save_provider_key)
      end
    end

    context 'with "set-key"' do
      it 'stores the API key for a provider' do
        allow(RubynCode::Auth::TokenStore).to receive(:save_provider_key)

        command.execute(%w[set-key groq gsk-new-key], ctx)

        expect(RubynCode::Auth::TokenStore).to have_received(:save_provider_key).with('groq', 'gsk-new-key')
        expect(renderer).to have_received(:success).with(/API key stored for 'groq'/)
      end

      it 'requires name and key' do
        command.execute(%w[set-key groq], ctx)
        expect(renderer).to have_received(:warning).with(/Usage:/)
      end

      it 'requires name' do
        command.execute(%w[set-key], ctx)
        expect(renderer).to have_received(:warning).with(/Usage:/)
      end
    end
  end
end
