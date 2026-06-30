# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Think do
  subject(:command) { described_class.new }

  let(:llm_client) { RubynCode::LLM::Client.allocate }
  let(:renderer) { instance_double('Renderer', info: nil, warning: nil) }
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      llm_client: llm_client
    )
  end

  before { llm_client.thinking_budget_tokens = 0 }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/think') }
  end

  describe '#execute' do
    it 'shows current state when called with no args' do
      llm_client.thinking_budget_tokens = 8192
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/ON \(8192/)
    end

    it 'shows OFF state when budget is 0' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/OFF/)
    end

    it 'sets budget when given integer' do
      command.execute(['4096'], ctx)
      expect(llm_client.thinking_budget_tokens).to eq(4096)
      expect(renderer).to have_received(:info).with(/4096 tokens/)
    end

    it 'disables when given "off"' do
      llm_client.thinking_budget_tokens = 8192
      command.execute(['off'], ctx)
      expect(llm_client.thinking_budget_tokens).to eq(0)
    end

    it 'disables when given "0"' do
      llm_client.thinking_budget_tokens = 4096
      command.execute(['0'], ctx)
      expect(llm_client.thinking_budget_tokens).to eq(0)
    end

    it 'warns on garbage input' do
      command.execute(['asdf'], ctx)
      expect(renderer).to have_received(:warning).with(/Usage:/)
    end
  end
end
