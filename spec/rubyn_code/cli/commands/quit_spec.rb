# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Quit do
  subject(:command) { described_class.new }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/quit') }
  end

  describe '.aliases' do
    it { expect(described_class.aliases).to eq(%w[/exit /q]) }
  end

  describe '.hidden?' do
    it { expect(described_class.hidden?).to be false }
  end
end
