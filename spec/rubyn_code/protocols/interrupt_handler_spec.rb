# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Protocols::InterruptHandler do
  before do
    # Suppress $stderr writes from signal handler output
    allow($stderr).to receive(:write)
  end

  after do
    described_class.reset!
    described_class.clear_callbacks!
  end

  describe '.setup!' do
    it 'resets the interrupted flag and installs the trap' do
      described_class.instance_variable_set(:@interrupted, true)
      described_class.setup!
      expect(described_class.interrupted?).to be false
    end

    it 'clears the last interrupt timestamp' do
      described_class.instance_variable_set(:@last_interrupt_at, 12_345.0)
      described_class.setup!
      last_at = described_class.instance_variable_get(:@last_interrupt_at)
      expect(last_at).to be_nil
    end
  end

  describe '.interrupted?' do
    it 'returns false by default' do
      described_class.reset!
      expect(described_class.interrupted?).to be false
    end
  end

  describe '.reset!' do
    it 'clears the interrupted flag' do
      described_class.instance_variable_set(:@interrupted, true)
      described_class.reset!
      expect(described_class.interrupted?).to be false
    end

    it 'clears the last interrupt timestamp' do
      described_class.instance_variable_set(:@last_interrupt_at, 99.0)
      described_class.reset!
      last_at = described_class.instance_variable_get(:@last_interrupt_at)
      expect(last_at).to be_nil
    end
  end

  describe '.on_interrupt' do
    it 'registers a callback that fires on interrupt' do
      called = false
      described_class.on_interrupt { called = true }
      # Simulate the interrupt handler logic
      described_class.send(:handle_interrupt)
      expect(called).to be true
      expect(described_class.interrupted?).to be true
    end

    it 'fires multiple callbacks in registration order' do
      order = []
      described_class.on_interrupt { order << :first }
      described_class.on_interrupt { order << :second }
      described_class.send(:handle_interrupt)
      expect(order).to eq(%i[first second])
    end

    it 'swallows errors in callbacks without crashing' do
      described_class.on_interrupt { raise 'boom' }
      expect { described_class.send(:handle_interrupt) }.not_to raise_error
      expect(described_class.interrupted?).to be true
    end
  end
end
