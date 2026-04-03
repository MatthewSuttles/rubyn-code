# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Plan do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      plan_mode?: plan_mode
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/plan') }
  end

  describe '#execute' do
    context 'when plan mode is off' do
      let(:plan_mode) { false }

      it 'returns action to enable plan mode' do
        result = command.execute([], ctx)
        expect(result).to eq(action: :set_plan_mode, enabled: true)
      end

      it 'shows enabled message' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/ON/)
      end
    end

    context 'when plan mode is on' do
      let(:plan_mode) { true }

      it 'returns action to disable plan mode' do
        result = command.execute([], ctx)
        expect(result).to eq(action: :set_plan_mode, enabled: false)
      end

      it 'shows disabled message' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/OFF/)
      end
    end
  end
end
