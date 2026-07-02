# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Effort do
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

  before { llm_client.effort = nil }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/effort') }
  end

  describe '#execute' do
    it 'shows current state when called with no args' do
      llm_client.effort = 'high'
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/Reasoning effort: high/)
    end

    it 'shows the unset state when not configured' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/not set/)
    end

    %w[low medium high xhigh max].each do |level|
      it "sets effort to #{level}" do
        command.execute([level], ctx)
        expect(llm_client.effort).to eq(level)
        expect(renderer).to have_received(:info).with(/#{level}/)
      end
    end

    it 'clears effort when given "off"' do
      llm_client.effort = 'high'
      command.execute(['off'], ctx)
      expect(llm_client.effort).to be_nil
    end

    it 'warns on garbage input' do
      command.execute(['asdf'], ctx)
      expect(renderer).to have_received(:warning).with(/Usage:/)
    end
  end
end
