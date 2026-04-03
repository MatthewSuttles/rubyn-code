# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Spawn do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer
    )
  end
  let(:renderer) { instance_double('Renderer', error: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/spawn') }
  end

  describe '#execute' do
    context 'with a name' do
      it 'returns spawn action with default role' do
        result = command.execute(['alice'], ctx)
        expect(result).to eq(action: :spawn_teammate, name: 'alice', role: 'coder')
      end

      it 'uses custom role when provided' do
        result = command.execute(%w[alice reviewer], ctx)
        expect(result).to eq(action: :spawn_teammate, name: 'alice', role: 'reviewer')
      end
    end

    context 'without arguments' do
      it 'shows error' do
        command.execute([], ctx)
        expect(renderer).to have_received(:error).with(/Usage/i)
      end
    end
  end
end
