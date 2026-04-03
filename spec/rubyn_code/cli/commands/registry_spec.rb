# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Registry do
  subject(:registry) { described_class.new }

  let(:quit_class) { RubynCode::CLI::Commands::Quit }
  let(:help_class) { RubynCode::CLI::Commands::Help }

  before do
    registry.register(quit_class)
    registry.register(help_class)
  end

  describe '#register' do
    it 'registers a command by its primary name' do
      expect(registry.known?('/quit')).to be true
    end

    it 'registers aliases' do
      expect(registry.known?('/exit')).to be true
      expect(registry.known?('/q')).to be true
    end
  end

  describe '#dispatch' do
    let(:ctx) { instance_double(RubynCode::CLI::Commands::Context) }

    it 'dispatches to the correct command' do
      result = registry.dispatch('/quit', [], ctx)
      expect(result).to eq(:quit)
    end

    it 'dispatches aliases to the same command' do
      result = registry.dispatch('/q', [], ctx)
      expect(result).to eq(:quit)
    end

    it 'returns :unknown for unregistered commands' do
      result = registry.dispatch('/nope', [], ctx)
      expect(result).to eq(:unknown)
    end
  end

  describe '#completions' do
    it 'returns all registered command names sorted' do
      completions = registry.completions
      expect(completions).to include('/quit', '/exit', '/q', '/help')
      expect(completions).to eq(completions.sort)
    end
  end

  describe '#visible_commands' do
    it 'returns unique command classes sorted by name' do
      visible = registry.visible_commands
      expect(visible).to include(quit_class, help_class)
    end

    it 'excludes hidden commands' do
      hidden_class = Class.new(RubynCode::CLI::Commands::Base) do
        def self.command_name = '/secret'
        def self.description = 'hidden'
        def self.hidden? = true

        def execute(_args, _ctx) = nil
      end

      registry.register(hidden_class)
      expect(registry.visible_commands).not_to include(hidden_class)
    end
  end

  describe '#known?' do
    it 'returns true for registered commands' do
      expect(registry.known?('/help')).to be true
    end

    it 'returns false for unknown commands' do
      expect(registry.known?('/nope')).to be false
    end
  end
end
