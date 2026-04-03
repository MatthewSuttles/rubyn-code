# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Help do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil) }

  let(:registry) do
    instance_double(
      RubynCode::CLI::Commands::Registry,
      visible_commands: [mock_command_class]
    )
  end

  let(:mock_command_class) do
    klass = Class.new(RubynCode::CLI::Commands::Base) do
      def self.command_name = 'test'
      def self.description = 'A test command'
      def self.aliases = ['t']
    end
    klass
  end

  before do
    described_class.instance_variable_set(:@registry, registry)
  end

  after do
    described_class.instance_variable_set(:@registry, nil)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/help') }
  end

  describe '#execute' do
    it 'prints available commands header' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with('Available commands:')
    end

    it 'prints command names and descriptions' do
      expect { command.execute([], ctx) }.to output(/test, t/).to_stdout
    end

    it 'prints tips section' do
      expect { command.execute([], ctx) }.to output(/Tips:/).to_stdout
    end
  end
end
