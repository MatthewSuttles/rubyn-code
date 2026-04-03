# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Clear do
  subject(:command) { described_class.new }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/clear') }
  end

  describe '#execute' do
    it 'clears the terminal' do
      allow(command).to receive(:system)
      command.execute([], nil)
      expect(command).to have_received(:system).with('clear')
    end
  end
end
