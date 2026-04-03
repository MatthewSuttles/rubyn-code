# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Cost do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      budget_enforcer: budget_enforcer,
      context_manager: context_manager
    )
  end
  let(:renderer) { instance_double('Renderer', cost_summary: nil) }
  let(:budget_enforcer) do
    instance_double('BudgetEnforcer', session_cost: 0.05, daily_cost: 0.15)
  end
  let(:context_manager) do
    instance_double('ContextManager', total_input_tokens: 1000, total_output_tokens: 500)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/cost') }
  end

  describe '#execute' do
    it 'calls renderer with cost summary data' do
      command.execute([], ctx)
      expect(renderer).to have_received(:cost_summary).with(
        session_cost: 0.05,
        daily_cost: 0.15,
        tokens: { input: 1000, output: 500 }
      )
    end
  end
end
