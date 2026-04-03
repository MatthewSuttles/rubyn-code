# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::InputHandler do
  let(:registry) do
    reg = RubynCode::CLI::Commands::Registry.new
    # Register a subset of commands for testing
    [
      RubynCode::CLI::Commands::Quit,
      RubynCode::CLI::Commands::Compact,
      RubynCode::CLI::Commands::Help,
      RubynCode::CLI::Commands::Doctor
    ].each { |cmd| reg.register(cmd) }
    reg
  end

  subject(:handler) { described_class.new(command_registry: registry) }

  describe '#parse' do
    it 'returns quit for /quit' do
      cmd = handler.parse('/quit')
      expect(cmd.action).to eq(:quit)
    end

    it 'returns quit for /exit' do
      expect(handler.parse('/exit').action).to eq(:quit)
    end

    it 'returns quit for /q' do
      expect(handler.parse('/q').action).to eq(:quit)
    end

    it 'dispatches registered commands as :slash_command' do
      cmd = handler.parse('/compact')
      expect(cmd.action).to eq(:slash_command)
      expect(cmd.args).to eq(['/compact'])
    end

    it 'passes arguments through for slash commands' do
      cmd = handler.parse('/compact focus_on_tests')
      expect(cmd.action).to eq(:slash_command)
      expect(cmd.args).to eq(['/compact', 'focus_on_tests'])
    end

    it 'returns unknown_command for unrecognized slash commands' do
      cmd = handler.parse('/foobar')
      expect(cmd.action).to eq(:unknown_command)
      expect(cmd.args).to include('/foobar')
    end

    it 'returns quit for nil input (EOF)' do
      expect(handler.parse(nil).action).to eq(:quit)
    end

    it 'returns empty for blank input' do
      expect(handler.parse('   ').action).to eq(:empty)
    end

    it 'returns message for regular text' do
      cmd = handler.parse('tell me about Ruby')
      expect(cmd.action).to eq(:message)
    end

    it 'returns list_commands for bare /' do
      cmd = handler.parse('/')
      expect(cmd.action).to eq(:list_commands)
    end

    it 'expands file references with @path' do
      with_temp_project do |dir|
        path = create_test_file(dir, 'sample.rb', "puts 'hi'")
        cmd = handler.parse("Read @#{path}")
        expect(cmd.args.first).to include('<file')
        expect(cmd.args.first).to include("puts 'hi'")
      end
    end
  end

  context 'without a command registry (legacy mode)' do
    subject(:handler) { described_class.new }

    it 'still handles /quit' do
      expect(handler.parse('/quit').action).to eq(:quit)
    end

    it 'reports unknown for non-quit commands' do
      expect(handler.parse('/compact').action).to eq(:unknown_command)
    end
  end

  describe '#multiline?' do
    it 'returns true for lines ending with backslash' do
      expect(handler.multiline?("hello\\")).to be true
    end

    it 'returns false for normal lines' do
      expect(handler.multiline?('hello')).to be false
    end
  end
end
