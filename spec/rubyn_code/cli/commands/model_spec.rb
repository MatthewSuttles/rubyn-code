# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Model do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil, warning: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/model') }
  end

  describe '#execute' do
    context 'without arguments' do
      it 'shows the current model' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/Current model:/)
      end

      it 'lists available models' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/Available:/)
      end
    end

    context 'with a valid model' do
      it 'returns action to switch model' do
        result = command.execute(['claude-sonnet-4-20250514'], ctx)
        expect(result).to eq(action: :set_model, model: 'claude-sonnet-4-20250514')
      end

      it 'confirms the switch' do
        command.execute(['claude-sonnet-4-20250514'], ctx)
        expect(renderer).to have_received(:info).with(/switched/i)
      end
    end

    context 'with an unknown model' do
      it 'shows warning' do
        command.execute(['gpt-4'], ctx)
        expect(renderer).to have_received(:warning).with(/Unknown model/)
      end
    end
  end
end
