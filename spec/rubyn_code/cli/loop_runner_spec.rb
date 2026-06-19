# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::LoopRunner do
  describe '.parse_interval' do
    it 'parses seconds, minutes, and hours' do
      expect(described_class.parse_interval('30s')).to eq(30)
      expect(described_class.parse_interval('5m')).to eq(300)
      expect(described_class.parse_interval('2h')).to eq(7200)
    end

    it 'treats a bare number as seconds' do
      expect(described_class.parse_interval('45')).to eq(45)
    end

    it 'is case-insensitive and tolerates surrounding whitespace' do
      expect(described_class.parse_interval(' 5M ')).to eq(300)
    end

    it 'returns nil for non-interval tokens' do
      expect(described_class.parse_interval('/review')).to be_nil
      expect(described_class.parse_interval('hello')).to be_nil
      expect(described_class.parse_interval('0s')).to be_nil
      expect(described_class.parse_interval(nil)).to be_nil
    end
  end

  describe '#run' do
    it 'runs once per iteration up to max_iterations, sleeping between runs' do
      runs = []
      sleeps = []
      runner = described_class.new(
        interval: 60, max_iterations: 3,
        runner: ->(i) { runs << i },
        sleeper: ->(s) { sleeps << s }
      )

      expect(runner.run).to eq(3)
      expect(runs).to eq([0, 1, 2])
      # Sleeps only happen between runs, not after the last one.
      expect(sleeps).to eq([60, 60])
    end

    it 'does not sleep in self-paced mode (nil interval)' do
      sleeps = []
      runner = described_class.new(
        interval: nil, max_iterations: 2,
        runner: ->(_i) { 'working' },
        sleeper: ->(s) { sleeps << s }
      )

      runner.run
      expect(sleeps).to be_empty
    end

    it 'stops early when the runner returns :stop' do
      count = 0
      runner = described_class.new(
        interval: nil, max_iterations: 10,
        runner: ->(_i) { (count += 1) >= 2 ? :stop : 'go' }
      )

      expect(runner.run).to eq(2)
    end

    it 'stops when the runner emits the done sentinel' do
      seq = ['still going', "all set #{described_class::DONE_SENTINEL}"]
      runner = described_class.new(
        interval: nil, max_iterations: 10,
        runner: ->(i) { seq[i] }
      )

      expect(runner.run).to eq(2)
    end

    it 'stops after the current iteration once stop! is called' do
      runner = nil
      runner = described_class.new(
        interval: nil, max_iterations: 10,
        runner: ->(_i) { runner.stop! }
      )

      expect(runner.run).to eq(1)
    end

    it 'fires the on_iteration callback before each run' do
      ticks = []
      runner = described_class.new(
        interval: nil, max_iterations: 2,
        runner: ->(_i) { nil },
        on_iteration: ->(n, total) { ticks << [n, total] }
      )

      runner.run
      expect(ticks).to eq([[1, 2], [2, 2]])
    end

    it 'returns the completed count when interrupted mid-sleep' do
      runner = described_class.new(
        interval: 60, max_iterations: 5,
        runner: ->(_i) { 'ok' },
        sleeper: ->(_s) { raise Interrupt }
      )

      expect(runner.run).to eq(1)
    end
  end
end
