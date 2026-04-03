# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Tokens do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double(RubynCode::CLI::Renderer, warning: nil) }
  let(:conversation) do
    instance_double('Agent::Conversation', messages: [
      { role: 'user', content: 'hello' },
      { role: 'assistant', content: 'hi there' }
    ])
  end
  let(:context_manager) do
    instance_double(
      'Context::Manager',
      total_input_tokens: 1500,
      total_output_tokens: 800
    )
  end

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      conversation: conversation,
      context_manager: context_manager
    )
  end

  before do
    allow(context_manager).to receive(:instance_variable_get).with(:@threshold).and_return(50_000)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/tokens') }
  end

  describe '#execute' do
    it 'displays token estimation without raising' do
      expect { command.execute([], ctx) }.to output(/Token Estimation/).to_stdout
    end

    it 'shows actual usage' do
      expect { command.execute([], ctx) }.to output(/Actual Usage/).to_stdout
    end

    it 'shows message count' do
      expect { command.execute([], ctx) }.to output(/Messages:.*2/).to_stdout
    end
  end
end
