# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Loop do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double('Renderer', info: nil) }
  let(:ctx)      { instance_double(RubynCode::CLI::Commands::Context, renderer: renderer) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/loop') }
  end

  describe '#execute' do
    it 'parses an interval and slash-command payload' do
      result = command.execute(%w[5m /review], ctx)
      expect(result).to eq(action: :run_loop, interval: 300, max: 50, payload: '/review')
    end

    it 'parses an interval and a multi-word prompt payload' do
      result = command.execute(%w[30s check the deploy], ctx)
      expect(result).to include(interval: 30, payload: 'check the deploy')
    end

    it 'treats a missing interval as self-paced (nil interval)' do
      result = command.execute(%w[keep triaging issues], ctx)
      expect(result).to include(interval: nil, payload: 'keep triaging issues')
    end

    it 'reads an xN max-iterations token before the interval' do
      result = command.execute(%w[x3 1m /babysit], ctx)
      expect(result).to include(max: 3, interval: 60, payload: '/babysit')
    end

    it 'reads an xN token after the interval too' do
      result = command.execute(%w[1m x7 /babysit], ctx)
      expect(result).to include(max: 7, interval: 60, payload: '/babysit')
    end

    it 'shows usage and returns nil when no args are given' do
      expect(command.execute([], ctx)).to be_nil
      expect(renderer).to have_received(:info).with(/Usage: \/loop/)
    end

    it 'shows usage when the payload is empty' do
      expect(command.execute(['5m'], ctx)).to be_nil
      expect(renderer).to have_received(:info).with(/Usage: \/loop/)
    end
  end
end
