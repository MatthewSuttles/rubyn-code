# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Budget do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      budget_enforcer: budget_enforcer
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil) }
  let(:budget_enforcer) { instance_double('BudgetEnforcer', remaining_budget: 0.75) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/budget') }
  end

  describe '#execute' do
    context 'without arguments' do
      it 'shows remaining budget' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/0\.7500/)
      end
    end

    context 'with amount argument' do
      it 'returns action to set budget' do
        result = command.execute(['10.0'], ctx)
        expect(result).to eq(action: :set_budget, amount: 10.0)
      end

      it 'confirms the new budget' do
        command.execute(['10.0'], ctx)
        expect(renderer).to have_received(:info).with(/10\.0/)
      end
    end
  end
end
