# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Base do
  let(:test_command_class) do
    Class.new(described_class) do
      def self.command_name = '/test'
      def self.description = 'A test command'
      def self.aliases = ['/t']
      def execute(_args, _ctx) = 'executed'
    end
  end

  describe '.all_names' do
    it 'includes command name and aliases' do
      expect(test_command_class.all_names).to eq(%w[/test /t])
    end
  end

  describe '.hidden?' do
    it 'defaults to false' do
      expect(test_command_class.hidden?).to be false
    end
  end

  describe '.aliases' do
    it 'defaults to empty array on base class' do
      expect(described_class.aliases).to eq([])
    end
  end

  describe '#execute' do
    it 'raises NotImplementedError on base class' do
      expect { described_class.new.execute([], nil) }.to raise_error(NotImplementedError)
    end
  end
end
